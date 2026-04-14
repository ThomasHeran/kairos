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
  source_type: string;
};

export async function listNews(countrySlug?: string) {
  const filters = countrySlug ? { country: countrySlug } : undefined;

  if (!hasDatabaseUrl()) {
    return {
      articles: [],
      total: 0,
      filters,
      source: "database_unconfigured",
    };
  }

  const country = countrySlug ? getCountryBySlug(countrySlug) : undefined;

  if (countrySlug && !country) {
    return {
      articles: [],
      total: 0,
      filters,
      source: "database",
      warning: "unknown_country",
    };
  }

  const params: Array<number | string> = [];
  let whereClause = "";

  if (country) {
    params.push(country.code_iso);
    whereClause = `WHERE c.code_iso = $${params.length}`;
  }

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
          s.type AS source_type
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
      filters,
      source: "database",
    };
  } catch (error) {
    return {
      articles: [],
      total: 0,
      filters,
      source: "database",
      error: error instanceof Error ? error.message : "Unknown database error",
    };
  }
}
