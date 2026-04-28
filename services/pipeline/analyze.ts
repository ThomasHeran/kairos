import { query } from "@/lib/db";
import { classifyArticle } from "@/services/pipeline/classify";
import { logPipeline } from "@/services/pipeline/common";
import { scoreArticle } from "@/services/pipeline/score";
import { summarizeArticle } from "@/services/pipeline/summarize";
import type { EnrichedArticle, PipelineArticle } from "@/services/pipeline/types";

const DEFAULT_BATCH_LIMIT = 10;
const MAX_BATCH_LIMIT = 10;

type ArticleRow = {
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

type UpdateRow = {
  analyzed_at: string;
};

function clampBatchLimit(limit?: number) {
  return Math.min(Math.max(limit ?? DEFAULT_BATCH_LIMIT, 1), MAX_BATCH_LIMIT);
}

function mapArticle(row: ArticleRow): PipelineArticle {
  return {
    id: row.id,
    title: row.title,
    content: row.content,
    url: row.url,
    published_at: row.published_at,
    scraped_at: row.scraped_at,
    source_name: row.source_name,
    source_url: row.source_url,
    country_code: row.country_code,
    country_name: row.country_name,
  };
}

async function persistAnalysis(
  articleId: number,
  input: {
    category: string;
    confidence: number;
    summary: string;
    importance_score: number;
    urgency_score: number;
    market_impact_score: number;
  },
) {
  const result = await query<UpdateRow>(
    `
      UPDATE articles
      SET
        category = $2,
        category_confidence = $3,
        summary = $4,
        importance_score = $5,
        urgency_score = $6,
        market_impact_score = $7,
        analyzed_at = NOW()
      WHERE id = $1
      RETURNING analyzed_at::text
    `,
    [
      articleId,
      input.category,
      input.confidence,
      input.summary,
      input.importance_score,
      input.urgency_score,
      input.market_impact_score,
    ],
  );

  const analyzedAt = result.rows[0]?.analyzed_at;

  if (!analyzedAt) {
    throw new Error(`Failed to persist analysis for article ${articleId}`);
  }

  return analyzedAt;
}

export async function loadPendingArticles(limit?: number) {
  const batchLimit = clampBatchLimit(limit);
  const result = await query<ArticleRow>(
    `
      SELECT
        a.id,
        a.title,
        a.content,
        a.url,
        a.published_at::text,
        a.scraped_at::text,
        s.name AS source_name,
        s.url AS source_url,
        c.code_iso AS country_code,
        c.name AS country_name
      FROM articles a
      INNER JOIN sources s ON s.id = a.source_id
      INNER JOIN countries c ON c.id = a.country_id
      WHERE a.analyzed_at IS NULL
      ORDER BY COALESCE(a.published_at, a.scraped_at) DESC, a.id DESC
      LIMIT $1
    `,
    [batchLimit],
  );

  return result.rows.map(mapArticle);
}

export async function loadArticleById(id: number) {
  const result = await query<ArticleRow>(
    `
      SELECT
        a.id,
        a.title,
        a.content,
        a.url,
        a.published_at::text,
        a.scraped_at::text,
        s.name AS source_name,
        s.url AS source_url,
        c.code_iso AS country_code,
        c.name AS country_name
      FROM articles a
      INNER JOIN sources s ON s.id = a.source_id
      INNER JOIN countries c ON c.id = a.country_id
      WHERE a.id = $1
      LIMIT 1
    `,
    [id],
  );

  return result.rows[0] ? mapArticle(result.rows[0]) : null;
}

export async function analyzeArticle(article: PipelineArticle): Promise<EnrichedArticle> {
  logPipeline("info", "article_analyze_started", {
    article_id: article.id,
    source_name: article.source_name,
  });

  const classification = await classifyArticle(article);
  const summaryResult = await summarizeArticle(article);
  const scoreResult = scoreArticle(article, classification.category);
  const analyzedAt = await persistAnalysis(article.id, {
    category: classification.category,
    confidence: classification.confidence,
    summary: summaryResult.summary,
    importance_score: scoreResult.importance_score,
    urgency_score: scoreResult.urgency_score,
    market_impact_score: scoreResult.market_impact_score,
  });

  logPipeline("info", "article_analyze_completed", {
    article_id: article.id,
    category: classification.category,
    classification_mode: classification.classification_mode,
    summary_mode: summaryResult.summary_mode,
    score_mode: scoreResult.score_mode,
  });

  return {
    ...article,
    ...classification,
    ...summaryResult,
    ...scoreResult,
    analyzed_at: analyzedAt,
  };
}

export async function analyzePendingArticles(limit?: number) {
  const articles = await loadPendingArticles(limit);
  let analyzed = 0;
  let errors = 0;

  for (const article of articles) {
    try {
      await analyzeArticle(article);
      analyzed += 1;
    } catch (error) {
      errors += 1;
      logPipeline("error", "article_analyze_failed", {
        article_id: article.id,
        error: error instanceof Error ? error.message : "Unknown analysis error",
      });
    }
  }

  return { analyzed, errors };
}

export async function analyzeArticleById(id: number) {
  const article = await loadArticleById(id);

  if (!article) {
    return null;
  }

  return analyzeArticle(article);
}

export function resolveAnalyzeLimit(rawLimit: string | null) {
  if (!rawLimit) {
    return DEFAULT_BATCH_LIMIT;
  }

  const parsed = Number.parseInt(rawLimit, 10);
  if (Number.isNaN(parsed)) {
    return DEFAULT_BATCH_LIMIT;
  }

  return clampBatchLimit(parsed);
}
