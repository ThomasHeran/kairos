"""
Kairos — Branch Generator
==========================
Génère les branches de l'arbre de scénarios à partir de:
1. La lookup table de calibration (probability_calibrations_v1.json)
2. Les drivers activés par l'event (event_driver_lookup)
3. Les analogies historiques (historical_episodes)

Pour chaque nœud N à profondeur D, génère 2-4 branches enfants
avec probabilités normalisées.
"""

import os
import uuid
from typing import Optional
from datetime import datetime

from engine.probability_calibrator import (
    find_best_calibration,
    ContextualAdjustment,
    attenuate_by_depth,
    should_prune,
)


# ---------------------------------------------------------------------------
# Structures de données
# ---------------------------------------------------------------------------

def make_driver_activation(
    driver: str,
    direction: int,
    intensity: str,
    coefficient: float,
    horizon: str,
    sub_driver: str = "",
    intensity_range: Optional[dict] = None,
) -> dict:
    return {
        "driver": driver,
        "sub_driver": sub_driver or driver,
        "direction": direction,
        "intensity": intensity,
        "coefficient": coefficient,
        "range": intensity_range or {"low": coefficient * 0.6, "central": coefficient, "high": coefficient * 1.4},
        "horizon": horizon,
    }


def make_scenario_node(
    tree_id: str,
    parent_node_id: Optional[str],
    depth: int,
    label: str,
    description: str,
    probability: float,
    probability_cumulative: float,
    trigger_condition: str,
    time_horizon: str,
    drivers_activated: list,
    asset_impacts: dict,
    historical_analogies: list,
    confidence: float,
) -> dict:
    """Crée un nœud de l'arbre de scénarios (en mémoire, avant DB insert)."""
    return {
        "node_id": str(uuid.uuid4()),
        "tree_id": tree_id,
        "parent_node_id": parent_node_id,
        "depth": depth,
        "label": label,
        "description": description,
        "probability": round(probability, 4),
        "probability_cumulative": round(probability_cumulative, 4),
        "trigger_condition": trigger_condition,
        "time_horizon": time_horizon,
        "drivers_activated": drivers_activated,
        "asset_impacts": asset_impacts,
        "historical_analogies": historical_analogies,
        "confidence": round(confidence, 3),
        "is_terminal": False,
        "is_pruned": False,
        "children": [],  # sera rempli après récursion
    }


# ---------------------------------------------------------------------------
# Branch Generator principal
# ---------------------------------------------------------------------------

class BranchGenerator:
    """
    Génère les branches (nœuds enfants) pour un nœud parent donné.

    Sources de données:
    1. Calibration lookup (probability_calibrations_v1.json)
    2. Event driver lookup (event_driver_lookup table en DB ou défaut intégré)
    3. Historical episodes (analogies)
    """

    def __init__(self, macro_context: Optional[dict] = None):
        self.macro_context = macro_context or {}
        self.adjuster = ContextualAdjustment(macro_context)

    def generate_branches(
        self,
        tree_id: str,
        parent_node: dict,
        event: dict,
        depth: int,
        max_depth: int,
        min_probability: float = 0.03,
    ) -> list[dict]:
        """
        Génère les branches enfants pour un nœud parent.

        Args:
            tree_id: ID de l'arbre
            parent_node: nœud parent (dict)
            event: event C2 {cat_id, subtype_id, importance_score, geography, ...}
            depth: profondeur actuelle dans l'arbre
            max_depth: profondeur maximale
            min_probability: seuil de pruning

        Returns:
            Liste de nœuds enfants (dicts)
        """
        if depth >= max_depth:
            return []

        cat_id = event.get("cat_id", "")
        subtype_id = event.get("subtype_id", "")
        geography = event.get("geography", [])
        parent_cumulative = parent_node.get("probability_cumulative", 1.0)

        # 1. Trouver la meilleure calibration
        calibration = find_best_calibration(cat_id, subtype_id, geography)

        if not calibration:
            # Fallback: générer des branches génériques selon le depth
            return self._generate_generic_branches(
                tree_id, parent_node, event, depth, parent_cumulative, min_probability
            )

        # 2. Ajuster les probabilités selon le contexte macro
        branches_raw = calibration.get("branches", [])
        branches_adjusted = self.adjuster.adjust_branch_probabilities(branches_raw)

        # 3. Construire les nœuds enfants
        child_nodes = []
        for branch in branches_adjusted:
            p_branch = branch.get("p_adjusted", branch.get("p_historical", 0.33))
            p_cumulative = parent_cumulative * p_branch

            # Pruning check
            drivers = branch.get("primary_drivers", [])
            max_coeff = max(
                (attenuate_by_depth(d.get("coefficient", 0.5), depth) for d in drivers),
                default=0.5
            )
            if should_prune(p_cumulative, max_coeff) and p_cumulative < min_probability:
                continue  # élaguer cette branche

            # Construire les drivers_activated avec atténuation par profondeur
            drivers_activated = []
            for d in drivers:
                coeff_attenuated = attenuate_by_depth(d.get("coefficient", 0.5), depth)
                if coeff_attenuated < 0.05:
                    continue
                drivers_activated.append(make_driver_activation(
                    driver=d.get("driver", ""),
                    direction=d.get("direction", 1),
                    intensity=d.get("intensity", "moderate"),
                    coefficient=coeff_attenuated,
                    horizon=d.get("horizon", "1-4w"),
                    intensity_range=d.get("range"),
                ))

            # Asset impacts
            asset_impacts = branch.get("asset_impacts", {})

            # Historical analogies
            analogies = branch.get("historical_analogies", [])

            # Confiance: diminue avec la profondeur
            confidence = max(0.30, 0.80 - (depth * 0.12))

            # Horizon principal
            primary_horizon = self._get_primary_horizon(drivers_activated, depth)

            node = make_scenario_node(
                tree_id=tree_id,
                parent_node_id=parent_node["node_id"],
                depth=depth,
                label=branch.get("label", branch.get("outcome", f"Branch_{depth}")),
                description=branch.get("outcome", ""),
                probability=p_branch,
                probability_cumulative=p_cumulative,
                trigger_condition=self._build_trigger_condition(branch, depth),
                time_horizon=primary_horizon,
                drivers_activated=drivers_activated,
                asset_impacts=asset_impacts,
                historical_analogies=analogies,
                confidence=confidence,
            )
            child_nodes.append(node)

        return child_nodes

    def _generate_generic_branches(
        self,
        tree_id: str,
        parent_node: dict,
        event: dict,
        depth: int,
        parent_cumulative: float,
        min_probability: float,
    ) -> list[dict]:
        """Branches génériques quand aucune calibration spécifique n'est disponible."""
        cat_id = event.get("cat_id", "")
        parent_id = parent_node["node_id"]

        generic_branches = []

        if cat_id in ("CAT-06", "CAT-08"):
            # Scénarios génériques géopolitiques/énergie
            scenarios = [
                ("Résolution rapide — impact transitoire", 0.50,
                 {"sentiment_marche": {"signal": "slightly_bearish", "magnitude_central": "-2%", "horizon": "immediate"}}),
                ("Impact modéré persistant", 0.35,
                 {"sentiment_marche": {"signal": "bearish", "magnitude_central": "-6%", "horizon": "1-4w"},
                  "gold": {"signal": "bullish", "magnitude_central": "+5%", "horizon": "immediate"}}),
                ("Escalade — choc sévère", 0.15,
                 {"sentiment_marche": {"signal": "strongly_bearish", "magnitude_central": "-15%", "horizon": "1-4w"},
                  "gold": {"signal": "strongly_bullish", "magnitude_central": "+12%", "horizon": "immediate"}}),
            ]
        elif cat_id == "CAT-05":
            # Scénarios stabilité financière
            scenarios = [
                ("Contagion limitée — autorités gèrent", 0.55,
                 {"equities_us": {"signal": "bearish", "magnitude_central": "-5%", "horizon": "immediate"},
                  "bonds_sovereign_us": {"signal": "bullish", "magnitude_central": "+3%", "horizon": "immediate"}}),
                ("Stress bancaire — resserrement crédit", 0.30,
                 {"equities_us": {"signal": "strongly_bearish", "magnitude_central": "-12%", "horizon": "1-4w"},
                  "spreads_credit": {"signal": "bearish", "magnitude_central": "+150bps", "horizon": "1-4w"}}),
                ("Crise systémique", 0.15,
                 {"equities_us": {"signal": "strongly_bearish", "magnitude_central": "-25%", "horizon": "1-4w"},
                  "gold": {"signal": "strongly_bullish", "magnitude_central": "+18%", "horizon": "immediate"}}),
            ]
        else:
            scenarios = [
                ("Scénario de base", 0.60,
                 {"equities_us": {"signal": "slightly_bearish", "magnitude_central": "-2%", "horizon": "1-4w"}}),
                ("Scénario adverse", 0.40,
                 {"equities_us": {"signal": "bearish", "magnitude_central": "-8%", "horizon": "1-4w"},
                  "gold": {"signal": "bullish", "magnitude_central": "+5%", "horizon": "immediate"}}),
            ]

        for label, p_branch, asset_impacts in scenarios:
            p_cumulative = parent_cumulative * p_branch
            if p_cumulative < min_probability:
                continue

            confidence = max(0.30, 0.65 - (depth * 0.12))
            node = make_scenario_node(
                tree_id=tree_id,
                parent_node_id=parent_id,
                depth=depth,
                label=label,
                description=label,
                probability=p_branch,
                probability_cumulative=p_cumulative,
                trigger_condition="Conditions de marché et contexte géopolitique",
                time_horizon="1-4w" if depth <= 1 else "1-6m",
                drivers_activated=[],
                asset_impacts=asset_impacts,
                historical_analogies=[],
                confidence=confidence,
            )
            generic_branches.append(node)

        return generic_branches

    def _get_primary_horizon(self, drivers: list, depth: int) -> str:
        """Détermine le time horizon principal basé sur les drivers activés."""
        if not drivers:
            horizons = ["immediate", "1-4w", "1-6m", "6m+"]
            return horizons[min(depth, 3)]

        # Priorité: prend le premier driver
        horizon = drivers[0].get("horizon", "1-4w")
        return horizon

    def _build_trigger_condition(self, branch: dict, depth: int) -> str:
        """Construit la trigger_condition textuelle pour un nœud."""
        conditions = branch.get("conditioning_factors", [])
        if conditions:
            return " ET ".join(conditions[:3])  # max 3 conditions
        return branch.get("outcome", "Conditions remplies")


# ---------------------------------------------------------------------------
# Root node generator
# ---------------------------------------------------------------------------

def generate_root_node(tree_id: str, event: dict) -> dict:
    """
    Génère le nœud racine à partir de l'event C2.
    Le root node représente l'event lui-même (depth=0, P=1.0).
    """
    cat_id = event.get("cat_id", "")
    subtype_id = event.get("subtype_id", "")
    label = event.get("event_label", event.get("text_en_canonical", "Event initial"))

    # Drivers primaires depuis l'event
    drivers_activated = _get_root_drivers(cat_id, subtype_id)

    # Asset impacts initiaux
    asset_impacts = _get_root_asset_impacts(cat_id, subtype_id)

    return make_scenario_node(
        tree_id=tree_id,
        parent_node_id=None,
        depth=0,
        label=label,
        description=event.get("text_en_canonical", label),
        probability=1.0,
        probability_cumulative=1.0,
        trigger_condition="Event déclencheur confirmé",
        time_horizon="immediate",
        drivers_activated=drivers_activated,
        asset_impacts=asset_impacts,
        historical_analogies=[],
        confidence=event.get("confidence", 0.80),
    )


def _get_root_drivers(cat_id: str, subtype_id: str) -> list:
    """Drivers initiaux selon le type d'event."""
    INITIAL_DRIVERS = {
        "CAT-06": {
            "military_conflict": [
                make_driver_activation("prix_petrole", 1, "moderate", 0.70, "immediate"),
                make_driver_activation("sentiment_marche", 1, "strong", 0.85, "immediate"),
                make_driver_activation("usd_strength", 1, "moderate", 0.55, "immediate"),
            ],
            "trade_war_escalation": [
                make_driver_activation("sentiment_marche", 1, "moderate", 0.65, "immediate"),
                make_driver_activation("inflation_headline", 1, "low", 0.35, "1-4w"),
            ],
            "energy_supply_shock": [
                make_driver_activation("prix_petrole", 1, "strong", 0.85, "immediate"),
                make_driver_activation("inflation_headline", 1, "moderate", 0.55, "1-4w"),
            ],
            "sanctions_imposed": [
                make_driver_activation("sentiment_marche", 1, "moderate", 0.65, "immediate"),
                make_driver_activation("usd_strength", 1, "low", 0.40, "immediate"),
            ],
        },
        "CAT-08": {
            "oil_price_surge": [
                make_driver_activation("prix_petrole", 1, "strong", 0.90, "immediate"),
                make_driver_activation("inflation_headline", 1, "moderate", 0.55, "1-4w"),
            ],
            "opec_decision": [
                make_driver_activation("prix_petrole", 1, "moderate", 0.70, "immediate"),
            ],
            "gas_supply_disruption": [
                make_driver_activation("prix_petrole", 1, "strong", 0.80, "immediate"),
                make_driver_activation("inflation_headline", 1, "moderate", 0.60, "1-4w"),
            ],
        },
        "CAT-05": {
            "bank_failure": [
                make_driver_activation("sentiment_marche", 1, "strong", 0.85, "immediate"),
                make_driver_activation("liquidite_bancaire", -1, "moderate", 0.70, "immediate"),
                make_driver_activation("spreads_credit", 1, "moderate", 0.65, "1-4w"),
            ],
            "sovereign_debt_stress": [
                make_driver_activation("spreads_souverains", 1, "strong", 0.85, "immediate"),
                make_driver_activation("sentiment_marche", 1, "moderate", 0.70, "immediate"),
            ],
            "currency_crisis": [
                make_driver_activation("usd_strength", 1, "strong", 0.85, "immediate"),
                make_driver_activation("spreads_souverains", 1, "moderate", 0.65, "1-4w"),
            ],
        },
    }

    cat_drivers = INITIAL_DRIVERS.get(cat_id, {})
    return cat_drivers.get(subtype_id, [
        make_driver_activation("sentiment_marche", 1, "moderate", 0.60, "immediate"),
    ])


def _get_root_asset_impacts(cat_id: str, subtype_id: str) -> dict:
    """Asset impacts initiaux (avant propagation des branches)."""
    if cat_id == "CAT-06" and subtype_id == "military_conflict":
        return {
            "oil_wti": {"signal": "bullish", "magnitude_central": "+10%", "range": ["+5%", "+20%"], "horizon": "immediate"},
            "gold": {"signal": "bullish", "magnitude_central": "+4%", "range": ["+2%", "+8%"], "horizon": "immediate"},
            "equities_us": {"signal": "bearish", "magnitude_central": "-3%", "range": ["-1%", "-6%"], "horizon": "immediate"},
            "bonds_sovereign_us": {"signal": "bullish", "magnitude_central": "+1%", "horizon": "immediate"},
        }
    elif cat_id == "CAT-08" and "oil" in subtype_id:
        return {
            "oil_wti": {"signal": "bullish", "magnitude_central": "+15%", "range": ["+8%", "+25%"], "horizon": "immediate"},
            "equities_us": {"signal": "bearish", "magnitude_central": "-3%", "horizon": "immediate"},
        }
    elif cat_id == "CAT-05":
        return {
            "equities_us": {"signal": "bearish", "magnitude_central": "-5%", "horizon": "immediate"},
            "bonds_sovereign_us": {"signal": "bullish", "magnitude_central": "+3%", "horizon": "immediate"},
            "gold": {"signal": "bullish", "magnitude_central": "+3%", "horizon": "immediate"},
        }
    return {
        "equities_us": {"signal": "slightly_bearish", "magnitude_central": "-2%", "horizon": "immediate"},
    }


if __name__ == "__main__":
    # Test rapide
    print("=== Branch Generator Test ===\n")

    event = {
        "event_id": str(uuid.uuid4()),
        "cat_id": "CAT-06",
        "subtype_id": "military_conflict",
        "importance_score": 0.90,
        "geography": ["MIDDLE_EAST", "IRAN"],
        "text_en_canonical": "US launches military strikes against Iran",
        "confidence": 0.85,
    }
    tree_id = str(uuid.uuid4())

    gen = BranchGenerator(macro_context={"oil_price_level": "high", "diplomatic_context": "hostile"})

    root = generate_root_node(tree_id, event)
    print(f"Root node: {root['label']}")
    print(f"Root drivers: {[d['driver'] for d in root['drivers_activated']]}\n")

    children = gen.generate_branches(tree_id, root, event, depth=1, max_depth=4)
    print(f"Generated {len(children)} first-level branches:")
    for child in children:
        print(f"  [{child['probability']:.0%}] {child['label']}")
        print(f"       P_cumul={child['probability_cumulative']:.4f}, confidence={child['confidence']:.2f}")
