CREATE TABLE IF NOT EXISTS countries (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  code_iso VARCHAR(2) NOT NULL UNIQUE,
  region TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sources (
  id BIGSERIAL PRIMARY KEY,
  country_id BIGINT NOT NULL REFERENCES countries(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('rss', 'twitter', 'reddit', 'forum', 'news', 'scraping', 'api')),
  slug TEXT,
  url TEXT NOT NULL,
  name TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  last_scraped_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (country_id, url),
  UNIQUE (slug)
);

CREATE TABLE IF NOT EXISTS articles (
  id BIGSERIAL PRIMARY KEY,
  source_id BIGINT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  country_id BIGINT NOT NULL REFERENCES countries(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT,
  url TEXT NOT NULL UNIQUE,
  published_at TIMESTAMPTZ,
  scraped_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  lang VARCHAR(12),
  tags TEXT[] NOT NULL DEFAULT '{}',
  news_type TEXT NOT NULL DEFAULT 'general',
  release_type TEXT,
  is_scheduled_release BOOLEAN NOT NULL DEFAULT FALSE,
  authority_score NUMERIC(4,3) NOT NULL DEFAULT 0.500 CHECK (authority_score >= 0 AND authority_score <= 1),
  canonical JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS scrape_jobs (
  id BIGSERIAL PRIMARY KEY,
  country_id BIGINT NOT NULL REFERENCES countries(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'success', 'failed')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  articles_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sources_country_id ON sources(country_id);
CREATE INDEX IF NOT EXISTS idx_articles_country_id ON articles(country_id);
CREATE INDEX IF NOT EXISTS idx_articles_source_id ON articles(source_id);
CREATE INDEX IF NOT EXISTS idx_articles_published_at ON articles(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_scrape_jobs_country_id ON scrape_jobs(country_id);
CREATE INDEX IF NOT EXISTS idx_scrape_jobs_status ON scrape_jobs(status);
