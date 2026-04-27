"""
Kairos — Scenario Report Generator
=====================================
Génère un rapport Markdown multi-scénarios complet via Anthropic Claude API.

Pour chaque scénario terminal, génère un narratif enrichi.
Produit le rapport final au format défini dans le cahier des charges.
"""

import os
import json
from datetime import datetime, timezone
from typing import Optional

try:
    import anthropic
    HAS_ANTHROPIC = True
except ImportError:
    HAS_ANTHROPIC = False


# ---------------------------------------------------------------------------
# Constantes et mappings
# ---------------------------------------------------------------------------

SIGNAL_EMOJI = {
    "strongly_bullish": "🚀",
    "bullish": "📈",
    "slightly_bullish": "↗️",
    "mixed": "↔️",
    "bearish_mixed": "↘️",
    "slightly_bearish": "↘️",
    "bearish": "📉",
    "strongly_bearish": "⬇️",
}

SIGNAL_LABEL_FR = {
    "strongly_bullish": "BULLISH FORT",
    "bullish": "BULLISH",
    "slightly_bullish": "LÉGÈREMENT BULLISH",
    "mixed": "MIXTE",
    "bearish_mixed": "MIXTE/BAISSIER",
    "slightly_bearish": "LÉGÈREMENT BEARISH",
    "bearish": "BEARISH",
    "strongly_bearish": "BEARISH FORT",
}

SCENARIO_COLORS = {
    0: "🔴",  # S1
    1: "🟡",  # S2
    2: "🔵",  # S3
    3: "🟢",  # S4
    4: "⚪",  # S5+
}

UNCERTAINTY_LABEL = {
    "LOW": "FAIBLE",
    "MEDIUM": "MODÉRÉE",
    "HIGH": "ÉLEVÉE",
    "EXTREME": "EXTRÊME",
}

CONFIDENCE_LABEL = {
    "HIGH": "HAUTE",
    "MODERATE": "MODÉRÉE",
    "LOW": "FAIBLE",
    "VERY_LOW": "TRÈS FAIBLE",
}


# ---------------------------------------------------------------------------
# LLM Narrative Generator
# ---------------------------------------------------------------------------

class LLMNarrativeGenerator:
    """Génère des narratifs enrichis via Anthropic Claude API."""

    def __init__(self, model: str = "claude-haiku-4-5-20251001"):
        self.model = model
        self.client = None
        if HAS_ANTHROPIC:
            api_key = os.environ.get("ANTHROPIC_API_KEY")
            if api_key:
                self.client = anthropic.Anthropic(api_key=api_key)

    def generate_scenario_narrative(
        self,
        scenario_path: dict,
        event: dict,
        nodes: Optional[dict] = None,
    ) -> str:
        """
        Génère un narratif pour un scénario terminal.

        Si l'API Anthropic est disponible → appel LLM.
        Sinon → narratif basé sur les données structurées.
        """
        if self.client:
            return self._generate_via_llm(scenario_path, event)
        else:
            return self._generate_fallback_narrative(scenario_path, event)

    def _generate_via_llm(self, scenario_path: dict, event: dict) -> str:
        """Génère le narratif via Claude API."""
        path_label = scenario_path.get("label", "")
        probability = scenario_path.get("probability_path", 0.0)
        asset_summary = scenario_path.get("terminal_asset_summary", {})
        event_label = event.get("text_en_canonical", "")

        asset_lines = []
        for asset, impact in asset_summary.items():
            asset_lines.append(f"- {asset}: {impact.get('signal', 'mixed')} {impact.get('magnitude', '')}")

        prompt = f"""Tu es un analyste macro senior chez Kairos. Génère un narratif analytique concis (3-4 phrases, max 120 mots) pour le scénario suivant.

Event déclencheur: {event_label}
Scénario: {path_label} (probabilité: {probability:.0%})

Impacts actifs finaux:
{chr(10).join(asset_lines)}

Le narratif doit:
1. Expliquer la chaîne causale logique qui mène à ces impacts
2. Mentionner les mécanismes macro clés (inflation, BC, demande, etc.)
3. Être rédigé en français, ton analytique, sans jargon excessif
4. Ne pas répéter les chiffres de probabilité

Narratif:"""

        try:
            response = self.client.messages.create(
                model=self.model,
                max_tokens=200,
                messages=[{"role": "user", "content": prompt}]
            )
            return response.content[0].text.strip()
        except Exception as e:
            return self._generate_fallback_narrative(scenario_path, event)

    def _generate_fallback_narrative(self, scenario_path: dict, event: dict) -> str:
        """Narratif de fallback basé sur les données structurées."""
        label = scenario_path.get("label", "Scénario terminal")
        asset_summary = scenario_path.get("terminal_asset_summary", {})

        bullish = [k for k, v in asset_summary.items() if "bullish" in v.get("signal", "")]
        bearish = [k for k, v in asset_summary.items() if "bearish" in v.get("signal", "")]

        parts = [f"Dans ce scénario ({label}),"]

        if bullish:
            bullish_str = ", ".join(bullish[:2])
            parts.append(f"les actifs refuge ({bullish_str}) bénéficient de la fuite vers la qualité.")

        if bearish:
            bearish_str = ", ".join(bearish[:2])
            parts.append(f"Les actifs risqués ({bearish_str}) sont sous pression en raison de l'incertitude accrue.")

        parts.append(
            f"Ce scénario se réalise si les conditions de déclenchement ({scenario_path.get('probability_path', 0.0):.0%} de probabilité) sont remplies."
        )

        return " ".join(parts)


# ---------------------------------------------------------------------------
# Report Generator principal
# ---------------------------------------------------------------------------

class ScenarioReportGenerator:
    """
    Génère le rapport Markdown complet d'un arbre de scénarios.
    """

    def __init__(self, use_llm: bool = True):
        self.llm = LLMNarrativeGenerator() if use_llm else None

    def generate_report(self, tree_data: dict, event: dict) -> str:
        """
        Génère le rapport Markdown complet.

        Args:
            tree_data: ScenarioTree dict (output de ScenarioTreeEngine)
            event: event C2 dict

        Returns:
            Rapport Markdown formaté
        """
        lines = []

        # Header
        lines.extend(self._build_header(tree_data, event))

        # Event section
        lines.extend(self._build_event_section(event))

        # Scenario tree section
        lines.extend(self._build_scenarios_section(tree_data, event))

        # Consensus section
        lines.extend(self._build_consensus_section(tree_data))

        # Revision factors
        lines.extend(self._build_revision_factors_section(tree_data))

        return "\n".join(lines)

    def generate_narratives(self, tree_data: dict, event: dict) -> dict:
        """
        Génère les narratifs LLM pour chaque scénario terminal.

        Returns: {path_id: narrative_text}
        """
        narratives = {}
        for path in tree_data.get("scenario_paths", []):
            path_id = path["path_id"]
            if self.llm:
                narrative = self.llm.generate_scenario_narrative(path, event)
            else:
                narrative = path.get("narrative_terminal", "")
            narratives[path_id] = narrative
        return narratives

    # -------------------------------------------------------------------------
    # Section builders
    # -------------------------------------------------------------------------

    def _build_header(self, tree_data: dict, event: dict) -> list[str]:
        event_label = tree_data.get("event_label", "Unknown Event").upper()
        generated_at = tree_data.get("generated_at", datetime.now(timezone.utc).isoformat())
        try:
            dt = datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
            date_str = dt.strftime("%Y-%m-%d %H:%M UTC")
        except Exception:
            date_str = generated_at

        uncertainty = tree_data.get("uncertainty_flag", "HIGH")
        uncertainty_fr = UNCERTAINTY_LABEL.get(uncertainty, uncertainty)
        n_scenarios = tree_data.get("total_scenarios", 0)

        return [
            f"# SCENARIO ANALYSIS — {event_label}",
            f"*Généré: {date_str} | Scénarios: {n_scenarios} | Incertitude: {uncertainty_fr}*",
            "",
            "---",
            "",
        ]

    def _build_event_section(self, event: dict) -> list[str]:
        event_text = event.get("text_en_canonical", "Event non spécifié")
        cat_id = event.get("cat_id", "?")
        subtype_id = event.get("subtype_id", "?")
        source = event.get("source_name", "Source inconnue")
        geography = ", ".join(event.get("geography", []) or [])
        importance = float(event.get("importance_score", 0.0))

        lines = [
            "## 📍 Événement déclencheur",
            "",
            f"**{event_text}**",
            "",
            f"- **Classification**: `{cat_id}` / `{subtype_id}`",
            f"- **Source**: {source}",
        ]
        if geography:
            lines.append(f"- **Géographie**: {geography}")
        lines.append(f"- **Importance**: {importance:.0%}")
        lines.extend(["", "---", ""])
        return lines

    def _build_scenarios_section(self, tree_data: dict, event: dict) -> list[str]:
        paths = tree_data.get("scenario_paths", [])
        n_primary = min(len(paths), 4)  # Afficher max 4 scénarios principaux

        lines = [
            f"## 🌳 Arbre de scénarios — {n_primary} branches principales",
            "",
        ]

        for i, path in enumerate(paths[:n_primary]):
            lines.extend(self._build_single_scenario(path, i, event))

        if len(paths) > n_primary:
            remaining = len(paths) - n_primary
            lines.extend([
                f"*{remaining} scénario(s) additionnel(s) disponible(s) via l'API.*",
                "",
            ])

        lines.extend(["---", ""])
        return lines

    def _build_single_scenario(self, path: dict, index: int, event: dict) -> list[str]:
        color = SCENARIO_COLORS.get(index, "⚪")
        path_id = path["path_id"]
        label = path["label"]
        prob = path.get("probability_path", 0.0)
        asset_summary = path.get("terminal_asset_summary", {})
        narrative = path.get("narrative_terminal", "")

        lines = [
            f"### {color} SCÉNARIO {path_id} — {label} [P = {prob:.0%}]",
            "",
        ]

        # Asset impacts
        if asset_summary:
            lines.append("**Impacts actifs terminaux :**")
            lines.append("")
            for asset_id, impact in asset_summary.items():
                signal = impact.get("signal", "mixed")
                emoji = SIGNAL_EMOJI.get(signal, "↔️")
                label_fr = SIGNAL_LABEL_FR.get(signal, signal.upper())
                magnitude = impact.get("magnitude", impact.get("magnitude_central", ""))
                horizon = impact.get("horizon", "")

                asset_display = asset_id.replace("_", " ").upper()
                magnitude_str = f" {magnitude}" if magnitude else ""
                horizon_str = f" ({horizon})" if horizon else ""
                lines.append(f"- {emoji} **{asset_display}** : {label_fr}{magnitude_str}{horizon_str}")

            lines.append("")

        # Narratif
        if narrative:
            lines.extend([
                "**Narratif :**",
                "",
                f"*{narrative}*",
                "",
            ])

        lines.append("")
        return lines

    def _build_consensus_section(self, tree_data: dict) -> list[str]:
        consensus = tree_data.get("consensus_asset_impacts", {})
        if not consensus:
            return []

        lines = [
            "## ⚖️ CONSENSUS PONDÉRÉ (tous scénarios)",
            "",
            "| Actif | Signal | Magnitude | Confiance |",
            "|-------|--------|-----------|-----------|",
        ]

        for asset_id, impact in consensus.items():
            signal = impact.get("signal", "mixed")
            signal_label = SIGNAL_LABEL_FR.get(signal, signal.upper())
            magnitude = impact.get("magnitude", "—")
            confidence_label = impact.get("confidence_label", "MODERATE")
            confidence_fr = CONFIDENCE_LABEL.get(confidence_label, confidence_label)

            asset_display = asset_id.replace("_", " ").upper()
            lines.append(f"| {asset_display} | {signal_label} | {magnitude} | {confidence_fr} |")

        lines.extend(["", "---", ""])
        return lines

    def _build_revision_factors_section(self, tree_data: dict) -> list[str]:
        factors = tree_data.get("revision_factors", [])
        if not factors:
            return []

        dominant_id = tree_data.get("dominant_scenario")
        dominant_prob = tree_data.get("dominant_probability", 0.0)
        uncertainty = tree_data.get("uncertainty_flag", "HIGH")

        lines = [
            "## ⚠️ FACTEURS DE RÉVISION",
            f"*Variables clés à surveiller. Scénario dominant actuel: **{dominant_id}** (P={dominant_prob:.0%}). Incertitude: {uncertainty}*",
            "",
        ]

        for factor in factors:
            lines.append(f"- {factor}")

        lines.extend(["", "---", ""])

        # Note méthodologique
        lines.extend([
            "## 📌 Note méthodologique",
            "",
            f"- Arbre généré le {tree_data.get('generated_at', '?')[:10]}",
            f"- Profondeur max: {tree_data.get('max_depth', 4)} | Seuil pruning: {tree_data.get('min_probability', 0.03):.0%}",
            f"- Scénarios totaux: {tree_data.get('total_scenarios', 0)}",
            f"- Calibration: `probability_calibrations_v1.json`",
            "",
        ])

        return lines


# ---------------------------------------------------------------------------
# Fonctions utilitaires
# ---------------------------------------------------------------------------

def generate_full_report(tree_data: dict, event: dict, use_llm: bool = True) -> str:
    """Point d'entrée simplifié pour générer le rapport complet."""
    gen = ScenarioReportGenerator(use_llm=use_llm)

    # Générer les narratifs LLM si disponible
    if use_llm and gen.llm:
        narratives = gen.generate_narratives(tree_data, event)
        # Injecter les narratifs dans les paths
        for path in tree_data.get("scenario_paths", []):
            path_id = path["path_id"]
            if path_id in narratives:
                path["narrative_terminal"] = narratives[path_id]

    return gen.generate_report(tree_data, event)


if __name__ == "__main__":
    # Test avec données fictives
    print("=== Scenario Report Generator Test ===\n")

    event = {
        "event_id": "test-001",
        "cat_id": "CAT-06",
        "subtype_id": "military_conflict",
        "importance_score": 0.92,
        "confidence": 0.85,
        "geography": ["MIDDLE_EAST", "IRAN", "GLOBAL"],
        "text_en_canonical": "US launches military strikes against Iran — targeted attacks on nuclear facilities",
        "source_name": "Reuters",
        "actors": ["United States", "Iran"],
    }

    tree_data = {
        "tree_id": "tree-001",
        "event_id": "test-001",
        "event_label": "US strikes Iran — military attack",
        "cat_id": "CAT-06",
        "subtype_id": "military_conflict",
        "generated_at": "2026-04-27T14:32:00+00:00",
        "total_scenarios": 3,
        "max_depth": 4,
        "min_probability": 0.03,
        "dominant_scenario": "S2",
        "dominant_probability": 0.45,
        "uncertainty_flag": "HIGH",
        "revision_factors": [
            "Décision OPEC+ compensation de l'offre",
            "Réponse diplomatique US/GCC sous 48h",
            "Activation ou non des proxies iraniens (Hezbollah, Houthis)",
            "Niveau des stocks pétroliers OCDE (buffer capacity)",
        ],
        "consensus_asset_impacts": {
            "oil_wti": {"signal": "bullish", "magnitude": "+18%", "confidence": 0.65, "confidence_label": "MODERATE"},
            "gold": {"signal": "bullish", "magnitude": "+9%", "confidence": 0.75, "confidence_label": "HIGH"},
            "equities_us": {"signal": "bearish", "magnitude": "-6%", "confidence": 0.60, "confidence_label": "MODERATE"},
            "em_fx": {"signal": "bearish", "magnitude": "-5%", "confidence": 0.55, "confidence_label": "MODERATE"},
            "bonds_sovereign_us": {"signal": "mixed", "magnitude": "—", "confidence": 0.40, "confidence_label": "LOW"},
        },
        "scenario_paths": [
            {
                "path_id": "S1",
                "label": "Choc pétrolier sévère + stagflation",
                "probability_path": 0.28,
                "terminal_asset_summary": {
                    "oil_wti": {"signal": "strongly_bullish", "magnitude": "+40%"},
                    "gold": {"signal": "bullish", "magnitude": "+15%"},
                    "equities_us": {"signal": "strongly_bearish", "magnitude": "-15%"},
                    "bonds_sovereign_us": {"signal": "bearish_mixed", "magnitude": "-3%"},
                    "em_fx": {"signal": "strongly_bearish", "magnitude": "-10%"},
                },
                "narrative_terminal": "Perturbation prolongée du Détroit d'Hormuz entraîne un choc pétrolier de type 1973. L'inflation importée force les banques centrales en configuration stagflationniste, comprimant les multiples de valorisation et dépréciant les devises EM exposées.",
            },
            {
                "path_id": "S2",
                "label": "Spike court terme — résolution rapide",
                "probability_path": 0.45,
                "terminal_asset_summary": {
                    "oil_wti": {"signal": "bullish", "magnitude": "+12%"},
                    "gold": {"signal": "bullish", "magnitude": "+5%"},
                    "equities_us": {"signal": "slightly_bearish", "magnitude": "-3%"},
                    "em_fx": {"signal": "slightly_bearish", "magnitude": "-3%"},
                },
                "narrative_terminal": "Conflit court et limité entraîne un spike transitoire du pétrole. La présence navale US dissuade toute fermeture du Détroit. Les banques centrales maintiennent leur posture, le marché retrouve la stabilité sous 3-4 semaines.",
            },
            {
                "path_id": "S3",
                "label": "Escalade régionale majeure",
                "probability_path": 0.15,
                "terminal_asset_summary": {
                    "oil_wti": {"signal": "strongly_bullish", "magnitude": "+60%"},
                    "gold": {"signal": "strongly_bullish", "magnitude": "+22%"},
                    "equities_us": {"signal": "strongly_bearish", "magnitude": "-25%"},
                    "em_fx": {"signal": "strongly_bearish", "magnitude": "-18%"},
                },
                "narrative_terminal": "L'Iran engage ses proxies régionaux (Hezbollah, Houthis) et ferme le Détroit d'Hormuz. La crise se régionalise avec implication israélienne. Le choc systémique global déclenche une crise financière EM et un flight to quality massif.",
            },
        ],
    }

    report = generate_full_report(tree_data, event, use_llm=False)
    print(report)
