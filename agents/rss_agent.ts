import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";
import {
  decodeHtml,
  extractTags,
  extractUrl,
  normalizeFeedEntries,
  parsePublishedAt,
  readText,
} from "@/lib/feed";

export class RSSAgent extends BaseSourceAgent {
  readonly type = "rss" as const;

  async scrape(country: CountryConfig, source: SourceConfig): Promise<ScrapeResult> {
    try {
      const response = await fetch(source.url, {
        headers: {
          "user-agent": `KairosBot/1.0 (+${country.code_iso})`,
          accept: "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
        },
        cache: "no-store",
        signal: AbortSignal.timeout(20_000),
      });

      if (!response.ok) {
        return {
          status: "failed",
          articles: [],
          notes: `[${country.code_iso}] ${source.name}: upstream returned ${response.status}.`,
        };
      }

      const feedPayload = await response.text();
      const seenUrls = new Set<string>();
      const articles = normalizeFeedEntries(feedPayload)
        .map((entry) => {
          const title = readText(entry.title);
          const url =
            extractUrl(entry.link) ??
            extractUrl(entry.guid) ??
            extractUrl(readText(entry.id));

          if (!title || !url || seenUrls.has(url)) {
            return null;
          }

          seenUrls.add(url);

          const summary =
            readText(entry.description) ??
            readText(entry.summary) ??
            readText(entry["content:encoded"]) ??
            readText(entry.content);

          return {
            title: decodeHtml(title),
            content: summary ? decodeHtml(summary) : undefined,
            url,
            published_at: parsePublishedAt(entry),
            lang: country.code_iso.toLowerCase() === "fr" ? "fr" : undefined,
            tags: extractTags(entry),
          };
        })
        .filter((article) => article !== null);

      return {
        status: "success",
        articles,
        notes: `[${country.code_iso}] ${source.name}: fetched ${articles.length} RSS articles.`,
      };
    } catch (error) {
      return {
        status: "failed",
        articles: [],
        notes: `[${country.code_iso}] ${source.name}: ${
          error instanceof Error ? error.message : "Unknown RSS fetch error"
        }`,
      };
    }
  }
}
