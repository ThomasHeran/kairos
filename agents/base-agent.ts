import type { CountryConfig, ScrapeResult, SourceConfig, SourceType } from "@/agents/types";

export abstract class BaseSourceAgent {
  abstract readonly type: SourceType;

  abstract scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult>;

  protected success(country: CountryConfig, source: SourceConfig, articlesCount: number): ScrapeResult["status"] {
    void country;
    void source;
    void articlesCount;

    return "success";
  }

  protected failed(country: CountryConfig, source: SourceConfig, notes: string): ScrapeResult {
    return {
      status: "failed",
      articles: [],
      notes: `[${country.code_iso}] ${source.name}: ${notes}`,
    };
  }

  protected idle(country: CountryConfig, source: SourceConfig, notes: string): ScrapeResult {
    return {
      status: "idle",
      articles: [],
      notes: `[${country.code_iso}] ${source.name}: ${notes}`,
    };
  }

  protected placeholder(
    country: CountryConfig,
    source: SourceConfig,
    notes: string,
  ): ScrapeResult {
    return this.idle(country, source, notes);
  }

  protected complete(
    country: CountryConfig,
    source: SourceConfig,
    articles: ScrapeResult["articles"],
    notes: string,
  ): ScrapeResult {
    return {
      status: this.success(country, source, articles.length),
      articles,
      notes: `[${country.code_iso}] ${source.name}: ${notes}`,
    };
  }
}
