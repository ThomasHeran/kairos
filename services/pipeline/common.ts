import type { PipelineArticle } from "@/services/pipeline/types";

type LogLevel = "info" | "warn" | "error";

export function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
}

export function round1(value: number) {
  return Math.round(value * 10) / 10;
}

export function truncate(value: string, maxLength: number) {
  if (value.length <= maxLength) {
    return value;
  }

  return value.slice(0, Math.max(0, maxLength - 1)).trimEnd() + "…";
}

export function normalizeWhitespace(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

export function articleText(article: Pick<PipelineArticle, "title" | "content">) {
  return normalizeWhitespace([article.title, article.content ?? ""].join(" ").trim());
}

export function compactContent(article: Pick<PipelineArticle, "title" | "content">, maxLength = 2000) {
  return truncate(articleText(article), maxLength);
}

export function hasOpenAiApiKey() {
  return Boolean(process.env.OPENAI_API_KEY);
}

export function logPipeline(level: LogLevel, event: string, data: Record<string, unknown> = {}) {
  const entry = {
    scope: "pipeline",
    level,
    event,
    ...data,
  };

  const message = JSON.stringify(entry);

  if (level === "error") {
    console.error(message);
    return;
  }

  if (level === "warn") {
    console.warn(message);
    return;
  }

  console.info(message);
}

function isRetryableOpenAiError(error: unknown) {
  const message = error instanceof Error ? error.message.toLowerCase() : String(error).toLowerCase();
  return (
    message.includes("429") ||
    message.includes("rate limit") ||
    message.includes("temporarily unavailable") ||
    message.includes("timeout")
  );
}

function sleep(ms: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

export async function withOpenAiRetry<T>(
  label: string,
  articleId: number,
  operation: () => Promise<T>,
) {
  let delayMs = 400;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      if (!isRetryableOpenAiError(error) || attempt === 3) {
        throw error;
      }

      logPipeline("warn", "openai_retry", {
        label,
        article_id: articleId,
        attempt,
        delay_ms: delayMs,
        error: error instanceof Error ? error.message : "Unknown OpenAI error",
      });

      await sleep(delayMs);
      delayMs *= 2;
    }
  }

  throw new Error(`OpenAI retry loop exhausted for ${label}`);
}
