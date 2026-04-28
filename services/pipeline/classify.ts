import { createStructuredJson } from "@/lib/openai";
import { CATEGORY_CONFIG, getCategoryPromptList } from "@/services/pipeline/category-config";
import {
  articleText,
  clamp,
  compactContent,
  hasOpenAiApiKey,
  logPipeline,
  withOpenAiRetry,
} from "@/services/pipeline/common";
import type { ClassificationResult, PipelineArticle, PipelineCategory } from "@/services/pipeline/types";
import { isPipelineCategory, PIPELINE_CATEGORIES } from "@/services/pipeline/types";

const CLASSIFICATION_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["category", "confidence"],
  properties: {
    category: {
      type: "string",
      enum: [...PIPELINE_CATEGORIES],
    },
    confidence: {
      type: "number",
      minimum: 0,
      maximum: 1,
    },
  },
};

function scoreFallbackCategory(article: PipelineArticle) {
  const haystack = articleText(article).toLowerCase();

  let winner: PipelineCategory = "CAT-02";
  let winnerScore = -1;

  for (const [category, config] of Object.entries(CATEGORY_CONFIG) as Array<
    [PipelineCategory, (typeof CATEGORY_CONFIG)[PipelineCategory]]
  >) {
    const score = config.keywords.reduce((total, keyword) => {
      if (!haystack.includes(keyword.toLowerCase())) {
        return total;
      }

      const titleWeight = article.title.toLowerCase().includes(keyword.toLowerCase()) ? 2 : 1;
      return total + titleWeight;
    }, 0);

    if (score > winnerScore) {
      winner = category;
      winnerScore = score;
    }
  }

  return {
    category: winner,
    confidence: clamp(0.35 + Math.max(winnerScore, 0) * 0.12, 0.2, 0.92),
  };
}

function fallbackClassify(article: PipelineArticle): ClassificationResult {
  const fallback = scoreFallbackCategory(article);

  return {
    category: fallback.category,
    confidence: fallback.confidence,
    classification_mode: "fallback",
  };
}

async function classifyWithOpenAi(article: PipelineArticle): Promise<ClassificationResult> {
  const response = await withOpenAiRetry("classify", article.id, async () => {
    return createStructuredJson<{ category: string; confidence: number }>({
      model: "gpt-4o-mini",
      system: [
        "You classify macro-financial news for Kairos.",
        `Classify this news article into ONE of these categories: ${getCategoryPromptList()}.`,
        'Return JSON only with the shape: { "category": "CAT-XX", "confidence": 0.0 }.',
      ].join(" "),
      user: [
        `TITLE: ${article.title}`,
        `SOURCE: ${article.source_name}`,
        `COUNTRY: ${article.country_code}`,
        `DATE: ${article.published_at ?? article.scraped_at ?? "unknown"}`,
        `CONTENT: ${compactContent(article, 2000)}`,
      ].join("\n"),
      schemaName: "kairos_article_category",
      schema: CLASSIFICATION_SCHEMA,
    });
  });

  if (!isPipelineCategory(response.category)) {
    throw new Error(`Unexpected category returned by OpenAI: ${response.category}`);
  }

  return {
    category: response.category,
    confidence: clamp(response.confidence, 0, 1),
    classification_mode: "openai",
  };
}

export async function classifyArticle(article: PipelineArticle): Promise<ClassificationResult> {
  if (!hasOpenAiApiKey()) {
    return fallbackClassify(article);
  }

  try {
    return await classifyWithOpenAi(article);
  } catch (error) {
    logPipeline("warn", "classify_fallback", {
      article_id: article.id,
      error: error instanceof Error ? error.message : "Unknown classification error",
    });
    return fallbackClassify(article);
  }
}
