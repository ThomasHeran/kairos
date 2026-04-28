import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";
import {
  buildFeedArticles,
  fetchTextUpstream,
  formatAgentError,
  looksLikeHtml,
  upstreamStatusMessage,
} from "@/lib/source-agent";

export class NewsAgent extends BaseSourceAgent {
  readonly type = "news" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    try {
      const { response, payload } = await fetchTextUpstream(source.url);

      if (!response.ok) {
        return this.failed(country, source, `${upstreamStatusMessage(response)}.`);
      }

      if (looksLikeHtml(payload)) {
        return this.failed(country, source, "publisher returned HTML instead of RSS.");
      }

      const articles = buildFeedArticles(country, source, payload, () => ({
        sourceName: source.name,
      }));

      return this.complete(country, source, articles, `fetched ${articles.length} news articles.`);
    } catch (error) {
      return this.failed(country, source, formatAgentError(error));
    }
  }
}
