import { BaseSourceAgent } from "@/agents/base-agent";
import type { CountryConfig, ScrapeResult, SourceConfig } from "@/agents/types";
import { XMLParser } from "fast-xml-parser";
import { decode } from "he";

type FeedNode = Record<string, unknown>;

const parser = new XMLParser({
  ignoreAttributes: false,
  parseTagValue: false,
  trimValues: true,
});

function asArray<T>(value: T | T[] | undefined): T[] {
  if (!value) {
    return [];
  }

  return Array.isArray(value) ? value : [value];
}

function readText(value: unknown): string | undefined {
  if (typeof value === "string") {
    const normalized = value.trim();
    return normalized.length > 0 ? normalized : undefined;
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      const text = readText(entry);
      if (text) {
        return text;
      }
    }

    return undefined;
  }

  if (!value || typeof value !== "object") {
    return undefined;
  }

  const node = value as FeedNode;

  for (const key of ["#text", "__text", "__cdata"]) {
    const text = readText(node[key]);
    if (text) {
      return text;
    }
  }

  return undefined;
}

function decodeHtml(value: string) {
  return decode(value)
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extractUrl(value: unknown): string | undefined {
  if (typeof value === "string") {
    const normalized = value.trim();
    if (normalized.startsWith("http://") || normalized.startsWith("https://")) {
      return normalized;
    }

    return undefined;
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      const url = extractUrl(entry);
      if (url) {
        return url;
      }
    }

    return undefined;
  }

  if (!value || typeof value !== "object") {
    return undefined;
  }

  const node = value as FeedNode;
  const href = readText(node["@_href"]);

  if (href && (href.startsWith("http://") || href.startsWith("https://"))) {
    return href;
  }

  return extractUrl(readText(node));
}

function parsePublishedAt(node: FeedNode): string | undefined {
  const rawValue =
    readText(node.pubDate) ??
    readText(node.published) ??
    readText(node.updated) ??
    readText(node["dc:date"]) ??
    readText(node.date);

  if (!rawValue) {
    return undefined;
  }

  const parsed = new Date(rawValue);
  if (Number.isNaN(parsed.getTime())) {
    return undefined;
  }

  return parsed.toISOString();
}

function extractTags(node: FeedNode): string[] {
  const collected = new Set<string>();

  for (const category of asArray(node.category)) {
    const value = readText(category);
    if (value) {
      collected.add(decodeHtml(value));
    }
  }

  const subject = readText(node["dc:subject"]);
  if (subject) {
    for (const value of subject.split(",")) {
      const normalized = decodeHtml(value).trim();
      if (normalized) {
        collected.add(normalized);
      }
    }
  }

  return [...collected];
}

function normalizeFeedEntries(payload: string) {
  const parsed = parser.parse(payload) as FeedNode;
  const rssChannel = parsed.rss as FeedNode | undefined;
  const atomFeed = parsed.feed as FeedNode | undefined;

  if (rssChannel && typeof rssChannel === "object") {
    return asArray(((rssChannel.channel as FeedNode | undefined)?.item as FeedNode | FeedNode[] | undefined));
  }

  if (atomFeed && typeof atomFeed === "object") {
    return asArray(atomFeed.entry as FeedNode | FeedNode[] | undefined);
  }

  return [];
}

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
