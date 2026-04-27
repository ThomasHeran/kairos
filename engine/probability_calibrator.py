"""
Kairos — Probability Calibrator
================================
Lookup + ajustement contextuel des probabilités de branches.
Charge probability_calibrations_v1.json et ajuste les probabilités
en fonction du contexte macro actuel vs le médian historique.
"""

import json
import os
from typing import Optional
from pathlib import Path


# ---------------------------------------------------------------------------
# Chargement de la lookup table
# ---------------------------------------------------------------------------

def _load_calibrations() -> dict:
    """Charge probability_calibrations_v1.json depuis config/."""
    base = Path(__file__).parent.parent / "config" / "probability_calibrations_v1.json"
    with open(base, "r", encoding="utf-8") as f:
        return json.load(f)


_CALIBRATION_DATA: Optional[dict] = None


def get_calibrations() -> dict:
    global _CALIBRATION_DATA
    if _CALIBRATION_DATA is None:
        _CALIBRATION_DATA = _load_calibrations()
    return _CALIBRATION_DATA


def get_calibration_by_id(bifurcation_id: str) -> Optional[dict]:
    """Retourne la calibration pour un bifurcation_id donné."""
    data = get_calibrations()
    for cal in data.get("calibrations", []):
        if cal["bifurcation_id"] == bifurcation_id:
            return cal
    return None


def get_calibrations_for_event(cat_id: str, subtype_id: str) -> list[dict]:
    """Retourne toutes les calibrations correspondant à un type d'event."""
    data = get_calibrations()
    results = []
    for cal in data.get("calibrations", []):
        if cal.get("cat_id") == cat_id and cal.get("subtype_id") == subtype_id:
            results.append(cal)
    return results


# ---------------------------------------------------------------------------
# Détection HIGH_UNCERTAINTY
# ---------------------------------------------------------------------------

HIGH_UNCERTAINTY_CATS = {"CAT-05", "CAT-06", "CAT-08"}
"""Catégories qui déclenchent le Scenario Tree Engine:
- CAT-05: FINANCIAL_STABILITY
- CAT-06: GEOPOLITICAL_RISK
- CAT-08: COMMODITY_MARKETS
"""

IMPORTANCE_THRESHOLD = 0.75


def is_high_uncertainty(cat_id: str, importance_score: float, has_unverified_conditions: bool = False) -> bool:
    """
    Détermine si un event doit déclencher le Scenario Tree Engine.

    Critères:
    - cat_id ∈ HIGH_UNCERTAINTY_CATS ET importance_score > 0.75
    - OU présence d'arcs avec conditions non encore vérifiées
    """
    if cat_id in HIGH_UNCERTAINTY_CATS and importance_score > IMPORTANCE_THRESHOLD:
        return True
    if has_unverified_conditions:
        return True
    return False


# ---------------------------------------------------------------------------
# Ajustement contextuel des probabilités
# ---------------------------------------------------------------------------

class ContextualAdjustment:
    """
    Ajuste les probabilités historiques en fonction du contexte macro actuel.

    Règle: P_adjusted = P_historical × adjustment_factor
    Avec renormalisation pour que ΣP = 1.0
    """

    def __init__(self, macro_context: Optional[dict] = None):
        """
        macro_context: {
            "oil_price_level": "high" | "medium" | "low",
            "inflation_regime": "above_target" | "on_target" | "below_target",
            "growth_regime": "strong" | "moderate" | "weak" | "recession",
            "us_rates_stance": "hiking" | "holding" | "cutting",
            "vix_level": "high" | "medium" | "low",
            "diplomatic_context": "hostile" | "neutral" | "cooperative"
        }
        """
        self.context = macro_context or {}

    def adjust_branch_probabilities(self, branches: list[dict]) -> list[dict]:
        """
        Ajuste et renormalise les probabilités d'un ensemble de branches.

        Retourne les branches avec p_adjusted calculé.
        """
        adjusted = []
        for branch in branches:
            factor = self._compute_adjustment_factor(branch)
            p_hist = branch.get("p_historical", 1.0 / len(branches))
            p_adj = p_hist * factor
            branch_copy = dict(branch)
            branch_copy["p_adjusted"] = p_adj
            adjusted.append(branch_copy)

        # Renormalisation: ΣP = 1.0
        total = sum(b["p_adjusted"] for b in adjusted)
        if total > 0:
            for b in adjusted:
                b["p_adjusted"] = round(b["p_adjusted"] / total, 4)

        return adjusted

    def _compute_adjustment_factor(self, branch: dict) -> float:
        """
        Calcule un facteur multiplicatif [0.5, 2.0] basé sur le contexte.

        Logique de base: si les conditioning_factors d'une branche sont
        actuellement présents dans le contexte macro → P_up.
        """
        factor = 1.0
        conditioning = branch.get("conditioning_factors", [])
        context = self.context

        # Ajustements selon le contexte
        for condition in conditioning:
            cond_lower = condition.lower()

            # Oil context
            if "oil" in cond_lower or "barrel" in cond_lower:
                oil_level = context.get("oil_price_level", "medium")
                if oil_level == "high" and "surge" in cond_lower:
                    factor *= 1.30
                elif oil_level == "low" and "drop" in cond_lower:
                    factor *= 1.30

            # Diplomatic context
            if "diplomatic" in cond_lower or "ceasefire" in cond_lower:
                diplo = context.get("diplomatic_context", "neutral")
                if diplo == "hostile":
                    factor *= 1.20  # moins de chance de résolution rapide
                elif diplo == "cooperative":
                    factor *= 0.80

            # US rates / monetary context
            if "rate" in cond_lower or "bc" in cond_lower or "tight" in cond_lower:
                stance = context.get("us_rates_stance", "holding")
                if stance == "hiking":
                    factor *= 1.15
                elif stance == "cutting":
                    factor *= 0.85

            # Growth
            if "recession" in cond_lower or "slowdown" in cond_lower:
                growth = context.get("growth_regime", "moderate")
                if growth in ("weak", "recession"):
                    factor *= 1.25

            # VIX / stress
            if "risk" in cond_lower or "confidence" in cond_lower or "stress" in cond_lower:
                vix = context.get("vix_level", "medium")
                if vix == "high":
                    factor *= 1.20

        return max(0.5, min(2.0, factor))


# ---------------------------------------------------------------------------
# Atténuation par profondeur
# ---------------------------------------------------------------------------

DEPTH_ATTENUATION = {
    0: 1.00,
    1: 0.90,
    2: 0.80,
    3: 0.70,
    4: 0.60,
}


def attenuate_by_depth(coefficient: float, depth: int) -> float:
    """
    Atténue un coefficient d'intensité par profondeur dans l'arbre.
    Au-delà de la profondeur 4, retourne 0 (pas d'impact significatif).
    """
    factor = DEPTH_ATTENUATION.get(depth, 0.0)
    return round(coefficient * factor, 4)


# ---------------------------------------------------------------------------
# Pruning
# ---------------------------------------------------------------------------

MIN_CUMULATIVE_PROBABILITY = 0.03
MIN_DRIVER_INTENSITY_AFTER_ATTENUATION = 0.10


def should_prune(cumulative_probability: float, max_driver_coefficient: float = 1.0) -> bool:
    """
    Détermine si une branche doit être élagée.

    Règles:
    - P_cumulatif < 0.03 → prune
    - Max driver_intensity_coefficient après atténuation < 0.10 → prune
    """
    if cumulative_probability < MIN_CUMULATIVE_PROBABILITY:
        return True
    if max_driver_coefficient < MIN_DRIVER_INTENSITY_AFTER_ATTENUATION:
        return True
    return False


# ---------------------------------------------------------------------------
# Récupération de la calibration la plus appropriée
# ---------------------------------------------------------------------------

FALLBACK_CALIBRATIONS = {
    "CAT-06": {
        "military_conflict": "armed_conflict_general_response",
        "sanctions_imposed": "sanctions_regime_impact",
        "trade_war_escalation": "trade_war_escalation_paths",
        "energy_supply_shock": "energy_supply_shock_cb_response",
    },
    "CAT-08": {
        "oil_price_surge": "oil_supply_disruption_response",
        "opec_decision": "opec_production_cut_impact",
    },
    "CAT-05": {
        "bank_failure": "financial_system_stress",
        "sovereign_debt_stress": "sovereign_debt_stress_paths",
        "systemic_risk_warning": "financial_system_stress",
    },
}


def find_best_calibration(cat_id: str, subtype_id: str, geography: list[str] = None) -> Optional[dict]:
    """
    Trouve la meilleure calibration pour un event donné.

    Priorité:
    1. Match exact cat_id + subtype_id
    2. Calibration de fallback par cat_id/subtype_id
    3. Calibration générique par cat_id
    """
    # 1. Match exact
    exact = get_calibrations_for_event(cat_id, subtype_id)
    if exact:
        # Si géographie MIDDLE_EAST + military → Hormuz calibration
        if geography and any(g in ("MIDDLE_EAST", "IRAN") for g in geography):
            for cal in exact:
                if "hormuz" in cal["bifurcation_id"]:
                    return cal
        return exact[0]

    # 2. Fallback par type
    fallback_id = FALLBACK_CALIBRATIONS.get(cat_id, {}).get(subtype_id)
    if fallback_id:
        return get_calibration_by_id(fallback_id)

    return None


if __name__ == "__main__":
    # Test rapide
    print("=== Probability Calibrator Test ===\n")

    cal = find_best_calibration("CAT-06", "military_conflict", ["MIDDLE_EAST", "IRAN"])
    if cal:
        print(f"Calibration trouvée: {cal['bifurcation_id']}")
        print(f"Branches: {[b['outcome'] for b in cal['branches']]}")

        adjuster = ContextualAdjustment({
            "oil_price_level": "high",
            "diplomatic_context": "hostile",
            "vix_level": "high"
        })
        adjusted = adjuster.adjust_branch_probabilities(cal["branches"])
        print("\nProbabilités ajustées:")
        for b in adjusted:
            print(f"  {b['outcome']}: {b.get('p_adjusted', b['p_historical']):.3f}")

        total = sum(b.get("p_adjusted", b["p_historical"]) for b in adjusted)
        print(f"\nTotal (doit = 1.0): {total:.3f}")

    print(f"\nHigh uncertainty CAT-06 + 0.85: {is_high_uncertainty('CAT-06', 0.85)}")
    print(f"High uncertainty CAT-01 + 0.85: {is_high_uncertainty('CAT-01', 0.85)}")
    print(f"High uncertainty CAT-06 + 0.50: {is_high_uncertainty('CAT-06', 0.50)}")
