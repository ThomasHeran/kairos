import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";

export class TwitterAgent extends BaseSourceAgent {
  readonly type = "twitter" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    return this.placeholder(
      country,
      source,
      "Twitter/X agent scaffolded; API or browser collector can be added here.",
    );
  }
}
