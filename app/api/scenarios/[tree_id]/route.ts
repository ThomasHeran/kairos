/**
 * GET /api/scenarios/:tree_id
 *
 * Retourne l'arbre complet avec tous les nœuds et chemins.
 */

import { getScenarioTreeWithPaths } from "@/lib/scenarios";

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

    const result = await getScenarioTreeWithPaths(tree_id);

    if (!result) {
      return Response.json({ error: `Scenario tree ${tree_id} not found` }, { status: 404 });
    }

    return Response.json(
      {
        tree: result.tree,
        scenario_paths: result.paths,
        nodes: result.nodes,
        total_nodes: result.nodes.length,
        total_paths: result.paths.length,
      },
      { status: 200 },
    );
  } catch (error) {
    console.error("[GET /api/scenarios/:tree_id] Error:", error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}
