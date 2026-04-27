ALTER TABLE sources
  DROP CONSTRAINT IF EXISTS sources_type_check;

ALTER TABLE sources
  ADD CONSTRAINT sources_type_check
  CHECK (type IN ('rss', 'twitter', 'reddit', 'forum', 'news', 'scraping', 'api'));

ALTER TABLE sources
  ADD COLUMN IF NOT EXISTS slug TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sources_slug_key'
  ) THEN
    ALTER TABLE sources ADD CONSTRAINT sources_slug_key UNIQUE (slug);
  END IF;
END $$;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS news_type TEXT NOT NULL DEFAULT 'general';

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS release_type TEXT;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS is_scheduled_release BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS authority_score NUMERIC(4,3) NOT NULL DEFAULT 0.500;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS canonical JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE articles
  DROP CONSTRAINT IF EXISTS articles_authority_score_check;

ALTER TABLE articles
  ADD CONSTRAINT articles_authority_score_check
  CHECK (authority_score >= 0 AND authority_score <= 1);

CREATE INDEX IF NOT EXISTS idx_sources_slug ON sources(slug);
CREATE INDEX IF NOT EXISTS idx_articles_news_type ON articles(news_type);
CREATE INDEX IF NOT EXISTS idx_articles_release_type ON articles(release_type);
