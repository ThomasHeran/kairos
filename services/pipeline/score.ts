import { CATEGORY_CONFIG } from "@/services/pipeline/category-config";
import { articleText, clamp, hasOpenAiApiKey, round1 } from "@/services/pipeline/common";
import type { PipelineArticle, PipelineCategory, ScoreResult } from "@/services/pipeline/types";

const KEYWORD_BONUSES: Array<{ pattern: RegExp; importance: number; impact: number }> = [
  { pattern: /\b(crisis|emergency|collapse|contagion|bank run)\b/i, importance: 1.4, impact: 1.2 },
  { pattern: /\b(crash|selloff|plunge|default|bankruptcy)\b/i, importance: 1.6, impact: 1.5 },
  { pattern: /\b(rate|interest rates?|fed|ecb|boj|boe)\b/i, importance: 0.8, impact: 0.9 },
  { pattern: /\b(gdp|cpi|inflation|payrolls?|unemployment|pmi)\b/i, importance: 0.7, impact: 0.8 },
  { pattern: /\b(oil|gas|brent|wti|opec)\b/i, importance: 0.8, impact: 0.9 },
  { pattern: /\b(sanction|tariff|trade war|export control)\b/i, importance: 0.7, impact: 0.7 },
];

function getUrgencyScore(article: PipelineArticle) {
  const baseline = article.published_at ?? article.scraped_at;

  if (!baseline) {
    return 2;
  }

  const ageMs = Date.now() - new Date(baseline).getTime();

  if (ageMs <= 60 * 60 * 1000) {
    return 10;
  }

  if (ageMs <= 6 * 60 * 60 * 1000) {
    return 8;
  }

  if (ageMs <= 24 * 60 * 60 * 1000) {
    return 5;
  }

  if (ageMs <= 72 * 60 * 60 * 1000) {
    return 3;
  }

  return 1;
}

function getDerivedScores(article: PipelineArticle, category: PipelineCategory): Pick<
  ScoreResult,
  "importance_score" | "market_impact_score"
> {
  const config = CATEGORY_CONFIG[category];
  let importance = config.importance;
  let marketImpact = config.marketImpact;
  const haystack = articleText(article);

  for (const bonus of KEYWORD_BONUSES) {
    if (!bonus.pattern.test(haystack)) {
      continue;
    }

    importance += bonus.importance;
    marketImpact += bonus.impact;
  }

  return {
    importance_score: round1(clamp(importance, 0, 10)),
    market_impact_score: round1(clamp(marketImpact, 0, 10)),
  };
}

function getFallbackScores(category: PipelineCategory): Pick<
  ScoreResult,
  "importance_score" | "market_impact_score"
> {
  const config = CATEGORY_CONFIG[category];

  return {
    importance_score: round1(config.importance),
    market_impact_score: round1(config.marketImpact),
  };
}

export function scoreArticle(article: PipelineArticle, category: PipelineCategory): ScoreResult {
  const useFixedScores = !hasOpenAiApiKey();
  const baseScores = useFixedScores ? getFallbackScores(category) : getDerivedScores(article, category);

  return {
    ...baseScores,
    urgency_score: getUrgencyScore(article),
    score_mode: useFixedScores ? "fallback" : "derived",
  };
}
