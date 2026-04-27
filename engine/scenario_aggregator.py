"""
Kairos — Scenario Aggregator
==============================
Agrège les scénarios terminaux d'un arbre pour produire:
1. Le scénario dominant (probabilité max)
2. Les impacts consensus pondérés par probabilité
3. L'incertitude globale

Entrée: liste de scenario_paths (chaque path = sequence de nœuds root→leaf)
Sortie: {dominant_scenario, consensus_asset_impacts, uncertainty_flag}
"""

from typing import Optional


# ---------------------------------------------------------------------------
# Signal mapping pour calcul consensus
# ---------------------------------------------------------------------------

SIGNAL_SCORES = {
    "strongly_bullish": 2.0,
    "bullish": 1.0,
    "slightly_bullish": 0.5,
    "mixed": 0.0,
    "slightly_bearish": -0.5,
    "bearish": -1.0,
    "bearish_mixed": -0.5,
    "strongly_bearish": -2.0,
}

SCORE_TO_SIGNAL = [
    (1.5, "strongly_bullish"),
    (0.75, "bullish"),
    (0.25, "slightly_bullish"),
    (-0.25, "mixed"),
    (-0.75, "slightly_bearish"),
    (-1.5, "bearish"),
    (-float("inf"), "strongly_bearish"),
]


def score_to_signal(score: float) -> str:
    for threshold, signal in SCORE_TO_SIGNAL:
        if score >= threshold:
            return signal
    return "mixed"


def confidence_from_dispersion(values: list[float]) -> tuple[float, str]:
    """
    Calcule la confiance basée sur la dispersion des valeurs pondérées.
    Faible dispersion → haute confiance.
    """
    if len(values) <= 1:
        return 0.70, "MODERATE"

    mean = sum(values) / len(values)
    variance = sum((v - mean) ** 2 for v in values) / len(values)
    std = variance ** 0.5

    # Normaliser la std
    if std < 0.2:
        return 0.85, "HIGH"
    elif std < 0.5:
        return 0.65, "MODERATE"
    elif std < 1.0:
        return 0.45, "LOW"
    else:
        return 0.25, "VERY_LOW"


# ---------------------------------------------------------------------------
# Agrégateur principal
# ---------------------------------------------------------------------------

class ScenarioAggregator:
    """
    Agrège les scénarios terminaux d'un arbre de scénarios.
    """

    def compute_dominant_scenario(self, scenario_paths: list[dict]) -> tuple[Optional[dict], float]:
        """
        Retourne le scénario (path) avec la probabilité la plus élevée.
        """
        if not scenario_paths:
            return None, 0.0

        dominant = max(scenario_paths, key=lambda p: p.get("probability_path", 0.0))
        return dominant, dominant.get("probability_path", 0.0)

    def compute_consensus_asset_impacts(self, scenario_paths: list[dict]) -> dict:
        """
        Calcule les impacts consensus agrégés pondérés par probabilité.

        Pour chaque actif:
        - Signal: moyenne pondérée des scores de signal
        - Magnitude: moyenne pondérée des magnitudes numériques
        - Confiance: inversement proportionnelle à la dispersion

        Returns:
            {asset_id: {signal, magnitude, magnitude_range, confidence, confidence_label}}
        """
        if not scenario_paths:
            return {}

        # Pondérations normalisées
        total_prob = sum(p.get("probability_path", 0.0) for p in scenario_paths)
        if total_prob == 0:
            return {}

        # Collecte des données par actif
        asset_data: dict[str, list[tuple[float, float, str]]] = {}
        # {asset_id: [(weight, signal_score, magnitude_str)]}

        for path in scenario_paths:
            weight = path.get("probability_path", 0.0) / total_prob
            asset_summary = path.get("terminal_asset_summary", {})

            for asset_id, impact in asset_summary.items():
                signal = impact.get("signal", "mixed")
                signal_score = SIGNAL_SCORES.get(signal, 0.0)
                magnitude_str = impact.get("magnitude", impact.get("magnitude_central", "0%"))
                magnitude_num = self._parse_magnitude(magnitude_str)
                confidence = impact.get("confidence", 0.60)

                if asset_id not in asset_data:
                    asset_data[asset_id] = []
                asset_data[asset_id].append((weight, signal_score, magnitude_num, confidence))

        # Calcul du consensus
        consensus = {}
        for asset_id, data_points in asset_data.items():
            # Moyenne pondérée du signal
            weighted_signal = sum(w * s for w, s, _, _ in data_points)
            weighted_magnitude = sum(w * m for w, _, m, _ in data_points)
            weighted_confidence = sum(w * c for w, _, _, c in data_points)

            # Dispersion pour évaluer la confiance
            signal_scores = [s for _, s, _, _ in data_points]
            _, confidence_label = confidence_from_dispersion(signal_scores)

            consensus_signal = score_to_signal(weighted_signal)

            # Format magnitude
            if abs(weighted_magnitude) < 0.5:
                magnitude_str = "~0%"
            elif weighted_magnitude > 0:
                magnitude_str = f"+{weighted_magnitude:.0f}%"
            else:
                magnitude_str = f"{weighted_magnitude:.0f}%"

            consensus[asset_id] = {
                "signal": consensus_signal,
                "signal_score": round(weighted_signal, 3),
                "magnitude": magnitude_str,
                "magnitude_pct": round(weighted_magnitude, 1),
                "confidence": round(weighted_confidence, 3),
                "confidence_label": confidence_label,
                "n_scenarios": len(data_points),
            }

        return consensus

    def compute_uncertainty_flag(self, scenario_paths: list[dict]) -> str:
        """
        Détermine le niveau d'incertitude global de l'arbre.

        LOW: scénario dominant > 60%
        MEDIUM: dominant 40-60%
        HIGH: dominant 25-40%
        EXTREME: dominant < 25%
        """
        if not scenario_paths:
            return "HIGH"

        probs = [p.get("probability_path", 0.0) for p in scenario_paths]
        max_prob = max(probs) if probs else 0.0

        if max_prob >= 0.60:
            return "LOW"
        elif max_prob >= 0.40:
            return "MEDIUM"
        elif max_prob >= 0.25:
            return "HIGH"
        else:
            return "EXTREME"

    def compute_revision_factors(self, scenario_paths: list[dict], cat_id: str, subtype_id: str) -> list[str]:
        """
        Identifie les facteurs de révision clés (variables à surveiller).
        """
        REVISION_FACTORS = {
            "CAT-06": {
                "military_conflict": [
                    "Décision OPEC+ compensation de l'offre",
                    "Réponse diplomatique US/GCC sous 48h",
                    "Activation ou non des proxies iraniens (Hezbollah, Houthis)",
                    "Niveau des stocks pétroliers OCDE (buffer capacity)",
                    "Décision de l'administration US sur les frappes de suivi",
                ],
                "trade_war_escalation": [
                    "Calendrier des pourparlers bilatéraux",
                    "Réponse OPEC+ sur la production",
                    "Réaction des marchés financiers chinois",
                    "Degré de compliance alliés US avec les sanctions",
                ],
                "sanctions_imposed": [
                    "Compliance des alliés avec les sanctions",
                    "Contournements via pays tiers (Inde, Turquie, EAU)",
                    "Réponse financière du pays sanctionné (réserves FX)",
                    "Impact sur les flux énergétiques globaux",
                ],
                "energy_supply_shock": [
                    "Volume de capacité de remplacement disponible (OPEC+, IEA stocks)",
                    "Durée estimée de la perturbation",
                    "Réponse des banques centrales (transitory vs persistent narrative)",
                    "Décision gouvernements sur les prix plafonnés",
                ],
            },
            "CAT-08": {
                "oil_price_surge": [
                    "Décision OPEC+ (cut ou compensation)",
                    "Réponse de la production US shale",
                    "Libération des réserves stratégiques (SPR/IEA)",
                    "Dynamique de la demande Chine/Asie émergente",
                ],
                "opec_decision": [
                    "Respect des quotas par la Russie et l'Irak",
                    "Production shale US en réponse",
                    "Niveau de la demande mondiale",
                    "Prochaine réunion OPEC+ (date, agenda)",
                ],
            },
            "CAT-05": {
                "bank_failure": [
                    "Intervention de la FDIC / BCE / autorités de résolution",
                    "Contagion interbancaire (indicateurs: spreads OIS-Libor)",
                    "Décision BC sur les taux directeurs en urgence",
                    "Flux des dépôts (bank run vs stabilisation)",
                ],
                "sovereign_debt_stress": [
                    "Négociation programme FMI (délai, conditions)",
                    "Vote budgétaire parlement national",
                    "Spread de taux souverains (10Y vs Bund)",
                    "Élections et changement politique potentiel",
                ],
            },
        }

        cat_factors = REVISION_FACTORS.get(cat_id, {})
        subtype_factors = cat_factors.get(subtype_id, [])

        if not subtype_factors:
            # Facteurs génériques
            subtype_factors = [
                "Évolution des indicateurs économiques clés",
                "Réponse des banques centrales",
                "Développements géopolitiques",
                "Sentiment de marché et flux d'actifs",
            ]

        return subtype_factors

    def _parse_magnitude(self, magnitude_str: str) -> float:
        """Parse une magnitude comme '+30%' en float 30.0."""
        if not magnitude_str or magnitude_str in ("—", "~0%", "0%"):
            return 0.0
        try:
            cleaned = magnitude_str.replace("%", "").replace("+", "").strip()
            return float(cleaned)
        except (ValueError, AttributeError):
            return 0.0

    def aggregate(self, tree_id: str, scenario_paths: list[dict], event: dict) -> dict:
        """
        Agrégation complète d'un arbre de scénarios.

        Returns:
            {
                dominant_scenario: path_id,
                dominant_probability: float,
                consensus_asset_impacts: dict,
                uncertainty_flag: str,
                revision_factors: list[str],
            }
        """
        dominant, dominant_prob = self.compute_dominant_scenario(scenario_paths)
        consensus = self.compute_consensus_asset_impacts(scenario_paths)
        uncertainty = self.compute_uncertainty_flag(scenario_paths)
        revision_factors = self.compute_revision_factors(
            scenario_paths,
            event.get("cat_id", ""),
            event.get("subtype_id", ""),
        )

        return {
            "tree_id": tree_id,
            "dominant_scenario": dominant.get("path_id") if dominant else None,
            "dominant_probability": round(dominant_prob, 4),
            "consensus_asset_impacts": consensus,
            "uncertainty_flag": uncertainty,
            "revision_factors": revision_factors,
            "total_scenarios": len(scenario_paths),
        }


if __name__ == "__main__":
    # Test rapide
    print("=== Scenario Aggregator Test ===\n")

    # Scénarios fictifs
    paths = [
        {
            "path_id": "S1",
            "label": "Choc pétrolier sévère",
            "probability_path": 0.28,
            "terminal_asset_summary": {
                "oil_wti": {"signal": "strongly_bullish", "magnitude": "+40%", "confidence": 0.70},
                "gold": {"signal": "bullish", "magnitude": "+15%", "confidence": 0.75},
                "equities_us": {"signal": "strongly_bearish", "magnitude": "-15%", "confidence": 0.65},
                "em_fx": {"signal": "strongly_bearish", "magnitude": "-10%", "confidence": 0.60},
            },
        },
        {
            "path_id": "S2",
            "label": "Spike court terme",
            "probability_path": 0.45,
            "terminal_asset_summary": {
                "oil_wti": {"signal": "bullish", "magnitude": "+12%", "confidence": 0.80},
                "gold": {"signal": "bullish", "magnitude": "+5%", "confidence": 0.80},
                "equities_us": {"signal": "slightly_bearish", "magnitude": "-3%", "confidence": 0.75},
                "em_fx": {"signal": "slightly_bearish", "magnitude": "-3%", "confidence": 0.70},
            },
        },
        {
            "path_id": "S3",
            "label": "Escalade régionale",
            "probability_path": 0.15,
            "terminal_asset_summary": {
                "oil_wti": {"signal": "strongly_bullish", "magnitude": "+60%", "confidence": 0.55},
                "gold": {"signal": "strongly_bullish", "magnitude": "+22%", "confidence": 0.60},
                "equities_us": {"signal": "strongly_bearish", "magnitude": "-25%", "confidence": 0.55},
                "em_fx": {"signal": "strongly_bearish", "magnitude": "-18%", "confidence": 0.50},
            },
        },
        {
            "path_id": "S4",
            "label": "Désescalade rapide",
            "probability_path": 0.12,
            "terminal_asset_summary": {
                "oil_wti": {"signal": "slightly_bullish", "magnitude": "+4%", "confidence": 0.85},
                "gold": {"signal": "slightly_bullish", "magnitude": "+2%", "confidence": 0.85},
                "equities_us": {"signal": "slightly_bullish", "magnitude": "+1%", "confidence": 0.85},
            },
        },
    ]

    event = {"cat_id": "CAT-06", "subtype_id": "military_conflict"}
    aggregator = ScenarioAggregator()

    result = aggregator.aggregate("test-tree-id", paths, event)
    print(f"Dominant scenario: {result['dominant_scenario']} (P={result['dominant_probability']:.0%})")
    print(f"Uncertainty: {result['uncertainty_flag']}")
    print("\nConsensus asset impacts:")
    for asset, impact in result["consensus_asset_impacts"].items():
        print(f"  {asset}: {impact['signal']} {impact['magnitude']} (confidence: {impact['confidence_label']})")
    print(f"\nRevision factors ({len(result['revision_factors'])} total):")
    for f in result["revision_factors"][:3]:
        print(f"  - {f}")
