/**
 * Kairos — Scenario Tree Engine (TypeScript layer)
 * Business logic for scenario tree generation and retrieval.
 * Mirrors the Python engine logic for use in Next.js API routes.
 */

import { query } from "@/lib/db";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ScenarioNode {
  node_id: string;
  tree_id: string;
  parent_node_id: string | null;
  depth: number;
  label: string;
  description: string;
  probability: number;
  probability_cumulative: number;
  trigger_condition: string;
  time_horizon: string;
  drivers_activated: DriverActivation[];
  asset_impacts: Record<string, AssetImpact>;
  historical_analogies: HistoricalAnalogy[];
  confidence: number;
  is_terminal: boolean;
  is_pruned: boolean;
}

export interface DriverActivation {
  driver: string;
  sub_driver: string;
  direction: number;
  intensity: string;
  coefficient: number;
  range: { low: number; central: number; high: number };
  horizon: string;
}

export interface AssetImpact {
  signal: string;
  magnitude_central?: string;
  magnitude?: string;
  range?: string[];
  horizon?: string;
  confidence?: number;
}

export interface HistoricalAnalogy {
  episode: string;
  match_score: number;
  oil_move?: string;
  duration_weeks?: number;
}

export interface ScenarioPath {
  path_id: string;
  tree_id: string;
  label: string;
  probability_path: number;
  node_ids: string[];
  terminal_node_id: string;
  terminal_asset_summary: Record<string, AssetImpact>;
  narrative_terminal: string;
  revision_factors: string[];
}

export interface ScenarioTree {
  tree_id: string;
  event_id: string;
  event_label: string;
  cat_id: string;
  subtype_id: string;
  generated_at: string;
  max_depth: number;
  min_probability: number;
  total_scenarios: number;
  root_node_id: string | null;
  dominant_scenario: string | null;
  dominant_probability: number | null;
  consensus_asset_impacts: Record<string, Record<string, unknown>>;
  uncertainty_flag: string;
  status: string;
}

// ---------------------------------------------------------------------------
// HIGH_UNCERTAINTY detection
// ---------------------------------------------------------------------------

const HIGH_UNCERTAINTY_CATS = new Set(["CAT-05", "CAT-06", "CAT-08"]);
const IMPORTANCE_THRESHOLD = 0.75;

export function isHighUncertainty(
  catId: string,
  importanceScore: number,
  hasUnverifiedConditions = false,
): boolean {
  if (HIGH_UNCERTAINTY_CATS.has(catId) && importanceScore > IMPORTANCE_THRESHOLD) {
    return true;
  }
  return hasUnverifiedConditions;
}

// ---------------------------------------------------------------------------
// Calibration lookup (reads from DB or config)
// ---------------------------------------------------------------------------

export async function loadCalibrations(): Promise<Record<string, unknown>[]> {
  const { readFileSync } = await import("fs");
  const path = await import("path");

  try {
    const filePath = path.join(process.cwd(), "config", "probability_calibrations_v1.json");
    const content = readFileSync(filePath, "utf-8");
    const data = JSON.parse(content);
    return data.calibrations || [];
  } catch {
    return [];
  }
}

export async function findBestCalibration(
  catId: string,
  subtypeId: string,
  geography: string[] = [],
): Promise<Record<string, unknown> | null> {
  const calibrations = await loadCalibrations();

  // Exact match with geography priority
  const exactMatches = calibrations.filter(
    (c: Record<string, unknown>) => c.cat_id === catId && c.subtype_id === subtypeId,
  );

  if (exactMatches.length > 0) {
    if (
      geography.some((g) => ["MIDDLE_EAST", "IRAN"].includes(g))
    ) {
      const hormuzMatch = exactMatches.find((c: Record<string, unknown>) =>
        typeof c.bifurcation_id === "string" && c.bifurcation_id.includes("hormuz"),
      );
      if (hormuzMatch) return hormuzMatch;
    }
    return exactMatches[0];
  }

  // Fallback mapping
  const FALLBACK: Record<string, Record<string, string>> = {
    "CAT-06": {
      military_conflict: "armed_conflict_general_response",
      sanctions_imposed: "sanctions_regime_impact",
      trade_war_escalation: "trade_war_escalation_paths",
      energy_supply_shock: "energy_supply_shock_cb_response",
    },
    "CAT-08": {
      oil_price_surge: "oil_supply_disruption_response",
      opec_decision: "opec_production_cut_impact",
    },
    "CAT-05": {
      bank_failure: "financial_system_stress",
      sovereign_debt_stress: "sovereign_debt_stress_paths",
    },
  };

  const fallbackId = FALLBACK[catId]?.[subtypeId];
  if (fallbackId) {
    return calibrations.find((c: Record<string, unknown>) => c.bifurcation_id === fallbackId) || null;
  }

  return null;
}

// ---------------------------------------------------------------------------
// DB queries
// ---------------------------------------------------------------------------

export async function getScenarioTree(treeId: string): Promise<ScenarioTree | null> {
  const result = await query<ScenarioTree>(
    `SELECT tree_id::text, event_id::text, event_label, cat_id, subtype_id,
            generated_at, max_depth, min_probability, total_scenarios,
            root_node_id::text, dominant_scenario, dominant_probability,
            consensus_asset_impacts, uncertainty_flag, status
     FROM scenario_trees
     WHERE tree_id = $1`,
    [treeId],
  );
  return result.rows[0] || null;
}

export async function getScenarioNodes(treeId: string): Promise<ScenarioNode[]> {
  const result = await query<ScenarioNode>(
    `SELECT node_id::text, tree_id::text, parent_node_id::text, depth,
            label, description, probability, probability_cumulative,
            trigger_condition, time_horizon, drivers_activated,
            asset_impacts, historical_analogies, confidence,
            is_terminal, is_pruned
     FROM scenario_nodes
     WHERE tree_id = $1 AND is_pruned = false
     ORDER BY depth ASC, probability_cumulative DESC`,
    [treeId],
  );
  return result.rows;
}

export async function getScenarioPaths(treeId: string): Promise<ScenarioPath[]> {
  const result = await query<ScenarioPath>(
    `SELECT path_id, tree_id::text, label, probability_path,
            node_ids::text[], terminal_node_id::text,
            terminal_asset_summary, narrative_terminal, revision_factors
     FROM scenario_paths
     WHERE tree_id = $1
     ORDER BY probability_path DESC`,
    [treeId],
  );
  return result.rows;
}

export async function getScenarioPath(
  treeId: string,
  pathId: string,
): Promise<ScenarioPath | null> {
  const result = await query<ScenarioPath>(
    `SELECT path_id, tree_id::text, label, probability_path,
            node_ids::text[], terminal_node_id::text,
            terminal_asset_summary, narrative_terminal, revision_factors
     FROM scenario_paths
     WHERE tree_id = $1 AND path_id = $2`,
    [treeId, pathId],
  );
  return result.rows[0] || null;
}

export async function getScenarioTreeWithPaths(treeId: string): Promise<{
  tree: ScenarioTree;
  paths: ScenarioPath[];
  nodes: ScenarioNode[];
} | null> {
  const tree = await getScenarioTree(treeId);
  if (!tree) return null;

  const [paths, nodes] = await Promise.all([
    getScenarioPaths(treeId),
    getScenarioNodes(treeId),
  ]);

  return { tree, paths, nodes };
}

// ---------------------------------------------------------------------------
// Probability normalization helper
// ---------------------------------------------------------------------------

function adjustBranchProbabilities(
  branches: Record<string, unknown>[],
  context: Record<string, string> = {},
): Record<string, unknown>[] {
  const adjusted = branches.map((branch) => {
    const conditions = (branch.conditioning_factors as string[]) || [];
    let factor = 1.0;

    for (const condition of conditions) {
      const lower = condition.toLowerCase();
      if (lower.includes("diplomatic") && context.diplomatic_context === "hostile") {
        factor *= 1.2;
      }
      if (lower.includes("us naval") && context.us_naval_presence === "strong") {
        factor *= 0.85;
      }
    }

    const pHist = (branch.p_historical as number) || 0.33;
    return { ...branch, p_adjusted: Math.max(0.01, Math.min(pHist * factor, 1.0)) };
  });

  const total = adjusted.reduce((s, b) => s + (b.p_adjusted as number), 0);
  if (total > 0) {
    return adjusted.map((b) => ({
      ...b,
      p_adjusted: Math.round(((b.p_adjusted as number) / total) * 10000) / 10000,
    }));
  }
  return adjusted;
}

// ---------------------------------------------------------------------------
// In-memory tree generation (fallback when no DB)
// ---------------------------------------------------------------------------

export interface GenerateOptions {
  maxDepth?: number;
  minProbability?: number;
  macroContext?: Record<string, string>;
}

export async function generateScenarioTreeInMemory(
  event: {
    event_id: string;
    cat_id: string;
    subtype_id: string;
    importance_score: number;
    confidence?: number;
    geography?: string[];
    text_en_canonical?: string;
    source_name?: string;
    actors?: string[];
  },
  options: GenerateOptions = {},
): Promise<Record<string, unknown>> {
  const { maxDepth = 4, minProbability = 0.03, macroContext = {} } = options;

  const treeId = crypto.randomUUID();
  const calibration = await findBestCalibration(
    event.cat_id,
    event.subtype_id,
    event.geography || [],
  );

  // Build scenario paths from calibration
  const scenarioPaths: ScenarioPath[] = [];
  let pathCounter = 0;

  if (calibration) {
    const branches = (calibration.branches as Record<string, unknown>[]) || [];
    const adjusted = adjustBranchProbabilities(branches, macroContext);

    for (const branch of adjusted) {
      const prob = (branch.p_adjusted as number) || 0.33;
      if (prob < minProbability) continue;

      pathCounter++;
      const pathId = `S${pathCounter}`;
      const nodeId = crypto.randomUUID();

      const assetImpacts = (branch.asset_impacts as Record<string, AssetImpact>) || {};
      const analogies = (branch.historical_analogies as HistoricalAnalogy[]) || [];

      scenarioPaths.push({
        path_id: pathId,
        tree_id: treeId,
        label: (branch.label as string) || (branch.outcome as string) || `Scenario ${pathId}`,
        probability_path: prob,
        node_ids: [nodeId],
        terminal_node_id: nodeId,
        terminal_asset_summary: Object.fromEntries(
          Object.entries(assetImpacts).map(([k, v]) => [
            k,
            {
              signal: v.signal,
              magnitude: v.magnitude_central || v.magnitude || "0%",
              confidence: 0.65,
            },
          ]),
        ),
        narrative_terminal: `Scénario: ${(branch.label as string) || branch.outcome}. Probabilité calibrée: ${(prob * 100).toFixed(0)}%.`,
        revision_factors: (branch.conditioning_factors as string[]) || [],
      });
    }
  }

  // Sort by probability descending
  scenarioPaths.sort((a, b) => b.probability_path - a.probability_path);
  scenarioPaths.forEach((p, i) => (p.path_id = `S${i + 1}`));

  // Compute consensus
  const consensus = computeConsensus(scenarioPaths);
  const dominant = scenarioPaths[0] || null;
  const uncertainty = computeUncertaintyFlag(scenarioPaths);

  return {
    tree_id: treeId,
    event_id: event.event_id,
    event_label: event.text_en_canonical || "Event",
    cat_id: event.cat_id,
    subtype_id: event.subtype_id,
    generated_at: new Date().toISOString(),
    total_scenarios: scenarioPaths.length,
    max_depth: maxDepth,
    min_probability: minProbability,
    root_node_id: null,
    scenario_paths: scenarioPaths,
    dominant_scenario: dominant?.path_id || null,
    dominant_probability: dominant?.probability_path || null,
    consensus_asset_impacts: consensus,
    uncertainty_flag: uncertainty,
    revision_factors: getRevisionFactors(event.cat_id, event.subtype_id),
    status: "complete",
  };
}

// ---------------------------------------------------------------------------
// Aggregation helpers
// ---------------------------------------------------------------------------

const SIGNAL_SCORES: Record<string, number> = {
  strongly_bullish: 2.0,
  bullish: 1.0,
  slightly_bullish: 0.5,
  mixed: 0.0,
  bearish_mixed: -0.5,
  slightly_bearish: -0.5,
  bearish: -1.0,
  strongly_bearish: -2.0,
};

function scoreToSignal(score: number): string {
  if (score >= 1.5) return "strongly_bullish";
  if (score >= 0.75) return "bullish";
  if (score >= 0.25) return "slightly_bullish";
  if (score >= -0.25) return "mixed";
  if (score >= -0.75) return "slightly_bearish";
  if (score >= -1.5) return "bearish";
  return "strongly_bearish";
}

function parseMagnitude(str: string): number {
  if (!str || str === "—" || str === "~0%") return 0;
  const num = parseFloat(str.replace("%", "").replace("+", ""));
  return isNaN(num) ? 0 : num;
}

function computeConsensus(
  paths: ScenarioPath[],
): Record<string, Record<string, unknown>> {
  const totalProb = paths.reduce((s, p) => s + p.probability_path, 0);
  if (totalProb === 0) return {};

  const assetData: Record<string, { signalSum: number; magSum: number; totalW: number }> = {};

  for (const path of paths) {
    const w = path.probability_path / totalProb;
    for (const [assetId, impact] of Object.entries(path.terminal_asset_summary || {})) {
      const sig = SIGNAL_SCORES[impact.signal] ?? 0;
      const mag = parseMagnitude(
        (impact as AssetImpact).magnitude_central ||
          (impact as AssetImpact).magnitude ||
          "0%",
      );

      if (!assetData[assetId]) assetData[assetId] = { signalSum: 0, magSum: 0, totalW: 0 };
      assetData[assetId].signalSum += sig * w;
      assetData[assetId].magSum += mag * w;
      assetData[assetId].totalW += w;
    }
  }

  const result: Record<string, Record<string, unknown>> = {};
  for (const [assetId, data] of Object.entries(assetData)) {
    if (data.totalW === 0) continue;
    const avgSig = data.signalSum / data.totalW;
    const avgMag = data.magSum / data.totalW;
    const magStr =
      Math.abs(avgMag) < 0.5 ? "~0%" : avgMag > 0 ? `+${avgMag.toFixed(0)}%` : `${avgMag.toFixed(0)}%`;

    result[assetId] = {
      signal: scoreToSignal(avgSig),
      signal_score: Math.round(avgSig * 1000) / 1000,
      magnitude: magStr,
      confidence_label: Math.abs(avgSig) > 1.0 ? "HIGH" : Math.abs(avgSig) > 0.5 ? "MODERATE" : "LOW",
    };
  }
  return result;
}

function computeUncertaintyFlag(paths: ScenarioPath[]): string {
  if (paths.length === 0) return "HIGH";
  const maxProb = Math.max(...paths.map((p) => p.probability_path));
  if (maxProb >= 0.6) return "LOW";
  if (maxProb >= 0.4) return "MEDIUM";
  if (maxProb >= 0.25) return "HIGH";
  return "EXTREME";
}

function getRevisionFactors(catId: string, subtypeId: string): string[] {
  const FACTORS: Record<string, Record<string, string[]>> = {
    "CAT-06": {
      military_conflict: [
        "Décision OPEC+ compensation de l'offre",
        "Réponse diplomatique US/GCC sous 48h",
        "Activation ou non des proxies iraniens (Hezbollah, Houthis)",
        "Niveau des stocks pétroliers OCDE (buffer capacity)",
      ],
      trade_war_escalation: [
        "Calendrier des pourparlers bilatéraux",
        "Réponse OPEC+ sur la production",
        "Degré de compliance alliés US",
      ],
    },
    "CAT-08": {
      oil_price_surge: [
        "Décision OPEC+ (cut ou compensation)",
        "Réponse de la production US shale",
        "Libération des réserves stratégiques (SPR/IEA)",
      ],
      opec_decision: [
        "Respect des quotas par la Russie et l'Irak",
        "Production shale US en réponse",
        "Niveau de la demande mondiale",
      ],
    },
    "CAT-05": {
      bank_failure: [
        "Intervention de la FDIC / BCE / autorités de résolution",
        "Contagion interbancaire (indicateurs: spreads OIS-Libor)",
        "Décision BC sur les taux directeurs en urgence",
      ],
      sovereign_debt_stress: [
        "Négociation programme FMI",
        "Vote budgétaire parlement national",
        "Spread de taux souverains (10Y vs Bund)",
      ],
    },
  };

  return (
    FACTORS[catId]?.[subtypeId] || [
      "Évolution des indicateurs économiques clés",
      "Réponse des banques centrales",
      "Développements géopolitiques",
      "Sentiment de marché et flux d'actifs",
    ]
  );
}

// ---------------------------------------------------------------------------
// Seed probability calibrations to DB
// ---------------------------------------------------------------------------

export async function seedCalibrationsToDb(): Promise<void> {
  const calibrations = await loadCalibrations();

  for (const cal of calibrations) {
    const c = cal as Record<string, unknown>;
    await query(
      `INSERT INTO probability_calibrations
         (bifurcation_id, cat_id, subtype_id, context_description, branches, version)
       VALUES ($1, $2, $3, $4, $5::jsonb, $6)
       ON CONFLICT (bifurcation_id) DO UPDATE
         SET branches = EXCLUDED.branches, last_updated = NOW()`,
      [
        c.bifurcation_id as string,
        (c.cat_id as string) || null,
        (c.subtype_id as string) || null,
        (c.context_description as string) || "",
        JSON.stringify(c.branches || []),
        "v1",
      ],
    );
  }
}
