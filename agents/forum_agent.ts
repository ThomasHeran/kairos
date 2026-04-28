import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";
import {
  buildFeedArticles,
  fetchTextUpstream,
  formatAgentError,
  upstreamStatusMessage,
} from "@/lib/source-agent";

export class ForumAgent extends BaseSourceAgent {
  readonly type = "forum" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    try {
      const { response, payload } = await fetchTextUpstream(source.url);

      if (!response.ok) {
        return this.failed(country, source, `${upstreamStatusMessage(response)}.`);
      }

      const query = new URL(source.url).searchParams.get("q")?.trim().toLowerCase();
      const articles = buildFeedArticles(country, source, payload, () => ({
        sourceName: query ? `Hacker News / ${query}` : source.name,
        tags: ["hackernews", query].filter((tag): tag is string => Boolean(tag)),
        lang: "en",
      }));

      return this.complete(
        country,
        source,
        articles,
        `fetched ${articles.length} Hacker News articles.`,
      );
    } catch (error) {
      return this.failed(country, source, formatAgentError(error));
    }
  }
}
