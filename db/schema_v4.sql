CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS article_uuid UUID;

UPDATE articles
SET article_uuid = COALESCE(
  NULLIF(canonical ->> 'article_id', '')::uuid,
  gen_random_uuid()
)
WHERE article_uuid IS NULL;

ALTER TABLE articles
  ALTER COLUMN article_uuid SET DEFAULT gen_random_uuid();

ALTER TABLE articles
  ALTER COLUMN article_uuid SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_articles_article_uuid ON articles(article_uuid);

UPDATE articles
SET canonical = jsonb_set(
  COALESCE(canonical, '{}'::jsonb),
  '{article_id}',
  to_jsonb(article_uuid::text),
  true
)
WHERE NOT (COALESCE(canonical, '{}'::jsonb) ? 'article_id');

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS qualification_status TEXT NOT NULL DEFAULT 'pending';

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS qualified_event_id UUID;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS qualified_at TIMESTAMPTZ;

ALTER TABLE articles
  ADD COLUMN IF NOT EXISTS qualification_error TEXT;

ALTER TABLE articles
  DROP CONSTRAINT IF EXISTS articles_qualification_status_check;

ALTER TABLE articles
  ADD CONSTRAINT articles_qualification_status_check
  CHECK (qualification_status IN ('pending', 'qualified', 'archived', 'failed'));

CREATE INDEX IF NOT EXISTS idx_articles_qualification_status
  ON articles(qualification_status, published_at DESC);

CREATE INDEX IF NOT EXISTS idx_articles_qualified_event_id
  ON articles(qualified_event_id);

CREATE TABLE IF NOT EXISTS article_embeddings (
  article_uuid         UUID PRIMARY KEY REFERENCES articles(article_uuid) ON DELETE CASCADE,
  article_id           BIGINT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  embedding_model      TEXT NOT NULL,
  embedding            vector(1536) NOT NULL,
  embedding_text_hash  TEXT NOT NULL,
  embedding_source     TEXT NOT NULL DEFAULT 'c2_dedup',
  embedded_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_article_embeddings_article_id
  ON article_embeddings(article_id);

CREATE INDEX IF NOT EXISTS idx_article_embeddings_embedded_at
  ON article_embeddings(embedded_at DESC);

CREATE INDEX IF NOT EXISTS idx_events_raw_article_ids
  ON events USING GIN(raw_article_ids);
