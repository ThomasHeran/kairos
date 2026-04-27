"""
Test end-to-end: "US strikes Iran" → arbre complet → rapport Markdown
Utilise le moteur sans base de données (mode standalone).
"""

import sys
import os
import uuid
import json

# Add repo root to Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from engine.scenario_tree_engine import ScenarioTreeEngine
from engine.scenario_report_generator import generate_full_report
from engine.probability_calibrator import is_high_uncertainty


def test_high_uncertainty_detection():
    """Test 1: Détection HIGH_UNCERTAINTY."""
    print("=== Test 1: HIGH_UNCERTAINTY detection ===")

    assert is_high_uncertainty("CAT-06", 0.90) is True, "CAT-06 + 0.90 doit être HIGH_UNCERTAINTY"
    assert is_high_uncertainty("CAT-08", 0.80) is True, "CAT-08 + 0.80 doit être HIGH_UNCERTAINTY"
    assert is_high_uncertainty("CAT-05", 0.76) is True, "CAT-05 + 0.76 doit être HIGH_UNCERTAINTY"
    assert is_high_uncertainty("CAT-01", 0.90) is False, "CAT-01 ne doit pas être HIGH_UNCERTAINTY"
    assert is_high_uncertainty("CAT-06", 0.50) is False, "Importance < 0.75 ne doit pas déclencher"
    assert is_high_uncertainty("CAT-06", 0.50, has_unverified_conditions=True) is True, "Conditions non vérifiées doit déclencher"

    print("  ✅ Tous les tests HIGH_UNCERTAINTY passent\n")


def test_tree_generation():
    """Test 2: Génération de l'arbre de scénarios."""
    print("=== Test 2: Génération arbre 'US strikes Iran' ===")

    event = {
        "event_id": str(uuid.uuid4()),
        "cat_id": "CAT-06",
        "subtype_id": "military_conflict",
        "importance_score": 0.92,
        "confidence": 0.85,
        "geography": ["MIDDLE_EAST", "IRAN", "GLOBAL"],
        "text_en_canonical": "US launches military strikes against Iran — targeted attacks on nuclear and military facilities",
        "source_name": "Reuters / AP",
        "actors": ["United States", "Iran", "CENTCOM"],
        "assets_mentioned": ["oil", "gold", "US Treasuries"],
        "horizon": "immediate",
    }

    engine = ScenarioTreeEngine(macro_context={
        "oil_price_level": "high",
        "diplomatic_context": "hostile",
        "vix_level": "high",
        "us_rates_stance": "holding",
        "growth_regime": "moderate",
        "inflation_regime": "above_target",
    })

    tree = engine.generate_without_db(event, max_depth=3, min_probability=0.03)

    # Assertions
    assert tree.get("status") == "complete", f"Status doit être 'complete', got: {tree.get('status')}"
    assert tree.get("tree_id"), "tree_id manquant"
    assert tree.get("root_node_id"), "root_node_id manquant"
    assert len(tree.get("scenario_paths", [])) >= 2, f"Au moins 2 chemins attendus, got: {len(tree.get('scenario_paths', []))}"
    assert tree.get("consensus_asset_impacts"), "consensus_asset_impacts manquant"
    assert tree.get("uncertainty_flag") in ("LOW", "MEDIUM", "HIGH", "EXTREME"), "uncertainty_flag invalide"
    assert tree.get("dominant_scenario"), "dominant_scenario manquant"

    # Vérifier que les probabilités des chemins somment à environ 1.0 (pruning peut en enlever)
    total_prob = sum(p.get("probability_path", 0.0) for p in tree["scenario_paths"])
    assert total_prob <= 1.01, f"Somme des probabilités > 1.0: {total_prob}"
    assert total_prob >= 0.50, f"Somme des probabilités trop faible (trop de pruning): {total_prob}"

    print(f"  ✅ Arbre généré: {len(tree['scenario_paths'])} scénarios")
    print(f"  📊 Uncertainty: {tree['uncertainty_flag']}")
    print(f"  🎯 Dominant: {tree['dominant_scenario']} (P={tree['dominant_probability']:.0%})")
    print(f"  💰 Somme P_paths: {total_prob:.2%}\n")

    return tree, event


def test_scenario_paths(tree: dict):
    """Test 3: Validation des chemins de scénarios."""
    print("=== Test 3: Validation des scénarios ===")

    paths = tree.get("scenario_paths", [])
    assert len(paths) >= 2, "Au moins 2 scénarios attendus"

    for path in paths:
        assert path.get("path_id"), "path_id manquant"
        assert path.get("label"), "label manquant"
        prob = path.get("probability_path", 0.0)
        assert 0 < prob <= 1.0, f"Probabilité invalide: {prob}"
        assert path.get("terminal_node_id"), "terminal_node_id manquant"
        assert path.get("terminal_asset_summary"), "terminal_asset_summary manquant"

    # Triés par probabilité décroissante
    probs = [p["probability_path"] for p in paths]
    assert probs == sorted(probs, reverse=True), "Chemins non triés par probabilité"

    print(f"  ✅ {len(paths)} scénarios validés")
    for path in paths[:3]:
        print(f"  📍 {path['path_id']} [{path['probability_path']:.0%}]: {path['label']}")
    print()


def test_consensus(tree: dict):
    """Test 4: Validation du consensus."""
    print("=== Test 4: Consensus pondéré ===")

    consensus = tree.get("consensus_asset_impacts", {})
    assert consensus, "Consensus vide"
    assert "oil_wti" in consensus or "equities_us" in consensus, "Actifs clés manquants dans le consensus"

    for asset, impact in consensus.items():
        signal = impact.get("signal", "")
        assert signal in (
            "strongly_bullish", "bullish", "slightly_bullish", "mixed",
            "slightly_bearish", "bearish_mixed", "bearish", "strongly_bearish"
        ), f"Signal invalide pour {asset}: {signal}"

    print(f"  ✅ Consensus calculé pour {len(consensus)} actifs")
    for asset, impact in list(consensus.items())[:4]:
        print(f"  📊 {asset}: {impact['signal']} {impact.get('magnitude', '?')} ({impact.get('confidence_label', '?')})")
    print()


def test_report_generation(tree: dict, event: dict):
    """Test 5: Génération du rapport Markdown."""
    print("=== Test 5: Rapport Markdown ===")

    report = generate_full_report(tree, event, use_llm=False)  # use_llm=False pour le test

    assert report, "Rapport vide"
    assert "SCENARIO ANALYSIS" in report, "Header manquant"
    assert "🌳" in report, "Section scénarios manquante"
    assert "⚖️" in report, "Section consensus manquante"
    assert "⚠️" in report, "Section facteurs de révision manquante"

    # Vérifier que tous les scénarios sont présents
    paths = tree.get("scenario_paths", [])
    for path in paths[:3]:
        path_id = path["path_id"]
        assert path_id in report, f"Scénario {path_id} manquant dans le rapport"

    print(f"  ✅ Rapport généré: {len(report)} caractères, {report.count(chr(10))} lignes")
    print(f"  📄 Aperçu (50 premières lignes):\n")
    for line in report.split("\n")[:50]:
        print(f"    {line}")
    print()

    return report


def test_calibration_lookup():
    """Test 6: Lookup table des calibrations."""
    print("=== Test 6: Calibration lookup ===")

    from engine.probability_calibrator import (
        find_best_calibration,
        get_calibrations,
        ContextualAdjustment,
    )

    data = get_calibrations()
    assert "calibrations" in data, "Clé 'calibrations' manquante"
    assert len(data["calibrations"]) >= 10, f"Attendu ≥10 calibrations, got: {len(data['calibrations'])}"

    # Test match exact
    cal = find_best_calibration("CAT-06", "military_conflict", ["MIDDLE_EAST", "IRAN"])
    assert cal, "Calibration pour military_conflict manquante"
    assert len(cal["branches"]) >= 2, "Au moins 2 branches attendues"

    # Test probabilités normalisées
    branches = cal["branches"]
    adjuster = ContextualAdjustment({"diplomatic_context": "hostile"})
    adjusted = adjuster.adjust_branch_probabilities(branches)
    total = sum(b["p_adjusted"] for b in adjusted)
    assert abs(total - 1.0) < 0.01, f"Probabilités ne somment pas à 1.0: {total}"

    print(f"  ✅ {len(data['calibrations'])} calibrations chargées")
    print(f"  ✅ Calibration hormuz: {cal['bifurcation_id']}")
    print(f"  ✅ Normalisation: {total:.4f} ≈ 1.0\n")


def test_pruning():
    """Test 7: Élagage des branches."""
    print("=== Test 7: Pruning ===")

    from engine.probability_calibrator import should_prune

    assert should_prune(0.02) is True, "P=0.02 doit être pruned"
    assert should_prune(0.04) is False, "P=0.04 ne doit pas être pruned"
    assert should_prune(0.05, max_driver_coefficient=0.05) is True, "Coefficient < 0.10 doit être pruned"
    assert should_prune(0.05, max_driver_coefficient=0.15) is False, "Coefficient ≥ 0.10 ne doit pas être pruned"

    print("  ✅ Règles de pruning correctes\n")


def main():
    print("=" * 60)
    print("KAIROS — Scenario Tree Engine — Test End-to-End")
    print("Event: US strikes Iran (military attack)")
    print("=" * 60)
    print()

    tests_passed = 0
    tests_total = 7

    try:
        test_high_uncertainty_detection()
        tests_passed += 1
    except AssertionError as e:
        print(f"  ❌ FAILED: {e}\n")

    try:
        tree, event = test_tree_generation()
        tests_passed += 1
    except AssertionError as e:
        print(f"  ❌ FAILED: {e}\n")
        sys.exit(1)

    try:
        test_scenario_paths(tree)
        tests_passed += 1
    except AssertionError as e:
        print(f"  ❌ FAILED: {e}\n")

    try:
        test_consensus(tree)
        tests_passed += 1
    except AssertionError as e:
        print(f"  ❌ FAILED: {e}\n")

    try:
        report = test_report_generation(tree, event)
        tests_passed += 1
    except AssertionError as e:
        print(f"  ❌ FAILED: {e}\n")

    try:
        test_calibration_lookup()
        tests_passed += 1
    except AssertionError as e:
        print(f"  ❌ FAILED: {e}\n")

    try:
        test_pruning()
        tests_passed += 1
    except AssertionError as e:
        print(f"  ❌ FAILED: {e}\n")

    print("=" * 60)
    print(f"RÉSULTATS: {tests_passed}/{tests_total} tests passés")
    print("=" * 60)

    if tests_passed == tests_total:
        print("\n🎉 Tous les tests passent — moteur opérationnel!")
    else:
        print(f"\n⚠️  {tests_total - tests_passed} test(s) échoué(s)")
        sys.exit(1)

    # Sauvegarder l'arbre JSON pour référence
    output_path = os.path.join(os.path.dirname(__file__), "test_output_scenario_tree.json")
    with open(output_path, "w", encoding="utf-8") as f:
        # Exclure 'nodes' pour alléger
        tree_export = {k: v for k, v in tree.items() if k != "nodes"}
        json.dump(tree_export, f, ensure_ascii=False, indent=2, default=str)
    print(f"\n📁 Arbre JSON sauvegardé: {output_path}")


if __name__ == "__main__":
    main()
