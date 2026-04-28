ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS category VARCHAR(50);

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS category_confidence FLOAT;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS summary TEXT;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS importance_score FLOAT;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS urgency_score FLOAT;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS market_impact_score FLOAT;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS analyzed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_articles_analyzed_at
  ON articles(analyzed_at, published_at DESC);
