import type { CountryConfig, ScrapeResult, SourceConfig, SourceType } from "@/agents/types";

export abstract class BaseSourceAgent {
  abstract readonly type: SourceType;

  abstract scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult>;

  protected placeholder(
    country: CountryConfig,
    source: SourceConfig,
    notes: string,
  ): ScrapeResult {
    return {
      status: "idle",
      articles: [],
      notes: `[${country.code_iso}] ${source.name}: ${notes}`,
    };
  }
}
