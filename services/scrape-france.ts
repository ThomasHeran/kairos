import { getAgentForType } from "@/agents";
import type { CountryConfig, ScrapedArticle, SourceConfig } from "@/agents/types";
import { getCountryBySlug } from "@/lib/config";
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

const INSERT_CHUNK_SIZE = 50;

function chunk<T>(items: T[], size: number) {
  const chunks: T[][] = [];

  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }

  return chunks;
}

async function upsertCountry(country: CountryConfig) {
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
    [country.name, country.code_iso, country.region, country.active],
  );

  return result.rows[0];
}

async function upsertSource(countryId: number, source: SourceConfig) {
  const existingSource = await query<SourceRow>(
    `
      SELECT id
      FROM sources
      WHERE country_id = $1 AND (url = $2 OR name = $3)
      ORDER BY CASE WHEN url = $2 THEN 0 ELSE 1 END
      LIMIT 1
    `,
    [countryId, source.url, source.name],
  );

  if ((existingSource.rowCount ?? 0) > 0) {
    const result = await query<SourceRow>(
      `
        UPDATE sources
        SET
          type = $2,
          url = $3,
          name = $4,
          active = $5
        WHERE id = $1
        RETURNING id
      `,
      [existingSource.rows[0].id, source.type, source.url, source.name, source.active],
    );

    return result.rows[0];
  }

  const result = await query<SourceRow>(
    `
      INSERT INTO sources (country_id, type, url, name, active)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING id
    `,
    [countryId, source.type, source.url, source.name, source.active],
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

async function insertArticles(countryId: number, sourceId: number, articles: ScrapedArticle[]) {
  let insertedArticles = 0;

  for (const batch of chunk(articles, INSERT_CHUNK_SIZE)) {
    const params: unknown[] = [sourceId, countryId];
    const values = batch
      .map((article, index) => {
        const base = 3 + index * 6;

        params.push(
          article.title,
          article.content ?? null,
          article.url,
          article.published_at ?? null,
          article.lang ?? null,
          article.tags ?? [],
        );

        return `($1, $2, $${base}, $${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5})`;
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
          tags
        )
        VALUES ${values}
        ON CONFLICT (url) DO NOTHING
      `,
      params,
    );

    insertedArticles += result.rowCount ?? 0;
  }

  return insertedArticles;
}

function getFranceCountryConfig() {
  const country = getCountryBySlug("fr");

  if (!country) {
    throw new Error("France country config is missing.");
  }

  return country;
}

async function scrapeCountrySources(countrySlug: string) {
  if (!hasDatabaseUrl()) {
    throw new Error("DATABASE_URL is not configured.");
  }

  const country =
    countrySlug === "fr" || countrySlug === "france"
      ? getFranceCountryConfig()
      : getCountryBySlug(countrySlug);

  if (!country) {
    throw new Error(`Country config is missing for "${countrySlug}".`);
  }

  const activeSources = country.sources.filter((source) => source.active);
  const countryRow = await upsertCountry(country);
  const scrapeJob = await createScrapeJob(countryRow.id);

  let articlesCollected = 0;
  let sourcesScraped = 0;
  let sourcesFailed = 0;
  let sourcesIdle = 0;

  try {
    for (const source of activeSources) {
      const sourceRow = await upsertSource(countryRow.id, source);

      try {
        const agent = getAgentForType(source.type);
        const result = await agent.scrape(country, source);

        if (result.status === "failed") {
          sourcesFailed += 1;
        } else if (result.status === "idle") {
          sourcesIdle += 1;
        } else {
          articlesCollected += await insertArticles(countryRow.id, sourceRow.id, result.articles);
        }
      } catch {
        sourcesFailed += 1;
      } finally {
        sourcesScraped += 1;
        await touchSource(sourceRow.id);
      }
    }

    const jobStatus = sourcesFailed === sourcesScraped ? "failed" : "success";
    await finalizeScrapeJob(scrapeJob.id, jobStatus, articlesCollected);

    return {
      articles_collected: articlesCollected,
      sources_scraped: sourcesScraped,
      sources_failed: sourcesFailed,
      sources_idle: sourcesIdle,
      job_status: jobStatus,
    };
  } catch (error) {
    await finalizeScrapeJob(scrapeJob.id, "failed", articlesCollected);
    throw error;
  }
}

export async function scrapeFranceSources() {
  return scrapeCountrySources("fr");
}

export async function scrapeFranceRssFeeds() {
  return scrapeFranceSources();
}
