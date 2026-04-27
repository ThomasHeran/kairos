import { XMLParser } from "fast-xml-parser";
import { decode } from "he";

type FeedNode = Record<string, unknown>;

const parser = new XMLParser({
  ignoreAttributes: false,
  parseTagValue: false,
  trimValues: true,
});

export type ParsedFeedEntry = FeedNode;

function asArray<T>(value: T | T[] | undefined): T[] {
  if (!value) {
    return [];
  }

  return Array.isArray(value) ? value : [value];
}

export function readText(value: unknown): string | undefined {
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

export function decodeHtml(value: string) {
  return decode(value)
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function extractUrl(value: unknown): string | undefined {
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

export function parsePublishedAt(node: FeedNode): string | undefined {
  const rawValue =
    readText(node.pubDate) ??
    readText(node.published) ??
    readText(node.updated) ??
    readText(node["dc:date"]) ??
    readText(node["dcterms:issued"]) ??
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

export function extractTags(node: FeedNode): string[] {
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

export function normalizeFeedEntries(payload: string) {
  const parsed = parser.parse(payload) as FeedNode;
  const rssRoot = parsed.rss as FeedNode | undefined;
  const atomFeed = parsed.feed as FeedNode | undefined;
  const rdfFeed = (parsed["rdf:RDF"] ?? parsed.RDF) as FeedNode | undefined;

  if (rssRoot && typeof rssRoot === "object") {
    return asArray(((rssRoot.channel as FeedNode | undefined)?.item as FeedNode | FeedNode[] | undefined));
  }

  if (atomFeed && typeof atomFeed === "object") {
    return asArray(atomFeed.entry as FeedNode | FeedNode[] | undefined);
  }

  if (rdfFeed && typeof rdfFeed === "object") {
    return asArray(rdfFeed.item as FeedNode | FeedNode[] | undefined);
  }

  return [];
}

export function absolutizeUrl(baseUrl: string, value: string) {
  try {
    return new URL(value, baseUrl).toString();
  } catch {
    return value;
  }
}
