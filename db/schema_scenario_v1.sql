-- =============================================================================
-- Kairos — Schema Scenario Tree Engine v1
-- Couche C4 étendue : arbre de scénarios probabilistes multi-branches
-- Appliquer APRÈS schema_v2.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. probability_calibrations
--    Lookup table des bifurcations historiques avec probabilités calibrées
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS probability_calibrations (
  calibration_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  bifurcation_id       TEXT         NOT NULL UNIQUE,  -- ex: 'armed_conflict_hormuz_impact'
  cat_id               VARCHAR(8),                     -- optional: lié à un type d'event
  subtype_id           TEXT,                           -- optional: lié à un sous-type
  context_description  TEXT         NOT NULL,
  branches             JSONB        NOT NULL DEFAULT '[]',
  -- [{outcome, p_historical, p_adjusted, conditioning_factors, n_historical_episodes}]
  last_updated         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  version              TEXT         NOT NULL DEFAULT 'v1',
  notes                TEXT,
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prob_calib_cat ON probability_calibrations(cat_id, subtype_id)
  WHERE cat_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_prob_calib_bifurcation ON probability_calibrations(bifurcation_id);

COMMENT ON TABLE probability_calibrations IS 'Lookup table des bifurcations géopolitiques/macro avec probabilités historiques calibrées. Alimentée depuis probability_calibrations_v1.json.';

-- ---------------------------------------------------------------------------
-- 2. scenario_trees
--    Arbre complet par event (métadonnées + résumé)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS scenario_trees (
  tree_id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id             UUID         NOT NULL REFERENCES events(event_id),
  event_label          TEXT         NOT NULL,
  cat_id               VARCHAR(8)   NOT NULL,
  subtype_id           TEXT         NOT NULL,
  generated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  max_depth            SMALLINT     NOT NULL DEFAULT 4,
  min_probability      NUMERIC(5,4) NOT NULL DEFAULT 0.03,
  total_scenarios      INTEGER      NOT NULL DEFAULT 0,
  root_node_id         UUID,        -- FK set after root node creation
  dominant_scenario    TEXT,        -- path_id of dominant scenario
  dominant_probability NUMERIC(5,4),
  consensus_asset_impacts JSONB     NOT NULL DEFAULT '{}',
  uncertainty_flag     TEXT         NOT NULL DEFAULT 'MEDIUM'
                         CHECK (uncertainty_flag IN ('LOW','MEDIUM','HIGH','EXTREME')),
  status               TEXT         NOT NULL DEFAULT 'generating'
                         CHECK (status IN ('generating','complete','error')),
  model_version        TEXT         NOT NULL DEFAULT 'v1',
  processing_time_ms   INTEGER,
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scenario_trees_event_id ON scenario_trees(event_id);
CREATE INDEX IF NOT EXISTS idx_scenario_trees_created  ON scenario_trees(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scenario_trees_status   ON scenario_trees(status);

COMMENT ON TABLE scenario_trees IS 'Arbre de scénarios C4 étendu. Un event HIGH_UNCERTAINTY génère un arbre de branches probabilistes au lieu d''une analyse linéaire unique.';

-- ---------------------------------------------------------------------------
-- 3. scenario_nodes
--    Chaque nœud de l'arbre (branche, avec probabilité et impacts)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS scenario_nodes (
  node_id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  tree_id              UUID         NOT NULL REFERENCES scenario_trees(tree_id) ON DELETE CASCADE,
  parent_node_id       UUID         REFERENCES scenario_nodes(node_id),
  depth                SMALLINT     NOT NULL DEFAULT 0,
  label                TEXT         NOT NULL,
  description          TEXT         NOT NULL DEFAULT '',
  probability          NUMERIC(6,4) NOT NULL CHECK (probability BETWEEN 0 AND 1),
  -- P(this branch | parent) — somme des enfants = 1.0
  probability_cumulative NUMERIC(6,4) NOT NULL CHECK (probability_cumulative BETWEEN 0 AND 1),
  -- P_root × P_branch1 × ... × P_this
  trigger_condition    TEXT         NOT NULL DEFAULT '',
  time_horizon         TEXT         NOT NULL DEFAULT 'immediate'
                         CHECK (time_horizon IN ('immediate','1-4w','1-6m','6m+')),
  drivers_activated    JSONB        NOT NULL DEFAULT '[]',
  -- [{driver, sub_driver, direction, intensity, coefficient, range:{low,central,high}, horizon}]
  asset_impacts        JSONB        NOT NULL DEFAULT '{}',
  -- {asset_id: {signal, magnitude_central, range:[low,high], horizon}}
  historical_analogies JSONB        NOT NULL DEFAULT '[]',
  -- [{episode, match_score, oil_move, duration_weeks}]
  confidence           NUMERIC(4,3) NOT NULL DEFAULT 0.5 CHECK (confidence BETWEEN 0 AND 1),
  is_terminal          BOOLEAN      NOT NULL DEFAULT FALSE,  -- leaf node (depth=max or no children)
  is_pruned            BOOLEAN      NOT NULL DEFAULT FALSE,  -- below min_probability threshold
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scenario_nodes_tree    ON scenario_nodes(tree_id);
CREATE INDEX IF NOT EXISTS idx_scenario_nodes_parent  ON scenario_nodes(parent_node_id);
CREATE INDEX IF NOT EXISTS idx_scenario_nodes_depth   ON scenario_nodes(depth);
CREATE INDEX IF NOT EXISTS idx_scenario_nodes_terminal ON scenario_nodes(is_terminal) WHERE is_terminal = TRUE;

COMMENT ON TABLE scenario_nodes IS 'Nœuds de l''arbre de scénarios. Chaque nœud = une branche conditionnelle avec impacts drivers/actifs.';

-- FK root_node_id dans scenario_trees (après création du root node)
ALTER TABLE scenario_trees
  ADD CONSTRAINT fk_scenario_trees_root_node
  FOREIGN KEY (root_node_id) REFERENCES scenario_nodes(node_id)
  DEFERRABLE INITIALLY DEFERRED;

-- ---------------------------------------------------------------------------
-- 4. scenario_paths
--    Chemins complets du root aux feuilles (scénarios terminaux)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS scenario_paths (
  path_id              TEXT         NOT NULL,   -- ex: 'S1', 'S2', 'S1a'
  tree_id              UUID         NOT NULL REFERENCES scenario_trees(tree_id) ON DELETE CASCADE,
  label                TEXT         NOT NULL,
  probability_path     NUMERIC(6,4) NOT NULL CHECK (probability_path BETWEEN 0 AND 1),
  node_ids             UUID[]       NOT NULL DEFAULT '{}',  -- ordered root→leaf
  terminal_node_id     UUID         NOT NULL REFERENCES scenario_nodes(node_id),
  terminal_asset_summary JSONB      NOT NULL DEFAULT '{}',
  -- {asset_id: {signal, magnitude, confidence}}
  narrative_terminal   TEXT         NOT NULL DEFAULT '',
  revision_factors     TEXT[]       NOT NULL DEFAULT '{}',  -- key variables to watch
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  PRIMARY KEY (path_id, tree_id)
);

CREATE INDEX IF NOT EXISTS idx_scenario_paths_tree ON scenario_paths(tree_id);
CREATE INDEX IF NOT EXISTS idx_scenario_paths_prob ON scenario_paths(probability_path DESC);

COMMENT ON TABLE scenario_paths IS 'Scénarios terminaux = chemins complets root→feuille dans l''arbre. Incluent résumé actifs et narratif.';

-- ---------------------------------------------------------------------------
-- 5. scenario_revisions
--    Tracking des révisions de probabilité dans le temps
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS scenario_revisions (
  revision_id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  tree_id              UUID         NOT NULL REFERENCES scenario_trees(tree_id),
  node_id              UUID         REFERENCES scenario_nodes(node_id),
  path_id              TEXT,        -- si révision d'un scénario terminal
  revision_type        TEXT         NOT NULL CHECK (revision_type IN (
                                     'probability_update','new_information','model_update','manual'
                                   )),
  old_probability      NUMERIC(6,4),
  new_probability      NUMERIC(6,4),
  revision_reason      TEXT         NOT NULL DEFAULT '',
  triggering_event_id  UUID         REFERENCES events(event_id),
  -- nouvel event qui a déclenché la révision
  revised_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  revised_by           TEXT         NOT NULL DEFAULT 'auto',
  notes                TEXT
);

CREATE INDEX IF NOT EXISTS idx_scenario_revisions_tree    ON scenario_revisions(tree_id);
CREATE INDEX IF NOT EXISTS idx_scenario_revisions_node    ON scenario_revisions(node_id) WHERE node_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_scenario_revisions_revised ON scenario_revisions(revised_at DESC);

COMMENT ON TABLE scenario_revisions IS 'Historique des révisions de probabilité dans les arbres de scénarios. Permet de tracer l''évolution des probabilités dans le temps.';

-- ---------------------------------------------------------------------------
-- Trigger updated_at pour scenario_trees
-- ---------------------------------------------------------------------------

-- Réutilise la fonction kairos_set_updated_at() déjà créée dans schema_v2.sql
-- (pas de redéfinition nécessaire)

-- Note: scenario_trees n'a pas de updated_at — utilisez created_at + status pour le suivi
