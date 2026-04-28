export type SourceType = "rss" | "twitter" | "reddit" | "forum" | "news" | "scraping" | "api";

export type ScrapedArticleCountry = "france" | "us" | "japan" | "global";
export type ScrapedArticleLanguage = "fr" | "en" | "ja";

export type SourceConfig = {
  id: number;
  type: SourceType;
  url: string;
  name: string;
  active: boolean;
};

export type CountryConfig = {
  id: number;
  name: string;
  code_iso: string;
  region: string;
  active: boolean;
  sources: SourceConfig[];
};

export type ScrapedArticle = {
  title: string;
  content: string | null;
  url: string;
  published_at: string;
  source: string;
  country: ScrapedArticleCountry;
  tags: string[];
  lang: ScrapedArticleLanguage;
};

export type ScrapeResult = {
  status: "idle" | "success" | "failed";
  articles: ScrapedArticle[];
  notes?: string;
};
