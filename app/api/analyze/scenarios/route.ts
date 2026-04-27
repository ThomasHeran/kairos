/**
 * POST /api/analyze/scenarios
 *
 * Génère un arbre de scénarios probabilistes pour un event donné.
 *
 * Body: {
 *   event_id?: string,      // UUID d'un event existant en DB
 *   event?: {...},           // Ou event inline (sans DB)
 *   max_depth?: number,      // Défaut: 4
 *   min_probability?: number, // Défaut: 0.03
 *   macro_context?: {...},   // Contexte macro optionnel
 *   force?: boolean          // Forcer même si non HIGH_UNCERTAINTY
 * }
 */

import { query } from "@/lib/db";
import {
  isHighUncertainty,
  generateScenarioTreeInMemory,
} from "@/lib/scenarios";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));

    const {
      event_id,
      event: inlineEvent,
      max_depth = 4,
      min_probability = 0.03,
      macro_context = {},
      force = false,
    } = body as {
      event_id?: string;
      event?: Record<string, unknown>;
      max_depth?: number;
      min_probability?: number;
      macro_context?: Record<string, string>;
      force?: boolean;
    };

    // Validate params
    if (max_depth < 1 || max_depth > 4) {
      return Response.json({ error: "max_depth must be between 1 and 4" }, { status: 400 });
    }
    if (min_probability < 0.01 || min_probability > 0.5) {
      return Response.json({ error: "min_probability must be between 0.01 and 0.50" }, { status: 400 });
    }

    let event: Record<string, unknown> | null = null;

    // Load event from DB or use inline
    if (event_id) {
      const result = await query<Record<string, unknown>>(
        `SELECT event_id::text, cat_id, subtype_id,
                importance_score, confidence, geography,
                text_en_canonical, source_name, actors, horizon
         FROM events WHERE event_id = $1`,
        [event_id],
      );

      if (result.rows.length === 0) {
        return Response.json({ error: `Event ${event_id} not found` }, { status: 404 });
      }
      event = result.rows[0];
    } else if (inlineEvent) {
      // Validate required fields
      if (!inlineEvent.cat_id || !inlineEvent.subtype_id) {
        return Response.json(
          { error: "Inline event must have cat_id and subtype_id" },
          { status: 400 },
        );
      }
      event = {
        event_id: (inlineEvent.event_id as string) || crypto.randomUUID(),
        ...inlineEvent,
      };
    } else {
      return Response.json(
        { error: "Either event_id or event object is required" },
        { status: 400 },
      );
    }

    // Check HIGH_UNCERTAINTY criteria
    const catId = (event.cat_id as string) || "";
    const importance = parseFloat((event.importance_score as string) || "0");

    const highUncertainty = isHighUncertainty(catId, importance);
    if (!highUncertainty && !force) {
      return Response.json(
        {
          status: "skipped",
          reason: "Event does not meet HIGH_UNCERTAINTY criteria (cat_id not in {CAT-05, CAT-06, CAT-08} or importance_score <= 0.75)",
          event_id: event.event_id,
          cat_id: catId,
          importance_score: importance,
          recommendation: "Use linear C4 pipeline. Pass force=true to override.",
        },
        { status: 200 },
      );
    }

    // Generate tree in-memory (Python engine handles DB persistence)
    const treeData = await generateScenarioTreeInMemory(
      {
        event_id: (event.event_id as string) || crypto.randomUUID(),
        cat_id: catId,
        subtype_id: (event.subtype_id as string) || "",
        importance_score: importance,
        confidence: parseFloat((event.confidence as string) || "0.75"),
        geography: (event.geography as string[]) || [],
        text_en_canonical: (event.text_en_canonical as string) || "",
        source_name: (event.source_name as string) || "",
        actors: (event.actors as string[]) || [],
      },
      { maxDepth: max_depth, minProbability: min_probability, macroContext: macro_context },
    );

    // Save to DB if event_id is from DB
    if (event_id) {
      await persistTree(treeData, event_id);
    }

    return Response.json(treeData, { status: 201 });
  } catch (error) {
    console.error("[POST /api/analyze/scenarios] Error:", error);
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}

// ---------------------------------------------------------------------------
// DB persistence
// ---------------------------------------------------------------------------

async function persistTree(treeData: Record<string, unknown>, eventId: string) {
  const treeId = treeData.tree_id as string;

  try {
    // Insert scenario_tree
    await query(
      `INSERT INTO scenario_trees (
         tree_id, event_id, event_label, cat_id, subtype_id,
         max_depth, min_probability, total_scenarios,
         dominant_scenario, dominant_probability,
         consensus_asset_impacts, uncertainty_flag, status
       ) VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb, $12, $13)
       ON CONFLICT (tree_id) DO NOTHING`,
      [
        treeId,
        eventId,
        treeData.event_label || "",
        treeData.cat_id || "",
        treeData.subtype_id || "",
        treeData.max_depth || 4,
        treeData.min_probability || 0.03,
        treeData.total_scenarios || 0,
        treeData.dominant_scenario || null,
        treeData.dominant_probability || null,
        JSON.stringify(treeData.consensus_asset_impacts || {}),
        treeData.uncertainty_flag || "HIGH",
        "complete",
      ],
    );

    // Insert scenario_paths
    const paths = (treeData.scenario_paths as Record<string, unknown>[]) || [];
    for (const path of paths) {
      const nodeId = crypto.randomUUID(); // terminal node placeholder
      await query(
        `INSERT INTO scenario_paths (
           path_id, tree_id, label, probability_path,
           node_ids, terminal_node_id, terminal_asset_summary,
           narrative_terminal, revision_factors
         ) VALUES ($1, $2, $3, $4, $5::text[], $6::uuid, $7::jsonb, $8, $9)
         ON CONFLICT (path_id, tree_id) DO NOTHING`,
        [
          path.path_id,
          treeId,
          path.label || "",
          path.probability_path || 0,
          [nodeId],
          nodeId,
          JSON.stringify(path.terminal_asset_summary || {}),
          path.narrative_terminal || "",
          path.revision_factors || [],
        ],
      );
    }
  } catch (e) {
    // Non-fatal: tree was generated, just not persisted
    console.warn("[persistTree] Failed to persist tree to DB:", e instanceof Error ? e.message : e);
  }
}
