import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";

export class ForumAgent extends BaseSourceAgent {
  readonly type = "forum" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    return this.placeholder(
      country,
      source,
      "Forum agent scaffolded; HTML extraction logic can be added here.",
    );
  }
}
