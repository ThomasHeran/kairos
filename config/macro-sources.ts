import type { SourceType } from "@/agents/types";

export type MacroSourceId =
  | "fed"
  | "ecb"
  | "imf"
  | "bis"
  | "eurostat"
  | "oecd"
  | "bls"
  | "boe"
  | "boj";

export type MacroFetchMode = "feed" | "imf_news" | "bls_latest" | "oecd_rss";

export type MacroCountryConfig = {
  name: string;
  code_iso: string;
  region: string;
  active: boolean;
};

export type MacroSourceDefinition = {
  id: MacroSourceId;
  name: string;
  type: SourceType;
  url: string;
  urls?: string[];
  fetchMode: MacroFetchMode;
  authorityScore: number;
  country: MacroCountryConfig;
};

const EUROSTAT_ATOM_URL =
  "https://ec.europa.eu/eurostat/news/euro-indicators?p_p_id=estatsearchportlet_WAR_estatsearchportlet_INSTANCE_OaTpFrwlabNK&p_p_lifecycle=2&p_p_state=normal&p_p_mode=view&p_p_resource_id=atom&p_p_cacheability=cacheLevelPage&_estatsearchportlet_WAR_estatsearchportlet_INSTANCE_OaTpFrwlabNK_pageNumber=1&_estatsearchportlet_WAR_estatsearchportlet_INSTANCE_OaTpFrwlabNK_pageSize=11&_estatsearchportlet_WAR_estatsearchportlet_INSTANCE_OaTpFrwlabNK_sort=lastUpdateDate&_estatsearchportlet_WAR_estatsearchportlet_INSTANCE_OaTpFrwlabNK_collection=CAT_PREREL";

export const MACRO_SOURCES: MacroSourceDefinition[] = [
  {
    id: "fed",
    name: "Federal Reserve",
    type: "rss",
    url: "https://www.federalreserve.gov/feeds/press_all.xml",
    urls: [
      "https://www.federalreserve.gov/feeds/press_all.xml",
      "https://www.federalreserve.gov/feeds/press_monetary.xml",
    ],
    fetchMode: "feed",
    authorityScore: 0.99,
    country: {
      name: "United States",
      code_iso: "US",
      region: "US",
      active: true,
    },
  },
  {
    id: "ecb",
    name: "European Central Bank",
    type: "rss",
    url: "https://www.ecb.europa.eu/rss/press.html",
    urls: [
      "https://www.ecb.europa.eu/rss/press.html",
      "https://www.ecb.europa.eu/rss/statpress.html",
      "https://www.ecb.europa.eu/rss/pub.html",
    ],
    fetchMode: "feed",
    authorityScore: 0.99,
    country: {
      name: "Euro Area",
      code_iso: "EZ",
      region: "EZ",
      active: true,
    },
  },
  {
    id: "imf",
    name: "International Monetary Fund",
    type: "scraping",
    url: "https://www.imf.org/en/news",
    fetchMode: "imf_news",
    authorityScore: 0.98,
    country: {
      name: "Global",
      code_iso: "GL",
      region: "GLOBAL",
      active: true,
    },
  },
  {
    id: "bis",
    name: "Bank for International Settlements",
    type: "rss",
    url: "https://www.bis.org/doclist/cbspeeches.rss?paging_length=15",
    fetchMode: "feed",
    authorityScore: 0.97,
    country: {
      name: "Global",
      code_iso: "GL",
      region: "GLOBAL",
      active: true,
    },
  },
  {
    id: "eurostat",
    name: "Eurostat",
    type: "rss",
    url: EUROSTAT_ATOM_URL,
    fetchMode: "feed",
    authorityScore: 0.98,
    country: {
      name: "Euro Area",
      code_iso: "EZ",
      region: "EZ",
      active: true,
    },
  },
  {
    id: "oecd",
    name: "OECD",
    type: "rss",
    url: "https://www.oecd.org/newsroom/rss.xml",
    fetchMode: "oecd_rss",
    authorityScore: 0.97,
    country: {
      name: "Global",
      code_iso: "GL",
      region: "GLOBAL",
      active: true,
    },
  },
  {
    id: "bls",
    name: "U.S. Bureau of Labor Statistics",
    type: "rss",
    url: "https://www.bls.gov/feed/bls_latest.rss",
    fetchMode: "bls_latest",
    authorityScore: 0.99,
    country: {
      name: "United States",
      code_iso: "US",
      region: "US",
      active: true,
    },
  },
  {
    id: "boe",
    name: "Bank of England",
    type: "rss",
    url: "https://www.bankofengland.co.uk/rss/news",
    fetchMode: "feed",
    authorityScore: 0.98,
    country: {
      name: "United Kingdom",
      code_iso: "UK",
      region: "UK",
      active: true,
    },
  },
  {
    id: "boj",
    name: "Bank of Japan",
    type: "rss",
    url: "https://www.boj.or.jp/en/rss/whatsnew.xml?id=1002",
    fetchMode: "feed",
    authorityScore: 0.98,
    country: {
      name: "Japan",
      code_iso: "JP",
      region: "JP",
      active: true,
    },
  },
];

export function listMacroSources() {
  return MACRO_SOURCES;
}

export function getMacroSourceById(sourceId: string) {
  return MACRO_SOURCES.find((source) => source.id === sourceId);
}
