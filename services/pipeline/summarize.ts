import { createPlainTextCompletion } from "@/lib/openai";
import {
  compactContent,
  hasOpenAiApiKey,
  logPipeline,
  normalizeWhitespace,
  withOpenAiRetry,
} from "@/services/pipeline/common";
import type { PipelineArticle, SummaryResult } from "@/services/pipeline/types";

function fallbackSummarize(article: PipelineArticle): SummaryResult {
  const sourceText = normalizeWhitespace(article.content ?? article.title);
  const sentences = sourceText
    .split(/(?<=[.!?])\s+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean)
    .slice(0, 3);

  const summary = sentences.length > 0 ? sentences.join(" ") : article.title;

  return {
    summary,
    summary_mode: "fallback",
  };
}

async function summarizeWithOpenAi(article: PipelineArticle): Promise<SummaryResult> {
  const text = await withOpenAiRetry("summarize", article.id, async () => {
    return createPlainTextCompletion({
      model: "gpt-4o-mini",
      temperature: 0.2,
      system: "Summarize this news article in 2-3 sentences focusing on economic and market implications.",
      user: [
        `TITLE: ${article.title}`,
        `SOURCE: ${article.source_name}`,
        `DATE: ${article.published_at ?? article.scraped_at ?? "unknown"}`,
        `CONTENT: ${compactContent(article, 2000)}`,
      ].join("\n"),
    });
  });

  return {
    summary: normalizeWhitespace(text),
    summary_mode: "openai",
  };
}

export async function summarizeArticle(article: PipelineArticle): Promise<SummaryResult> {
  if (!hasOpenAiApiKey()) {
    return fallbackSummarize(article);
  }

  try {
    return await summarizeWithOpenAi(article);
  } catch (error) {
    logPipeline("warn", "summarize_fallback", {
      article_id: article.id,
      error: error instanceof Error ? error.message : "Unknown summarization error",
    });
    return fallbackSummarize(article);
  }
}
