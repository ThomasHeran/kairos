import type {
  CountryConfig,
  ScrapedArticle,
  ScrapedArticleCountry,
  ScrapedArticleLanguage,
  SourceConfig,
} from "@/agents/types";
import {
  decodeHtml,
  extractTags,
  extractUrl,
  normalizeFeedEntries,
  parsePublishedAt,
  readText,
  type ParsedFeedEntry,
} from "@/lib/feed";

const DEFAULT_TIMEOUT_MS = 10_000;
const DEFAULT_USER_AGENT = "Kairos/1.0";
const DEFAULT_FEED_ACCEPT = "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8";
const DEFAULT_JSON_ACCEPT = "application/json, text/json;q=0.9, */*;q=0.8";

type FeedEntryOverrides = {
  title?: string;
  url?: string;
  content?: string | null;
  publishedAt?: string | number | Date | null;
  sourceName?: string;
  tags?: string[];
  lang?: string | null;
};

type FeedEntryMapper = (entry: ParsedFeedEntry) => FeedEntryOverrides | null | undefined;

function normalizeCountrySlug(country: CountryConfig): ScrapedArticleCountry {
  switch (country.code_iso.trim().toLowerCase()) {
    case "fr":
      return "france";
    case "us":
      return "us";
    case "jp":
      return "japan";
    default:
      return "global";
  }
}

function normalizeLanguage(value: string | null | undefined): ScrapedArticleLanguage | undefined {
  switch ((value ?? "").trim().toLowerCase()) {
    case "fr":
    case "fr-fr":
      return "fr";
    case "ja":
    case "ja-jp":
      return "ja";
    case "en":
    case "en-us":
    case "en-gb":
      return "en";
    default:
      return undefined;
  }
}

export function normalizeIsoDate(value: string | number | Date | null | undefined) {
  if (typeof value === "number") {
    return new Date(value).toISOString();
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed.toISOString();
    }
  }

  return new Date().toISOString();
}

function uniqueTags(tags: Array<string | null | undefined>) {
  const collected = new Set<string>();

  for (const tag of tags) {
    const normalized = tag ? decodeHtml(tag).trim() : "";

    if (normalized) {
      collected.add(normalized);
    }
  }

  return [...collected];
}

export function inferArticleLanguage(
  country: CountryConfig,
  source: SourceConfig,
  hint?: string | null,
): ScrapedArticleLanguage {
  const normalizedHint = normalizeLanguage(hint);
  if (normalizedHint) {
    return normalizedHint;
  }

  const haystack = `${country.name} ${source.name} ${source.url}`.toLowerCase();

  if (
    /(le monde|le figaro|lib[ée]ration|bfm|france info|francetvinfo|l[’']?équipe|20minutes|20 minutes|mediapart|les echos|\/r\/france|reddit france)/.test(
      haystack,
    )
  ) {
    return "fr";
  }

  if (/nhk\.or\.jp\/rss\/news|日本|japonais/.test(haystack)) {
    return "ja";
  }

  return country.code_iso.toLowerCase() === "fr" ? "fr" : "en";
}

export function normalizeArticle(
  country: CountryConfig,
  source: SourceConfig,
  article: {
    title: string;
    url: string;
    content?: string | null;
    publishedAt?: string | number | Date | null;
    sourceName?: string;
    tags?: string[];
    lang?: string | null;
  },
): ScrapedArticle {
  return {
    title: decodeHtml(article.title).trim(),
    url: article.url,
    content: article.content ? decodeHtml(article.content) : null,
    published_at: normalizeIsoDate(article.publishedAt),
    source: article.sourceName?.trim() || source.name,
    country: normalizeCountrySlug(country),
    tags: uniqueTags(article.tags ?? []),
    lang: inferArticleLanguage(country, source, article.lang),
  };
}

export function formatAgentError(error: unknown) {
  return error instanceof Error ? error.message : "Unknown upstream error";
}

export function buildFeedArticles(
  country: CountryConfig,
  source: SourceConfig,
  payload: string,
  mapEntry?: FeedEntryMapper,
) {
  const seenUrls = new Set<string>();
  const articles: ScrapedArticle[] = [];

  for (const entry of normalizeFeedEntries(payload)) {
    const overrides = mapEntry?.(entry);

    if (overrides === null) {
      continue;
    }

    const title = overrides?.title ?? readText(entry.title);
    const url =
      overrides?.url ??
      extractUrl(entry.link) ??
      extractUrl(entry.guid) ??
      extractUrl(readText(entry.id));

    if (!title || !url || seenUrls.has(url)) {
      continue;
    }

    seenUrls.add(url);

    const content =
      overrides?.content ??
      readText(entry.description) ??
      readText(entry.summary) ??
      readText(entry["content:encoded"]) ??
      readText(entry.content);

    const tags = overrides?.tags ?? extractTags(entry);

    articles.push(
      normalizeArticle(country, source, {
        title,
        url,
        content,
        publishedAt: overrides?.publishedAt ?? parsePublishedAt(entry),
        sourceName: overrides?.sourceName,
        tags,
        lang: overrides?.lang,
      }),
    );
  }

  return articles;
}

export async function fetchTextUpstream(
  url: string,
  options?: {
    accept?: string;
    userAgent?: string;
  },
) {
  const response = await fetch(url, {
    headers: {
      "user-agent": options?.userAgent ?? DEFAULT_USER_AGENT,
      accept: options?.accept ?? DEFAULT_FEED_ACCEPT,
    },
    cache: "no-store",
    redirect: "follow",
    signal: AbortSignal.timeout(DEFAULT_TIMEOUT_MS),
  });

  const payload = await response.text();

  return { response, payload };
}

export async function fetchJsonUpstream<T>(
  url: string,
  options?: {
    userAgent?: string;
  },
) {
  const { response, payload } = await fetchTextUpstream(url, {
    accept: DEFAULT_JSON_ACCEPT,
    userAgent: options?.userAgent,
  });

  return {
    response,
    payload,
    data: JSON.parse(payload) as T,
  };
}

export function upstreamStatusMessage(response: Response) {
  return `upstream returned ${response.status}`;
}

export function looksLikeHtml(payload: string) {
  return /^\s*</.test(payload) && /<(html|body|!doctype)/i.test(payload);
}

export function looksLikeProtectionWall(payload: string) {
  return /just a moment|enable javascript and cookies to continue|cf-browser-verification|verifying your browser|access denied|blocked/i.test(
    payload,
  );
}

