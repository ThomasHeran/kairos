"""
Kairos — Scenario Tree Engine
================================
Moteur principal du générateur d'arbres de scénarios probabilistes.

Pipeline:
1. Vérifie si l'event est HIGH_UNCERTAINTY
2. Crée le nœud racine
3. Génère récursivement les branches jusqu'à max_depth
4. Élague les branches sous min_probability
5. Extrait les chemins root→feuille (scenario_paths)
6. Calcule les impacts terminaux pour chaque chemin
7. Agrège (consensus, dominant, uncertainty)
8. Sauvegarde dans PostgreSQL
9. Retourne le ScenarioTree JSON complet
"""

import os
import uuid
import json
import time
from datetime import datetime, timezone
from typing import Optional
import psycopg2
import psycopg2.extras

from engine.probability_calibrator import is_high_uncertainty
from engine.branch_generator import BranchGenerator, generate_root_node
from engine.scenario_aggregator import ScenarioAggregator


# ---------------------------------------------------------------------------
# DB connection
# ---------------------------------------------------------------------------

def get_db_connection():
    """Retourne une connexion PostgreSQL via DATABASE_URL."""
    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL environment variable not set")
    return psycopg2.connect(database_url)


# ---------------------------------------------------------------------------
# Scenario Tree Engine
# ---------------------------------------------------------------------------

class ScenarioTreeEngine:
    """
    Moteur principal de génération d'arbres de scénarios.

    Usage:
        engine = ScenarioTreeEngine()
        tree = engine.generate(event_id="...", max_depth=4, min_probability=0.03)
    """

    def __init__(self, macro_context: Optional[dict] = None):
        self.macro_context = macro_context or {}
        self.branch_gen = BranchGenerator(macro_context)
        self.aggregator = ScenarioAggregator()

    # -------------------------------------------------------------------------
    # Public API
    # -------------------------------------------------------------------------

    def generate(
        self,
        event_id: str,
        max_depth: int = 4,
        min_probability: float = 0.03,
        force: bool = False,
    ) -> dict:
        """
        Génère l'arbre de scénarios pour un event donné.

        Args:
            event_id: UUID de l'event C2
            max_depth: profondeur maximale de l'arbre
            min_probability: seuil de pruning cumulatif
            force: forcer la génération même si non HIGH_UNCERTAINTY

        Returns:
            ScenarioTree dict complet
        """
        start_time = time.time()

        conn = get_db_connection()
        try:
            event = self._fetch_event(conn, event_id)
            if not event:
                raise ValueError(f"Event {event_id} not found in database")

            # Vérification HIGH_UNCERTAINTY
            cat_id = event.get("cat_id", "")
            importance = float(event.get("importance_score", 0.0))
            is_uncertain = is_high_uncertainty(cat_id, importance) or force

            if not is_uncertain:
                return {
                    "status": "skipped",
                    "reason": "Event does not meet HIGH_UNCERTAINTY criteria",
                    "event_id": event_id,
                    "cat_id": cat_id,
                    "importance_score": importance,
                    "recommendation": "Use linear C4 pipeline instead",
                }

            # Générer l'arbre
            tree_id = str(uuid.uuid4())
            tree_data = self._build_tree(tree_id, event, max_depth, min_probability)

            # Sauvegarder dans DB
            tree_record = self._save_tree(conn, tree_data, event, max_depth, min_probability)

            processing_ms = int((time.time() - start_time) * 1000)
            tree_record["processing_time_ms"] = processing_ms

            conn.commit()
            return tree_record

        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    def generate_without_db(
        self,
        event: dict,
        max_depth: int = 4,
        min_probability: float = 0.03,
    ) -> dict:
        """
        Génère l'arbre sans connexion DB (mode standalone / test).

        event: dict avec cat_id, subtype_id, importance_score, geography, etc.
        """
        tree_id = str(uuid.uuid4())
        return self._build_tree(tree_id, event, max_depth, min_probability)

    # -------------------------------------------------------------------------
    # Core logic
    # -------------------------------------------------------------------------

    def _build_tree(
        self,
        tree_id: str,
        event: dict,
        max_depth: int,
        min_probability: float,
    ) -> dict:
        """Construction récursive de l'arbre."""
        # 1. Root node
        root_node = generate_root_node(tree_id, event)
        all_nodes = {root_node["node_id"]: root_node}

        # 2. Récursion (BFS)
        queue = [root_node]
        nodes_by_depth = {0: [root_node]}

        current_depth = 1
        while queue and current_depth <= max_depth:
            next_queue = []
            for parent_node in queue:
                if parent_node["is_pruned"]:
                    continue

                children = self.branch_gen.generate_branches(
                    tree_id=tree_id,
                    parent_node=parent_node,
                    event=event,
                    depth=current_depth,
                    max_depth=max_depth,
                    min_probability=min_probability,
                )

                for child in children:
                    child_id = child["node_id"]
                    parent_node["children"].append(child_id)
                    all_nodes[child_id] = child
                    next_queue.append(child)

                # Mark as terminal if no children generated
                if not children:
                    parent_node["is_terminal"] = True

            if current_depth not in nodes_by_depth:
                nodes_by_depth[current_depth] = []
            nodes_by_depth[current_depth].extend(next_queue)

            queue = next_queue
            current_depth += 1

        # 3. Marquer les feuilles comme terminales
        for node in all_nodes.values():
            if not node["children"]:
                node["is_terminal"] = True

        # 4. Extraire les chemins root→feuille
        scenario_paths = self._extract_paths(root_node, all_nodes, event)

        # 5. Agréger
        aggregation = self.aggregator.aggregate(tree_id, scenario_paths, event)

        # 6. Construire le ScenarioTree
        cat_id = event.get("cat_id", "")
        return {
            "tree_id": tree_id,
            "event_id": event.get("event_id", ""),
            "event_label": event.get("text_en_canonical", event.get("event_label", "")),
            "cat_id": cat_id,
            "subtype_id": event.get("subtype_id", ""),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "max_depth": max_depth,
            "min_probability": min_probability,
            "total_scenarios": len(scenario_paths),
            "root_node_id": root_node["node_id"],
            "nodes": all_nodes,
            "scenario_paths": scenario_paths,
            "dominant_scenario": aggregation.get("dominant_scenario"),
            "dominant_probability": aggregation.get("dominant_probability"),
            "consensus_asset_impacts": aggregation.get("consensus_asset_impacts", {}),
            "uncertainty_flag": aggregation.get("uncertainty_flag", "HIGH"),
            "revision_factors": aggregation.get("revision_factors", []),
            "status": "complete",
        }

    def _extract_paths(
        self,
        root_node: dict,
        all_nodes: dict,
        event: dict,
    ) -> list[dict]:
        """
        Extrait tous les chemins root→feuille de l'arbre.
        Chaque chemin = un scénario terminal.
        """
        paths = []
        path_counter = [0]

        def dfs(node: dict, current_path: list[str]):
            current_path = current_path + [node["node_id"]]

            if node["is_terminal"] or not node["children"]:
                # Chemin terminal
                path_counter[0] += 1
                path_id = f"S{path_counter[0]}"

                # Calcul des impacts terminaux (agrégés sur le chemin)
                terminal_summary = self._compute_terminal_summary(current_path, all_nodes)

                # Narratif placeholder (sera remplacé par LLM dans scenario_report_generator)
                narrative = self._build_basic_narrative(node, current_path, all_nodes, event)

                path_data = {
                    "path_id": path_id,
                    "tree_id": root_node.get("tree_id", ""),
                    "label": node["label"],
                    "probability_path": node["probability_cumulative"],
                    "node_ids": current_path,
                    "terminal_node_id": node["node_id"],
                    "terminal_asset_summary": terminal_summary,
                    "narrative_terminal": narrative,
                    "revision_factors": [],  # rempli par aggregator
                    "depth": len(current_path) - 1,
                }
                paths.append(path_data)
            else:
                for child_id in node["children"]:
                    child = all_nodes.get(child_id)
                    if child and not child.get("is_pruned"):
                        dfs(child, current_path)

        dfs(root_node, [])

        # Trier par probabilité décroissante
        paths.sort(key=lambda p: p["probability_path"], reverse=True)

        # Re-numéroter par ordre de probabilité
        for i, path in enumerate(paths, 1):
            path["path_id"] = f"S{i}"

        return paths

    def _compute_terminal_summary(self, path_node_ids: list[str], all_nodes: dict) -> dict:
        """
        Calcule le résumé des impacts actifs pour un chemin terminal.
        Combine les impacts de tous les nœuds du chemin (additivité).
        """
        combined: dict[str, dict] = {}
        SIGNAL_SCORES = {
            "strongly_bullish": 2.0, "bullish": 1.0, "slightly_bullish": 0.5,
            "mixed": 0.0, "slightly_bearish": -0.5, "bearish": -1.0,
            "bearish_mixed": -0.5, "strongly_bearish": -2.0,
        }
        SCORE_TO_SIGNAL = [
            (1.5, "strongly_bullish"), (0.75, "bullish"), (0.25, "slightly_bullish"),
            (-0.25, "mixed"), (-0.75, "slightly_bearish"), (-1.5, "bearish"),
            (-float("inf"), "strongly_bearish"),
        ]

        # Poids décroissant par profondeur (contribution des nœuds profonds est moindre)
        for idx, node_id in enumerate(path_node_ids):
            node = all_nodes.get(node_id)
            if not node:
                continue
            depth_weight = 1.0 / (idx + 1)  # nœuds précoces pèsent plus

            for asset_id, impact in node.get("asset_impacts", {}).items():
                if asset_id not in combined:
                    combined[asset_id] = {"signal_score_sum": 0.0, "magnitude_sum": 0.0, "total_weight": 0.0}

                signal = impact.get("signal", "mixed")
                score = SIGNAL_SCORES.get(signal, 0.0)
                magnitude = self._parse_magnitude(impact.get("magnitude_central", "0%"))

                combined[asset_id]["signal_score_sum"] += score * depth_weight
                combined[asset_id]["magnitude_sum"] += magnitude * depth_weight
                combined[asset_id]["total_weight"] += depth_weight

        # Normaliser
        result = {}
        for asset_id, data in combined.items():
            if data["total_weight"] == 0:
                continue

            avg_score = data["signal_score_sum"] / data["total_weight"]
            avg_magnitude = data["magnitude_sum"] / data["total_weight"]

            # Score to signal
            final_signal = "mixed"
            for threshold, sig in SCORE_TO_SIGNAL:
                if avg_score >= threshold:
                    final_signal = sig
                    break

            magnitude_str = "~0%"
            if abs(avg_magnitude) >= 0.5:
                magnitude_str = f"+{avg_magnitude:.0f}%" if avg_magnitude > 0 else f"{avg_magnitude:.0f}%"

            result[asset_id] = {
                "signal": final_signal,
                "magnitude": magnitude_str,
                "confidence": round(0.75 - len(path_node_ids) * 0.05, 2),
            }

        return result

    def _parse_magnitude(self, magnitude_str: str) -> float:
        if not magnitude_str or magnitude_str in ("—", "~0%", "0%"):
            return 0.0
        try:
            cleaned = magnitude_str.replace("%", "").replace("+", "").strip()
            return float(cleaned)
        except (ValueError, AttributeError):
            return 0.0

    def _build_basic_narrative(
        self,
        terminal_node: dict,
        path_node_ids: list[str],
        all_nodes: dict,
        event: dict,
    ) -> str:
        """
        Construit un narratif de base pour un scénario terminal.
        (Remplacé par narratif LLM dans scenario_report_generator.py)
        """
        labels = []
        for node_id in path_node_ids:
            node = all_nodes.get(node_id)
            if node and node.get("label"):
                labels.append(node["label"])

        path_str = " → ".join(labels[:4])
        event_label = event.get("text_en_canonical", "Event initial")

        return (
            f"À partir de '{event_label}', ce scénario suit le chemin: {path_str}. "
            f"Probabilité cumulative: {terminal_node['probability_cumulative']:.0%}. "
            f"Horizon temporel principal: {terminal_node.get('time_horizon', '1-4w')}."
        )

    # -------------------------------------------------------------------------
    # DB operations
    # -------------------------------------------------------------------------

    def _fetch_event(self, conn, event_id: str) -> Optional[dict]:
        """Récupère l'event C2 depuis la DB."""
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT event_id::text, cat_id, subtype_id, importance_score,
                       geography, text_en_canonical, confidence,
                       actors, assets_mentioned, source_name, horizon
                FROM events
                WHERE event_id = %s
            """, (event_id,))
            row = cur.fetchone()
            if row:
                return dict(row)
        return None

    def _save_tree(self, conn, tree_data: dict, event: dict, max_depth: int, min_probability: float) -> dict:
        """Sauvegarde l'arbre complet dans PostgreSQL."""
        tree_id = tree_data["tree_id"]
        nodes = tree_data["nodes"]
        scenario_paths = tree_data["scenario_paths"]

        with conn.cursor() as cur:
            # 1. Créer le scenario_tree (sans root_node_id d'abord)
            cur.execute("""
                INSERT INTO scenario_trees (
                    tree_id, event_id, event_label, cat_id, subtype_id,
                    max_depth, min_probability, total_scenarios,
                    dominant_scenario, dominant_probability,
                    consensus_asset_impacts, uncertainty_flag, status
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, %s, %s)
            """, (
                tree_id,
                event.get("event_id"),
                tree_data.get("event_label", ""),
                tree_data.get("cat_id", ""),
                tree_data.get("subtype_id", ""),
                max_depth,
                min_probability,
                tree_data.get("total_scenarios", 0),
                tree_data.get("dominant_scenario"),
                tree_data.get("dominant_probability"),
                json.dumps(tree_data.get("consensus_asset_impacts", {})),
                tree_data.get("uncertainty_flag", "HIGH"),
                "complete",
            ))

            # 2. Insérer les nœuds (en ordre BFS: depth 0 → max)
            sorted_nodes = sorted(nodes.values(), key=lambda n: n["depth"])

            for node in sorted_nodes:
                cur.execute("""
                    INSERT INTO scenario_nodes (
                        node_id, tree_id, parent_node_id, depth, label, description,
                        probability, probability_cumulative, trigger_condition,
                        time_horizon, drivers_activated, asset_impacts,
                        historical_analogies, confidence, is_terminal, is_pruned
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                              %s::jsonb, %s::jsonb, %s::jsonb, %s, %s, %s)
                """, (
                    node["node_id"],
                    tree_id,
                    node.get("parent_node_id"),
                    node["depth"],
                    node["label"],
                    node.get("description", ""),
                    node["probability"],
                    node["probability_cumulative"],
                    node.get("trigger_condition", ""),
                    node.get("time_horizon", "immediate"),
                    json.dumps(node.get("drivers_activated", [])),
                    json.dumps(node.get("asset_impacts", {})),
                    json.dumps(node.get("historical_analogies", [])),
                    node.get("confidence", 0.5),
                    node.get("is_terminal", False),
                    node.get("is_pruned", False),
                ))

            # 3. Mettre à jour root_node_id dans scenario_trees
            cur.execute("""
                UPDATE scenario_trees SET root_node_id = %s WHERE tree_id = %s
            """, (tree_data["root_node_id"], tree_id))

            # 4. Insérer les scenario_paths
            for path in scenario_paths:
                cur.execute("""
                    INSERT INTO scenario_paths (
                        path_id, tree_id, label, probability_path,
                        node_ids, terminal_node_id, terminal_asset_summary,
                        narrative_terminal, revision_factors
                    ) VALUES (%s, %s, %s, %s, %s::uuid[], %s, %s::jsonb, %s, %s)
                """, (
                    path["path_id"],
                    tree_id,
                    path["label"],
                    path["probability_path"],
                    path["node_ids"],
                    path["terminal_node_id"],
                    json.dumps(path.get("terminal_asset_summary", {})),
                    path.get("narrative_terminal", ""),
                    path.get("revision_factors", []),
                ))

        # Retourner la représentation publique (sans les nœuds bruts)
        return {
            "tree_id": tree_id,
            "event_id": tree_data.get("event_id"),
            "event_label": tree_data.get("event_label"),
            "cat_id": tree_data.get("cat_id"),
            "subtype_id": tree_data.get("subtype_id"),
            "generated_at": tree_data.get("generated_at"),
            "total_scenarios": tree_data.get("total_scenarios"),
            "max_depth": max_depth,
            "root_node_id": tree_data.get("root_node_id"),
            "scenario_paths": [
                {k: v for k, v in p.items() if k != "node_ids"}
                for p in scenario_paths
            ],
            "dominant_scenario": tree_data.get("dominant_scenario"),
            "dominant_probability": tree_data.get("dominant_probability"),
            "consensus_asset_impacts": tree_data.get("consensus_asset_impacts"),
            "uncertainty_flag": tree_data.get("uncertainty_flag"),
            "revision_factors": tree_data.get("revision_factors"),
            "status": "complete",
        }


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import sys

    print("=== Scenario Tree Engine — Test Standalone ===\n")

    # Simulation d'un event (sans DB)
    event = {
        "event_id": str(uuid.uuid4()),
        "cat_id": "CAT-06",
        "subtype_id": "military_conflict",
        "importance_score": 0.92,
        "confidence": 0.85,
        "geography": ["MIDDLE_EAST", "IRAN", "GLOBAL"],
        "text_en_canonical": "US launches military strikes against Iran — targeted attacks on nuclear facilities",
        "source_name": "Reuters",
        "actors": ["United States", "Iran"],
        "assets_mentioned": ["oil", "gold"],
        "horizon": "immediate",
    }

    engine = ScenarioTreeEngine(macro_context={
        "oil_price_level": "high",
        "diplomatic_context": "hostile",
        "vix_level": "high",
        "us_rates_stance": "holding",
        "growth_regime": "moderate",
    })

    print(f"Generating scenario tree for: {event['text_en_canonical']}")
    print(f"Event: {event['cat_id']}/{event['subtype_id']}, importance={event['importance_score']}\n")

    tree = engine.generate_without_db(event, max_depth=3, min_probability=0.03)

    print(f"Tree ID: {tree['tree_id']}")
    print(f"Total scenarios: {tree['total_scenarios']}")
    print(f"Uncertainty: {tree['uncertainty_flag']}")
    print(f"Dominant scenario: {tree['dominant_scenario']} (P={tree['dominant_probability']:.0%})")

    print("\n--- Scenario Paths ---")
    for path in tree["scenario_paths"]:
        print(f"\n{path['path_id']} [{path['probability_path']:.0%}]: {path['label']}")
        print(f"  Depth: {path.get('depth', '?')}")
        if path.get("terminal_asset_summary"):
            for asset, impact in list(path["terminal_asset_summary"].items())[:3]:
                print(f"  {asset}: {impact.get('signal', '?')} {impact.get('magnitude', '?')}")

    print("\n--- Consensus ---")
    for asset, impact in tree["consensus_asset_impacts"].items():
        print(f"  {asset}: {impact['signal']} {impact['magnitude']} ({impact['confidence_label']})")

    print("\n--- Revision Factors ---")
    for f in tree["revision_factors"][:3]:
        print(f"  - {f}")
