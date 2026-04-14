import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";

export class RSSAgent extends BaseSourceAgent {
  readonly type = "rss" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    return this.placeholder(
      country,
      source,
      "RSS agent scaffolded; parsing logic can be added here.",
    );
  }
}
