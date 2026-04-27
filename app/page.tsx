"use client";

import { useState, useEffect, useCallback } from "react";

// ─── Types ─────────────────────────────────────────────────────────────────

type Country = {
  id: string;
  name: string;
  code_iso: string;
  region: string;
  active: boolean;
  sources_count: number;
};

type Article = {
  id: number;
  title: string;
  content: string | null;
  url: string;
  published_at: string | null;
  scraped_at: string | null;
  lang: string | null;
  country_code: string;
  country_name: string;
  source_name: string;
  source_slug: string | null;
  news_type: string;
  release_type: string | null;
  is_scheduled_release: boolean;
  authority_score: string | null;
};

// ─── Helpers ────────────────────────────────────────────────────────────────

const COUNTRY_FLAGS: Record<string, string> = {
  FR: "🇫🇷",
  US: "🇺🇸",
  JP: "🇯🇵",
  GB: "🇬🇧",
  DE: "🇩🇪",
  CN: "🇨🇳",
  IN: "🇮🇳",
  BR: "🇧🇷",
};

function getFlag(code_iso: string) {
  return COUNTRY_FLAGS[code_iso.toUpperCase()] ?? "🌐";
}

function timeAgo(dateStr: string | null): string {
  if (!dateStr) return "—";
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return "—";
  const diff = Date.now() - date.getTime();
  const mins = Math.floor(diff / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d ago`;
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function excerpt(content: string | null, maxLen = 140): string {
  if (!content) return "";
  const cleaned = content.replace(/<[^>]+>/g, "").trim();
  return cleaned.length > maxLen ? cleaned.slice(0, maxLen) + "…" : cleaned;
}

// ─── Sub-components ─────────────────────────────────────────────────────────

function Spinner({ size = 16 }: { size?: number }) {
  return (
    <span
      style={{
        display: "inline-block",
        width: size,
        height: size,
        border: `2px solid var(--border)`,
        borderTopColor: "var(--accent)",
        borderRadius: "50%",
        animation: "spin 0.7s linear infinite",
        flexShrink: 0,
      }}
    />
  );
}

function ArticleCard({ article }: { article: Article }) {
  const ts = article.published_at ?? article.scraped_at;
  const flag = getFlag(article.country_code);
  const blurb = excerpt(article.content);

  return (
    <article
      style={{
        borderRadius: "1.25rem",
        border: "1px solid var(--border)",
        background: "var(--surface-strong)",
        padding: "1.25rem 1.5rem",
        display: "flex",
        flexDirection: "column",
        gap: "0.6rem",
        transition: "box-shadow 0.18s, border-color 0.18s",
      }}
      onMouseEnter={(e) => {
        const el = e.currentTarget;
        el.style.boxShadow = "0 4px 24px rgba(93,67,38,0.10)";
        el.style.borderColor = "rgba(221,107,32,0.32)";
      }}
      onMouseLeave={(e) => {
        const el = e.currentTarget;
        el.style.boxShadow = "";
        el.style.borderColor = "var(--border)";
      }}
    >
      {/* Meta row */}
      <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", flexWrap: "wrap" }}>
        <span style={{ fontSize: "0.85rem" }}>{flag}</span>
        <span
          className="eyebrow"
          style={{ letterSpacing: "0.1em", fontSize: "0.68rem" }}
        >
          {article.source_name}
        </span>
        {article.release_type && (
          <span
            style={{
              background: "var(--accent-soft)",
              color: "var(--accent)",
              borderRadius: "999px",
              padding: "0.1rem 0.55rem",
              fontSize: "0.65rem",
              fontFamily: "var(--font-plex-mono)",
              letterSpacing: "0.06em",
              textTransform: "uppercase",
            }}
          >
            {article.release_type}
          </span>
        )}
        <span style={{ marginLeft: "auto", color: "var(--muted)", fontSize: "0.72rem", fontFamily: "var(--font-plex-mono)", flexShrink: 0 }}>
          {timeAgo(ts)}
        </span>
      </div>

      {/* Title */}
      {article.url ? (
        <a
          href={article.url}
          target="_blank"
          rel="noopener noreferrer"
          style={{
            fontSize: "0.975rem",
            fontWeight: 600,
            lineHeight: 1.45,
            color: "var(--foreground)",
            textDecoration: "none",
          }}
          onMouseEnter={(e) => { (e.currentTarget as HTMLAnchorElement).style.color = "var(--accent)"; }}
          onMouseLeave={(e) => { (e.currentTarget as HTMLAnchorElement).style.color = "var(--foreground)"; }}
        >
          {article.title}
        </a>
      ) : (
        <p style={{ fontSize: "0.975rem", fontWeight: 600, lineHeight: 1.45 }}>
          {article.title}
        </p>
      )}

      {/* Excerpt */}
      {blurb && (
        <p style={{ fontSize: "0.82rem", color: "var(--muted)", lineHeight: 1.65, margin: 0 }}>
          {blurb}
        </p>
      )}
    </article>
  );
}

// ─── Main Page ───────────────────────────────────────────────────────────────

export default function Home() {
  const [countries, setCountries] = useState<Country[]>([]);
  const [articles, setArticles] = useState<Article[]>([]);
  const [selectedCountry, setSelectedCountry] = useState<string | null>(null);
  const [loadingCountries, setLoadingCountries] = useState(true);
  const [loadingArticles, setLoadingArticles] = useState(true);
  const [scraping, setScraping] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [scrapeMessage, setScrapeMessage] = useState<string | null>(null);

  // Fetch countries once
  useEffect(() => {
    fetch("/api/countries")
      .then((r) => r.json())
      .then((data) => {
        setCountries(data.countries ?? []);
      })
      .catch(() => {
        // non-fatal; countries list is optional
      })
      .finally(() => setLoadingCountries(false));
  }, []);

  // Fetch articles (re-runs on country filter change)
  const fetchArticles = useCallback(async (countryCode?: string | null) => {
    setLoadingArticles(true);
    setError(null);
    try {
      const url = countryCode
        ? `/api/news?country=${encodeURIComponent(countryCode.toLowerCase())}`
        : "/api/news";
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setArticles(data.articles ?? []);
      setLastUpdated(new Date());
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load articles");
    } finally {
      setLoadingArticles(false);
    }
  }, []);

  useEffect(() => {
    fetchArticles(selectedCountry);
  }, [selectedCountry, fetchArticles]);

  // Manual scrape trigger
  const handleScrape = async () => {
    setScraping(true);
    setScrapeMessage(null);
    try {
      const res = await fetch("/api/scrape/france", { method: "POST" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setScrapeMessage("Scrape triggered — refreshing articles…");
      await fetchArticles(selectedCountry);
    } catch {
      setScrapeMessage("Scrape failed. Check server logs.");
    } finally {
      setScraping(false);
      setTimeout(() => setScrapeMessage(null), 4000);
    }
  };

  const totalSources = countries.reduce((n, c) => n + c.sources_count, 0);

  // Filtered articles are already server-filtered, but sort client-side
  const sorted = [...articles].sort((a, b) => {
    const ta = new Date(a.published_at ?? a.scraped_at ?? 0).getTime();
    const tb = new Date(b.published_at ?? b.scraped_at ?? 0).getTime();
    return tb - ta;
  });

  return (
    <>
      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
        .article-enter { animation: fadeIn 0.25s ease both; }
      `}</style>

      <main
        style={{
          maxWidth: "72rem",
          margin: "0 auto",
          padding: "2rem 1.5rem 4rem",
          display: "flex",
          flexDirection: "column",
          gap: "2rem",
        }}
      >
        {/* ── Header ── */}
        <header
          className="grid-panel"
          style={{
            borderRadius: "2rem",
            padding: "2rem 2.5rem",
            display: "flex",
            flexDirection: "column",
            gap: "1.5rem",
          }}
        >
          <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", flexWrap: "wrap", gap: "1.5rem" }}>
            <div>
              <p className="eyebrow">Kairos</p>
              <h1 style={{ margin: "0.5rem 0 0.35rem", fontSize: "clamp(1.75rem, 4vw, 2.75rem)", fontWeight: 700, letterSpacing: "-0.02em", lineHeight: 1.15 }}>
                Multi-Country News Intelligence Platform
              </h1>
              <p style={{ color: "var(--muted)", fontSize: "0.95rem", margin: 0 }}>
                {loadingArticles
                  ? "Loading articles…"
                  : `${articles.length} article${articles.length !== 1 ? "s" : ""}${selectedCountry ? ` · ${selectedCountry.toUpperCase()}` : " · all countries"}`}
                {lastUpdated && (
                  <span style={{ marginLeft: "0.75rem", fontFamily: "var(--font-plex-mono)", fontSize: "0.72rem" }}>
                    · updated {timeAgo(lastUpdated.toISOString())}
                  </span>
                )}
              </p>
            </div>

            {/* Stats */}
            <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
              {[
                { label: "Countries", value: countries.length },
                { label: "Sources", value: totalSources },
                { label: "Articles", value: articles.length },
              ].map(({ label, value }) => (
                <div
                  key={label}
                  style={{
                    borderRadius: "1.25rem",
                    border: "1px solid var(--border)",
                    background: "var(--surface-strong)",
                    padding: "0.75rem 1.25rem",
                    minWidth: "80px",
                  }}
                >
                  <div className="eyebrow" style={{ fontSize: "0.65rem" }}>{label}</div>
                  <div style={{ marginTop: "0.35rem", fontSize: "1.75rem", fontWeight: 600, fontFamily: "var(--font-plex-mono)", lineHeight: 1 }}>
                    {value}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Scrape button + message */}
          <div style={{ display: "flex", alignItems: "center", gap: "1rem", flexWrap: "wrap" }}>
            <button
              onClick={handleScrape}
              disabled={scraping}
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: "0.5rem",
                padding: "0.55rem 1.1rem",
                borderRadius: "999px",
                border: "1px solid var(--accent)",
                background: scraping ? "var(--accent-soft)" : "transparent",
                color: "var(--accent)",
                fontFamily: "var(--font-plex-mono)",
                fontSize: "0.75rem",
                letterSpacing: "0.06em",
                cursor: scraping ? "not-allowed" : "pointer",
                transition: "background 0.15s",
              }}
              onMouseEnter={(e) => { if (!scraping) (e.currentTarget as HTMLButtonElement).style.background = "var(--accent-soft)"; }}
              onMouseLeave={(e) => { if (!scraping) (e.currentTarget as HTMLButtonElement).style.background = "transparent"; }}
            >
              {scraping ? <Spinner size={13} /> : <span>↺</span>}
              {scraping ? "Scraping…" : "Scrape Now"}
            </button>

            {scrapeMessage && (
              <span style={{ color: "var(--muted)", fontSize: "0.8rem", fontFamily: "var(--font-plex-mono)" }}>
                {scrapeMessage}
              </span>
            )}
          </div>
        </header>

        {/* ── Country Filter Bar ── */}
        <section>
          {loadingCountries ? (
            <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", color: "var(--muted)", fontSize: "0.82rem" }}>
              <Spinner size={14} /> Loading countries…
            </div>
          ) : (
            <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
              {/* All button */}
              <button
                onClick={() => setSelectedCountry(null)}
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: "0.4rem",
                  padding: "0.45rem 1rem",
                  borderRadius: "999px",
                  border: `1px solid ${selectedCountry === null ? "var(--accent)" : "var(--border)"}`,
                  background: selectedCountry === null ? "var(--accent-soft)" : "var(--surface-strong)",
                  color: selectedCountry === null ? "var(--accent)" : "var(--foreground)",
                  fontFamily: "var(--font-plex-mono)",
                  fontSize: "0.75rem",
                  letterSpacing: "0.05em",
                  cursor: "pointer",
                  transition: "all 0.15s",
                  fontWeight: selectedCountry === null ? 600 : 400,
                }}
              >
                All
                <span
                  style={{
                    background: selectedCountry === null ? "var(--accent)" : "rgba(93,67,38,0.12)",
                    color: selectedCountry === null ? "#fff" : "var(--muted)",
                    borderRadius: "999px",
                    padding: "0.05rem 0.45rem",
                    fontSize: "0.65rem",
                  }}
                >
                  {articles.length}
                </span>
              </button>

              {/* Country buttons */}
              {countries.map((country) => {
                const active = selectedCountry === country.code_iso;
                return (
                  <button
                    key={country.code_iso}
                    onClick={() => setSelectedCountry(active ? null : country.code_iso)}
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: "0.4rem",
                      padding: "0.45rem 1rem",
                      borderRadius: "999px",
                      border: `1px solid ${active ? "var(--accent)" : "var(--border)"}`,
                      background: active ? "var(--accent-soft)" : "var(--surface-strong)",
                      color: active ? "var(--accent)" : "var(--foreground)",
                      fontFamily: "var(--font-plex-mono)",
                      fontSize: "0.75rem",
                      letterSpacing: "0.05em",
                      cursor: "pointer",
                      transition: "all 0.15s",
                      fontWeight: active ? 600 : 400,
                    }}
                  >
                    <span>{getFlag(country.code_iso)}</span>
                    <span>{country.name}</span>
                    <span
                      style={{
                        background: active ? "var(--accent)" : "rgba(93,67,38,0.12)",
                        color: active ? "#fff" : "var(--muted)",
                        borderRadius: "999px",
                        padding: "0.05rem 0.45rem",
                        fontSize: "0.65rem",
                      }}
                    >
                      {country.sources_count}
                    </span>
                  </button>
                );
              })}
            </div>
          )}
        </section>

        {/* ── News Feed ── */}
        <section>
          {loadingArticles ? (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                justifyContent: "center",
                gap: "1rem",
                minHeight: "240px",
                color: "var(--muted)",
                fontSize: "0.9rem",
              }}
            >
              <Spinner size={32} />
              <span>Fetching articles…</span>
            </div>
          ) : error ? (
            <div
              style={{
                borderRadius: "1.5rem",
                border: "1px solid rgba(220,38,38,0.2)",
                background: "rgba(220,38,38,0.05)",
                padding: "2rem",
                textAlign: "center",
                color: "#dc2626",
                fontFamily: "var(--font-plex-mono)",
                fontSize: "0.85rem",
              }}
            >
              ⚠ Failed to load articles: {error}
            </div>
          ) : sorted.length === 0 ? (
            <div
              className="grid-panel"
              style={{
                borderRadius: "1.5rem",
                padding: "3rem 2rem",
                textAlign: "center",
                color: "var(--muted)",
              }}
            >
              <p style={{ fontSize: "2rem", margin: "0 0 0.5rem" }}>📭</p>
              <p style={{ fontWeight: 600, margin: "0 0 0.25rem" }}>No articles found</p>
              <p style={{ fontSize: "0.85rem", margin: 0 }}>
                {selectedCountry
                  ? `No articles for ${selectedCountry.toUpperCase()} yet. Try scraping or selecting another country.`
                  : "The database is empty. Trigger a scrape to populate articles."}
              </p>
            </div>
          ) : (
            <div
              style={{
                display: "grid",
                gap: "0.75rem",
                gridTemplateColumns: "repeat(auto-fill, minmax(min(100%, 420px), 1fr))",
              }}
            >
              {sorted.map((article, i) => (
                <div
                  key={article.id}
                  className="article-enter"
                  style={{ animationDelay: `${Math.min(i * 18, 300)}ms` }}
                >
                  <ArticleCard article={article} />
                </div>
              ))}
            </div>
          )}
        </section>
      </main>
    </>
  );
}
