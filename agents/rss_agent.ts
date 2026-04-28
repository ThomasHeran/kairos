import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";
import {
  buildFeedArticles,
  fetchTextUpstream,
  formatAgentError,
  upstreamStatusMessage,
} from "@/lib/source-agent";

export class RSSAgent extends BaseSourceAgent {
  readonly type = "rss" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    try {
      const { response, payload } = await fetchTextUpstream(source.url);

      if (!response.ok) {
        return this.failed(country, source, `${upstreamStatusMessage(response)}.`);
      }

      const articles = buildFeedArticles(country, source, payload);

      return this.complete(country, source, articles, `fetched ${articles.length} RSS articles.`);
    } catch (error) {
      return this.failed(country, source, formatAgentError(error));
    }
  }
}
