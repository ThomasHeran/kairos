import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";

export class RedditAgent extends BaseSourceAgent {
  readonly type = "reddit" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    return this.placeholder(
      country,
      source,
      "Reddit agent scaffolded; collector logic can be added here.",
    );
  }
}
