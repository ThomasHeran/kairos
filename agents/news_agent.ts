import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";

export class NewsAgent extends BaseSourceAgent {
  readonly type = "news" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    return this.placeholder(
      country,
      source,
      "Generic news agent scaffolded; publisher-specific logic can be added here.",
    );
  }
}
