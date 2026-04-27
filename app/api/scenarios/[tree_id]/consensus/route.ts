/**
 * GET /api/scenarios/:tree_id/consensus
 *
 * Retourne les impacts consensuels agrégés (moyenne pondérée par probabilité)
 * pour tous les scénarios d'un arbre.
 */

import { getScenarioTree, getScenarioPaths } from "@/lib/scenarios";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ tree_id: string }> },
) {
  try {
    const { tree_id } = await params;

    if (!tree_id || !/^[0-9a-f-]{36}$/.test(tree_id)) {
      return Response.json({ error: "Invalid tree_id format" }, { status: 400 });
    }

    const [tree, paths] = await Promise.all([
      getScenarioTree(tree_id),
      getScenarioPaths(tree_id),
    ]);

    if (!tree) {
      return Response.json({ error: `Scenario tree ${tree_id} not found` }, { status: 404 });
    }

    // Return pre-computed consensus from DB (calculated at tree generation)
    const consensus = tree.consensus_asset_impacts || {};

    // Also include per-scenario breakdown for the top scenarios
    const topPaths = paths.slice(0, 5).map((path) => ({
      path_id: path.path_id,
      label: path.label,
      probability: path.probability_path,
      asset_summary: path.terminal_asset_summary,
    }));

    return Response.json(
      {
        tree_id,
        event_label: tree.event_label,
        cat_id: tree.cat_id,
        subtype_id: tree.subtype_id,
        uncertainty_flag: tree.uncertainty_flag,
        dominant_scenario: tree.dominant_scenario,
        dominant_probability: tree.dominant_probability,
        total_scenarios: tree.total_scenarios,
        consensus_asset_impacts: consensus,
        top_scenarios: topPaths,
        methodology:
          "Weighted average of asset signals across all scenario paths, weighted by path probability.",
      },
      { status: 200 },
    );
  } catch (error) {
    console.error("[GET /api/scenarios/:tree_id/consensus] Error:", error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}
