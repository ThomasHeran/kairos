import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";

import { query } from "@/lib/db";
import { createEmbedding, createPlainTextCompletion, createStructuredJson } from "@/lib/openai";
import {
  getTaxonomySubtype,
  getTaxonomySubtypes,
  type TaxonomySubtype,
} from "@/lib/taxonomy";

const DEDUP_WINDOW_MS = 48 * 60 * 60 * 1000;
const DEDUP_SIMILARITY_THRESHOLD = 0.92;
const ROUTING_THRESHOLD = 0.6;
const EMBEDDING_MODEL = "text-embedding-3-small";
const CLASSIFICATION_MODEL = "gpt-4o-mini";
const DEFAULT_BATCH_LIMIT = 25;
const MAX_BATCH_LIMIT = 100;

const CATEGORY_WEIGHTS: Record<string, number> = {
  MONETARY_POLICY: 1.0,
  MACRO_DATA_RELEASE: 0.9,
  GEOPOLITICAL_SHOCK: 0.85,
  ENERGY_COMMODITY_SHOCK: 0.85,
  TRADE_POLICY: 0.8,
  FISCAL_REGULATORY_POLICY: 0.8,
  FINANCIAL_STABILITY: 0.95,
  SUPPLY_CHAIN_DISRUPTION: 0.75,
  CLIMATE_NATURAL_DISASTER: 0.7,
  TECHNOLOGY_STRUCTURAL: 0.65,
};

const AUTHORITY_BY_SOURCE_NAME: Record<string, number> = {
  "Federal Reserve": 1.0,
  "European Central Bank": 1.0,
  "Bank of England": 1.0,
  "Bank of Japan": 1.0,
  IMF: 0.95,
  "International Monetary Fund": 0.95,
  BIS: 0.95,
  "Bank for International Settlements": 0.95,
  "World Bank": 0.95,
  Reuters: 0.85,
  Bloomberg: 0.85,
  WSJ: 0.85,
  "Wall Street Journal": 0.85,
  FT: 0.85,
  "Financial Times": 0.85,
  AP: 0.8,
  AFP: 0.8,
  dpa: 0.8,
  "Le Monde": 0.65,
  "Le Figaro": 0.65,
  "Libération": 0.65,
  "Liberation": 0.65,
  "Liberation.fr": 0.65,
  "France Info": 0.65,
  "BFM TV": 0.65,
  Mediapart: 0.65,
  "20 Minutes": 0.65,
  "L'Equipe": 0.65,
  "L’Équipe": 0.65,
};

const AUTHORITY_BY_DOMAIN: Array<{ pattern: RegExp; score: number }> = [
  { pattern: /(^|\.)federalreserve\.gov$/i, score: 1.0 },
  { pattern: /(^|\.)ecb\.europa\.eu$/i, score: 1.0 },
  { pattern: /(^|\.)bankofengland\.co\.uk$/i, score: 1.0 },
  { pattern: /(^|\.)boj\.or\.jp$/i, score: 1.0 },
  { pattern: /(^|\.)imf\.org$/i, score: 0.95 },
  { pattern: /(^|\.)bis\.org$/i, score: 0.95 },
  { pattern: /(^|\.)worldbank\.org$/i, score: 0.95 },
  { pattern: /(^|\.)reuters\.com$/i, score: 0.85 },
  { pattern: /(^|\.)bloomberg\.com$/i, score: 0.85 },
  { pattern: /(^|\.)wsj\.com$/i, score: 0.85 },
  { pattern: /(^|\.)ft\.com$/i, score: 0.85 },
  { pattern: /(^|\.)apnews\.com$/i, score: 0.8 },
  { pattern: /(^|\.)afp\.com$/i, score: 0.8 },
  { pattern: /(^|\.)dpa\.com$/i, score: 0.8 },
  { pattern: /(^|\.)lemonde\.fr$/i, score: 0.65 },
  { pattern: /(^|\.)lefigaro\.fr$/i, score: 0.65 },
  { pattern: /(^|\.)liberation\.fr$/i, score: 0.65 },
  { pattern: /(^|\.)francetvinfo\.fr$/i, score: 0.65 },
  { pattern: /(^|\.)bfmtv\.com$/i, score: 0.65 },
  { pattern: /(^|\.)mediapart\.fr$/i, score: 0.65 },
  { pattern: /(^|\.)20minutes\.fr$/i, score: 0.65 },
  { pattern: /(^|\.)lequipe\.fr$/i, score: 0.65 },
];

const ACTOR_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  { pattern: /\bFederal Reserve\b/i, label: "Federal Reserve" },
  { pattern: /\bECB\b|\bEuropean Central Bank\b/i, label: "European Central Bank" },
  { pattern: /\bBank of England\b|\bBoE\b/i, label: "Bank of England" },
  { pattern: /\bBank of Japan\b|\bBoJ\b/i, label: "Bank of Japan" },
  { pattern: /\bIMF\b|\bInternational Monetary Fund\b/i, label: "International Monetary Fund" },
  { pattern: /\bBIS\b|\bBank for International Settlements\b/i, label: "Bank for International Settlements" },
  { pattern: /\bWorld Bank\b/i, label: "World Bank" },
  { pattern: /\bOPEC\+?\b/i, label: "OPEC+" },
  { pattern: /\bEuropean Union\b|\bEU\b/i, label: "European Union" },
  { pattern: /\bWhite House\b/i, label: "White House" },
  { pattern: /\bU\.S\. Treasury\b|\bUS Treasury\b/i, label: "U.S. Treasury" },
];

const ASSET_PATTERNS: Array<{ pattern: RegExp; label: string }> = [
  { pattern: /\bEUR\/USD\b/i, label: "EUR/USD" },
  { pattern: /\bUSD\/JPY\b/i, label: "USD/JPY" },
  { pattern: /\bGBP\/USD\b/i, label: "GBP/USD" },
  { pattern: /\bUS10Y\b|\b10-year Treasury\b|\bTreasury yields?\b/i, label: "US10Y" },
  { pattern: /\bBunds?\b/i, label: "Bund" },
  { pattern: /\bGilts?\b/i, label: "Gilt" },
  { pattern: /\bBrent\b/i, label: "Brent" },
  { pattern: /\bWTI\b/i, label: "WTI" },
  { pattern: /\bgold\b/i, label: "Gold" },
  { pattern: /\bsilver\b/i, label: "Silver" },
  { pattern: /\bcopper\b/i, label: "Copper" },
  { pattern: /\bnatural gas\b|\bnatgas\b/i, label: "Natural Gas" },
  { pattern: /\bBitcoin\b|\bBTC\b/i, label: "BTC" },
];

type RouteChoice = "full_pipeline" | "archive";
type QualifyOutcome = "qualified" | "merged" | "archived" | "failed" | "already_processed";

type DbArticleRow = {
  id: number;
  article_uuid: string;
  title: string;
  content: string | null;
  url: string;
  published_at: string | null;
  scraped_at: string;
  lang: string | null;
  tags: string[] | null;
  canonical: Record<string, unknown> | null;
  authority_score: string | null;
  qualification_status: string;
  qualified_event_id: string | null;
  source_id: number;
  source_name: string;
  source_slug: string | null;
  source_type: string;
  source_url: string;
  country_code: string;
  country_name: string;
};

type ExistingEventRow = {
  event_id: string;
  dedup_cluster_id: string | null;
  cluster_size: number;
  event_timestamp: string;
  source_name: string;
  source_authority: string;
  cat_id: string;
  subtype_id: string;
  confidence: string;
  geography: string[];
  horizon: string;
  actors: string[];
  assets_mentioned: string[];
  key_figures: KeyFigure[];
  importance_score: string;
  routing: RouteChoice;
  text_en_canonical: string | null;
  raw_article_ids: string[];
  subtype_label: string;
  category: string;
  embedding_text: string;
};

type EmbeddedArticle = DbArticleRow & {
  embedding: number[];
  effective_authority: number;
  published_at_date: Date;
};

type CandidateCluster = {
  dedup_cluster_id: string | null;
  articles: EmbeddedArticle[];
  representative: EmbeddedArticle;
};

type KeyFigure = {
  label: string;
  value: number;
  unit: string;
};

type ClassificationResult = {
  cat_id: string;
  category: string;
  subtype_id: string;
  subtype_label: string;
  confidence: number;
  geography: string[];
  horizon: "immediate" | "weeks" | "months" | "structural";
  key_figures: KeyFigure[];
  reasoning: string;
};

type EventClassification = Omit<ClassificationResult, "key_figures" | "reasoning">;

type QualifiedEventRecord = {
  event_id: string;
  raw_article_ids: string[];
  dedup_cluster_id: string | null;
  cluster_size: number;
  timestamp: string;
  source_best: {
    name: string;
    authority_score: number;
  };
  classification: EventClassification;
  entities: {
    actors: string[];
    assets_mentioned: string[];
    key_figures: KeyFigure[];
  };
  importance_score: number;
  routing: RouteChoice;
  text_en_canonical: string | null;
};

export type QualifyResult = {
  status: QualifyOutcome;
  article_ids: number[];
  article_uuids: string[];
  event?: QualifiedEventRecord;
  event_id?: string;
  reason?: string;
  error?: string;
};

let classificationPromptPromise: Promise<string> | null = null;

const CLASSIFICATION_RESPONSE_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: [
    "cat_id",
    "category",
    "subtype_id",
    "subtype_label",
    "confidence",
    "geography",
    "horizon",
    "key_figures",
    "reasoning",
  ],
  properties: {
    cat_id: { type: "string" },
    category: { type: "string" },
    subtype_id: { type: "string" },
    subtype_label: { type: "string" },
    confidence: { type: "number" },
    geography: {
      type: "array",
      items: { type: "string" },
    },
    horizon: {
      type: "string",
      enum: ["immediate", "weeks", "months", "structural"],
    },
    key_figures: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["label", "value", "unit"],
        properties: {
          label: { type: "string" },
          value: { type: "number" },
          unit: { type: "string" },
        },
      },
    },
    reasoning: { type: "string" },
  },
};

function clamp(value: number, min = 0, max = 1) {
  return Math.min(Math.max(value, min), max);
}

function round3(value: number) {
  return Math.round(value * 1000) / 1000;
}

function unique<T>(items: T[]) {
  return [...new Set(items)];
}

function normalizeWhitespace(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function truncate(value: string, maxLength: number) {
  if (value.length <= maxLength) {
    return value;
  }

  return `${value.slice(0, maxLength - 1).trim()}…`;
}

function parseOptionalUrlHost(value: string | null | undefined) {
  if (!value) {
    return null;
  }

  try {
    return new URL(value).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function toPgVector(values: number[]) {
  return `[${values.join(",")}]`;
}

function parsePgVector(raw: string) {
  const trimmed = raw.trim();

  if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) {
    return [];
  }

  return trimmed
    .slice(1, -1)
    .split(",")
    .map((value) => Number.parseFloat(value))
    .filter((value) => Number.isFinite(value));
}

function cosineSimilarity(left: number[], right: number[]) {
  if (left.length === 0 || right.length === 0 || left.length !== right.length) {
    return 0;
  }

  let dot = 0;
  let leftNorm = 0;
  let rightNorm = 0;

  for (let index = 0; index < left.length; index += 1) {
    dot += left[index] * right[index];
    leftNorm += left[index] * left[index];
    rightNorm += right[index] * right[index];
  }

  if (leftNorm === 0 || rightNorm === 0) {
    return 0;
  }

  return dot / (Math.sqrt(leftNorm) * Math.sqrt(rightNorm));
}

function getCanonicalField(article: DbArticleRow, key: string) {
  const canonical = article.canonical;

  if (!canonical || typeof canonical !== "object") {
    return null;
  }

  const value = canonical[key];
  return typeof value === "string" ? value : null;
}

function getCombinedArticleText(article: DbArticleRow) {
  const textParts = [
    article.title,
    getCanonicalField(article, "text_en"),
    getCanonicalField(article, "text_raw"),
    article.content ?? "",
  ]
    .map((part) => (typeof part === "string" ? normalizeWhitespace(part) : ""))
    .filter(Boolean);

  return truncate(unique(textParts).join("\n\n"), 8000);
}

function getEmbeddingInput(article: DbArticleRow) {
  return truncate(
    [
      article.title,
      getCanonicalField(article, "text_en"),
      getCanonicalField(article, "text_raw"),
      article.content ?? "",
      article.country_code,
      article.source_name,
    ]
      .map((value) => normalizeWhitespace(value ?? ""))
      .filter(Boolean)
      .join("\n"),
    6000,
  );
}

function getTextHash(input: string) {
  return createHash("sha256").update(input).digest("hex");
}

function normalizeHorizon(
  value: string | null | undefined,
  fallback: TaxonomySubtype["default_horizon"],
): "immediate" | "weeks" | "months" | "structural" {
  if (value === "immediate" || value === "weeks" || value === "months" || value === "structural") {
    return value;
  }

  return fallback;
}

function normalizeGeography(values: string[], fallback: string[]) {
  const cleaned = unique(
    values
      .map((value) => normalizeWhitespace(value).toUpperCase())
      .filter((value) => value.length > 0 && value.length <= 12),
  );

  if (cleaned.length > 0) {
    return cleaned;
  }

  const fallbackGeography = fallback.map((value) => value.toUpperCase()).filter(Boolean);
  return fallbackGeography.length > 0 ? unique(fallbackGeography) : ["GLOBAL"];
}

function detectGeographyHints(article: DbArticleRow) {
  const text = `${article.title}\n${getCombinedArticleText(article)}`.toLowerCase();
  const hints: string[] = [];

  if (/(federal reserve|u\.s\.|united states|washington|treasury|fed)/i.test(text)) {
    hints.push("US");
  }

  if (/(ecb|bce|eurozone|euro area|euro|germany|france|italy|spain|hungary)/i.test(text)) {
    hints.push("EZ");
  }

  if (/(bank of england|boe|uk|britain|british|london)/i.test(text)) {
    hints.push("UK");
  }

  if (/(bank of japan|boj|japan|tokyo)/i.test(text)) {
    hints.push("JP");
  }

  if (/(china|beijing|pboc)/i.test(text)) {
    hints.push("CN");
  }

  if (/(isra[eë]l|lebanon|liban|gaza|iran|saudi|middle east|mer rouge|red sea)/i.test(text)) {
    hints.push("ME");
  }

  if (/(ukraine|russia|moscow|kyiv|kiev)/i.test(text)) {
    hints.push("EU");
  }

  if (/(opec|imf|world bank|bis|global|worldwide)/i.test(text)) {
    hints.push("GLOBAL");
  }

  if (hints.length === 0 && article.country_code) {
    hints.push(article.country_code);
  }

  return unique(hints);
}

function normalizeKeyFigures(values: KeyFigure[]) {
  return values
    .filter(
      (value) =>
        typeof value.label === "string" &&
        value.label.length > 0 &&
        Number.isFinite(value.value) &&
        typeof value.unit === "string" &&
        value.unit.length > 0,
    )
    .map((value) => ({
      label: normalizeWhitespace(value.label),
      value: round3(value.value),
      unit: normalizeWhitespace(value.unit),
    }));
}

function computeAuthorityScore(article: DbArticleRow) {
  const sourceName = normalizeWhitespace(article.source_name);
  const byName = AUTHORITY_BY_SOURCE_NAME[sourceName];

  if (typeof byName === "number") {
    return byName;
  }

  const hosts = [parseOptionalUrlHost(article.source_url), parseOptionalUrlHost(article.url)].filter(
    (value): value is string => Boolean(value),
  );

  for (const host of hosts) {
    const match = AUTHORITY_BY_DOMAIN.find((candidate) => candidate.pattern.test(host));
    if (match) {
      return match.score;
    }
  }

  const existing = Number.parseFloat(article.authority_score ?? "");
  if (Number.isFinite(existing) && existing > 0) {
    return clamp(existing);
  }

  return 0.45;
}

function determineGeographyScope(geography: string[]) {
  const values = geography.map((value) => value.toUpperCase());

  if (values.includes("GLOBAL")) {
    return 1.0;
  }

  if (values.includes("US") || values.includes("EZ") || values.includes("EU") || values.includes("UK")) {
    return 0.8;
  }

  if (values.includes("CN") || values.includes("JP") || values.includes("IN") || values.includes("G20")) {
    return 0.7;
  }

  if (values.some((value) => ["EM", "LATAM", "ASIA", "AF", "ME"].includes(value))) {
    return 0.4;
  }

  return 0.2;
}

function computeImportanceScore({
  authorityScore,
  geography,
  novelty,
  category,
}: {
  authorityScore: number;
  geography: string[];
  novelty: number;
  category: string;
}) {
  const geographyScope = determineGeographyScope(geography);
  const eventTypeWeight = CATEGORY_WEIGHTS[category] ?? 0.6;

  return round3(
    authorityScore * 0.35 + geographyScope * 0.2 + novelty * 0.2 + eventTypeWeight * 0.25,
  );
}

function buildUserClassificationPrompt(article: DbArticleRow) {
  const articleText = getCombinedArticleText(article);

  return `Classify the following news item into the Kairos taxonomy.\n\nTITLE: ${article.title}\nSUMMARY: ${truncate(articleText, 5000)}\nSOURCE: ${article.source_name}\nDATE: ${article.published_at ?? article.scraped_at}\nLANGUAGE: ${article.lang ?? "unknown"}\nCOUNTRY: ${article.country_code}\nURL: ${article.url}\n\nReturn ONLY the JSON classification object.`;
}

async function getClassificationSystemPrompt() {
  if (!classificationPromptPromise) {
    classificationPromptPromise = readFile(
      path.join(process.cwd(), "docs", "classification_prompt_v1.md"),
      "utf8",
    ).then((content) => {
      const match = content.match(/```([\s\S]*?)```/);
      return (match?.[1] ?? content).trim();
    });
  }

  return classificationPromptPromise;
}

function scoreKeywordMatch(text: string, subtype: TaxonomySubtype) {
  let score = 0;

  for (const keyword of subtype.detection_keywords) {
    const normalizedKeyword = keyword.toLowerCase();
    if (text.includes(normalizedKeyword)) {
      score += 2;
    }
  }

  if (text.includes(subtype.subtype_id.replaceAll("_", " "))) {
    score += 3;
  }

  if (text.includes(subtype.category.toLowerCase().replaceAll("_", " "))) {
    score += 1;
  }

  return score;
}

function isClearlyIrrelevant(text: string) {
  return /(psg|liverpool|ligue des champions|football|soccer|rugby|tennis|nba|but de|goal|demi-finale|coupe du monde|atletico madrid|barcelone|cin[eé]ma|film|com[eé]die|festival|album|s[eé]rie|people|c[eé]l[eé]brit[eé]|fiv)/i.test(
    text,
  );
}

function hasRelevantSignal(text: string) {
  return /(inflation|cpi|hicp|ipc|gdp|pib|payrolls?|emploi|unemployment|ch[oô]mage|pmi|retail sales|consumer confidence|fed|federal reserve|ecb|bce|boe|boj|central bank|interest rates?|taux|fomc|guerre|war|sanctions?|tariff|trade|opec|oil|petrol|gas|commodity|bank failure|liquidity|sovereign|debt ceiling|export restriction|supply chain|shipping|port blockage|drought|flood|hurricane|earthquake|wildfire|carbon tax|cyber attack|antitrust|export ban|demographic|iran|isra[eë]l|ukraine|russia)/i.test(
    text,
  );
}

function heuristicSubtypeByRules(article: DbArticleRow) {
  const text = `${article.title}\n${getCombinedArticleText(article)}`.toLowerCase();
  const releaseType =
    typeof article.canonical?.metadata === "object" &&
    article.canonical?.metadata &&
    "release_type" in article.canonical.metadata &&
    typeof article.canonical.metadata.release_type === "string"
      ? article.canonical.metadata.release_type.toLowerCase()
      : null;

  if (/(ceasefire|cessez-le-feu|truce|armistice)/i.test(text)) {
    return "armed_conflict_ceasefire";
  }

  if (/(sanctions?|embargo)/i.test(text)) {
    return "sanctions_announcement";
  }

  if (/(guerre|war|missile|strike|attack|bombardment|offensive|conflict|isra[eë]l|liban|lebanon|ukraine|russia|iran)/i.test(text)) {
    return "armed_conflict_escalation";
  }

  if (releaseType === "rate_decision" || /(taux|rates?|interest rate|fomc|ecb|bce|boe|boj|fed)/i.test(text)) {
    if (/(cut|lower|baisse|easing|assouplissement)/i.test(text)) {
      return "rate_decision_cut";
    }

    if (/(hold|unchanged|maintain|statu quo|pause)/i.test(text)) {
      return "rate_decision_hold";
    }

    if (/(hike|raise|hausse|tightening|resserrement)/i.test(text)) {
      return "rate_decision_hike";
    }
  }

  if (releaseType === "cpi" || /(inflation|cpi|hicp|ipc)/i.test(text)) {
    if (/(cools|decelerates|slows|below|sous|recul)/i.test(text)) {
      return "inflation_cpi_below";
    }

    if (/(hotter|accelerates|rises|above|surge|bondit)/i.test(text)) {
      return "inflation_cpi_above";
    }

    return "inflation_cpi_inline";
  }

  if (releaseType === "gdp" || /(gdp|pib)/i.test(text)) {
    if (/(contracts|shrinks|miss|below|negative|contraction|recession)/i.test(text)) {
      return "gdp_below";
    }

    return "gdp_above";
  }

  if (releaseType === "pmi" || /\bpmi\b/i.test(text)) {
    if (/(below 50|contraction|contracts|miss)/i.test(text)) {
      return "pmi_contraction";
    }

    return "pmi_expansion";
  }

  if (releaseType === "nfp" || /(payrolls|emploi|jobs|jobless|unemployment|ch[oô]mage)/i.test(text)) {
    if (/(rise|rises|up|hausse|increase)/i.test(text)) {
      return "unemployment_rise";
    }

    if (/(fall|falls|drop|baisse|decline)/i.test(text)) {
      return "unemployment_fall";
    }
  }

  if (/(bank failure|banque.*faillite|bank collaps|bank seized)/i.test(text)) {
    return "bank_failure";
  }

  if (/(bank rescue|bailout|sauvetage|rescue package)/i.test(text)) {
    return "bank_rescue";
  }

  if (/(liquidity crisis|crise de liquidit[eé]|funding stress)/i.test(text)) {
    return "liquidity_crisis";
  }

  if (/(opec|production cut|quota cut)/i.test(text)) {
    if (/(increase|boost|raise|restore)/i.test(text)) {
      return "opec_increase";
    }

    return "opec_cut";
  }

  if (/(oil supply|pipeline|outage|rupture d'approvisionnement|supply disruption)/i.test(text)) {
    return "oil_supply_disruption";
  }

  if (/(red sea|mer rouge|panama canal|shipping disruption|route maritime|port blockage|blocage portuaire)/i.test(text)) {
    return "shipping_disruption";
  }

  if (/(drought|s[eé]cheresse)/i.test(text)) {
    return "drought_major";
  }

  return null;
}

function heuristicClassification(article: DbArticleRow): ClassificationResult | null {
  const text = `${article.title}\n${getCombinedArticleText(article)}`.toLowerCase();

  if (isClearlyIrrelevant(text)) {
    return null;
  }

  const ruleMatch = heuristicSubtypeByRules(article);

  if (ruleMatch) {
    const subtype = getTaxonomySubtype(ruleMatch);
    if (subtype) {
      return {
        cat_id: subtype.cat_id,
        category: subtype.category,
        subtype_id: subtype.subtype_id,
        subtype_label: subtype.subtype_label,
        confidence: 0.72,
        geography: normalizeGeography(detectGeographyHints(article), subtype.typical_geography),
        horizon: subtype.default_horizon,
        key_figures: [],
        reasoning: "Rule-based fallback classifier matched the primary event pattern.",
      };
    }
  }

  if (!hasRelevantSignal(text)) {
    return null;
  }

  let bestSubtype: TaxonomySubtype | null = null;
  let bestScore = 0;

  for (const subtype of getTaxonomySubtypes()) {
    const score = scoreKeywordMatch(text, subtype);

    if (score > bestScore) {
      bestScore = score;
      bestSubtype = subtype;
    }
  }

  if (!bestSubtype || bestScore < 4) {
    return null;
  }

  return {
    cat_id: bestSubtype.cat_id,
    category: bestSubtype.category,
    subtype_id: bestSubtype.subtype_id,
    subtype_label: bestSubtype.subtype_label,
    confidence: clamp(0.45 + bestScore * 0.05),
    geography: normalizeGeography(detectGeographyHints(article), bestSubtype.typical_geography),
    horizon: bestSubtype.default_horizon,
    key_figures: [],
    reasoning: "Keyword fallback classifier selected the closest Kairos subtype.",
  };
}

async function classifyRepresentativeArticle(article: DbArticleRow) {
  const prompt = await getClassificationSystemPrompt();

  try {
    const response = await createStructuredJson<ClassificationResult>({
      model: CLASSIFICATION_MODEL,
      system: prompt,
      user: buildUserClassificationPrompt(article),
      schemaName: "kairos_c2_classification",
      schema: CLASSIFICATION_RESPONSE_SCHEMA,
      temperature: 0,
    });

    const taxonomySubtype =
      getTaxonomySubtype(response.subtype_id) ?? getTaxonomySubtype(response.subtype_id.trim());

    if (!taxonomySubtype || response.cat_id === "OTHER") {
      return heuristicClassification(article);
    }

    return {
      cat_id: taxonomySubtype.cat_id,
      category: taxonomySubtype.category,
      subtype_id: taxonomySubtype.subtype_id,
      subtype_label: taxonomySubtype.subtype_label,
      confidence: clamp(Number(response.confidence) || 0),
      geography: normalizeGeography(
        response.geography ?? detectGeographyHints(article),
        taxonomySubtype.typical_geography,
      ),
      horizon: normalizeHorizon(response.horizon, taxonomySubtype.default_horizon),
      key_figures: normalizeKeyFigures(response.key_figures ?? []),
      reasoning: normalizeWhitespace(response.reasoning ?? ""),
    };
  } catch {
    return heuristicClassification(article);
  }
}

function extractActors(article: DbArticleRow) {
  const text = `${article.title}\n${getCombinedArticleText(article)}`;
  const matches = ACTOR_PATTERNS.filter((candidate) => candidate.pattern.test(text)).map(
    (candidate) => candidate.label,
  );

  const personMatches = text.match(
    /\b(?:President|Chair|Governor|Prime Minister|Chancellor|CEO|Treasury Secretary)\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2}\b/g,
  );

  return unique([...matches, ...(personMatches ?? []).map((value) => normalizeWhitespace(value))]).slice(0, 12);
}

function extractAssets(article: DbArticleRow) {
  const text = `${article.title}\n${getCombinedArticleText(article)}`;
  return unique(
    ASSET_PATTERNS.filter((candidate) => candidate.pattern.test(text)).map((candidate) => candidate.label),
  ).slice(0, 12);
}

function extractRegexFigures(article: DbArticleRow) {
  const text = `${article.title}\n${getCombinedArticleText(article)}`;
  const figures: KeyFigure[] = [];

  for (const match of text.matchAll(/(-?\d+(?:\.\d+)?)\s?(?:bps|basis points?)/gi)) {
    const value = Number.parseFloat(match[1]);
    if (Number.isFinite(value)) {
      figures.push({ label: "basis_points", value, unit: "bps" });
    }
  }

  for (const match of text.matchAll(/(-?\d+(?:\.\d+)?)\s?%/g)) {
    const value = Number.parseFloat(match[1]);
    if (Number.isFinite(value)) {
      figures.push({ label: "percentage", value, unit: "%" });
    }
  }

  for (const match of text.matchAll(/\$ ?(\d+(?:\.\d+)?)\s?(tn|trillion|bn|billion|m|million)?/gi)) {
    const value = Number.parseFloat(match[1]);
    const qualifier = (match[2] ?? "usd").toLowerCase();

    if (!Number.isFinite(value)) {
      continue;
    }

    let multiplier = 1;
    let unit = "USD";

    if (qualifier === "tn" || qualifier === "trillion") {
      multiplier = 1_000;
      unit = "USD bn";
    } else if (qualifier === "bn" || qualifier === "billion") {
      unit = "USD bn";
    } else if (qualifier === "m" || qualifier === "million") {
      multiplier = 0.001;
      unit = "USD bn";
    }

    figures.push({ label: "usd_amount", value: round3(value * multiplier), unit });
  }

  return figures;
}

function mergeKeyFigures(primary: KeyFigure[], secondary: KeyFigure[]) {
  const merged = [...primary, ...secondary];
  const seen = new Set<string>();

  return merged.filter((item) => {
    const key = `${item.label}:${item.value}:${item.unit}`;
    if (seen.has(key)) {
      return false;
    }

    seen.add(key);
    return true;
  });
}

async function buildCanonicalEnglishText(article: DbArticleRow) {
  const canonicalText = getCanonicalField(article, "text_en");

  if (canonicalText) {
    return truncate(normalizeWhitespace(canonicalText), 1500);
  }

  const combined = getCombinedArticleText(article);

  if ((article.lang ?? "").toLowerCase().startsWith("en")) {
    return truncate(combined, 1500);
  }

  try {
    const translated = await createPlainTextCompletion({
      model: CLASSIFICATION_MODEL,
      system:
        "You produce one concise English sentence that captures the primary market-relevant event from the article. Do not add commentary.",
      user: `TITLE: ${article.title}\nTEXT: ${truncate(combined, 3500)}`,
      temperature: 0,
    });

    return truncate(normalizeWhitespace(translated), 1500);
  } catch {
    return truncate(combined, 1500);
  }
}

async function getOrCreateArticleEmbedding(article: DbArticleRow) {
  const embeddingInput = getEmbeddingInput(article);
  const textHash = getTextHash(embeddingInput);
  const existing = await query<{ embedding_text: string }>(
    `
      SELECT embedding::text AS embedding_text
      FROM article_embeddings
      WHERE article_uuid = $1 AND embedding_text_hash = $2
      LIMIT 1
    `,
    [article.article_uuid, textHash],
  );

  if ((existing.rowCount ?? 0) > 0) {
    const parsed = parsePgVector(existing.rows[0].embedding_text);
    if (parsed.length > 0) {
      return parsed;
    }
  }

  const embedding = await createEmbedding(embeddingInput, EMBEDDING_MODEL);

  await query(
    `
      INSERT INTO article_embeddings (
        article_uuid,
        article_id,
        embedding_model,
        embedding,
        embedding_text_hash,
        embedding_source,
        embedded_at
      )
      VALUES ($1, $2, $3, $4::vector, $5, 'c2_dedup', NOW())
      ON CONFLICT (article_uuid)
      DO UPDATE
      SET
        article_id = EXCLUDED.article_id,
        embedding_model = EXCLUDED.embedding_model,
        embedding = EXCLUDED.embedding,
        embedding_text_hash = EXCLUDED.embedding_text_hash,
        embedding_source = EXCLUDED.embedding_source,
        embedded_at = NOW()
    `,
    [article.article_uuid, article.id, EMBEDDING_MODEL, toPgVector(embedding), textHash],
  );

  return embedding;
}

async function loadArticleBySelector(selector: {
  article_id?: number;
  article_uuid?: string;
  url?: string;
}) {
  const params: Array<number | string> = [];
  const where: string[] = [];

  if (selector.article_id !== undefined) {
    params.push(selector.article_id);
    where.push(`a.id = $${params.length}`);
  }

  if (selector.article_uuid) {
    params.push(selector.article_uuid);
    where.push(`a.article_uuid = $${params.length}::uuid`);
  }

  if (selector.url) {
    params.push(selector.url);
    where.push(`a.url = $${params.length}`);
  }

  if (where.length === 0) {
    throw new Error("Missing article selector");
  }

  const result = await query<DbArticleRow>(
    `
      SELECT
        a.id,
        a.article_uuid::text,
        a.title,
        a.content,
        a.url,
        a.published_at,
        a.scraped_at,
        a.lang,
        a.tags,
        a.canonical,
        a.authority_score::text,
        a.qualification_status,
        a.qualified_event_id::text,
        s.id AS source_id,
        s.name AS source_name,
        s.slug AS source_slug,
        s.type AS source_type,
        s.url AS source_url,
        c.code_iso AS country_code,
        c.name AS country_name
      FROM articles a
      INNER JOIN sources s ON s.id = a.source_id
      INNER JOIN countries c ON c.id = a.country_id
      WHERE ${where.join(" OR ")}
      ORDER BY a.published_at DESC NULLS LAST, a.scraped_at DESC NULLS LAST
      LIMIT 1
    `,
    params,
  );

  return result.rows[0] ?? null;
}

async function loadPendingArticles(filters: {
  limit?: number;
  country?: string;
  force?: boolean;
}) {
  const params: Array<number | string> = [];
  const where = filters.force ? ["TRUE"] : ["a.qualification_status = 'pending'"];

  if (filters.country) {
    params.push(filters.country.toUpperCase());
    where.push(`c.code_iso = $${params.length}`);
  }

  params.push(Math.min(Math.max(filters.limit ?? DEFAULT_BATCH_LIMIT, 1), MAX_BATCH_LIMIT));

  const result = await query<DbArticleRow>(
    `
      SELECT
        a.id,
        a.article_uuid::text,
        a.title,
        a.content,
        a.url,
        a.published_at,
        a.scraped_at,
        a.lang,
        a.tags,
        a.canonical,
        a.authority_score::text,
        a.qualification_status,
        a.qualified_event_id::text,
        s.id AS source_id,
        s.name AS source_name,
        s.slug AS source_slug,
        s.type AS source_type,
        s.url AS source_url,
        c.code_iso AS country_code,
        c.name AS country_name
      FROM articles a
      INNER JOIN sources s ON s.id = a.source_id
      INNER JOIN countries c ON c.id = a.country_id
      WHERE ${where.join(" AND ")}
      ORDER BY a.published_at DESC NULLS LAST, a.scraped_at DESC NULLS LAST
      LIMIT $${params.length}
    `,
    params,
  );

  return result.rows;
}

async function loadEventById(eventId: string) {
  const result = await query<ExistingEventRow>(
    `
      SELECT
        e.event_id::text,
        e.dedup_cluster_id::text,
        e.cluster_size,
        e.event_timestamp::text,
        e.source_name,
        e.source_authority::text,
        e.cat_id,
        e.subtype_id,
        e.confidence::text,
        e.geography,
        e.horizon,
        e.actors,
        e.assets_mentioned,
        e.key_figures,
        e.importance_score::text,
        e.routing,
        e.text_en_canonical,
        e.raw_article_ids::text[],
        et.label AS subtype_label,
        et.category,
        COALESCE(ae.embedding::text, '[]') AS embedding_text
      FROM events e
      INNER JOIN event_taxonomy et
        ON et.cat_id = e.cat_id AND et.subtype_id = e.subtype_id
      LEFT JOIN article_embeddings ae
        ON ae.article_uuid = e.raw_article_ids[1]
      WHERE e.event_id = $1::uuid
      LIMIT 1
    `,
    [eventId],
  );

  return result.rows[0] ?? null;
}

async function loadExistingEventRepresentatives(start: Date, end: Date) {
  const result = await query<ExistingEventRow>(
    `
      SELECT
        e.event_id::text,
        e.dedup_cluster_id::text,
        e.cluster_size,
        e.event_timestamp::text,
        e.source_name,
        e.source_authority::text,
        e.cat_id,
        e.subtype_id,
        e.confidence::text,
        e.geography,
        e.horizon,
        e.actors,
        e.assets_mentioned,
        e.key_figures,
        e.importance_score::text,
        e.routing,
        e.text_en_canonical,
        e.raw_article_ids::text[],
        et.label AS subtype_label,
        et.category,
        ae.embedding::text AS embedding_text
      FROM events e
      INNER JOIN event_taxonomy et
        ON et.cat_id = e.cat_id AND et.subtype_id = e.subtype_id
      INNER JOIN article_embeddings ae
        ON ae.article_uuid = e.raw_article_ids[1]
      WHERE e.event_timestamp BETWEEN $1::timestamptz AND $2::timestamptz
    `,
    [start.toISOString(), end.toISOString()],
  );

  return result.rows;
}

function pickRepresentative(articles: EmbeddedArticle[]) {
  return [...articles].sort((left, right) => {
    if (right.effective_authority !== left.effective_authority) {
      return right.effective_authority - left.effective_authority;
    }

    return right.published_at_date.getTime() - left.published_at_date.getTime();
  })[0];
}

function isWithinDedupWindow(left: Date, right: Date) {
  return Math.abs(left.getTime() - right.getTime()) <= DEDUP_WINDOW_MS;
}

function groupArticlesIntoClusters(articles: EmbeddedArticle[]) {
  const clusters: CandidateCluster[] = [];

  for (const article of articles) {
    let bestCluster: CandidateCluster | null = null;
    let bestSimilarity = 0;

    for (const cluster of clusters) {
      if (!isWithinDedupWindow(article.published_at_date, cluster.representative.published_at_date)) {
        continue;
      }

      const similarity = cosineSimilarity(article.embedding, cluster.representative.embedding);
      if (similarity > DEDUP_SIMILARITY_THRESHOLD && similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestCluster = cluster;
      }
    }

    if (!bestCluster) {
      clusters.push({
        dedup_cluster_id: null,
        articles: [article],
        representative: article,
      });
      continue;
    }

    bestCluster.articles.push(article);
    bestCluster.representative = pickRepresentative(bestCluster.articles);
  }

  return clusters.map((cluster) => {
    const sortedArticles = [...cluster.articles].sort((left, right) => {
      if (right.effective_authority !== left.effective_authority) {
        return right.effective_authority - left.effective_authority;
      }

      return right.published_at_date.getTime() - left.published_at_date.getTime();
    });

    return {
      dedup_cluster_id: sortedArticles.length > 1 ? crypto.randomUUID() : null,
      articles: sortedArticles,
      representative: sortedArticles[0],
    };
  });
}

function findMatchingEvent(cluster: CandidateCluster, recentEvents: ExistingEventRow[]) {
  let bestMatch: ExistingEventRow | null = null;
  let bestSimilarity = 0;

  for (const event of recentEvents) {
    const eventTimestamp = new Date(event.event_timestamp);
    if (!isWithinDedupWindow(cluster.representative.published_at_date, eventTimestamp)) {
      continue;
    }

    const similarity = cosineSimilarity(cluster.representative.embedding, parsePgVector(event.embedding_text));
    if (similarity > DEDUP_SIMILARITY_THRESHOLD && similarity > bestSimilarity) {
      bestSimilarity = similarity;
      bestMatch = event;
    }
  }

  return bestMatch;
}

function buildQualifiedEventRecord(input: {
  event_id: string;
  raw_article_ids: string[];
  dedup_cluster_id: string | null;
  cluster_size: number;
  timestamp: string;
  source_name: string;
  source_authority: number;
  classification: EventClassification;
  actors: string[];
  assets_mentioned: string[];
  key_figures: KeyFigure[];
  importance_score: number;
  routing: RouteChoice;
  text_en_canonical: string | null;
}) {
  return {
    event_id: input.event_id,
    raw_article_ids: input.raw_article_ids,
    dedup_cluster_id: input.dedup_cluster_id,
    cluster_size: input.cluster_size,
    timestamp: input.timestamp,
    source_best: {
      name: input.source_name,
      authority_score: round3(input.source_authority),
    },
    classification: {
      cat_id: input.classification.cat_id,
      category: input.classification.category,
      subtype_id: input.classification.subtype_id,
      subtype_label: input.classification.subtype_label,
      confidence: input.classification.confidence,
      geography: input.classification.geography,
      horizon: input.classification.horizon,
    },
    entities: {
      actors: input.actors,
      assets_mentioned: input.assets_mentioned,
      key_figures: input.key_figures,
    },
    importance_score: input.importance_score,
    routing: input.routing,
    text_en_canonical: input.text_en_canonical,
  } satisfies QualifiedEventRecord;
}

async function markArticlesArchived(articleUuids: string[], reason: string) {
  await query(
    `
      UPDATE articles
      SET
        qualification_status = 'archived',
        qualified_at = NOW(),
        qualification_error = $2,
        qualified_event_id = NULL
      WHERE article_uuid = ANY($1::uuid[])
    `,
    [articleUuids, reason],
  );
}

async function markArticlesFailed(articleUuids: string[], errorMessage: string) {
  await query(
    `
      UPDATE articles
      SET
        qualification_status = 'failed',
        qualification_error = $2
      WHERE article_uuid = ANY($1::uuid[])
    `,
    [articleUuids, truncate(errorMessage, 1000)],
  );
}

async function attachArticlesToEvent(articleUuids: string[], eventId: string) {
  await query(
    `
      UPDATE articles
      SET
        qualification_status = 'qualified',
        qualified_at = NOW(),
        qualification_error = NULL,
        qualified_event_id = $2::uuid
      WHERE article_uuid = ANY($1::uuid[])
    `,
    [articleUuids, eventId],
  );
}

async function insertEventRecord(input: {
  raw_article_ids: string[];
  dedup_cluster_id: string | null;
  cluster_size: number;
  event_timestamp: string;
  source_name: string;
  source_authority: number;
  classification: ClassificationResult;
  actors: string[];
  assets_mentioned: string[];
  key_figures: KeyFigure[];
  importance_score: number;
  routing: RouteChoice;
  text_en_canonical: string | null;
}) {
  const result = await query<{ event_id: string }>(
    `
      INSERT INTO events (
        raw_article_ids,
        dedup_cluster_id,
        cluster_size,
        event_timestamp,
        source_name,
        source_authority,
        cat_id,
        subtype_id,
        confidence,
        geography,
        horizon,
        actors,
        assets_mentioned,
        key_figures,
        importance_score,
        routing,
        text_en_canonical
      )
      VALUES (
        $1::uuid[],
        $2::uuid,
        $3,
        $4::timestamptz,
        $5,
        $6,
        $7,
        $8,
        $9,
        $10::text[],
        $11,
        $12::text[],
        $13::text[],
        $14::jsonb,
        $15,
        $16,
        $17
      )
      RETURNING event_id::text
    `,
    [
      input.raw_article_ids,
      input.dedup_cluster_id,
      input.cluster_size,
      input.event_timestamp,
      input.source_name,
      input.source_authority,
      input.classification.cat_id,
      input.classification.subtype_id,
      input.classification.confidence,
      input.classification.geography,
      input.classification.horizon,
      input.actors,
      input.assets_mentioned,
      JSON.stringify(input.key_figures),
      input.importance_score,
      input.routing,
      input.text_en_canonical,
    ],
  );

  return result.rows[0].event_id;
}

async function mergeClusterIntoExistingEvent(cluster: CandidateCluster, event: ExistingEventRow) {
  const articleUuids = cluster.articles.map((article) => article.article_uuid);
  const representative = cluster.representative;
  const existingAuthority = Number.parseFloat(event.source_authority);
  const shouldPromoteRepresentative = representative.effective_authority > existingAuthority;
  const canonicalText = shouldPromoteRepresentative
    ? await buildCanonicalEnglishText(representative)
    : event.text_en_canonical;

  const rawArticleIds = unique(
    shouldPromoteRepresentative
      ? [representative.article_uuid, ...event.raw_article_ids, ...articleUuids]
      : [...event.raw_article_ids, ...articleUuids],
  );

  const clusterSize = rawArticleIds.length;
  const dedupClusterId =
    event.dedup_cluster_id ?? (clusterSize > 1 ? cluster.dedup_cluster_id ?? crypto.randomUUID() : null);

  await query(
    `
      UPDATE events
      SET
        raw_article_ids = $2::uuid[],
        cluster_size = $3,
        dedup_cluster_id = $4::uuid,
        source_name = $5,
        source_authority = $6,
        text_en_canonical = $7,
        updated_at = NOW()
      WHERE event_id = $1::uuid
    `,
    [
      event.event_id,
      rawArticleIds,
      clusterSize,
      dedupClusterId,
      shouldPromoteRepresentative ? representative.source_name : event.source_name,
      shouldPromoteRepresentative ? representative.effective_authority : existingAuthority,
      canonicalText,
    ],
  );

  await attachArticlesToEvent(articleUuids, event.event_id);

  const updated = await loadEventById(event.event_id);
  if (!updated) {
    throw new Error(`Merged event ${event.event_id} could not be reloaded`);
  }

  return serializeEventRow(updated);
}

function serializeEventRow(row: ExistingEventRow) {
  return buildQualifiedEventRecord({
    event_id: row.event_id,
    raw_article_ids: row.raw_article_ids,
    dedup_cluster_id: row.dedup_cluster_id,
    cluster_size: row.cluster_size,
    timestamp: row.event_timestamp,
    source_name: row.source_name,
    source_authority: Number.parseFloat(row.source_authority),
    classification: {
      cat_id: row.cat_id,
      category: row.category,
      subtype_id: row.subtype_id,
      subtype_label: row.subtype_label,
      confidence: Number.parseFloat(row.confidence),
      geography: row.geography ?? [],
      horizon: normalizeHorizon(row.horizon, "immediate"),
    },
    actors: row.actors ?? [],
    assets_mentioned: row.assets_mentioned ?? [],
    key_figures: normalizeKeyFigures(row.key_figures ?? []),
    importance_score: Number.parseFloat(row.importance_score),
    routing: row.routing,
    text_en_canonical: row.text_en_canonical,
  });
}

async function qualifyCluster(cluster: CandidateCluster) {
  const representative = cluster.representative;
  const classification = await classifyRepresentativeArticle(representative);

  if (!classification) {
    await markArticlesArchived(
      cluster.articles.map((article) => article.article_uuid),
      "Classifier returned no valid Kairos subtype for this article cluster.",
    );

    return {
      status: "archived" as const,
      article_ids: cluster.articles.map((article) => article.id),
      article_uuids: cluster.articles.map((article) => article.article_uuid),
      reason: "unclassifiable_or_irrelevant",
    };
  }

  const subtype = getTaxonomySubtype(classification.subtype_id);
  if (!subtype) {
    await markArticlesArchived(
      cluster.articles.map((article) => article.article_uuid),
      `Unknown taxonomy subtype: ${classification.subtype_id}`,
    );

    return {
      status: "archived" as const,
      article_ids: cluster.articles.map((article) => article.id),
      article_uuids: cluster.articles.map((article) => article.article_uuid),
      reason: "unknown_taxonomy_subtype",
    };
  }

  const authorityPenalty = representative.effective_authority < subtype.authority_floor;
  const canonicalText = await buildCanonicalEnglishText(representative);
  const actors = extractActors(representative);
  const assetsMentioned = extractAssets(representative);
  const keyFigures = mergeKeyFigures(classification.key_figures, extractRegexFigures(representative));
  const novelty = 1.0;
  const importanceScore = computeImportanceScore({
    authorityScore: representative.effective_authority,
    geography: classification.geography,
    novelty,
    category: classification.category,
  });
  const routing: RouteChoice =
    importanceScore > ROUTING_THRESHOLD && !authorityPenalty ? "full_pipeline" : "archive";
  const eventTimestamp = representative.published_at ?? representative.scraped_at;
  const rawArticleIds = cluster.articles.map((article) => article.article_uuid);

  const eventId = await insertEventRecord({
    raw_article_ids: rawArticleIds,
    dedup_cluster_id: cluster.dedup_cluster_id,
    cluster_size: cluster.articles.length,
    event_timestamp: eventTimestamp,
    source_name: representative.source_name,
    source_authority: representative.effective_authority,
    classification: {
      ...classification,
      confidence: authorityPenalty
        ? clamp(classification.confidence * (representative.effective_authority / subtype.authority_floor))
        : classification.confidence,
    },
    actors,
    assets_mentioned: assetsMentioned,
    key_figures: keyFigures,
    importance_score: importanceScore,
    routing,
    text_en_canonical: canonicalText,
  });

  await attachArticlesToEvent(rawArticleIds, eventId);

  return {
    status: "qualified" as const,
    article_ids: cluster.articles.map((article) => article.id),
    article_uuids: rawArticleIds,
    event_id: eventId,
    event: buildQualifiedEventRecord({
      event_id: eventId,
      raw_article_ids: rawArticleIds,
      dedup_cluster_id: cluster.dedup_cluster_id,
      cluster_size: cluster.articles.length,
      timestamp: eventTimestamp,
      source_name: representative.source_name,
      source_authority: representative.effective_authority,
      classification: {
        ...classification,
        confidence: authorityPenalty
          ? clamp(classification.confidence * (representative.effective_authority / subtype.authority_floor))
          : classification.confidence,
      },
      actors,
      assets_mentioned: assetsMentioned,
      key_figures: keyFigures,
      importance_score: importanceScore,
      routing,
      text_en_canonical: canonicalText,
    }),
  };
}

async function hydrateEmbeddedArticles(articles: DbArticleRow[]) {
  const embeddedArticles: EmbeddedArticle[] = [];

  for (const article of articles) {
    const embedding = await getOrCreateArticleEmbedding(article);
    embeddedArticles.push({
      ...article,
      embedding,
      effective_authority: computeAuthorityScore(article),
      published_at_date: new Date(article.published_at ?? article.scraped_at),
    });
  }

  return embeddedArticles;
}

export async function qualifyStoredArticle(options: {
  article_id?: number;
  article_uuid?: string;
  url?: string;
  force?: boolean;
}) {
  const article = await loadArticleBySelector(options);

  if (!article) {
    throw new Error("Article not found");
  }

  if (!options.force) {
    if (article.qualification_status === "qualified" && article.qualified_event_id) {
      const existing = await loadEventById(article.qualified_event_id);
      return {
        status: "already_processed" as const,
        article_ids: [article.id],
        article_uuids: [article.article_uuid],
        event_id: article.qualified_event_id,
        event: existing ? serializeEventRow(existing) : undefined,
        reason: "already_qualified",
      };
    }

    if (article.qualification_status === "archived") {
      return {
        status: "already_processed" as const,
        article_ids: [article.id],
        article_uuids: [article.article_uuid],
        reason: "already_archived",
      };
    }
  }

  try {
    const embeddedArticles = await hydrateEmbeddedArticles([article]);
    const cluster = groupArticlesIntoClusters(embeddedArticles)[0];
    const eventWindowStart = new Date(cluster.representative.published_at_date.getTime() - DEDUP_WINDOW_MS);
    const eventWindowEnd = new Date(cluster.representative.published_at_date.getTime() + DEDUP_WINDOW_MS);
    const recentEvents = await loadExistingEventRepresentatives(eventWindowStart, eventWindowEnd);
    const existingEvent = findMatchingEvent(cluster, recentEvents);

    if (existingEvent) {
      const mergedEvent = await mergeClusterIntoExistingEvent(cluster, existingEvent);
      return {
        status: "merged" as const,
        article_ids: [article.id],
        article_uuids: [article.article_uuid],
        event_id: existingEvent.event_id,
        event: mergedEvent,
      };
    }

    return await qualifyCluster(cluster);
  } catch (error) {
    await markArticlesFailed([article.article_uuid], error instanceof Error ? error.message : "Unknown error");
    throw error;
  }
}

export async function qualifyPendingBatch(options: {
  limit?: number;
  country?: string;
  force?: boolean;
}) {
  const articles = await loadPendingArticles(options);

  if (articles.length === 0) {
    return {
      processed: 0,
      qualified: 0,
      merged: 0,
      archived: 0,
      failed: 0,
      results: [] as QualifyResult[],
    };
  }

  const embeddedArticles = await hydrateEmbeddedArticles(articles);
  const clusters = groupArticlesIntoClusters(embeddedArticles);

  const publishedDates = embeddedArticles.map((article) => article.published_at_date.getTime());
  const minDate = new Date(Math.min(...publishedDates) - DEDUP_WINDOW_MS);
  const maxDate = new Date(Math.max(...publishedDates) + DEDUP_WINDOW_MS);
  const recentEvents = await loadExistingEventRepresentatives(minDate, maxDate);

  const results: QualifyResult[] = [];

  for (const cluster of clusters) {
    try {
      const existingEvent = findMatchingEvent(cluster, recentEvents);

      if (existingEvent) {
        const mergedEvent = await mergeClusterIntoExistingEvent(cluster, existingEvent);
        results.push({
          status: "merged",
          article_ids: cluster.articles.map((article) => article.id),
          article_uuids: cluster.articles.map((article) => article.article_uuid),
          event_id: existingEvent.event_id,
          event: mergedEvent,
        });
        continue;
      }

      results.push(await qualifyCluster(cluster));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      await markArticlesFailed(
        cluster.articles.map((article) => article.article_uuid),
        message,
      );
      results.push({
        status: "failed",
        article_ids: cluster.articles.map((article) => article.id),
        article_uuids: cluster.articles.map((article) => article.article_uuid),
        error: message,
      });
    }
  }

  return {
    processed: articles.length,
    qualified: results.filter((result) => result.status === "qualified").length,
    merged: results.filter((result) => result.status === "merged").length,
    archived: results.filter((result) => result.status === "archived").length,
    failed: results.filter((result) => result.status === "failed").length,
    results,
  };
}

export async function listQualifiedEvents(options: {
  limit?: number;
  routing?: RouteChoice;
  cat_id?: string;
}) {
  const params: Array<number | string> = [];
  const where: string[] = [];

  if (options.routing) {
    params.push(options.routing);
    where.push(`e.routing = $${params.length}`);
  }

  if (options.cat_id) {
    params.push(options.cat_id);
    where.push(`e.cat_id = $${params.length}`);
  }

  params.push(Math.min(Math.max(options.limit ?? 50, 1), MAX_BATCH_LIMIT));

  const whereClause = where.length > 0 ? `WHERE ${where.join(" AND ")}` : "";
  const result = await query<ExistingEventRow>(
    `
      SELECT
        e.event_id::text,
        e.dedup_cluster_id::text,
        e.cluster_size,
        e.event_timestamp::text,
        e.source_name,
        e.source_authority::text,
        e.cat_id,
        e.subtype_id,
        e.confidence::text,
        e.geography,
        e.horizon,
        e.actors,
        e.assets_mentioned,
        e.key_figures,
        e.importance_score::text,
        e.routing,
        e.text_en_canonical,
        e.raw_article_ids::text[],
        et.label AS subtype_label,
        et.category,
        COALESCE(ae.embedding::text, '[]') AS embedding_text
      FROM events e
      INNER JOIN event_taxonomy et
        ON et.cat_id = e.cat_id AND et.subtype_id = e.subtype_id
      LEFT JOIN article_embeddings ae
        ON ae.article_uuid = e.raw_article_ids[1]
      ${whereClause}
      ORDER BY e.event_timestamp DESC
      LIMIT $${params.length}
    `,
    params,
  );

  return {
    total: result.rowCount ?? result.rows.length,
    events: result.rows.map(serializeEventRow),
  };
}
