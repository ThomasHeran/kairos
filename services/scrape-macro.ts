import { randomUUID } from "node:crypto";

import type { SourceType } from "@/agents/types";
import {
  type MacroSourceDefinition,
  type MacroSourceId,
  getMacroSourceById,
  listMacroSources,
} from "@/config/macro-sources";
import {
  absolutizeUrl,
  decodeHtml,
  extractTags,
  extractUrl,
  normalizeFeedEntries,
  parsePublishedAt,
  readText,
} from "@/lib/feed";
import { hasDatabaseUrl, query } from "@/lib/db";

type CountryRow = {
  id: number;
};

type SourceRow = {
  id: number;
};

type JobRow = {
  id: number;
};

type MacroReleaseType =
  | "rate_decision"
  | "cpi"
  | "gdp"
  | "pmi"
  | "nfp"
  | "speech"
  | "report";

type RawMacroArticle = {
  title: string;
  content?: string;
  url: string;
  sourceUrl: string;
  publishedAt?: string;
  lang?: string;
  tags?: string[];
};

type NormalizedMacroArticle = {
  title: string;
  content?: string;
  url: string;
  source_url: string;
  published_at?: string;
  lang?: string;
  tags: string[];
  release_type: MacroReleaseType;
  is_scheduled_release: boolean;
  authority_score: number;
  canonical: Record<string, unknown>;
};

const INSERT_CHUNK_SIZE = 25;

function chunk<T>(items: T[], size: number) {
  const chunks: T[][] = [];

  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }

  return chunks;
}

function isProtectionPage(payload: string) {
  return /just a moment|enable javascript and cookies to continue|cf-browser-verification/i.test(
    payload,
  );
}

async function fetchText(url: string, accept: string) {
  const response = await fetch(url, {
    headers: {
      "user-agent": "KairosBot/1.0 (+macro-global)",
      accept,
    },
    cache: "no-store",
    signal: AbortSignal.timeout(20_000),
  });

  if (!response.ok) {
    throw new Error(`upstream returned ${response.status}`);
  }

  const payload = await response.text();

  if (isProtectionPage(payload)) {
    throw new Error("upstream requires a browser challenge");
  }

  return payload;
}

function detectReleaseType(definition: MacroSourceDefinition, article: RawMacroArticle): MacroReleaseType {
  const titleHaystack = [article.title, article.url, ...(article.tags ?? [])]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  const fullHaystack = [titleHaystack, article.content]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  if (
    /\bspeech\b|\bremarks\b|\binterview\b|\blecture\b|\btestimony\b|press briefing transcript|\btranscript\b|opening statement/.test(
      titleHaystack,
    )
  ) {
    return "speech";
  }

  if (/interest rate statistics|bank interest rate statistics/.test(titleHaystack)) {
    return "report";
  }

  if (
    /rate decision|bank rate decision|target range|monetary policy decision|governing council.*interest rates|fomc statement|federal reserve issues fomc statement|policy decision|key ecb interest rates|discount rate meetings/.test(
      titleHaystack,
    )
  ) {
    return "rate_decision";
  }

  if (
    /consumer price|cpi|inflation|hicp|harmonised index|producer price index|ppi|personal consumption expenditures/.test(
      fullHaystack,
    )
  ) {
    return "cpi";
  }

  if (/gross domestic product|\bgdp\b|national accounts|quarterly growth|economic growth/.test(fullHaystack)) {
    return "gdp";
  }

  if (/pmi|purchasing managers/.test(fullHaystack)) {
    return "pmi";
  }

  if (
    /nonfarm payroll|payroll employment|employment situation|unemployment rate|labor market|labour market/.test(
      fullHaystack,
    )
  ) {
    return "nfp";
  }

  if (definition.id === "bis") {
    return "speech";
  }

  return "report";
}

function detectScheduledRelease(
  definition: MacroSourceDefinition,
  releaseType: MacroReleaseType,
  article: RawMacroArticle,
) {
  if (["rate_decision", "cpi", "gdp", "pmi", "nfp"].includes(releaseType)) {
    return true;
  }

  if (definition.id === "bls" || definition.id === "eurostat") {
    return true;
  }

  return /minutes of the board|economic bulletin|statistical release|flash estimate/i.test(
    `${article.title} ${article.content ?? ""}`,
  );
}

function buildCanonicalArticle(
  definition: MacroSourceDefinition,
  article: RawMacroArticle,
  releaseType: MacroReleaseType,
  isScheduledRelease: boolean,
) {
  return {
    article_id: randomUUID(),
    timestamp_scraped: new Date().toISOString(),
    source: {
      name: definition.name,
      type: definition.type satisfies SourceType,
      url: article.sourceUrl,
      authority_score: definition.authorityScore,
    },
    title: article.title,
    text_raw: article.content ?? article.title,
    text_en: (article.lang ?? "en") === "en" ? article.content ?? article.title : null,
    language_original: article.lang ?? "en",
    url: article.url,
    published_at: article.publishedAt ?? null,
    country: definition.country.code_iso,
    region: definition.country.region,
    metadata: {
      source_id: definition.id,
      news_type: "macro_global",
      release_type: releaseType,
      is_scheduled_release: isScheduledRelease,
    },
  };
}

function normalizeMacroArticle(definition: MacroSourceDefinition, article: RawMacroArticle) {
  const releaseType = detectReleaseType(definition, article);
  const isScheduledRelease = detectScheduledRelease(definition, releaseType, article);

  return {
    title: article.title,
    content: article.content,
    url: article.url,
    source_url: article.sourceUrl,
    published_at: article.publishedAt,
    lang: article.lang ?? "en",
    tags: [...new Set([...(article.tags ?? []), definition.id, definition.name, releaseType])],
    release_type: releaseType,
    is_scheduled_release: isScheduledRelease,
    authority_score: definition.authorityScore,
    canonical: buildCanonicalArticle(definition, article, releaseType, isScheduledRelease),
  } satisfies NormalizedMacroArticle;
}

function normalizeFeedArticle(
  definition: MacroSourceDefinition,
  entry: Record<string, unknown>,
  sourceUrl: string,
): RawMacroArticle | null {
  const title = readText(entry.title);
  const url = extractUrl(entry.link) ?? extractUrl(entry.guid) ?? extractUrl(readText(entry.id));

  if (!title || !url) {
    return null;
  }

  const summary =
    readText(entry.description) ??
    readText(entry.summary) ??
    readText(entry["content:encoded"]) ??
    readText(entry.content);

  return {
    title: decodeHtml(title),
    content: summary ? decodeHtml(summary) : undefined,
    url,
    sourceUrl,
    publishedAt: parsePublishedAt(entry),
    lang: "en",
    tags: extractTags(entry),
  };
}

async function collectFeedArticles(definition: MacroSourceDefinition) {
  const seenUrls = new Set<string>();
  const collected: NormalizedMacroArticle[] = [];
  const sourceUrls = definition.urls ?? [definition.url];

  for (const sourceUrl of sourceUrls) {
    const payload = await fetchText(
      sourceUrl,
      "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
    );

    for (const entry of normalizeFeedEntries(payload)) {
      const rawArticle = normalizeFeedArticle(definition, entry, sourceUrl);

      if (!rawArticle || seenUrls.has(rawArticle.url)) {
        continue;
      }

      seenUrls.add(rawArticle.url);
      collected.push(normalizeMacroArticle(definition, rawArticle));
    }
  }

  return collected;
}

async function collectImfArticles(definition: MacroSourceDefinition) {
  const payload = await fetchText(definition.url, "text/html,application/xhtml+xml");
  const matches = payload.matchAll(
    /<li><a href="([^"]+)"><span>([^<]+)<\/span>([\s\S]*?)<\/a><\/li>/gi,
  );
  const seenUrls = new Set<string>();
  const collected: NormalizedMacroArticle[] = [];

  for (const match of matches) {
    const url = absolutizeUrl(definition.url, decodeHtml(match[1]));
    if (seenUrls.has(url)) {
      continue;
    }

    const title = decodeHtml(match[3]).trim();
    const dateText = decodeHtml(match[2]).trim();
    const publishedAt = Number.isNaN(new Date(dateText).getTime())
      ? undefined
      : new Date(dateText).toISOString();

    if (!title) {
      continue;
    }

    seenUrls.add(url);
    collected.push(
      normalizeMacroArticle(definition, {
        title,
        content: title,
        url,
        sourceUrl: definition.url,
        publishedAt,
        lang: "en",
        tags: ["IMF", "Latest News"],
      }),
    );
  }

  return collected;
}

async function collectBlsArticles(definition: MacroSourceDefinition) {
  const payload = await fetchText(
    definition.url,
    "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
  );
  const entries = normalizeFeedEntries(payload);
  const primaryEntry = entries[0];

  if (!primaryEntry) {
    return [];
  }

  const description = readText(primaryEntry.description) ?? "";
  const publishedAt = parsePublishedAt(primaryEntry) ?? undefined;
  const matches = description.matchAll(
    /<p>\s*([^:<]+?)\s*:\s*<br>\s*<strong>([\s\S]*?)<\/strong>\s*<br>\s*<a href="([^"]+)">News Release<\/a>/gi,
  );

  const collected: NormalizedMacroArticle[] = [];
  const seenUrls = new Set<string>();

  for (const match of matches) {
    const label = decodeHtml(match[1]).trim();
    const value = decodeHtml(match[2]).trim();
    const url = absolutizeUrl(definition.url, decodeHtml(match[3]));

    if (!label || seenUrls.has(url)) {
      continue;
    }

    seenUrls.add(url);
    collected.push(
      normalizeMacroArticle(definition, {
        title: `${label}: ${value}`.trim(),
        content: value,
        url,
        sourceUrl: definition.url,
        publishedAt,
        lang: "en",
        tags: ["BLS", label],
      }),
    );
  }

  return collected;
}

async function collectSourceArticles(definition: MacroSourceDefinition) {
  switch (definition.fetchMode) {
    case "imf_news":
      return collectImfArticles(definition);
    case "bls_latest":
      return collectBlsArticles(definition);
    case "oecd_rss":
    case "feed":
      return collectFeedArticles(definition);
    default:
      return [];
  }
}

async function upsertCountry(definition: MacroSourceDefinition) {
  const result = await query<CountryRow>(
    `
      INSERT INTO countries (name, code_iso, region, active, updated_at)
      VALUES ($1, $2, $3, $4, NOW())
      ON CONFLICT (code_iso)
      DO UPDATE
      SET
        name = EXCLUDED.name,
        region = EXCLUDED.region,
        active = EXCLUDED.active,
        updated_at = NOW()
      RETURNING id
    `,
    [
      definition.country.name,
      definition.country.code_iso,
      definition.country.region,
      definition.country.active,
    ],
  );

  return result.rows[0];
}

async function upsertSource(countryId: number, definition: MacroSourceDefinition) {
  const existingSource = await query<SourceRow>(
    `
      SELECT id
      FROM sources
      WHERE slug = $1 OR (country_id = $2 AND (url = $3 OR name = $4))
      ORDER BY CASE WHEN slug = $1 THEN 0 ELSE 1 END
      LIMIT 1
    `,
    [definition.id, countryId, definition.url, definition.name],
  );

  if ((existingSource.rowCount ?? 0) > 0) {
    const result = await query<SourceRow>(
      `
        UPDATE sources
        SET
          country_id = $2,
          type = $3,
          slug = $4,
          url = $5,
          name = $6,
          active = TRUE
        WHERE id = $1
        RETURNING id
      `,
      [existingSource.rows[0].id, countryId, definition.type, definition.id, definition.url, definition.name],
    );

    return result.rows[0];
  }

  const result = await query<SourceRow>(
    `
      INSERT INTO sources (country_id, type, slug, url, name, active)
      VALUES ($1, $2, $3, $4, $5, TRUE)
      RETURNING id
    `,
    [countryId, definition.type, definition.id, definition.url, definition.name],
  );

  return result.rows[0];
}

async function createScrapeJob(countryId: number) {
  const result = await query<JobRow>(
    `
      INSERT INTO scrape_jobs (country_id, status, started_at)
      VALUES ($1, 'running', NOW())
      RETURNING id
    `,
    [countryId],
  );

  return result.rows[0];
}

async function finalizeScrapeJob(jobId: number, status: "success" | "failed", articlesCount: number) {
  await query(
    `
      UPDATE scrape_jobs
      SET status = $2, articles_count = $3, finished_at = NOW()
      WHERE id = $1
    `,
    [jobId, status, articlesCount],
  );
}

async function touchSource(sourceId: number) {
  await query(
    `
      UPDATE sources
      SET last_scraped_at = NOW()
      WHERE id = $1
    `,
    [sourceId],
  );
}

async function insertArticles(
  countryId: number,
  sourceId: number,
  articles: NormalizedMacroArticle[],
) {
  let affectedArticles = 0;

  for (const batch of chunk(articles, INSERT_CHUNK_SIZE)) {
    const params: unknown[] = [sourceId, countryId];
    const values = batch
      .map((article, index) => {
        const base = 3 + index * 11;

        params.push(
          article.title,
          article.content ?? null,
          article.url,
          article.published_at ?? null,
          article.lang ?? null,
          article.tags,
          "macro_global",
          article.release_type,
          article.is_scheduled_release,
          article.authority_score,
          JSON.stringify(article.canonical),
        );

        return `($1, $2, $${base}, $${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6}, $${base + 7}, $${base + 8}, $${base + 9}, $${base + 10})`;
      })
      .join(", ");

    const result = await query(
      `
        INSERT INTO articles (
          source_id,
          country_id,
          title,
          content,
          url,
          published_at,
          lang,
          tags,
          news_type,
          release_type,
          is_scheduled_release,
          authority_score,
          canonical
        )
        VALUES ${values}
        ON CONFLICT (url)
        DO UPDATE SET
          source_id = EXCLUDED.source_id,
          country_id = EXCLUDED.country_id,
          title = EXCLUDED.title,
          content = EXCLUDED.content,
          published_at = COALESCE(EXCLUDED.published_at, articles.published_at),
          lang = COALESCE(EXCLUDED.lang, articles.lang),
          tags = EXCLUDED.tags,
          news_type = EXCLUDED.news_type,
          release_type = EXCLUDED.release_type,
          is_scheduled_release = EXCLUDED.is_scheduled_release,
          authority_score = EXCLUDED.authority_score,
          canonical = EXCLUDED.canonical,
          scraped_at = NOW()
      `,
      params,
    );

    affectedArticles += result.rowCount ?? 0;
  }

  return affectedArticles;
}

export async function scrapeMacroSource(sourceId: MacroSourceId) {
  if (!hasDatabaseUrl()) {
    throw new Error("DATABASE_URL is not configured.");
  }

  const definition = getMacroSourceById(sourceId);

  if (!definition) {
    throw new Error(`Unknown macro source: ${sourceId}`);
  }

  const countryRow = await upsertCountry(definition);
  const sourceRow = await upsertSource(countryRow.id, definition);
  const scrapeJob = await createScrapeJob(countryRow.id);

  let affectedArticles = 0;

  try {
    const articles = await collectSourceArticles(definition);
    affectedArticles = await insertArticles(countryRow.id, sourceRow.id, articles);
    await finalizeScrapeJob(scrapeJob.id, "success", affectedArticles);
    await touchSource(sourceRow.id);

    return {
      source_id: sourceId,
      source_name: definition.name,
      status: "success" as const,
      articles_collected: affectedArticles,
      articles_seen: articles.length,
      country_code: definition.country.code_iso,
    };
  } catch (error) {
    await finalizeScrapeJob(scrapeJob.id, "failed", affectedArticles);
    await touchSource(sourceRow.id);

    return {
      source_id: sourceId,
      source_name: definition.name,
      status: "failed" as const,
      articles_collected: affectedArticles,
      country_code: definition.country.code_iso,
      error: error instanceof Error ? error.message : "Unknown macro scrape error",
    };
  }
}

export async function scrapeMacroGlobalSources() {
  const results = [];

  for (const source of listMacroSources()) {
    results.push(await scrapeMacroSource(source.id));
  }

  const successful = results.filter((result) => result.status === "success");
  const failed = results.filter((result) => result.status === "failed");

  return {
    type: "macro_global",
    sources_attempted: results.length,
    sources_succeeded: successful.length,
    sources_failed: failed.length,
    articles_collected: results.reduce((total, result) => total + result.articles_collected, 0),
    results,
  };
}
