export const PIPELINE_CATEGORIES = [
  "CAT-01",
  "CAT-02",
  "CAT-03",
  "CAT-04",
  "CAT-05",
  "CAT-06",
  "CAT-07",
  "CAT-08",
  "CAT-09",
  "CAT-10",
] as const;

export type PipelineCategory = (typeof PIPELINE_CATEGORIES)[number];

export type PipelineArticle = {
  id: number;
  title: string;
  content: string | null;
  url: string;
  published_at: string | null;
  scraped_at: string | null;
  source_name: string;
  source_url: string;
  country_code: string;
  country_name: string;
};

export type ClassificationResult = {
  category: PipelineCategory;
  confidence: number;
  classification_mode: "openai" | "fallback";
};

export type SummaryResult = {
  summary: string;
  summary_mode: "openai" | "fallback";
};

export type ScoreResult = {
  importance_score: number;
  urgency_score: number;
  market_impact_score: number;
  score_mode: "derived" | "fallback";
};

export type EnrichedArticle = PipelineArticle &
  ClassificationResult &
  SummaryResult &
  ScoreResult & {
    analyzed_at: string;
  };

export function isPipelineCategory(value: string): value is PipelineCategory {
  return (PIPELINE_CATEGORIES as readonly string[]).includes(value);
}
