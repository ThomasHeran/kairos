import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";
import {
  buildFeedArticles,
  fetchTextUpstream,
  formatAgentError,
  looksLikeProtectionWall,
} from "@/lib/source-agent";

const NITTER_INSTANCES = [
  "https://nitter.net",
  "https://nitter.poast.org",
  "https://nitter.privacydev.net",
];

function buildCandidateUrls(source: SourceConfig) {
  if (/nitter\./i.test(source.url)) {
    return [source.url];
  }

  const query = source.name.trim().toLowerCase().replace(/\s+/g, "+");
  const usernameMatch = source.url.match(/x\.com\/([^/?#]+)/i);
  const username = usernameMatch?.[1];

  return NITTER_INSTANCES.flatMap((instance) => {
    const urls = [`${instance}/search/rss?q=${encodeURIComponent(query)}`];

    if (username) {
      urls.unshift(`${instance}/${username}/rss`);
    }

    return urls;
  });
}

export class TwitterAgent extends BaseSourceAgent {
  readonly type = "twitter" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    try {
      for (const url of buildCandidateUrls(source)) {
        try {
          const { response, payload } = await fetchTextUpstream(url);

          if (!response.ok) {
            continue;
          }

          if (!payload.trim() || looksLikeProtectionWall(payload)) {
            continue;
          }

          const articles = buildFeedArticles(country, source, payload, () => ({
            sourceName: source.name,
            tags: ["social", "twitter", "nitter"],
            lang: "en",
          }));

          if (articles.length > 0) {
            return this.complete(
              country,
              source,
              articles,
              `fetched ${articles.length} social signal articles via Nitter.`,
            );
          }
        } catch {
          continue;
        }
      }

      return this.idle(
        country,
        source,
        "no public Nitter RSS instance was readable; social signals were skipped.",
      );
    } catch (error) {
      return this.idle(country, source, formatAgentError(error));
    }
  }
}
