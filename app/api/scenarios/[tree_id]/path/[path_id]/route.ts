/**
 * GET /api/scenarios/:tree_id/path/:path_id
 *
 * Retourne le détail d'un scénario spécifique (nœuds, impacts, narratif).
 */

import { getScenarioPath, getScenarioTree, getScenarioNodes } from "@/lib/scenarios";
import { query } from "@/lib/db";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ tree_id: string; path_id: string }> },
) {
  try {
    const { tree_id, path_id } = await params;

    if (!tree_id || !/^[0-9a-f-]{36}$/.test(tree_id)) {
      return Response.json({ error: "Invalid tree_id format" }, { status: 400 });
    }
    if (!path_id) {
      return Response.json({ error: "path_id is required" }, { status: 400 });
    }

    // Load tree metadata
    const [tree, path] = await Promise.all([
      getScenarioTree(tree_id),
      getScenarioPath(tree_id, path_id),
    ]);

    if (!tree) {
      return Response.json({ error: `Scenario tree ${tree_id} not found` }, { status: 404 });
    }
    if (!path) {
      return Response.json(
        { error: `Path ${path_id} not found in tree ${tree_id}` },
        { status: 404 },
      );
    }

    // Load nodes along this path
    const nodeIds = (path.node_ids as string[]) || [];
    let pathNodes: Record<string, unknown>[] = [];

    if (nodeIds.length > 0) {
      try {
        const nodesResult = await query<Record<string, unknown>>(
          `SELECT node_id::text, parent_node_id::text, depth, label, description,
                  probability, probability_cumulative, trigger_condition,
                  time_horizon, drivers_activated, asset_impacts,
                  historical_analogies, confidence
           FROM scenario_nodes
           WHERE node_id = ANY($1::uuid[])
           ORDER BY depth ASC`,
          [nodeIds],
        );
        pathNodes = nodesResult.rows;
      } catch {
        pathNodes = []; // nodes table may not exist yet
      }
    }

    // Build response
    const response = {
      path_id: path.path_id,
      tree_id: path.tree_id,
      label: path.label,
      probability_path: path.probability_path,
      depth: nodeIds.length - 1,
      terminal_node_id: path.terminal_node_id,
      terminal_asset_summary: path.terminal_asset_summary,
      narrative_terminal: path.narrative_terminal,
      revision_factors: path.revision_factors,
      path_nodes: pathNodes,
      // Context
      tree_context: {
        event_label: tree.event_label,
        cat_id: tree.cat_id,
        subtype_id: tree.subtype_id,
        uncertainty_flag: tree.uncertainty_flag,
        dominant_scenario: tree.dominant_scenario,
        total_scenarios: tree.total_scenarios,
      },
    };

    return Response.json(response, { status: 200 });
  } catch (error) {
    console.error("[GET /api/scenarios/:tree_id/path/:path_id] Error:", error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}
