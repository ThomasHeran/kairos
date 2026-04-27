import { getCountryBySlug } from "@/lib/config";
import { hasDatabaseUrl, query } from "@/lib/db";

type ArticleRow = {
  id: number;
  title: string;
  content: string | null;
  url: string;
  published_at: string | null;
  scraped_at: string | null;
  lang: string | null;
  tags: string[] | null;
  country_code: string;
  country_name: string;
  source_name: string;
  source_slug: string | null;
  source_type: string;
  news_type: string;
  release_type: string | null;
  is_scheduled_release: boolean;
  authority_score: string | null;
  canonical: Record<string, unknown> | null;
};

type ListNewsFilters = {
  country?: string;
  type?: string;
  source?: string;
  release_type?: string;
};

export async function listNews(filters: ListNewsFilters = {}) {
  const resolvedFilters = Object.fromEntries(
    Object.entries(filters).filter(([, value]) => value !== undefined && value !== ""),
  );

  if (!hasDatabaseUrl()) {
    return {
      articles: [],
      total: 0,
      filters: Object.keys(resolvedFilters).length > 0 ? resolvedFilters : undefined,
      source: "database_unconfigured",
    };
  }

  const country = filters.country ? getCountryBySlug(filters.country) : undefined;

  if (filters.country && !country) {
    return {
      articles: [],
      total: 0,
      filters: Object.keys(resolvedFilters).length > 0 ? resolvedFilters : undefined,
      source: "database",
      warning: "unknown_country",
    };
  }

  const params: Array<number | string> = [];
  const whereClauses: string[] = [];

  if (country) {
    params.push(country.code_iso);
    whereClauses.push(`c.code_iso = $${params.length}`);
  }

  if (filters.type) {
    params.push(filters.type);
    whereClauses.push(`a.news_type = $${params.length}`);
  }

  if (filters.source) {
    params.push(filters.source);
    whereClauses.push(`(s.slug = $${params.length} OR s.name ILIKE $${params.length})`);
  }

  if (filters.release_type) {
    params.push(filters.release_type);
    whereClauses.push(`a.release_type = $${params.length}`);
  }

  const whereClause = whereClauses.length > 0 ? `WHERE ${whereClauses.join(" AND ")}` : "";

  try {
    const result = await query<ArticleRow>(
      `
        SELECT
          a.id,
          a.title,
          a.content,
          a.url,
          a.published_at,
          a.scraped_at,
          a.lang,
          a.tags,
          c.code_iso AS country_code,
          c.name AS country_name,
          s.name AS source_name,
          s.slug AS source_slug,
          s.type AS source_type,
          a.news_type,
          a.release_type,
          a.is_scheduled_release,
          a.authority_score::text,
          a.canonical
        FROM articles a
        INNER JOIN countries c ON c.id = a.country_id
        INNER JOIN sources s ON s.id = a.source_id
        ${whereClause}
        ORDER BY a.published_at DESC NULLS LAST, a.scraped_at DESC NULLS LAST
        LIMIT 100
      `,
      params,
    );

    return {
      articles: result.rows,
      total: result.rowCount ?? result.rows.length,
      filters: Object.keys(resolvedFilters).length > 0 ? resolvedFilters : undefined,
      source: "database",
    };
  } catch (error) {
    return {
      articles: [],
      total: 0,
      filters: Object.keys(resolvedFilters).length > 0 ? resolvedFilters : undefined,
      source: "database",
      error: error instanceof Error ? error.message : "Unknown database error",
    };
  }
}
