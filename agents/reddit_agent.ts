import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";
import {
  buildFeedArticles,
  fetchTextUpstream,
  formatAgentError,
  looksLikeHtml,
  normalizeArticle,
  normalizeIsoDate,
  upstreamStatusMessage,
} from "@/lib/source-agent";

type RedditListing = {
  data?: {
    children?: Array<{
      data?: {
        title?: string;
        url?: string;
        url_overridden_by_dest?: string;
        selftext?: string;
        created_utc?: number;
        subreddit?: string;
        permalink?: string;
        stickied?: boolean;
      };
    }>;
  };
};

function resolveRedditRssUrl(url: string) {
  if (url.endsWith(".rss")) {
    return url;
  }

  return url.replace(/\.json(?:\?.*)?$/i, ".rss");
}

function resolveSubredditName(url: string, rawSubreddit?: string) {
  if (rawSubreddit) {
    return rawSubreddit;
  }

  const match = url.match(/\/r\/([^/?#]+)/i);
  return match?.[1];
}

export class RedditAgent extends BaseSourceAgent {
  readonly type = "reddit" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    try {
      const { response, payload } = await fetchTextUpstream(source.url, {
        accept: "application/json, text/json;q=0.9, */*;q=0.8",
        userAgent: "Kairos/1.0",
      });

      if (response.ok && !looksLikeHtml(payload)) {
        const data = JSON.parse(payload) as RedditListing;
        const articles = (data.data?.children ?? [])
          .map((entry) => entry.data)
          .filter((entry): entry is NonNullable<typeof entry> => Boolean(entry))
          .filter((entry) => !entry.stickied)
          .map((entry) => {
            const subreddit = resolveSubredditName(source.url, entry.subreddit);
            const targetUrl =
              entry.url_overridden_by_dest ??
              entry.url ??
              (entry.permalink ? `https://www.reddit.com${entry.permalink}` : undefined);

            if (!entry.title || !targetUrl) {
              return null;
            }

            return normalizeArticle(country, source, {
              title: entry.title,
              url: targetUrl,
              content: entry.selftext ?? null,
              publishedAt: normalizeIsoDate((entry.created_utc ?? Date.now() / 1000) * 1000),
              sourceName: subreddit ? `Reddit /r/${subreddit}` : source.name,
              tags: ["reddit", subreddit ? `subreddit:${subreddit.toLowerCase()}` : undefined].filter(
                (tag): tag is string => Boolean(tag),
              ),
              lang: subreddit === "france" ? "fr" : "en",
            });
          })
          .filter((article): article is NonNullable<typeof article> => Boolean(article));

        return this.complete(country, source, articles, `fetched ${articles.length} Reddit articles.`);
      }

      if (!response.ok && response.status !== 403) {
        return this.failed(country, source, `${upstreamStatusMessage(response)}.`);
      }

      const rssUrl = resolveRedditRssUrl(source.url);
      const rssResponse = await fetchTextUpstream(rssUrl, { userAgent: "Kairos/1.0" });

      if (!rssResponse.response.ok) {
        return this.failed(
          country,
          source,
          `Reddit JSON blocked and RSS fallback returned ${rssResponse.response.status}.`,
        );
      }

      const articles = buildFeedArticles(country, source, rssResponse.payload, (entry) => {
        const subreddit =
          (Array.isArray(entry.category) ? entry.category : [entry.category])
            .map((category) => {
              if (!category || typeof category !== "object") {
                return undefined;
              }

              const term = category["@_term"];
              return typeof term === "string" ? term : undefined;
            })
            .find(Boolean) ?? resolveSubredditName(source.url);

        return {
          sourceName: subreddit ? `Reddit /r/${subreddit}` : source.name,
          tags: ["reddit", subreddit ? `subreddit:${subreddit.toLowerCase()}` : undefined].filter(
            (tag): tag is string => Boolean(tag),
          ),
          lang: subreddit === "france" ? "fr" : "en",
        };
      });

      return this.complete(
        country,
        source,
        articles,
        `fetched ${articles.length} Reddit articles via RSS fallback.`,
      );
    } catch (error) {
      return this.failed(country, source, formatAgentError(error));
    }
  }
}
