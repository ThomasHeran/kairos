export type SourceType = "rss" | "twitter" | "reddit" | "forum" | "news" | "scraping" | "api";

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
  content?: string;
  url: string;
  published_at?: string;
  lang?: string;
  tags?: string[];
};

export type ScrapeResult = {
  status: "idle" | "success" | "failed";
  articles: ScrapedArticle[];
  notes?: string;
};
