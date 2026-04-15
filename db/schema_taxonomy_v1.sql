-- ============================================================================
-- schema_taxonomy_v1.sql — Kairos Taxonomy v1.0 Migration
-- Run AFTER schema_v2.sql
-- Creates/seeds: event_taxonomy (full), event_driver_lookup (full), new drivers
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. New drivers (liquidite_globale, risque_geopolitique, prix_gaz, prix_agricoles)
-- ---------------------------------------------------------------------------
INSERT INTO drivers (driver_id, label_fr, label_en, category, unit, description) VALUES
  ('liquidite_globale',    'Liquidité mondiale',               'Global liquidity',            'monetary',  'index',  'Indice synthétique de la liquidité mondiale: bilan CB + conditions financement.'),
  ('risque_geopolitique',  'Risque géopolitique',              'Geopolitical risk',           'macro',     'index',  'Indice composite de risque géopolitique (GPR index ou proxy VIX géopolitique).'),
  ('prix_gaz',             'Prix du gaz naturel (TTF/Henry)',  'Natural gas price (TTF/Henry)','commodity', 'EUR/MWh','Prix spot du gaz naturel européen TTF ou US Henry Hub.'),
  ('prix_agricoles',       'Prix agricoles (GSCI Agri)',       'Agricultural prices (GSCI)',   'commodity', 'index',  'Indice S&P GSCI des prix agricoles (blé, maïs, soja, café, sucre).')
ON CONFLICT (driver_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 1. DROP & RECREATE event_taxonomy with full schema
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS event_taxonomy CASCADE;

CREATE TABLE event_taxonomy (
  cat_id               VARCHAR(8)   NOT NULL,
  category             TEXT         NOT NULL,
  subtype_id           TEXT         NOT NULL,
  label                TEXT         NOT NULL,
  description          TEXT,
  examples             JSONB        NOT NULL DEFAULT '[]',
  detection_keywords   JSONB        NOT NULL DEFAULT '[]',
  authority_floor      NUMERIC(3,2) NOT NULL CHECK (authority_floor BETWEEN 0 AND 1),
  typical_geography    TEXT[]       NOT NULL DEFAULT '{}',
  drivers_json         JSONB        NOT NULL DEFAULT '{}',
  asset_bias_json      JSONB        NOT NULL DEFAULT '{}',
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (cat_id, subtype_id)
);

CREATE INDEX IF NOT EXISTS idx_event_taxonomy_cat ON event_taxonomy(cat_id);
CREATE INDEX IF NOT EXISTS idx_event_taxonomy_category ON event_taxonomy(category);

COMMENT ON TABLE event_taxonomy IS 'Taxonomie fermée Kairos v1.0 — 10 catégories, ~100 sous-types. Source de vérité C2→C4.';

-- ---------------------------------------------------------------------------
-- 2. SEED event_taxonomy
-- ---------------------------------------------------------------------------

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'rate_decision_hike', 'MONETARY_POLICY', 'Rate Decision — Hike',
   'Central bank raises policy rate (planned or surprise)',
   '["Fed +25bps FOMC", "BCE +50bps emergency", "BoE MPC hike"]'::jsonb, '["rate hike", "basis points", "policy rate", "raises rates", "hausse des taux"]'::jsonb,
   0.85, '{US,EZ,UK,JP,CN,GLOBAL}'::text[],
   '{"primary": [{"driver": "taux_directeurs", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "taux_directeurs→conditions_credit", "direction": -1, "intensity": "strong", "horizon": "1-4w"}, {"driver": "liquidite_globale", "via_arc": "taux_directeurs→liquidite_globale", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "spreads_credit", "via_arc": "taux_directeurs→spreads_credit", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "usd_strength", "via_arc": "taux_directeurs→usd_strength", "direction": 1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "anticipations_inflation", "via_arc": "taux_directeurs→anticipations_inflation", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "If QT already in progress, intensity_credit may be amplified"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'rate_decision_cut', 'MONETARY_POLICY', 'Rate Decision — Cut',
   'Central bank lowers policy rate',
   '["Fed -50bps emergency Mar 2020", "ECB -25bps Jun 2024", "BoE rate cut"]'::jsonb, '["rate cut", "lowers rates", "easing", "baisse des taux", "rate reduction"]'::jsonb,
   0.85, '{US,EZ,UK,JP,CN,GLOBAL}'::text[],
   '{"primary": [{"driver": "taux_directeurs", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "taux_directeurs→conditions_credit", "direction": 1, "intensity": "strong", "horizon": "1-4w"}, {"driver": "liquidite_globale", "via_arc": "taux_directeurs→liquidite_globale", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "spreads_credit", "via_arc": "taux_directeurs→spreads_credit", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "usd_strength", "via_arc": "taux_directeurs→usd_strength", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "croissance_pib", "via_arc": "conditions_credit→croissance_pib", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "If cutting into inflation, gold may diverge bullish"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'rate_decision_hold', 'MONETARY_POLICY', 'Rate Decision — Hold',
   'Central bank keeps policy rate unchanged; market focus on forward guidance tone',
   '["Fed holds FOMC Sep 2023", "ECB pause Oct 2023"]'::jsonb, '["holds rates", "unchanged", "pause", "maintains", "statu quo taux"]'::jsonb,
   0.7, '{US,EZ,UK,JP,CN}'::text[],
   '{"primary": [], "auto_propagate": [{"driver": "anticipations_inflation", "via_arc": "hold→anticipations_inflation", "direction": 0, "intensity": "low", "horizon": "1-4w"}, {"driver": "sentiment_marche", "via_arc": "hold→sentiment_marche", "direction": 0, "intensity": "low", "horizon": "immediate"}], "conditions": [{"if": "tone=hawkish", "then_treat_as": "forward_guidance_hawkish"}], "conflict_note": "Pure hold has minimal impact; dominant signal is the statement tone"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_growth": "neutral"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'forward_guidance_hawkish', 'MONETARY_POLICY', 'Forward Guidance — Hawkish',
   'CB signals higher-for-longer or future tightening without immediate action',
   '["Powell ''not yet'' Jun 2023", "Lagarde hawkish data-dependent", "BoJ yield-curve tightening signal"]'::jsonb, '["hawkish", "higher for longer", "not ready to cut", "inflation vigilance", "guidance restrictive"]'::jsonb,
   0.75, '{US,EZ,UK,JP}'::text[],
   '{"primary": [{"driver": "anticipations_inflation", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}, {"driver": "taux_directeurs", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "1-4w"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "taux_directeurs→conditions_credit", "direction": -1, "intensity": "low", "horizon": "1-4w"}, {"driver": "spreads_credit", "via_arc": "taux_directeurs→spreads_credit", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Signal strength depends on market positioning; surprise factor amplifies"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'forward_guidance_dovish', 'MONETARY_POLICY', 'Forward Guidance — Dovish',
   'CB signals rate cuts ahead or more accommodative stance',
   '["Fed ''pivot'' Dec 2023", "ECB opens door to cuts Mar 2024"]'::jsonb, '["dovish", "ready to cut", "easing bias", "lower rates", "guidance accommodante"]'::jsonb,
   0.75, '{US,EZ,UK,JP}'::text[],
   '{"primary": [{"driver": "anticipations_inflation", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.3, "horizon": "immediate"}, {"driver": "taux_directeurs", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "1-4w"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "taux_directeurs→conditions_credit", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "croissance_pib", "via_arc": "conditions_credit→croissance_pib", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "usd_strength", "via_arc": "taux_directeurs→usd_strength", "direction": -1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "If dovish pivot occurs amid high inflation, equities may rally but bonds less"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'qe_announcement', 'MONETARY_POLICY', 'QE Announcement',
   'Central bank announces new asset purchase programme (quantitative easing)',
   '["Fed QE4 $120bn/month Mar 2020", "ECB PEPP €1.85tn", "BoJ QQE expansion"]'::jsonb, '["quantitative easing", "asset purchases", "QE", "bond buying programme", "PEPP"]'::jsonb,
   0.85, '{US,EZ,UK,JP}'::text[],
   '{"primary": [{"driver": "liquidite_globale", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}, {"driver": "taux_directeurs", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "spreads_souverains", "via_arc": "liquidite_globale→spreads_souverains", "direction": -1, "intensity": "strong", "horizon": "1-4w"}, {"driver": "conditions_credit", "via_arc": "liquidite_globale→conditions_credit", "direction": 1, "intensity": "strong", "horizon": "1-4w"}, {"driver": "spreads_credit", "via_arc": "liquidite_globale→spreads_credit", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "usd_strength", "via_arc": "liquidite_globale→usd_strength", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Diminishing returns on successive QE rounds; currency wars risk in multi-CB context"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'qt_announcement', 'MONETARY_POLICY', 'QT Announcement',
   'Central bank announces balance sheet reduction (quantitative tightening)',
   '["Fed QT $95bn/month Jun 2022", "ECB APP runoff", "BoE active gilt sales"]'::jsonb, '["quantitative tightening", "balance sheet reduction", "QT", "runoff", "gilt sales"]'::jsonb,
   0.85, '{US,EZ,UK}'::text[],
   '{"primary": [{"driver": "liquidite_globale", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "1-4w"}], "auto_propagate": [{"driver": "spreads_souverains", "via_arc": "liquidite_globale→spreads_souverains", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "conditions_credit", "via_arc": "liquidite_globale→conditions_credit", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "liquidite_bancaire", "via_arc": "liquidite_globale→liquidite_bancaire", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Pace matters: $60bn vs $95bn/month has very different transmission speed"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'tapering', 'MONETARY_POLICY', 'Tapering',
   'Gradual reduction of existing QE pace before full stop',
   '["Fed taper Nov 2021", "ECB PEPP wind-down Q1 2022"]'::jsonb, '["taper", "tapering", "reduce purchases", "wind down", "réduire les achats"]'::jsonb,
   0.8, '{US,EZ}'::text[],
   '{"primary": [{"driver": "liquidite_globale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-4w"}], "auto_propagate": [{"driver": "spreads_souverains", "via_arc": "tapering→spreads_souverains", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "taux_directeurs", "via_arc": "tapering→taux_directeurs", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Taper tantrum risk if unexpected; well-telegraphed tapers have limited impact"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "neutral", "gold": "bearish", "equities_growth": "neutral"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'emergency_action_easing', 'MONETARY_POLICY', 'Emergency Action — Easing',
   'Unscheduled CB intervention: emergency rate cut, liquidity facility, FX intervention',
   '["Fed emergency -100bps Mar 2020", "SNB EUR/CHF floor", "BoJ emergency liquidity Oct 2022"]'::jsonb, '["emergency cut", "unscheduled", "crisis intervention", "liquidity facility", "urgence banque centrale"]'::jsonb,
   0.9, '{US,EZ,UK,JP,EM}'::text[],
   '{"primary": [{"driver": "liquidite_globale", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.95, "horizon": "immediate"}, {"driver": "taux_directeurs", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "sentiment_marche", "via_arc": "emergency→sentiment_marche", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "conditions_credit", "via_arc": "liquidite_globale→conditions_credit", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "spreads_credit", "via_arc": "liquidite_globale→spreads_credit", "direction": -1, "intensity": "strong", "horizon": "immediate"}], "conditions": [], "conflict_note": "Emergency actions signal CB sees a crisis; may paradoxically increase fear short-term"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish_short_term"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-01', 'emergency_action_tightening', 'MONETARY_POLICY', 'Emergency Action — Tightening',
   'Unscheduled CB intervention: emergency hike or FX intervention to defend currency',
   '["Turkish TCMB +500bps emergency", "BoE gilt market backstop Oct 2022"]'::jsonb, '["emergency hike", "currency defense", "FX intervention", "defending currency"]'::jsonb,
   0.9, '{EM,UK,TR}'::text[],
   '{"primary": [{"driver": "taux_directeurs", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "liquidite_globale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}], "auto_propagate": [{"driver": "spreads_souverains", "via_arc": "emergency_tightening→spreads_souverains", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "conditions_credit", "via_arc": "taux_directeurs→conditions_credit", "direction": -1, "intensity": "strong", "horizon": "1-4w"}], "conditions": [], "conflict_note": "May signal currency stress; sovereign spread reaction depends on credibility"}'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'inflation_cpi_above', 'MACRO_DATA_RELEASE', 'CPI — Above Expectations',
   'Published CPI materially exceeds consensus (+0.1pp or more)',
   '["US CPI 9.1% Jun 2022", "EZ HICP 10.6% Oct 2022"]'::jsonb, '["CPI above", "inflation surprise", "hot inflation", "exceeds forecast", "inflation supérieure"]'::jsonb,
   0.8, '{US,EZ,UK,JP,CN}'::text[],
   '{"primary": [{"driver": "inflation_headline", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}, {"driver": "anticipations_inflation", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}], "auto_propagate": [{"driver": "taux_directeurs", "via_arc": "inflation_headline→taux_directeurs", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "spreads_souverains", "via_arc": "anticipations_inflation→spreads_souverains", "direction": 1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "conditions_credit", "via_arc": "taux_directeurs→conditions_credit", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "If driven by energy alone, core inflation may diverge; central bank response varies"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "mixed", "equities_growth": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'inflation_cpi_below', 'MACRO_DATA_RELEASE', 'CPI — Below Expectations',
   'Published CPI materially misses consensus (-0.1pp or more)',
   '["US CPI 3.0% Jun 2023 below 3.1% est", "EZ deflation risk 2014-15"]'::jsonb, '["CPI below", "disinflation", "inflation miss", "lower than expected inflation"]'::jsonb,
   0.8, '{US,EZ,UK,JP,CN}'::text[],
   '{"primary": [{"driver": "inflation_headline", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "anticipations_inflation", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}], "auto_propagate": [{"driver": "taux_directeurs", "via_arc": "inflation_headline→taux_directeurs", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "spreads_souverains", "via_arc": "anticipations_inflation→spreads_souverains", "direction": -1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Deflation risk context changes asset reaction: equities may sell if deflationary spiral feared"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'inflation_cpi_inline', 'MACRO_DATA_RELEASE', 'CPI — In Line with Expectations',
   'Published CPI within ±0.05pp of consensus',
   '["US CPI 3.2% Aug 2023 in line", "EZ core CPI confirms trend"]'::jsonb, '["CPI inline", "as expected", "in line with consensus", "conforme aux attentes"]'::jsonb,
   0.7, '{US,EZ,UK}'::text[],
   '{"primary": [], "auto_propagate": [{"driver": "sentiment_marche", "via_arc": "inline_data→sentiment_marche", "direction": -1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Minimal price action; markets move on core vs headline divergence"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_growth": "neutral"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'gdp_above', 'MACRO_DATA_RELEASE', 'GDP — Above Expectations',
   'GDP print materially beats consensus',
   '["US Q3 2023 GDP 4.9% vs 4.2% est", "EZ avoids recession Q4 2022"]'::jsonb, '["GDP beat", "stronger growth", "above forecast GDP", "croissance supérieure"]'::jsonb,
   0.8, '{US,EZ,UK,JP,CN}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}], "auto_propagate": [{"driver": "emploi_chomage", "via_arc": "croissance_pib→emploi_chomage", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "investissement", "via_arc": "croissance_pib→investissement", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "consommation", "via_arc": "croissance_pib→consommation", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "taux_directeurs", "via_arc": "croissance_pib→taux_directeurs", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Strong GDP raises rate expectations; may be net negative for equities in inflation context"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_cyclical": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'gdp_below', 'MACRO_DATA_RELEASE', 'GDP — Below Expectations',
   'GDP print materially misses consensus or negative',
   '["EZ GDP -0.1% Q3 2022 recession", "UK GDP -0.3% contraction"]'::jsonb, '["GDP miss", "recession", "contraction", "weaker growth", "récession"]'::jsonb,
   0.8, '{US,EZ,UK,JP,CN}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}], "auto_propagate": [{"driver": "emploi_chomage", "via_arc": "croissance_pib→emploi_chomage", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "investissement", "via_arc": "croissance_pib→investissement", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "taux_directeurs", "via_arc": "croissance_pib→taux_directeurs", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Recession + high inflation = stagflation; bonds may also sell"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_cyclical": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'gdp_revision_up', 'MACRO_DATA_RELEASE', 'GDP Revision — Upward',
   'Revision of prior GDP estimate upward',
   '["BEA Q2 2023 GDP revised to 2.4% from 2.0%"]'::jsonb, '["GDP revision up", "upward revision", "revised higher", "révision à la hausse PIB"]'::jsonb,
   0.7, '{US,EZ,UK}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "immediate"}], "auto_propagate": [], "conditions": [], "conflict_note": "Revisions rarely move markets unless magnitude is large"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_cyclical": "neutral"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'gdp_revision_down', 'MACRO_DATA_RELEASE', 'GDP Revision — Downward',
   'Revision of prior GDP estimate downward',
   '["UK GDP revised to -0.5% confirming recession"]'::jsonb, '["GDP revision down", "downward revision", "revised lower", "révision à la baisse PIB"]'::jsonb,
   0.7, '{US,EZ,UK}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "immediate"}], "auto_propagate": [], "conditions": [], "conflict_note": "Downward revisions confirming recession fears more impactful"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_cyclical": "neutral"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'nfp_above', 'MACRO_DATA_RELEASE', 'NFP — Above Expectations',
   'US Non-Farm Payrolls beat consensus',
   '["NFP 517k Jan 2023 vs 187k est", "NFP 336k Sep 2023 vs 170k est"]'::jsonb, '["NFP beat", "payrolls above", "jobs beat", "strong employment"]'::jsonb,
   0.85, '{US}'::text[],
   '{"primary": [{"driver": "emploi_chomage", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "consommation", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "taux_directeurs", "via_arc": "emploi_chomage→taux_directeurs", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "inflation_headline", "via_arc": "consommation→inflation_headline", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Strong jobs in soft-landing scenario bullish equities; in inflation scenario bearish"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'nfp_below', 'MACRO_DATA_RELEASE', 'NFP — Below Expectations',
   'US Non-Farm Payrolls miss consensus',
   '["NFP 49k Jan 2021 vs 105k est", "NFP -2.8M May 2020"]'::jsonb, '["NFP miss", "payrolls below", "jobs miss", "weak employment"]'::jsonb,
   0.85, '{US}'::text[],
   '{"primary": [{"driver": "emploi_chomage", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "consommation", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.5, "horizon": "1-4w"}], "auto_propagate": [{"driver": "taux_directeurs", "via_arc": "emploi_chomage→taux_directeurs", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "croissance_pib", "via_arc": "consommation→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Weak jobs + high inflation = stagflation risk"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'unemployment_rise', 'MACRO_DATA_RELEASE', 'Unemployment — Rising',
   'Unemployment rate increases above consensus or trend',
   '["US unemployment 4.3% Jul 2024 Sahm rule trigger"]'::jsonb, '["unemployment rise", "jobless rate up", "taux chômage hausse", "labor market weakness"]'::jsonb,
   0.75, '{US,EZ,UK}'::text[],
   '{"primary": [{"driver": "emploi_chomage", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.75, "horizon": "immediate"}, {"driver": "consommation", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "emploi_chomage→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "taux_directeurs", "via_arc": "emploi_chomage→taux_directeurs", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Sahm Rule crossing 0.5% signals recession with high historical accuracy"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_cyclical": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'unemployment_fall', 'MACRO_DATA_RELEASE', 'Unemployment — Falling',
   'Unemployment rate decreases below consensus or multi-year low',
   '["US unemployment 3.4% Jan 2023 (50y low)", "EZ record low 6.0%"]'::jsonb, '["unemployment fall", "jobless rate down", "record low unemployment", "taux chômage bas"]'::jsonb,
   0.75, '{US,EZ,UK}'::text[],
   '{"primary": [{"driver": "emploi_chomage", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}, {"driver": "consommation", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-4w"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "consommation→inflation_headline", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "taux_directeurs", "via_arc": "emploi_chomage→taux_directeurs", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Tight labor market signals wage pressure → inflation risk"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "bearish", "equities_cyclical": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'pmi_expansion', 'MACRO_DATA_RELEASE', 'PMI — Expansion',
   'PMI (composite/manufacturing/services) above 50 and/or beats consensus',
   '["ISM Manufacturing 57.1", "EZ Composite PMI 52.6"]'::jsonb, '["PMI above 50", "expansion", "manufacturing activity up", "services expansion"]'::jsonb,
   0.7, '{US,EZ,UK,JP,CN,GLOBAL}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}, {"driver": "investissement", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-4w"}], "auto_propagate": [{"driver": "sentiment_marche", "via_arc": "pmi→sentiment_marche", "direction": 1, "intensity": "low", "horizon": "immediate"}, {"driver": "emploi_chomage", "via_arc": "pmi→emploi_chomage", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Leading indicator; actual GDP print may diverge"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_cyclical": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'pmi_contraction', 'MACRO_DATA_RELEASE', 'PMI — Contraction',
   'PMI below 50 and/or misses consensus materially',
   '["ISM Manufacturing 46.0 recession signal", "EZ PMI 44.4 deep contraction"]'::jsonb, '["PMI below 50", "contraction", "manufacturing decline", "services contraction"]'::jsonb,
   0.7, '{US,EZ,UK,JP,CN,GLOBAL}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}, {"driver": "investissement", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-4w"}], "auto_propagate": [{"driver": "sentiment_marche", "via_arc": "pmi→sentiment_marche", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "emploi_chomage", "via_arc": "pmi→emploi_chomage", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Manufacturing vs Services divergence is key; services PMI more predictive in modern economy"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_cyclical": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'trade_balance_deficit_widen', 'MACRO_DATA_RELEASE', 'Trade Balance — Deficit Widening',
   'Trade deficit widens significantly beyond expectations',
   '["US trade deficit $100bn record 2022", "UK current account deficit 8% GDP"]'::jsonb, '["trade deficit", "current account deficit", "imports surge", "déficit commercial"]'::jsonb,
   0.7, '{US,UK,EZ}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}], "auto_propagate": [{"driver": "usd_strength", "via_arc": "balance_commerciale→usd_strength", "direction": -1, "intensity": "low", "horizon": "1-4w"}, {"driver": "dette_publique", "via_arc": "balance_commerciale→dette_publique", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Trade deficit can be positive (strong domestic demand) or negative (structural weakness)"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bearish", "gold": "neutral", "equities_growth": "neutral"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'consumer_confidence_rise', 'MACRO_DATA_RELEASE', 'Consumer Confidence — Rising',
   'Consumer confidence index beats consensus significantly',
   '["Michigan Consumer Sentiment 79 vs 73 est", "Conference Board 117 vs 104 est"]'::jsonb, '["consumer confidence up", "sentiment rise", "Michigan survey beat", "confiance consommateurs hausse"]'::jsonb,
   0.65, '{US,EZ,UK}'::text[],
   '{"primary": [{"driver": "consommation", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "consommation→croissance_pib", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "sentiment_marche", "via_arc": "confidence→sentiment_marche", "direction": 1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Soft data; actual retail sales print is more actionable"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_consumer": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'consumer_confidence_fall', 'MACRO_DATA_RELEASE', 'Consumer Confidence — Falling',
   'Consumer confidence index misses consensus significantly or multi-year low',
   '["Michigan Sentiment 50 Jun 2022 (historic low)", "Conference Board 98 vs 110 est"]'::jsonb, '["consumer confidence fall", "sentiment decline", "pessimism", "confiance consommateurs baisse"]'::jsonb,
   0.65, '{US,EZ,UK}'::text[],
   '{"primary": [{"driver": "consommation", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "consommation→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-6m"}, {"driver": "sentiment_marche", "via_arc": "confidence→sentiment_marche", "direction": -1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "University of Michigan vs Conference Board have different leading properties"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_consumer": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'retail_sales_above', 'MACRO_DATA_RELEASE', 'Retail Sales — Above Expectations',
   'Retail sales beat consensus, signalling robust consumer spending',
   '["US Retail Sales +1.3% MoM vs +0.3% est Dec 2023"]'::jsonb, '["retail sales beat", "consumer spending strong", "retail above", "ventes détail supérieures"]'::jsonb,
   0.75, '{US,UK,EZ}'::text[],
   '{"primary": [{"driver": "consommation", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "consommation→inflation_headline", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "croissance_pib", "via_arc": "consommation→croissance_pib", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Control group retail sales (ex-auto, gas, food) most predictive for GDP"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_consumer": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-02', 'retail_sales_below', 'MACRO_DATA_RELEASE', 'Retail Sales — Below Expectations',
   'Retail sales miss consensus, signalling consumer spending weakness',
   '["US Retail Sales -1.1% MoM Jan 2023"]'::jsonb, '["retail sales miss", "consumer spending weak", "retail below", "ventes détail inférieures"]'::jsonb,
   0.75, '{US,UK,EZ}'::text[],
   '{"primary": [{"driver": "consommation", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "consommation→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "taux_directeurs", "via_arc": "croissance_pib→taux_directeurs", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "One-month miss often weather/seasonal; trend over 3m more meaningful"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_consumer": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'armed_conflict_start', 'GEOPOLITICAL_SHOCK', 'Armed Conflict — Start',
   'New armed conflict begins between nations or major intra-national war',
   '["Russia invades Ukraine Feb 2022", "Hamas attack Oct 2023", "Iraq invasion Mar 2003"]'::jsonb, '["invasion", "war begins", "military attack", "armed conflict", "invasion militaire"]'::jsonb,
   0.85, '{GLOBAL,EU,ME,EE}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.95, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "risque_geopolitique→prix_petrole", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "prix_metaux", "via_arc": "risque_geopolitique→prix_metaux", "direction": 1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "liquidite_globale", "via_arc": "risque_geopolitique→liquidite_globale", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "usd_strength", "via_arc": "risque_geopolitique→usd_strength", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "spreads_souverains", "via_arc": "risque_geopolitique→spreads_souverains", "direction": 1, "intensity": "strong", "horizon": "1-4w"}], "conditions": [{"if": "conflict_near_oil_region", "then": "prix_petrole_amplified"}], "conflict_note": "UST safe haven bid competes with inflation/fiscal fear; depends on US involvement"}'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities": "bearish", "energy": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'armed_conflict_escalation', 'GEOPOLITICAL_SHOCK', 'Armed Conflict — Escalation',
   'Existing conflict escalates materially (new front, nuclear threat, NATO involvement)',
   '["Ukraine war nuclear threat Oct 2022", "Gaza escalation Jan 2024"]'::jsonb, '["escalation", "escalates", "new offensive", "nuclear threat", "OTAN impliqué"]'::jsonb,
   0.8, '{GLOBAL,EU,ME}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.75, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "risque_geopolitique→prix_petrole", "direction": 1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "usd_strength", "via_arc": "risque_geopolitique→usd_strength", "direction": 1, "intensity": "moderate", "horizon": "immediate"}], "conditions": [], "conflict_note": "Escalation effects diminish with market fatigue; first event most impactful"}'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'armed_conflict_ceasefire', 'GEOPOLITICAL_SHOCK', 'Armed Conflict — Ceasefire',
   'Ceasefire agreement or major de-escalation in ongoing conflict',
   '["Ukraine ceasefire talks", "Gaza ceasefire", "Minsk agreements"]'::jsonb, '["ceasefire", "peace talks", "truce", "cessez-le-feu"]'::jsonb,
   0.8, '{GLOBAL,EU,ME}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "risque_geopolitique→prix_petrole", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "usd_strength", "via_arc": "risque_geopolitique→usd_strength", "direction": -1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Credibility of ceasefire key; fragile truces have limited lasting market impact"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bearish", "gold": "bearish", "equities": "bullish", "energy": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'sanctions_announcement', 'GEOPOLITICAL_SHOCK', 'Sanctions — New Package Announced',
   'Major sanctions package announced against a country or entity',
   '["G7 sanctions on Russia Feb 2022", "SWIFT disconnection", "Iran JCPOA sanctions"]'::jsonb, '["sanctions", "embargo", "SWIFT disconnection", "asset freeze", "sanctions annoncées"]'::jsonb,
   0.85, '{GLOBAL,RU,IR,CN}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "1-4w"}, {"driver": "prix_petrole", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}], "auto_propagate": [{"driver": "usd_strength", "via_arc": "sanctions→usd_strength", "direction": 1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "spreads_souverains", "via_arc": "sanctions→spreads_souverains", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "risque_geopolitique", "via_arc": "sanctions→risque_geopolitique", "direction": 1, "intensity": "moderate", "horizon": "immediate"}], "conditions": [{"if": "sanctions_include_energy", "then": "prix_petrole_amplified"}], "conflict_note": "Secondary sanctions and implementation speed determine market impact magnitude"}'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities_target_country": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'sanctions_lifted', 'GEOPOLITICAL_SHOCK', 'Sanctions — Lifted or Eased',
   'Significant lifting or easing of existing sanctions',
   '["Iran nuclear deal 2015", "Sudan sanctions lifted 2017"]'::jsonb, '["sanctions lifted", "sanctions eased", "embargo lifted", "sanctions levées"]'::jsonb,
   0.8, '{GLOBAL}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}, {"driver": "prix_petrole", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.5, "horizon": "immediate"}], "auto_propagate": [{"driver": "risque_geopolitique", "via_arc": "sanctions_lifted→risque_geopolitique", "direction": -1, "intensity": "moderate", "horizon": "immediate"}], "conditions": [], "conflict_note": "Oil supply addition from sanctions lifting depends on target country capacity"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bearish", "gold": "bearish", "energy": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'diplomatic_crisis', 'GEOPOLITICAL_SHOCK', 'Diplomatic Crisis',
   'Major diplomatic breakdown without direct military action',
   '["US-China balloon crisis Feb 2023", "UK-Russia Salisbury poisoning 2018"]'::jsonb, '["diplomatic crisis", "ambassador recalled", "expulsion diplomatique", "trade spat"]'::jsonb,
   0.75, '{GLOBAL,US,CN,EU,RU}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "immediate"}], "auto_propagate": [{"driver": "balance_commerciale", "via_arc": "risque_geopolitique→balance_commerciale", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Diplomatic crises rarely move markets substantially unless escalation risk is high"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities": "slightly_bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'regime_change_unstable', 'GEOPOLITICAL_SHOCK', 'Regime Change — Destabilizing',
   'Government overthrow, coup, or election producing political instability',
   '["Venezuela crisis 2019", "Egypt coup 2013", "Myanmar coup 2021"]'::jsonb, '["coup", "overthrow", "instability", "government collapse", "coup d''état"]'::jsonb,
   0.8, '{EM,ME,AF,LATAM}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.8, "horizon": "immediate"}, {"driver": "spreads_souverains", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "sentiment_marche", "via_arc": "risque_geopolitique→sentiment_marche", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "liquidite_globale", "via_arc": "risque_geopolitique→liquidite_globale", "direction": -1, "intensity": "low", "horizon": "immediate"}], "conditions": [{"if": "country_is_oil_producer", "then": "prix_petrole_impacted"}], "conflict_note": "EM contagion depends on country size and financial linkages"}'::jsonb, '{"bonds_sovereign_em": "bearish", "usd": "bullish", "gold": "bullish", "equities_local": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'regime_change_stable', 'GEOPOLITICAL_SHOCK', 'Regime Change — Stabilizing',
   'Peaceful transition or election producing stable pro-market government',
   '["Brazil Lula election 2022 (market calm)", "South Africa ANC coalition"]'::jsonb, '["election stabilizing", "transition stable", "reform government", "pro-market election"]'::jsonb,
   0.7, '{EM,LATAM,AF}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "immediate"}, {"driver": "spreads_souverains", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "immediate"}], "auto_propagate": [{"driver": "investissement", "via_arc": "regime_stable→investissement", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Market reaction depends on pre-existing risk premium compression"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "neutral", "gold": "neutral", "equities_local": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-03', 'major_terrorism', 'GEOPOLITICAL_SHOCK', 'Major Terrorism Event',
   'High-casualty terrorist attack on civilian or infrastructure targets',
   '["9/11 Sep 2001", "Paris attacks Nov 2015", "London Bridge attack 2017"]'::jsonb, '["terrorist attack", "terrorism", "explosion", "mass casualty", "attentat"]'::jsonb,
   0.85, '{GLOBAL,US,EU,ME}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.8, "horizon": "immediate"}, {"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "risque_geopolitique→prix_petrole", "direction": 1, "intensity": "low", "horizon": "immediate"}, {"driver": "usd_strength", "via_arc": "risque_geopolitique→usd_strength", "direction": 1, "intensity": "moderate", "horizon": "immediate"}], "conditions": [{"if": "attack_on_energy_infrastructure", "then": "prix_petrole_strong"}], "conflict_note": "Recovery typically fast (days); 9/11 exception due to systemic disruption scale"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'opec_cut', 'ENERGY_COMMODITY_SHOCK', 'OPEC+ Production Cut',
   'OPEC+ announces meaningful production reduction',
   '["OPEC+ -2Mb/d Oct 2022", "Saudi voluntary cut -1Mb/d 2023"]'::jsonb, '["OPEC cut", "production cut", "OPEC+", "barrels per day reduction", "réduction production OPEP"]'::jsonb,
   0.9, '{GLOBAL,ME}'::text[],
   '{"primary": [{"driver": "prix_petrole", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_petrole→inflation_headline", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "anticipations_inflation", "via_arc": "inflation_headline→anticipations_inflation", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "taux_directeurs", "via_arc": "anticipations_inflation→taux_directeurs", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "balance_commerciale", "via_arc": "prix_petrole→balance_commerciale", "direction": -1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Compliance rate and global demand outlook modulate magnitude of oil price move"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities_energy": "bullish", "equities_broad": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'opec_increase', 'ENERGY_COMMODITY_SHOCK', 'OPEC+ Production Increase',
   'OPEC+ announces production quota increase or restoration',
   '["OPEC+ +650kb/d 2022 summer", "Saudi Arabia production ramp-up"]'::jsonb, '["OPEC increase", "production boost", "quota increase", "supply increase OPEC"]'::jsonb,
   0.85, '{GLOBAL,ME}'::text[],
   '{"primary": [{"driver": "prix_petrole", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.75, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_petrole→inflation_headline", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "anticipations_inflation", "via_arc": "inflation_headline→anticipations_inflation", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Demand destruction context may limit price relief effect"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bearish", "equities_energy": "bearish", "equities_consumer": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'oil_supply_disruption', 'ENERGY_COMMODITY_SHOCK', 'Oil Supply Disruption',
   'Major unplanned supply disruption (attack, natural disaster, embargo)',
   '["Abqaiq attack -5Mb/d Sep 2019", "Libya disruption 2011"]'::jsonb, '["oil disruption", "supply outage", "pipeline attack", "rupture approvisionnement pétrole"]'::jsonb,
   0.85, '{GLOBAL,ME,AF}'::text[],
   '{"primary": [{"driver": "prix_petrole", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_petrole→inflation_headline", "direction": 1, "intensity": "strong", "horizon": "1-4w"}, {"driver": "prix_metaux", "via_arc": "prix_petrole→prix_metaux", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "sentiment_marche", "via_arc": "oil_disruption→sentiment_marche", "direction": -1, "intensity": "moderate", "horizon": "immediate"}], "conditions": [], "conflict_note": "SPR releases can offset short-term; duration depends on reserve buffer vs outage"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities_energy": "bullish", "equities_airline": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'oil_demand_revision_up', 'ENERGY_COMMODITY_SHOCK', 'Oil Demand Revision — Upward',
   'IEA/OPEC/EIA revises global oil demand upward significantly',
   '["IEA +300kb/d demand revision", "China reopening demand surge 2023"]'::jsonb, '["oil demand up", "demand revision higher", "demand surge", "IEA upgrades demand"]'::jsonb,
   0.75, '{GLOBAL,CN}'::text[],
   '{"primary": [{"driver": "prix_petrole", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_petrole→inflation_headline", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Agency revisions are lagging; market often already priced move"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_energy": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'oil_demand_revision_down', 'ENERGY_COMMODITY_SHOCK', 'Oil Demand Revision — Downward',
   'IEA/OPEC/EIA revises global oil demand downward (recession, EV adoption)',
   '["IEA demand revision -400kb/d 2023", "recession demand cut forecast"]'::jsonb, '["oil demand down", "demand revision lower", "demand weakness", "IEA cuts demand"]'::jsonb,
   0.75, '{GLOBAL}'::text[],
   '{"primary": [{"driver": "prix_petrole", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_petrole→inflation_headline", "direction": -1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Long-term EV transition demand destruction = structural not cyclical"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bearish", "equities_energy": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'gas_supply_disruption', 'ENERGY_COMMODITY_SHOCK', 'Natural Gas Supply Disruption',
   'Major gas supply outage or infrastructure damage',
   '["Nord Stream sabotage Sep 2022", "Russia gas cutoff to Europe"]'::jsonb, '["gas disruption", "gas supply cut", "pipeline disruption", "gaz naturel rupture"]'::jsonb,
   0.85, '{EZ,EU,UK}'::text[],
   '{"primary": [{"driver": "prix_gaz", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_gaz→inflation_headline", "direction": 1, "intensity": "strong", "horizon": "1-4w"}, {"driver": "croissance_pib", "via_arc": "prix_gaz→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "anticipations_inflation", "via_arc": "inflation_headline→anticipations_inflation", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "taux_directeurs", "via_arc": "anticipations_inflation→taux_directeurs", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "winter_season", "then": "inflation_impact_amplified"}], "conflict_note": "European economy particularly sensitive; industrial curtailment = GDP drag"}'::jsonb, '{"bonds_sovereign": "bearish", "eur": "bearish", "gold": "bullish", "equities_europe": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'gas_storage_alert', 'ENERGY_COMMODITY_SHOCK', 'Gas Storage — Critical Alert',
   'Gas storage falls to critically low levels or policy emergency declared',
   '["EU gas storage 20% Aug 2022", "UK gas alert"]'::jsonb, '["gas storage low", "gas shortage", "energy alert", "réserves gaz critiques"]'::jsonb,
   0.8, '{EZ,UK,EU}'::text[],
   '{"primary": [{"driver": "prix_gaz", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_gaz→inflation_headline", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "croissance_pib", "via_arc": "prix_gaz→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "EU 80% refill target is market anchor"}'::jsonb, '{"bonds_sovereign": "bearish", "eur": "bearish", "gold": "neutral", "equities_europe": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'agricultural_drought', 'ENERGY_COMMODITY_SHOCK', 'Agricultural — Major Drought',
   'Significant drought impacting major crop producing region',
   '["US Midwest drought 2012", "Black Sea wheat disruption 2022"]'::jsonb, '["drought", "crop failure", "harvest loss", "sécheresse", "food shortage"]'::jsonb,
   0.75, '{US,BR,AU,UA,IN}'::text[],
   '{"primary": [{"driver": "prix_agricoles", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_agricoles→inflation_headline", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "anticipations_inflation", "via_arc": "inflation_headline→anticipations_inflation", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "major_crop_exporter", "then": "global_food_inflation_amplified"}], "conflict_note": "Food inflation particularly impactful in EM where food weight in CPI is higher"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_agri": "bullish", "equities_food": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'agricultural_surplus', 'ENERGY_COMMODITY_SHOCK', 'Agricultural — Surplus / Bumper Harvest',
   'Major crop surplus or bumper harvest reducing food prices',
   '["Record US corn harvest 2016", "Brazil soy record 2023"]'::jsonb, '["bumper harvest", "crop surplus", "record harvest", "récolte record"]'::jsonb,
   0.65, '{US,BR,AR}'::text[],
   '{"primary": [{"driver": "prix_agricoles", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_agricoles→inflation_headline", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Disinflation from food prices modest in DM where food weight is low"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_agri": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'metals_shortage', 'ENERGY_COMMODITY_SHOCK', 'Critical Metals — Shortage',
   'Significant shortage of industrial or critical metals',
   '["LME nickel short squeeze Mar 2022", "Lithium shortage 2022"]'::jsonb, '["metals shortage", "copper deficit", "lithium shortage", "pénurie métaux"]'::jsonb,
   0.75, '{GLOBAL,CN,DRC}'::text[],
   '{"primary": [{"driver": "prix_metaux", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_metaux→inflation_headline", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "investissement", "via_arc": "prix_metaux→investissement", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Critical minerals shortage increasingly geopolitical — China export controls risk"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bullish", "equities_mining": "bullish", "equities_ev": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-04', 'metals_surplus', 'ENERGY_COMMODITY_SHOCK', 'Critical Metals — Surplus',
   'Oversupply of industrial metals depressing prices',
   '["Iron ore glut 2015", "Aluminum oversupply 2015-16"]'::jsonb, '["metals surplus", "oversupply", "metal glut", "excédent métaux"]'::jsonb,
   0.65, '{GLOBAL,CN}'::text[],
   '{"primary": [{"driver": "prix_metaux", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}], "auto_propagate": [{"driver": "investissement", "via_arc": "prix_metaux→investissement", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Chinese demand signal is primary driver of metals surplus/deficit cycle"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_mining": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'tariff_hike', 'TRADE_POLICY', 'Tariff — New or Increased',
   'New tariff or significant tariff increase imposed on goods',
   '["US 25% tariffs on $200bn Chinese goods 2018", "EU steel tariffs", "Trump 2025 tariffs"]'::jsonb, '["tariff", "import tax", "duties imposed", "tariff hike", "droits de douane"]'::jsonb,
   0.85, '{US,CN,EU}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}, {"driver": "inflation_headline", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "balance_commerciale→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "conditions_credit", "via_arc": "tariff_hike→conditions_credit", "direction": -1, "intensity": "low", "horizon": "1-6m"}, {"driver": "usd_strength", "via_arc": "tariff_hike→usd_strength", "direction": 1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Retaliation risk amplifies impact; affected sectors (autos, agri, tech) diverge"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities_exporter": "bearish", "equities_domestic": "mixed"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'tariff_cut', 'TRADE_POLICY', 'Tariff — Cut or Removal',
   'Tariff reduction or removal as part of trade deal or unilateral easing',
   '["US-China Phase 1 tariff rollback 2020", "UK post-Brexit tariff reductions"]'::jsonb, '["tariff cut", "tariff removed", "trade liberalization", "réduction droits de douane"]'::jsonb,
   0.8, '{US,CN,UK,EU}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}, {"driver": "inflation_headline", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "balance_commerciale→croissance_pib", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Impact depends on magnitude and strategic significance of goods targeted"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bearish", "gold": "bearish", "equities_exporter": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'tariff_threat', 'TRADE_POLICY', 'Tariff — Threat or Warning',
   'Official tariff threat without implementation',
   '["Trump tariff tweet", "EU threatening counter-tariffs"]'::jsonb, '["tariff threat", "threatens tariffs", "tariff warning", "trade threat", "menace tarifaire"]'::jsonb,
   0.7, '{US,CN,EU}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "immediate"}], "auto_propagate": [{"driver": "usd_strength", "via_arc": "tariff_threat→usd_strength", "direction": 1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Markets increasingly desensitized to repeated threats"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "slightly_bullish", "gold": "neutral", "equities": "slightly_bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'trade_agreement_signed', 'TRADE_POLICY', 'Trade Agreement — Signed',
   'Major free trade agreement signed or enters into force',
   '["USMCA ratification 2020", "EU-Japan EPA", "RCEP 2022"]'::jsonb, '["trade deal signed", "free trade agreement", "FTA signed", "accord commercial signé"]'::jsonb,
   0.8, '{GLOBAL,US,EU,ASIA}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-6m"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "balance_commerciale→croissance_pib", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "investissement", "via_arc": "trade_agreement→investissement", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Markets often price in deal before signing; announcement effect may be limited"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_exporter": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'trade_agreement_collapsed', 'TRADE_POLICY', 'Trade Agreement — Collapsed',
   'Major trade deal falls apart or withdrawal announced',
   '["US withdrawal from TPP 2017", "Brexit hard exit risk", "TTIP collapse"]'::jsonb, '["trade deal collapsed", "withdrawal trade", "trade agreement failure", "accord commercial effondré"]'::jsonb,
   0.8, '{US,EU,UK}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "balance_commerciale→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "investissement", "via_arc": "trade_collapse→investissement", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "risque_geopolitique", "via_arc": "trade_risk→risque_geopolitique", "direction": 1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Uncertainty premium added; renegotiation risk vs clean break"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities_exporter": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'export_restriction_tech', 'TRADE_POLICY', 'Export Restriction — Technology',
   'Export controls on technology (semiconductors, AI chips, software)',
   '["US chip export ban to China Oct 2022", "TSMC China restriction", "Dutch ASML controls"]'::jsonb, '["export controls", "chip ban", "technology restriction", "semiconductor export ban", "contrôles export tech"]'::jsonb,
   0.85, '{US,CN,NL,JP}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}, {"driver": "balance_commerciale", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-4w"}], "auto_propagate": [{"driver": "investissement", "via_arc": "tech_restriction→investissement", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "croissance_pib", "via_arc": "investissement→croissance_pib", "direction": -1, "intensity": "low", "horizon": "6m+"}], "conditions": [], "conflict_note": "Long-term supply chain restructuring impact dominates short-term"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_semiconductor_cn": "bearish", "equities_semiconductor_us": "mixed"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'export_restriction_commodity', 'TRADE_POLICY', 'Export Restriction — Commodity',
   'Export ban or restriction on agricultural or raw material commodities',
   '["India wheat export ban May 2022", "Indonesia palm oil ban", "Russia fertilizer restrictions"]'::jsonb, '["export ban commodity", "food export restriction", "commodity export ban", "restriction exportation matières"]'::jsonb,
   0.8, '{IN,RU,CN,AU}'::text[],
   '{"primary": [{"driver": "prix_agricoles", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}, {"driver": "balance_commerciale", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "1-4w"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_agricoles→inflation_headline", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Particularly inflationary for food-importing EM countries"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "neutral", "gold": "neutral", "equities_agri": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'currency_manipulation_accused', 'TRADE_POLICY', 'Currency Manipulation — Accusation',
   'Major country accused of currency manipulation by Treasury or trading partner',
   '["US labels China currency manipulator Aug 2019", "Vietnam manipulation 2020"]'::jsonb, '["currency manipulator", "currency devaluation accused", "FX manipulation", "manipulation monétaire"]'::jsonb,
   0.8, '{CN,VN,KR}'::text[],
   '{"primary": [{"driver": "usd_strength", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "immediate"}, {"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "immediate"}], "auto_propagate": [{"driver": "balance_commerciale", "via_arc": "fx_manipulation→balance_commerciale", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Accusation rarely leads to formal action; political signaling dominates"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities_cn": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'trade_war_escalation', 'TRADE_POLICY', 'Trade War — Escalation',
   'Tit-for-tat tariff/trade retaliation cycle escalating',
   '["US-China escalation 2018-19", "US-EU steel/aluminum tit-for-tat"]'::jsonb, '["trade war", "escalation tariffs", "retaliation", "guerre commerciale", "tit-for-tat"]'::jsonb,
   0.85, '{US,CN,EU}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.8, "horizon": "immediate"}, {"driver": "balance_commerciale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "trade_war→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "investissement", "via_arc": "trade_war→investissement", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "conditions_credit", "via_arc": "trade_war→conditions_credit", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Global supply chain disruption adds persistence to impact"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "mixed", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-05', 'trade_war_deescalation', 'TRADE_POLICY', 'Trade War — De-escalation',
   'Trade war truce, phase deal, or tariff rollback reducing tensions',
   '["US-China Phase 1 deal Dec 2019", "US-EU steel truce 2021"]'::jsonb, '["trade truce", "trade deal", "trade deescalation", "tariff rollback", "désescalade commerciale"]'::jsonb,
   0.8, '{US,CN,EU}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}, {"driver": "balance_commerciale", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "trade_deescalation→croissance_pib", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "investissement", "via_arc": "trade_deescalation→investissement", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Partial deals may boost sentiment without fundamentally resolving tensions"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bearish", "gold": "bearish", "equities": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'fiscal_stimulus_major', 'FISCAL_REGULATORY_POLICY', 'Fiscal Stimulus — Major',
   'Large-scale government spending package (>1% GDP)',
   '["US CARES Act $2.2tn 2020", "EU Recovery Fund €750bn", "IRA $369bn"]'::jsonb, '["fiscal stimulus", "spending package", "relief fund", "infrastructure bill", "relance budgétaire majeure"]'::jsonb,
   0.85, '{US,EU,CN}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "1-4w"}, {"driver": "dette_publique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-6m"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "croissance_pib→inflation_headline", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "taux_directeurs", "via_arc": "inflation_headline→taux_directeurs", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "spreads_souverains", "via_arc": "dette_publique→spreads_souverains", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "emploi_chomage", "via_arc": "fiscal_stimulus→emploi_chomage", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Multiplier depends on output gap; stimulus in full employment = inflation not growth"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "mixed", "gold": "bullish", "equities_cyclical": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'fiscal_stimulus_minor', 'FISCAL_REGULATORY_POLICY', 'Fiscal Stimulus — Minor',
   'Targeted government spending or tax credit (<1% GDP)',
   '["UK mini-budget 2022 (initially)", "Germany energy subsidy"]'::jsonb, '["targeted stimulus", "fiscal support", "spending increase", "relance ciblée"]'::jsonb,
   0.75, '{US,EU,UK}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.45, "horizon": "1-4w"}], "auto_propagate": [{"driver": "dette_publique", "via_arc": "fiscal_minor→dette_publique", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Narrow impact; sector-specific rather than macro"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_targeted": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'fiscal_austerity', 'FISCAL_REGULATORY_POLICY', 'Fiscal Austerity',
   'Major government spending cuts or fiscal consolidation programme',
   '["Greece bailout austerity 2010-12", "UK Osborne austerity 2010-16"]'::jsonb, '["austerity", "spending cuts", "fiscal consolidation", "budget cuts", "austérité budgétaire"]'::jsonb,
   0.8, '{EZ,UK,EM}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "1-4w"}, {"driver": "dette_publique", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-6m"}], "auto_propagate": [{"driver": "emploi_chomage", "via_arc": "austerity→emploi_chomage", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "consommation", "via_arc": "austerity→consommation", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "spreads_souverains", "via_arc": "dette_publique→spreads_souverains", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Expansionary austerity theory empirically weak; typically contractionary short-term"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "neutral", "gold": "neutral", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'tax_hike_corporate', 'FISCAL_REGULATORY_POLICY', 'Corporate Tax Hike',
   'Announced increase in corporate tax rate',
   '["Biden 28% corp tax proposal 2021", "UK corp tax 25% 2023"]'::jsonb, '["corporate tax hike", "corporate tax increase", "business tax", "hausse impôt sociétés"]'::jsonb,
   0.8, '{US,UK,EZ}'::text[],
   '{"primary": [{"driver": "investissement", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-6m"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "investissement→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-6m"}, {"driver": "dette_publique", "via_arc": "tax_hike→dette_publique", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Market impact front-runs effective date; actual vs proposed rate matters"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_corporate": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'tax_cut_corporate', 'FISCAL_REGULATORY_POLICY', 'Corporate Tax Cut',
   'Announced decrease in corporate tax rate',
   '["Trump TCJA 35%→21% Dec 2017", "Ireland 12.5% corporate rate defense"]'::jsonb, '["corporate tax cut", "tax reform", "tax reduction business", "baisse impôt sociétés"]'::jsonb,
   0.8, '{US,UK,IE}'::text[],
   '{"primary": [{"driver": "investissement", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "1-4w"}], "auto_propagate": [{"driver": "dette_publique", "via_arc": "tax_cut→dette_publique", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "spreads_souverains", "via_arc": "dette_publique→spreads_souverains", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "croissance_pib", "via_arc": "investissement→croissance_pib", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Buyback activity surge often first market signal of corporate tax cuts"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_corporate": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'tax_hike_consumer', 'FISCAL_REGULATORY_POLICY', 'Consumer Tax Hike',
   'VAT, income tax, or sales tax increase hitting consumer purchasing power',
   '["Japan VAT 8%→10% 2019", "UK NIC increase 2022"]'::jsonb, '["VAT hike", "income tax increase", "sales tax", "consumer tax", "hausse TVA"]'::jsonb,
   0.75, '{JP,UK,EZ,FR}'::text[],
   '{"primary": [{"driver": "consommation", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "1-4w"}, {"driver": "inflation_headline", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "immediate"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "consommation→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Japan VAT hikes historically triggered mini-recessions"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_consumer": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'financial_regulation_tighten', 'FISCAL_REGULATORY_POLICY', 'Financial Regulation — Tightening',
   'New banking regulation increasing capital requirements or compliance burden',
   '["Basel III implementation", "Dodd-Frank 2010", "EU MiFID II"]'::jsonb, '["financial regulation", "capital requirements", "regulatory tightening", "réglementation financière renforcement"]'::jsonb,
   0.8, '{US,EU,GLOBAL}'::text[],
   '{"primary": [{"driver": "conditions_credit", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-6m"}, {"driver": "liquidite_bancaire", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "1-6m"}], "auto_propagate": [{"driver": "spreads_credit", "via_arc": "conditions_credit→spreads_credit", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "investissement", "via_arc": "conditions_credit→investissement", "direction": -1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Long implementation timelines; financial stocks react to announcement"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_banks": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'financial_regulation_ease', 'FISCAL_REGULATORY_POLICY', 'Financial Regulation — Easing',
   'Rollback of financial regulation reducing compliance burden',
   '["Dodd-Frank rollback 2018", "EU banking union easing"]'::jsonb, '["deregulation", "regulation rollback", "financial deregulation", "déréglementation financière"]'::jsonb,
   0.75, '{US,EU}'::text[],
   '{"primary": [{"driver": "conditions_credit", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-6m"}, {"driver": "liquidite_bancaire", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-6m"}], "auto_propagate": [{"driver": "spreads_credit", "via_arc": "conditions_credit→spreads_credit", "direction": -1, "intensity": "low", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Moral hazard risk; short-term positive for banks, long-term systemic risk increase"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_banks": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'sovereign_downgrade', 'FISCAL_REGULATORY_POLICY', 'Sovereign Credit Downgrade',
   'Rating agency downgrades sovereign credit rating',
   '["US downgrade by S&P Aug 2011", "Italy Baa3 Moody''s", "France AA+ S&P 2023"]'::jsonb, '["sovereign downgrade", "credit rating cut", "ratings downgrade", "dégradation note souveraine"]'::jsonb,
   0.9, '{US,EZ,EM}'::text[],
   '{"primary": [{"driver": "spreads_souverains", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "dette_publique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "spreads_souverains→conditions_credit", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "sentiment_marche", "via_arc": "sovereign_downgrade→sentiment_marche", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "croissance_pib", "via_arc": "conditions_credit→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-6m"}], "conditions": [{"if": "downgrade_triggers_forced_selling", "then": "cascade_risk"}], "conflict_note": "US downgrade paradoxically can trigger UST rally (safe haven demand)"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bearish_if_us", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'sovereign_upgrade', 'FISCAL_REGULATORY_POLICY', 'Sovereign Credit Upgrade',
   'Rating agency upgrades sovereign credit rating',
   '["Portugal upgrade to investment grade 2017", "Greece upgrade 2023"]'::jsonb, '["sovereign upgrade", "credit rating upgrade", "ratings improvement", "relèvement note souveraine"]'::jsonb,
   0.85, '{EZ,EM}'::text[],
   '{"primary": [{"driver": "spreads_souverains", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "spreads_souverains→conditions_credit", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "investissement", "via_arc": "sovereign_upgrade→investissement", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Often partially priced in; surprise upgrades have more impact"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "neutral", "gold": "neutral", "equities_local": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-06', 'debt_ceiling_crisis', 'FISCAL_REGULATORY_POLICY', 'Debt Ceiling Crisis',
   'Government hits debt ceiling with risk of technical default',
   '["US debt ceiling crisis Aug 2011", "US debt ceiling 2023 X-date"]'::jsonb, '["debt ceiling", "government shutdown", "default risk", "X-date", "plafond dette"]'::jsonb,
   0.9, '{US}'::text[],
   '{"primary": [{"driver": "spreads_souverains", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.8, "horizon": "immediate"}], "auto_propagate": [{"driver": "liquidite_globale", "via_arc": "debt_ceiling→liquidite_globale", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "usd_strength", "via_arc": "debt_ceiling→usd_strength", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "dette_publique", "via_arc": "debt_ceiling→dette_publique", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "resolution_announced", "then": "full_reversal"}], "conflict_note": "T-bills near X-date trade at big discount; resolution produces sharp V-shaped reversal"}'::jsonb, '{"bonds_sovereign": "bearish_t_bills", "usd": "bearish", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'bank_failure', 'FINANCIAL_STABILITY', 'Bank Failure',
   'A bank fails or is seized by regulators',
   '["SVB collapse Mar 2023", "Lehman Brothers Sep 2008", "Credit Suisse AT1 writedown"]'::jsonb, '["bank failure", "bank collapse", "receivership", "FDIC takeover", "faillite bancaire"]'::jsonb,
   0.9, '{US,EU}'::text[],
   '{"primary": [{"driver": "liquidite_bancaire", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "liquidite_bancaire→conditions_credit", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "spreads_credit", "via_arc": "bank_failure→spreads_credit", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "liquidite_globale", "via_arc": "bank_failure→liquidite_globale", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "croissance_pib", "via_arc": "conditions_credit→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [{"if": "systemic_bank", "then": "contagion_risk_high"}], "conflict_note": "Contagion speed amplified by social media bank run dynamics (SVB 2023)"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities_banks": "bearish", "equities_broad": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'bank_rescue', 'FINANCIAL_STABILITY', 'Bank Rescue / Bailout',
   'Government or CB intervenes to rescue a failing institution',
   '["UBS acquires Credit Suisse Mar 2023", "US bank guarantee expansion 2023"]'::jsonb, '["bank rescue", "bailout", "government backstop", "emergency acquisition", "sauvetage bancaire"]'::jsonb,
   0.9, '{US,EU,UK}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}, {"driver": "liquidite_bancaire", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "bank_rescue→conditions_credit", "direction": 1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "spreads_credit", "via_arc": "bank_rescue→spreads_credit", "direction": -1, "intensity": "moderate", "horizon": "immediate"}], "conditions": [], "conflict_note": "Rescue credibility depends on firepower; equity shareholders typically wiped out"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_banks": "mixed"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'credit_event_sovereign', 'FINANCIAL_STABILITY', 'Credit Event — Sovereign Default',
   'Sovereign default, restructuring, or missed payment',
   '["Greece default 2012", "Argentina default 2001/2020", "Sri Lanka default 2022"]'::jsonb, '["sovereign default", "debt restructuring", "missed payment", "défaut souverain"]'::jsonb,
   0.95, '{EM,EZ}'::text[],
   '{"primary": [{"driver": "spreads_souverains", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.95, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "liquidite_globale", "via_arc": "credit_event_sov→liquidite_globale", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "spreads_credit", "via_arc": "contagion→spreads_credit", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "conditions_credit", "via_arc": "spreads_credit→conditions_credit", "direction": -1, "intensity": "strong", "horizon": "1-4w"}], "conditions": [{"if": "large_EM_country", "then": "contagion_to_other_EM"}], "conflict_note": "Orderly restructuring vs disorderly default has very different contagion dynamics"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'credit_event_corporate', 'FINANCIAL_STABILITY', 'Credit Event — Corporate Default',
   'Major corporate default, bankruptcy, or restructuring',
   '["Evergrande default 2021", "FTX collapse 2022", "Enron 2001"]'::jsonb, '["corporate default", "bankruptcy", "Chapter 11", "creditors", "défaut corporate"]'::jsonb,
   0.85, '{US,CN,EU}'::text[],
   '{"primary": [{"driver": "spreads_credit", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "spreads_credit→conditions_credit", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "liquidite_globale", "via_arc": "credit_event_corp→liquidite_globale", "direction": -1, "intensity": "low", "horizon": "immediate"}], "conditions": [{"if": "sector_wide_contagion", "then": "spreads_HY_amplified"}], "conflict_note": "Sector contagion model matters: real estate vs crypto vs finance"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "neutral", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'market_crash', 'FINANCIAL_STABILITY', 'Market Crash',
   'Sudden large equity or multi-asset selloff (>5% in a day)',
   '["Black Monday Oct 1987", "COVID crash Mar 2020", "Aug 2015 China flash crash"]'::jsonb, '["market crash", "market selloff", "equity plunge", "crash boursier"]'::jsonb,
   0.9, '{GLOBAL,US}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.95, "horizon": "immediate"}, {"driver": "liquidite_globale", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "market_crash→conditions_credit", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "spreads_credit", "via_arc": "market_crash→spreads_credit", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "croissance_pib", "via_arc": "conditions_credit→croissance_pib", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Circuit breakers may pause market; Fed put probability high in severe crashes"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'flash_crash', 'FINANCIAL_STABILITY', 'Flash Crash',
   'Sudden extreme intraday market move reversed quickly, often algo-driven',
   '["May 2010 Flash Crash", "GBP flash crash Oct 2016", "Crypto flash crash May 2021"]'::jsonb, '["flash crash", "mini-crash", "algo crash", "rapid reversal", "micro-crash"]'::jsonb,
   0.8, '{GLOBAL,US}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}], "auto_propagate": [], "conditions": [], "conflict_note": "Flash crashes typically fully reverse; persistent fear signal if partial recovery only"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities": "bearish_momentary"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'contagion_spread_widening', 'FINANCIAL_STABILITY', 'Contagion — Spread Widening',
   'Credit or sovereign spread contagion spreading across countries or asset classes',
   '["EZ sovereign contagion 2011", "EM contagion 2013 taper tantrum"]'::jsonb, '["contagion", "spread widening", "spillover", "systemic risk", "contagion financière"]'::jsonb,
   0.85, '{EZ,EM,GLOBAL}'::text[],
   '{"primary": [{"driver": "spreads_souverains", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}, {"driver": "spreads_credit", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "conditions_credit", "via_arc": "spreads_credit→conditions_credit", "direction": -1, "intensity": "strong", "horizon": "1-4w"}, {"driver": "liquidite_globale", "via_arc": "contagion→liquidite_globale", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "sentiment_marche", "via_arc": "contagion→sentiment_marche", "direction": -1, "intensity": "strong", "horizon": "immediate"}], "conditions": [], "conflict_note": "Draghi ''whatever it takes'' showed CB can arrest contagion"}'::jsonb, '{"bonds_sovereign_core": "bullish", "bonds_sovereign_periph": "bearish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'systemic_risk_warning', 'FINANCIAL_STABILITY', 'Systemic Risk Warning',
   'Official systemic risk warning from FSB, BIS, IMF, or major CB',
   '["BIS annual report warning 2022", "FSB leverage concerns 2023", "IMF GFSR red flag"]'::jsonb, '["systemic risk", "financial stability warning", "FSB alert", "BIS concern", "risque systémique"]'::jsonb,
   0.8, '{GLOBAL}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "immediate"}], "auto_propagate": [{"driver": "liquidite_globale", "via_arc": "systemic_warn→liquidite_globale", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Official warnings often lagging; BIS early warnings more prescient"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities": "slightly_bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-07', 'liquidity_crisis', 'FINANCIAL_STABILITY', 'Liquidity Crisis',
   'Acute market or banking liquidity shortage (repo stress, dollar shortage)',
   '["Repo market crisis Sep 2019", "Dollar shortage Mar 2020", "UK gilt crisis Sep 2022"]'::jsonb, '["liquidity crisis", "repo stress", "dollar shortage", "margin calls", "crise liquidité"]'::jsonb,
   0.9, '{US,UK,GLOBAL}'::text[],
   '{"primary": [{"driver": "liquidite_globale", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}, {"driver": "liquidite_bancaire", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.85, "horizon": "immediate"}], "auto_propagate": [{"driver": "spreads_credit", "via_arc": "liquidite_bancaire→spreads_credit", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "conditions_credit", "via_arc": "liquidite_globale→conditions_credit", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "usd_strength", "via_arc": "dollar_shortage→usd_strength", "direction": 1, "intensity": "strong", "horizon": "immediate"}], "conditions": [], "conflict_note": "Fed/ECB/BoE backstop credibility determines duration; swap lines resolve dollar shortage"}'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "mixed", "equities": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-08', 'port_blockage', 'SUPPLY_CHAIN_DISRUPTION', 'Port Blockage',
   'Major port or shipping lane blocked or severely disrupted',
   '["Suez Canal Ever Given Mar 2021", "Shanghai port blockade 2022"]'::jsonb, '["port blockage", "Suez Canal", "port disruption", "port strike", "blocage port"]'::jsonb,
   0.8, '{GLOBAL,EZ,CN}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}, {"driver": "inflation_headline", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "balance_commerciale→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-4w"}, {"driver": "prix_metaux", "via_arc": "supply_disruption→prix_metaux", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "duration_>2weeks", "then": "inflationary_impact_amplified"}], "conflict_note": "Suez blockage added ~$200bn/week in supply chain delays"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_shipping": "bullish", "equities_retail": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-08', 'shipping_disruption', 'SUPPLY_CHAIN_DISRUPTION', 'Shipping Disruption',
   'Major disruption to global shipping routes (Red Sea attacks, Panama Canal drought)',
   '["Red Sea Houthi attacks 2024", "Panama Canal low water 2023", "container shortage 2021"]'::jsonb, '["shipping disruption", "Red Sea", "container shortage", "freight rates spike", "perturbation fret"]'::jsonb,
   0.8, '{GLOBAL,ME}'::text[],
   '{"primary": [{"driver": "balance_commerciale", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-4w"}, {"driver": "inflation_headline", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.5, "horizon": "1-4w"}], "auto_propagate": [{"driver": "prix_agricoles", "via_arc": "shipping→prix_agricoles", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "prix_metaux", "via_arc": "shipping→prix_metaux", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Drewry composite freight index is primary real-time indicator"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "neutral", "equities_shipping": "bullish", "equities_consumer": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-08', 'factory_shutdown_major', 'SUPPLY_CHAIN_DISRUPTION', 'Major Factory Shutdown',
   'Key factory or industrial complex forced to shut down',
   '["Toyota shutdowns 2021", "TSMC earthquake risk", "COVID Wuhan factory closures 2020"]'::jsonb, '["factory shutdown", "production halt", "plant closure", "fermeture usine majeure"]'::jsonb,
   0.75, '{CN,JP,US,TW}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.45, "horizon": "1-4w"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "factory_shutdown→inflation_headline", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "balance_commerciale", "via_arc": "factory_shutdown→balance_commerciale", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "sole_supplier_of_critical_component", "then": "cascade_effect"}], "conflict_note": "TSMC concentration risk = potential single-point failure for global semiconductor supply"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_sector": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-08', 'semiconductor_shortage', 'SUPPLY_CHAIN_DISRUPTION', 'Semiconductor Shortage',
   'Widespread chip shortage affecting multiple industries',
   '["Global chip shortage 2021-22", "automotive chip shortage 2021"]'::jsonb, '["chip shortage", "semiconductor shortage", "wafer shortage", "pénurie puces"]'::jsonb,
   0.8, '{GLOBAL,TW,KR,US}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-6m"}, {"driver": "inflation_headline", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.5, "horizon": "1-4w"}], "auto_propagate": [{"driver": "investissement", "via_arc": "semiconductor_shortage→investissement", "direction": -1, "intensity": "moderate", "horizon": "1-6m"}, {"driver": "balance_commerciale", "via_arc": "semiconductor_shortage→balance_commerciale", "direction": -1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Lead times 12-18m in automotive; capex super-cycle creates future oversupply risk"}'::jsonb, '{"bonds_sovereign": "bearish", "usd": "neutral", "gold": "neutral", "equities_auto": "bearish", "equities_semiconductor": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-08', 'critical_material_shortage', 'SUPPLY_CHAIN_DISRUPTION', 'Critical Material Shortage',
   'Shortage of rare earth, critical minerals, or strategic inputs',
   '["China rare earth export restrictions", "cobalt shortage 2018", "lithium crunch 2022"]'::jsonb, '["rare earth shortage", "critical mineral", "strategic material", "pénurie matériaux critiques"]'::jsonb,
   0.8, '{CN,DRC,GLOBAL}'::text[],
   '{"primary": [{"driver": "prix_metaux", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.7, "horizon": "immediate"}, {"driver": "investissement", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-6m"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "investissement→croissance_pib", "direction": -1, "intensity": "low", "horizon": "6m+"}], "conditions": [], "conflict_note": "Energy transition creates structural demand for Li, Co, Ni, rare earths through 2040+"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bullish", "equities_mining": "bullish", "equities_ev_tech": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-08', 'logistics_bottleneck', 'SUPPLY_CHAIN_DISRUPTION', 'Logistics Bottleneck',
   'General logistics system stress (trucking, rail, warehouse)',
   '["US trucker shortage 2021", "UK lorry driver shortage 2021"]'::jsonb, '["logistics bottleneck", "supply chain stress", "trucker shortage", "goulot logistique"]'::jsonb,
   0.7, '{US,UK,EU}'::text[],
   '{"primary": [{"driver": "inflation_headline", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "logistics→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "PMI supply delivery times is best aggregate proxy"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_logistics": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-08', 'pandemic_supply_shock', 'SUPPLY_CHAIN_DISRUPTION', 'Pandemic / Mass Disease Supply Shock',
   'Pandemic-level disruption to production and logistics',
   '["COVID-19 lockdowns 2020", "China COVID zero 2022"]'::jsonb, '["pandemic", "lockdown", "COVID", "epidemic supply shock", "confinement production"]'::jsonb,
   0.9, '{GLOBAL,CN}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.9, "horizon": "immediate"}, {"driver": "liquidite_globale", "direction": -1, "intensity_initial": "strong", "coefficient_initial": 0.8, "horizon": "immediate"}], "auto_propagate": [{"driver": "emploi_chomage", "via_arc": "pandemic→emploi_chomage", "direction": 1, "intensity": "strong", "horizon": "immediate"}, {"driver": "consommation", "via_arc": "pandemic→consommation", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "sentiment_marche", "via_arc": "pandemic→sentiment_marche", "direction": -1, "intensity": "strong", "horizon": "immediate"}, {"driver": "inflation_headline", "via_arc": "supply_shock→inflation_headline", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "CB/fiscal response determines post-shock inflation trajectory"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities": "bearish_initial"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'drought_major', 'CLIMATE_NATURAL_DISASTER', 'Major Drought',
   'Severe drought impacting agriculture, energy (hydro), or water supply at national scale',
   '["US 2012 drought", "European drought 2022 Rhine low water", "California 2021"]'::jsonb, '["major drought", "severe drought", "water shortage", "sécheresse majeure"]'::jsonb,
   0.8, '{US,EU,AU,IN,BR}'::text[],
   '{"primary": [{"driver": "prix_agricoles", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.8, "horizon": "1-4w"}, {"driver": "croissance_pib", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-4w"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "prix_agricoles→inflation_headline", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}, {"driver": "prix_gaz", "via_arc": "drought→prix_gaz", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "hydropower_dependent_region", "then": "energy_price_amplified"}], "conflict_note": "Rhine low water impacted German industrial output directly in 2022"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_agri": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'flood_major', 'CLIMATE_NATURAL_DISASTER', 'Major Flood',
   'Catastrophic flooding causing significant economic damage',
   '["Pakistan floods 2022", "Germany Ahr Valley 2021", "China Henan 2021"]'::jsonb, '["major flood", "catastrophic flooding", "inondation majeure", "flood disaster"]'::jsonb,
   0.8, '{GLOBAL,PK,CN,EU}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-4w"}], "auto_propagate": [{"driver": "dette_publique", "via_arc": "flood→dette_publique", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "prix_agricoles", "via_arc": "flood→prix_agricoles", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Reconstruction spending partially offsets GDP drag"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_insurance": "bearish", "equities_reconstruction": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'hurricane_typhoon', 'CLIMATE_NATURAL_DISASTER', 'Hurricane / Major Typhoon',
   'Category 3-5 hurricane or typhoon causing major economic damage',
   '["Hurricane Katrina 2005", "Hurricane Ian 2022 ($100bn+)", "Typhoon Hainan 2013"]'::jsonb, '["hurricane", "typhoon", "category 4", "major storm", "ouragan"]'::jsonb,
   0.8, '{US,JP,PH,CN}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-4w"}, {"driver": "prix_petrole", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.3, "horizon": "immediate"}], "auto_propagate": [{"driver": "inflation_headline", "via_arc": "hurricane→inflation_headline", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "dette_publique", "via_arc": "hurricane→dette_publique", "direction": 1, "intensity": "low", "horizon": "1-6m"}], "conditions": [{"if": "Gulf_of_Mexico_track", "then": "oil_supply_disruption_risk"}], "conflict_note": "Katrina hit Gulf oil infrastructure; 2022 hurricanes impacted Florida insurance market"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_insurance": "bearish", "equities_energy": "bullish_if_gulf"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'earthquake_tsunami', 'CLIMATE_NATURAL_DISASTER', 'Major Earthquake / Tsunami',
   'Magnitude 7+ earthquake or tsunami with major economic impact',
   '["Tohoku + Fukushima Mar 2011", "Turkey earthquake Feb 2023", "Haiti 2010"]'::jsonb, '["earthquake", "tsunami", "magnitude 7", "seismic", "séisme"]'::jsonb,
   0.85, '{JP,TR,TW,US}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}, {"driver": "dette_publique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.55, "horizon": "1-6m"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "earthquake→prix_petrole", "direction": 1, "intensity": "low", "horizon": "1-4w"}, {"driver": "prix_gaz", "via_arc": "earthquake→prix_gaz", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "nuclear_facility_impacted", "then": "energy_price_spike"}], "conflict_note": "Japan repatriated yen post-Fukushima → JPY strength despite disaster"}'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities_local": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'wildfire_major', 'CLIMATE_NATURAL_DISASTER', 'Major Wildfire',
   'Catastrophic wildfire season causing economic damage',
   '["California wildfires 2018/2020", "Australia bushfires 2019-20", "Canada 2023"]'::jsonb, '["wildfire", "forest fire", "bushfire", "incendie forêt"]'::jsonb,
   0.75, '{US,AU,CA,EU}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-4w"}], "auto_propagate": [{"driver": "dette_publique", "via_arc": "wildfire→dette_publique", "direction": 1, "intensity": "low", "horizon": "1-6m"}, {"driver": "prix_agricoles", "via_arc": "wildfire→prix_agricoles", "direction": 1, "intensity": "low", "horizon": "1-4w"}], "conditions": [], "conflict_note": "PG&E bankruptcy from California wildfires shows utility sector tail risk"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_insurance": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'climate_policy_new', 'CLIMATE_NATURAL_DISASTER', 'Major Climate Policy Announced',
   'New climate law or international agreement with significant economic implications',
   '["US IRA Aug 2022", "EU Green Deal 2019", "UK net-zero 2050 law", "Paris Agreement"]'::jsonb, '["climate policy", "green deal", "net zero", "climate law", "politique climatique"]'::jsonb,
   0.8, '{US,EU,UK,GLOBAL}'::text[],
   '{"primary": [{"driver": "investissement", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "1-6m"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "climate_policy→prix_petrole", "direction": -1, "intensity": "low", "horizon": "6m+"}, {"driver": "prix_metaux", "via_arc": "climate_policy→prix_metaux", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "IRA $369bn triggered massive capex reallocation to US green manufacturing"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_green": "bullish", "equities_fossil": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'carbon_tax_announced', 'CLIMATE_NATURAL_DISASTER', 'Carbon Tax / ETS Announced',
   'New carbon tax or major ETS price change',
   '["EU ETS price €100+/ton 2023", "Canada carbon price increase", "UK ETS launch"]'::jsonb, '["carbon tax", "carbon price", "ETS", "emissions trading", "taxe carbone"]'::jsonb,
   0.8, '{EU,CA,UK}'::text[],
   '{"primary": [{"driver": "inflation_headline", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.4, "horizon": "1-4w"}, {"driver": "prix_petrole", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.3, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "carbon_cost→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-6m"}, {"driver": "investissement", "via_arc": "carbon_tax→investissement", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Carbon border adjustment (CBAM) creates new trade policy dimension"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_carbon_intensive": "bearish", "equities_clean_energy": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'green_deal_regulation', 'CLIMATE_NATURAL_DISASTER', 'Green Deal / ESG Regulation',
   'Major ESG or sustainability regulation (CSRD, taxonomy, SFDR)',
   '["EU CSRD corporate sustainability reporting", "EU taxonomy regulation", "SEC climate disclosure"]'::jsonb, '["ESG regulation", "CSRD", "green taxonomy", "sustainability disclosure", "réglementation ESG"]'::jsonb,
   0.75, '{EU,US}'::text[],
   '{"primary": [{"driver": "investissement", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-6m"}], "auto_propagate": [], "conditions": [], "conflict_note": "Compliance costs vs capital reallocation; long lag to economic impact"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_esg_compliant": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-09', 'energy_transition_target', 'CLIMATE_NATURAL_DISASTER', 'Energy Transition Target Announced',
   'Major renewable energy capacity target or fossil phase-out deadline',
   '["EU 2030 55% RE target", "UK offshore wind 50GW by 2030", "Biden 100% clean power 2035"]'::jsonb, '["renewable target", "energy transition", "phase out fossil", "RE capacity target", "cible renouvelables"]'::jsonb,
   0.75, '{EU,US,UK,CN}'::text[],
   '{"primary": [{"driver": "investissement", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-6m"}, {"driver": "prix_metaux", "direction": 1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "1-6m"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "energy_transition→prix_petrole", "direction": -1, "intensity": "low", "horizon": "6m+"}, {"driver": "croissance_pib", "via_arc": "green_capex→croissance_pib", "direction": 1, "intensity": "low", "horizon": "6m+"}], "conditions": [], "conflict_note": "Target credibility depends on policy mechanism; EU has binding targets"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_utilities": "bullish", "equities_oil_major": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-10', 'ai_breakthrough_major', 'TECHNOLOGY_STRUCTURAL', 'Major AI Breakthrough',
   'Major AI capability announcement with significant economic implications',
   '["ChatGPT launch Nov 2022", "GPT-4 release Mar 2023", "DeepSeek R1 Jan 2025", "AlphaFold 2"]'::jsonb, '["AI breakthrough", "AI model release", "artificial intelligence", "percée IA", "language model"]'::jsonb,
   0.8, '{US,CN,GLOBAL}'::text[],
   '{"primary": [{"driver": "investissement", "direction": 1, "intensity_initial": "strong", "coefficient_initial": 0.8, "horizon": "1-4w"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "investissement→croissance_pib", "direction": 1, "intensity": "low", "horizon": "6m+"}, {"driver": "emploi_chomage", "via_arc": "AI→emploi_chomage", "direction": 1, "intensity": "low", "horizon": "6m+"}, {"driver": "prix_metaux", "via_arc": "AI_capex→prix_metaux", "direction": 1, "intensity": "moderate", "horizon": "1-4w"}], "conditions": [], "conflict_note": "Productivity shock potential: general purpose technology multiplier ~5-10x direct effect"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_tech": "bullish", "equities_semiconductor": "bullish", "equities_labor_intensive": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-10', 'tech_antitrust_action', 'TECHNOLOGY_STRUCTURAL', 'Tech Antitrust Action',
   'Major antitrust lawsuit, fine, or breakup order against tech company',
   '["EU Google €2.4bn fine 2017", "US DOJ vs Google 2023", "Meta antitrust 2021"]'::jsonb, '["antitrust", "competition ruling", "tech fine", "monopoly ruling", "antitrust tech"]'::jsonb,
   0.85, '{US,EU}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.35, "horizon": "immediate"}, {"driver": "investissement", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.3, "horizon": "1-6m"}], "auto_propagate": [], "conditions": [{"if": "breakup_order", "then": "sector_disruption_amplified"}], "conflict_note": "EU DMA/DSA more impactful than US antitrust due to faster enforcement"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_targeted_tech": "bearish", "equities_broad_tech": "slightly_bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-10', 'tech_export_ban', 'TECHNOLOGY_STRUCTURAL', 'Technology Export Ban',
   'Strategic technology export ban affecting chip, software, or dual-use tech',
   '["US CHIPS Act + export controls Oct 2022", "EDA tool export ban to China"]'::jsonb, '["export ban tech", "chip export control", "technology restriction", "interdiction export technologie"]'::jsonb,
   0.85, '{US,CN}'::text[],
   '{"primary": [{"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}, {"driver": "investissement", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "1-6m"}], "auto_propagate": [{"driver": "croissance_pib", "via_arc": "investissement→croissance_pib", "direction": -1, "intensity": "low", "horizon": "6m+"}], "conditions": [], "conflict_note": "NVIDIA H100/H800 controls most impactful for AI supply chain globally"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_semiconductor_cn": "bearish", "equities_semiconductor_us": "mixed"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-10', 'productivity_shock_positive', 'TECHNOLOGY_STRUCTURAL', 'Positive Productivity Shock',
   'Technological breakthrough creating measurable productivity gains',
   '["Internet productivity boom 1995-2000", "AI productivity estimates 2023+"]'::jsonb, '["productivity gain", "efficiency breakthrough", "technology adoption surge", "choc productivité positif"]'::jsonb,
   0.7, '{US,GLOBAL}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "6m+"}], "auto_propagate": [{"driver": "inflation_core", "via_arc": "productivity→inflation_core", "direction": -1, "intensity": "low", "horizon": "6m+"}, {"driver": "investissement", "via_arc": "productivity→investissement", "direction": 1, "intensity": "moderate", "horizon": "1-6m"}], "conditions": [], "conflict_note": "Productivity shocks have long lags; market prices future earnings"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities_tech": "bullish", "equities_broad": "bullish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-10', 'cyber_attack_critical_infra', 'TECHNOLOGY_STRUCTURAL', 'Cyber Attack — Critical Infrastructure',
   'Major cyber attack on power grid, water, transport, or government systems',
   '["Colonial Pipeline ransomware May 2021", "Ukraine power grid attack 2015/2022", "SolarWinds 2020"]'::jsonb, '["cyber attack infrastructure", "ransomware critical", "power grid hack", "cyberattaque infrastructure critique"]'::jsonb,
   0.85, '{US,UA,EU}'::text[],
   '{"primary": [{"driver": "sentiment_marche", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}, {"driver": "risque_geopolitique", "direction": 1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}], "auto_propagate": [{"driver": "prix_petrole", "via_arc": "cyber_energy→prix_petrole", "direction": 1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "croissance_pib", "via_arc": "cyber_infra→croissance_pib", "direction": -1, "intensity": "low", "horizon": "1-4w"}], "conditions": [{"if": "energy_sector_targeted", "then": "prix_petrole_spike"}], "conflict_note": "Colonial Pipeline: +30% east coast fuel prices in days"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities_cyber_security": "bullish", "equities_targeted": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-10', 'cyber_attack_financial', 'TECHNOLOGY_STRUCTURAL', 'Cyber Attack — Financial System',
   'Major cyber attack on financial institutions, exchanges, or payment systems',
   '["Bangladesh Bank heist $81M 2016", "SWIFT system attacks", "exchange hack crypto"]'::jsonb, '["financial cyber attack", "bank hack", "exchange hack", "SWIFT attack", "cyberattaque financière"]'::jsonb,
   0.85, '{GLOBAL,US}'::text[],
   '{"primary": [{"driver": "liquidite_bancaire", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.6, "horizon": "immediate"}, {"driver": "sentiment_marche", "direction": -1, "intensity_initial": "moderate", "coefficient_initial": 0.65, "horizon": "immediate"}], "auto_propagate": [{"driver": "liquidite_globale", "via_arc": "cyber_fin→liquidite_globale", "direction": -1, "intensity": "moderate", "horizon": "immediate"}, {"driver": "spreads_credit", "via_arc": "cyber_fin→spreads_credit", "direction": 1, "intensity": "low", "horizon": "immediate"}], "conditions": [], "conflict_note": "Payment system disruption most systemic; SWIFT alternatives reduce concentration risk"}'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities_banks": "bearish"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();

INSERT INTO event_taxonomy (cat_id, subtype_id, category, label, description, examples, detection_keywords, authority_floor, typical_geography, drivers_json, asset_bias_json) VALUES
  ('CAT-10', 'demographic_structural_shift', 'TECHNOLOGY_STRUCTURAL', 'Demographic Structural Shift',
   'Major demographic change announcement with long-term economic implications',
   '["Japan population decline 2023 official", "China end of one-child policy 2015"]'::jsonb, '["demographic shift", "aging population", "birth rate decline", "population decline", "vieillissement démographique"]'::jsonb,
   0.65, '{JP,CN,EU,US}'::text[],
   '{"primary": [{"driver": "croissance_pib", "direction": -1, "intensity_initial": "low", "coefficient_initial": 0.3, "horizon": "6m+"}], "auto_propagate": [{"driver": "dette_publique", "via_arc": "aging→dette_publique", "direction": 1, "intensity": "low", "horizon": "6m+"}, {"driver": "investissement", "via_arc": "aging→investissement", "direction": -1, "intensity": "low", "horizon": "6m+"}], "conditions": [], "conflict_note": "Ultra-long horizon (decades); markets price via yield curve shape"}'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_healthcare": "bullish", "equities_real_estate": "mixed"}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  label = EXCLUDED.label,
  description = EXCLUDED.description,
  drivers_json = EXCLUDED.drivers_json,
  asset_bias_json = EXCLUDED.asset_bias_json,
  updated_at = NOW();


-- ---------------------------------------------------------------------------
-- 3. DROP & RECREATE event_driver_lookup with full data
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS event_driver_lookup CASCADE;

CREATE TABLE event_driver_lookup (
  cat_id                  VARCHAR(8)   NOT NULL,
  subtype_id              TEXT         NOT NULL,
  primary_drivers         JSONB        NOT NULL DEFAULT '[]',
  secondary_drivers       JSONB        NOT NULL DEFAULT '[]',
  asset_bias_fast         JSONB        NOT NULL DEFAULT '{}',
  confidence_floor        TEXT         NOT NULL CHECK (confidence_floor IN ('high','medium','low')),
  authority_floor         NUMERIC(3,2) NOT NULL,
  horizon_primary         TEXT         NOT NULL,
  horizon_secondary       TEXT         NOT NULL DEFAULT '1-6m',
  typical_geography       TEXT[]       NOT NULL DEFAULT '{}',
  conflict_note           TEXT,
  created_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (cat_id, subtype_id),
  FOREIGN KEY (cat_id, subtype_id) REFERENCES event_taxonomy(cat_id, subtype_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_lookup_cat ON event_driver_lookup(cat_id);

COMMENT ON TABLE event_driver_lookup IS 'Lookup table plate optimisée pour le moteur C4 — mapping event_type → drivers primaires/secondaires + asset bias.';


INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'rate_decision_hike',
   '[{"driver": "taux_directeurs", "dir": 1, "intensity": 0.9}]'::jsonb, '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.9, "delay": "1-4w"}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "spreads_credit", "dir": 1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "usd_strength", "dir": 1, "intensity": 0.603, "delay": "immediate"}, {"driver": "anticipations_inflation", "dir": -1, "intensity": 0.603, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,CN,GLOBAL}'::text[], 'If QT already in progress, intensity_credit may be amplified')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'rate_decision_cut',
   '[{"driver": "taux_directeurs", "dir": -1, "intensity": 0.9}]'::jsonb, '[{"driver": "conditions_credit", "dir": 1, "intensity": 0.9, "delay": "1-4w"}, {"driver": "liquidite_globale", "dir": 1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "spreads_credit", "dir": -1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "usd_strength", "dir": -1, "intensity": 0.603, "delay": "immediate"}, {"driver": "croissance_pib", "dir": 1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,CN,GLOBAL}'::text[], 'If cutting into inflation, gold may diverge bullish')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'rate_decision_hold',
   '[]'::jsonb, '[{"driver": "anticipations_inflation", "dir": 0, "intensity": 0.24, "delay": "1-4w"}, {"driver": "sentiment_marche", "dir": 0, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_growth": "neutral"}'::jsonb,
   'low', 0.7,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,CN}'::text[], 'Pure hold has minimal impact; dominant signal is the statement tone')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'forward_guidance_hawkish',
   '[{"driver": "anticipations_inflation", "dir": -1, "intensity": 0.6}, {"driver": "taux_directeurs", "dir": 1, "intensity": 0.4}]'::jsonb, '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.16, "delay": "1-4w"}, {"driver": "spreads_credit", "dir": 1, "intensity": 0.16, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{US,EZ,UK,JP}'::text[], 'Signal strength depends on market positioning; surprise factor amplifies')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'forward_guidance_dovish',
   '[{"driver": "anticipations_inflation", "dir": 1, "intensity": 0.3}, {"driver": "taux_directeurs", "dir": -1, "intensity": 0.4}]'::jsonb, '[{"driver": "conditions_credit", "dir": 1, "intensity": 0.16, "delay": "1-4w"}, {"driver": "croissance_pib", "dir": 1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "usd_strength", "dir": -1, "intensity": 0.16, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{US,EZ,UK,JP}'::text[], 'If dovish pivot occurs amid high inflation, equities may rally but bonds less')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'qe_announcement',
   '[{"driver": "liquidite_globale", "dir": 1, "intensity": 0.9}, {"driver": "taux_directeurs", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "spreads_souverains", "dir": -1, "intensity": 0.9, "delay": "1-4w"}, {"driver": "conditions_credit", "dir": 1, "intensity": 0.9, "delay": "1-4w"}, {"driver": "spreads_credit", "dir": -1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "usd_strength", "dir": -1, "intensity": 0.603, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,EZ,UK,JP}'::text[], 'Diminishing returns on successive QE rounds; currency wars risk in multi-CB context')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'qt_announcement',
   '[{"driver": "liquidite_globale", "dir": -1, "intensity": 0.85}]'::jsonb, '[{"driver": "spreads_souverains", "dir": 1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "conditions_credit", "dir": -1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "liquidite_bancaire", "dir": -1, "intensity": 0.57, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb,
   'high', 0.85,
   '1-4w', '1-6m',
   '{US,EZ,UK}'::text[], 'Pace matters: $60bn vs $95bn/month has very different transmission speed')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'tapering',
   '[{"driver": "liquidite_globale", "dir": -1, "intensity": 0.55}]'::jsonb, '[{"driver": "spreads_souverains", "dir": 1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "taux_directeurs", "dir": 1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "neutral", "gold": "bearish", "equities_growth": "neutral"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{US,EZ}'::text[], 'Taper tantrum risk if unexpected; well-telegraphed tapers have limited impact')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'emergency_action_easing',
   '[{"driver": "liquidite_globale", "dir": 1, "intensity": 0.95}, {"driver": "taux_directeurs", "dir": -1, "intensity": 0.85}]'::jsonb, '[{"driver": "sentiment_marche", "dir": 1, "intensity": 0.6, "delay": "immediate"}, {"driver": "conditions_credit", "dir": 1, "intensity": 0.95, "delay": "immediate"}, {"driver": "spreads_credit", "dir": -1, "intensity": 0.95, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish_short_term"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,EM}'::text[], 'Emergency actions signal CB sees a crisis; may paradoxically increase fear short-term')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-01', 'emergency_action_tightening',
   '[{"driver": "taux_directeurs", "dir": 1, "intensity": 0.85}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "spreads_souverains", "dir": -1, "intensity": 0.402, "delay": "immediate"}, {"driver": "conditions_credit", "dir": -1, "intensity": 0.85, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{EM,UK,TR}'::text[], 'May signal currency stress; sovereign spread reaction depends on credibility')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'inflation_cpi_above',
   '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.9}, {"driver": "anticipations_inflation", "dir": 1, "intensity": 0.7}]'::jsonb, '[{"driver": "taux_directeurs", "dir": 1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "spreads_souverains", "dir": 1, "intensity": 0.469, "delay": "immediate"}, {"driver": "conditions_credit", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "mixed", "equities_growth": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,CN}'::text[], 'If driven by energy alone, core inflation may diverge; central bank response varies')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'inflation_cpi_below',
   '[{"driver": "inflation_headline", "dir": -1, "intensity": 0.85}, {"driver": "anticipations_inflation", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "taux_directeurs", "dir": -1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "spreads_souverains", "dir": -1, "intensity": 0.26, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,CN}'::text[], 'Deflation risk context changes asset reaction: equities may sell if deflationary spiral feared')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'inflation_cpi_inline',
   '[]'::jsonb, '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_growth": "neutral"}'::jsonb,
   'low', 0.7,
   'immediate', '1-6m',
   '{US,EZ,UK}'::text[], 'Minimal price action; markets move on core vs headline divergence')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'gdp_above',
   '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.9}]'::jsonb, '[{"driver": "emploi_chomage", "dir": -1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "investissement", "dir": 1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "consommation", "dir": 1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "taux_directeurs", "dir": 1, "intensity": 0.36, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_cyclical": "bullish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,CN}'::text[], 'Strong GDP raises rate expectations; may be net negative for equities in inflation context')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'gdp_below',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.9}]'::jsonb, '[{"driver": "emploi_chomage", "dir": 1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "investissement", "dir": -1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "taux_directeurs", "dir": -1, "intensity": 0.36, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_cyclical": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{US,EZ,UK,JP,CN}'::text[], 'Recession + high inflation = stagflation; bonds may also sell')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'gdp_revision_up',
   '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.4}]'::jsonb, '[]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_cyclical": "neutral"}'::jsonb,
   'low', 0.7,
   'immediate', '1-6m',
   '{US,EZ,UK}'::text[], 'Revisions rarely move markets unless magnitude is large')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'gdp_revision_down',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.4}]'::jsonb, '[]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_cyclical": "neutral"}'::jsonb,
   'low', 0.7,
   'immediate', '1-6m',
   '{US,EZ,UK}'::text[], 'Downward revisions confirming recession fears more impactful')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'nfp_above',
   '[{"driver": "emploi_chomage", "dir": -1, "intensity": 0.85}, {"driver": "consommation", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "taux_directeurs", "dir": 1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "inflation_headline", "dir": 1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_growth": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US}'::text[], 'Strong jobs in soft-landing scenario bullish equities; in inflation scenario bearish')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'nfp_below',
   '[{"driver": "emploi_chomage", "dir": 1, "intensity": 0.85}, {"driver": "consommation", "dir": -1, "intensity": 0.5}]'::jsonb, '[{"driver": "taux_directeurs", "dir": -1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.2, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_growth": "bullish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US}'::text[], 'Weak jobs + high inflation = stagflation risk')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'unemployment_rise',
   '[{"driver": "emploi_chomage", "dir": 1, "intensity": 0.75}, {"driver": "consommation", "dir": -1, "intensity": 0.55}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.503, "delay": "1-6m"}, {"driver": "taux_directeurs", "dir": -1, "intensity": 0.3, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_cyclical": "bearish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{US,EZ,UK}'::text[], 'Sahm Rule crossing 0.5% signals recession with high historical accuracy')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'unemployment_fall',
   '[{"driver": "emploi_chomage", "dir": -1, "intensity": 0.7}, {"driver": "consommation", "dir": 1, "intensity": 0.55}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.22, "delay": "1-6m"}, {"driver": "taux_directeurs", "dir": 1, "intensity": 0.28, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "bearish", "equities_cyclical": "bullish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{US,EZ,UK}'::text[], 'Tight labor market signals wage pressure → inflation risk')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'pmi_expansion',
   '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.65}, {"driver": "investissement", "dir": 1, "intensity": 0.55}]'::jsonb, '[{"driver": "sentiment_marche", "dir": 1, "intensity": 0.24, "delay": "immediate"}, {"driver": "emploi_chomage", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_cyclical": "bullish"}'::jsonb,
   'low', 0.7,
   '1-4w', '1-6m',
   '{US,EZ,UK,JP,CN,GLOBAL}'::text[], 'Leading indicator; actual GDP print may diverge')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'pmi_contraction',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.65}, {"driver": "investissement", "dir": -1, "intensity": 0.55}]'::jsonb, '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.402, "delay": "immediate"}, {"driver": "emploi_chomage", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_cyclical": "bearish"}'::jsonb,
   'low', 0.7,
   '1-4w', '1-6m',
   '{US,EZ,UK,JP,CN,GLOBAL}'::text[], 'Manufacturing vs Services divergence is key; services PMI more predictive in modern economy')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'trade_balance_deficit_widen',
   '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "usd_strength", "dir": -1, "intensity": 0.26, "delay": "1-4w"}, {"driver": "dette_publique", "dir": 1, "intensity": 0.26, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bearish", "gold": "neutral", "equities_growth": "neutral"}'::jsonb,
   'low', 0.7,
   'immediate', '1-6m',
   '{US,UK,EZ}'::text[], 'Trade deficit can be positive (strong domestic demand) or negative (structural weakness)')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'consumer_confidence_rise',
   '[{"driver": "consommation", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "sentiment_marche", "dir": 1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_consumer": "bullish"}'::jsonb,
   'low', 0.65,
   '1-4w', '1-6m',
   '{US,EZ,UK}'::text[], 'Soft data; actual retail sales print is more actionable')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'consumer_confidence_fall',
   '[{"driver": "consommation", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_consumer": "bearish"}'::jsonb,
   'low', 0.65,
   '1-4w', '1-6m',
   '{US,EZ,UK}'::text[], 'University of Michigan vs Conference Board have different leading properties')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'retail_sales_above',
   '[{"driver": "consommation", "dir": 1, "intensity": 0.7}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.28, "delay": "1-4w"}, {"driver": "croissance_pib", "dir": 1, "intensity": 0.469, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_consumer": "bullish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{US,UK,EZ}'::text[], 'Control group retail sales (ex-auto, gas, food) most predictive for GDP')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-02', 'retail_sales_below',
   '[{"driver": "consommation", "dir": -1, "intensity": 0.7}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.469, "delay": "1-4w"}, {"driver": "taux_directeurs", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bullish", "equities_consumer": "bearish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{US,UK,EZ}'::text[], 'One-month miss often weather/seasonal; trend over 3m more meaningful')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'armed_conflict_start',
   '[{"driver": "risque_geopolitique", "dir": 1, "intensity": 0.95}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.85}]'::jsonb, '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.95, "delay": "immediate"}, {"driver": "prix_metaux", "dir": 1, "intensity": 0.636, "delay": "immediate"}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.636, "delay": "immediate"}, {"driver": "usd_strength", "dir": 1, "intensity": 0.95, "delay": "immediate"}, {"driver": "spreads_souverains", "dir": 1, "intensity": 0.95, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities": "bearish", "energy": "bullish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{GLOBAL,EU,ME,EE}'::text[], 'UST safe haven bid competes with inflation/fiscal fear; depends on US involvement')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'armed_conflict_escalation',
   '[{"driver": "risque_geopolitique", "dir": 1, "intensity": 0.75}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.503, "delay": "immediate"}, {"driver": "usd_strength", "dir": 1, "intensity": 0.503, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{GLOBAL,EU,ME}'::text[], 'Escalation effects diminish with market fatigue; first event most impactful')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'armed_conflict_ceasefire',
   '[{"driver": "risque_geopolitique", "dir": -1, "intensity": 0.7}, {"driver": "sentiment_marche", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "prix_petrole", "dir": -1, "intensity": 0.469, "delay": "immediate"}, {"driver": "usd_strength", "dir": -1, "intensity": 0.28, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bearish", "gold": "bearish", "equities": "bullish", "energy": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{GLOBAL,EU,ME}'::text[], 'Credibility of ceasefire key; fragile truces have limited lasting market impact')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'sanctions_announcement',
   '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.7}, {"driver": "prix_petrole", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "usd_strength", "dir": 1, "intensity": 0.402, "delay": "immediate"}, {"driver": "spreads_souverains", "dir": 1, "intensity": 0.6, "delay": "immediate"}, {"driver": "risque_geopolitique", "dir": 1, "intensity": 0.402, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities_target_country": "bearish"}'::jsonb,
   'high', 0.85,
   '1-4w', '1-6m',
   '{GLOBAL,RU,IR,CN}'::text[], 'Secondary sanctions and implementation speed determine market impact magnitude')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'sanctions_lifted',
   '[{"driver": "balance_commerciale", "dir": 1, "intensity": 0.65}, {"driver": "prix_petrole", "dir": -1, "intensity": 0.5}]'::jsonb, '[{"driver": "risque_geopolitique", "dir": -1, "intensity": 0.402, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bearish", "gold": "bearish", "energy": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{GLOBAL}'::text[], 'Oil supply addition from sanctions lifting depends on target country capacity')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'diplomatic_crisis',
   '[{"driver": "risque_geopolitique", "dir": 1, "intensity": 0.4}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.35}]'::jsonb, '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.16, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities": "slightly_bearish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{GLOBAL,US,CN,EU,RU}'::text[], 'Diplomatic crises rarely move markets substantially unless escalation risk is high')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'regime_change_unstable',
   '[{"driver": "risque_geopolitique", "dir": 1, "intensity": 0.8}, {"driver": "spreads_souverains", "dir": 1, "intensity": 0.85}]'::jsonb, '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.536, "delay": "immediate"}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.32, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign_em": "bearish", "usd": "bullish", "gold": "bullish", "equities_local": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{EM,ME,AF,LATAM}'::text[], 'EM contagion depends on country size and financial linkages')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'regime_change_stable',
   '[{"driver": "risque_geopolitique", "dir": -1, "intensity": 0.35}, {"driver": "spreads_souverains", "dir": -1, "intensity": 0.55}]'::jsonb, '[{"driver": "investissement", "dir": 1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "neutral", "gold": "neutral", "equities_local": "bullish"}'::jsonb,
   'low', 0.7,
   'immediate', '1-6m',
   '{EM,LATAM,AF}'::text[], 'Market reaction depends on pre-existing risk premium compression')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-03', 'major_terrorism',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.8}, {"driver": "risque_geopolitique", "dir": 1, "intensity": 0.65}]'::jsonb, '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.26, "delay": "immediate"}, {"driver": "usd_strength", "dir": 1, "intensity": 0.436, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{GLOBAL,US,EU,ME}'::text[], 'Recovery typically fast (days); 9/11 exception due to systemic disruption scale')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'opec_cut',
   '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.9}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.603, "delay": "1-4w"}, {"driver": "anticipations_inflation", "dir": 1, "intensity": 0.402, "delay": "1-4w"}, {"driver": "taux_directeurs", "dir": 1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "balance_commerciale", "dir": -1, "intensity": 0.36, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities_energy": "bullish", "equities_broad": "bearish"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{GLOBAL,ME}'::text[], 'Compliance rate and global demand outlook modulate magnitude of oil price move')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'opec_increase',
   '[{"driver": "prix_petrole", "dir": -1, "intensity": 0.75}]'::jsonb, '[{"driver": "inflation_headline", "dir": -1, "intensity": 0.503, "delay": "1-4w"}, {"driver": "anticipations_inflation", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bearish", "equities_energy": "bearish", "equities_consumer": "bullish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{GLOBAL,ME}'::text[], 'Demand destruction context may limit price relief effect')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'oil_supply_disruption',
   '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.9}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.9, "delay": "1-4w"}, {"driver": "prix_metaux", "dir": 1, "intensity": 0.36, "delay": "1-4w"}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.402, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities_energy": "bullish", "equities_airline": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{GLOBAL,ME,AF}'::text[], 'SPR releases can offset short-term; duration depends on reserve buffer vs outage')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'oil_demand_revision_up',
   '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.65}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.26, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_energy": "bullish"}'::jsonb,
   'medium', 0.75,
   '1-4w', '1-6m',
   '{GLOBAL,CN}'::text[], 'Agency revisions are lagging; market often already priced move')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'oil_demand_revision_down',
   '[{"driver": "prix_petrole", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "inflation_headline", "dir": -1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bearish", "gold": "bearish", "equities_energy": "bearish"}'::jsonb,
   'medium', 0.75,
   '1-4w', '1-6m',
   '{GLOBAL}'::text[], 'Long-term EV transition demand destruction = structural not cyclical')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'gas_supply_disruption',
   '[{"driver": "prix_gaz", "dir": 1, "intensity": 0.9}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.9, "delay": "1-4w"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.603, "delay": "1-6m"}, {"driver": "anticipations_inflation", "dir": 1, "intensity": 0.402, "delay": "1-4w"}, {"driver": "taux_directeurs", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "eur": "bearish", "gold": "bullish", "equities_europe": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{EZ,EU,UK}'::text[], 'European economy particularly sensitive; industrial curtailment = GDP drag')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'gas_storage_alert',
   '[{"driver": "prix_gaz", "dir": 1, "intensity": 0.7}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.469, "delay": "1-4w"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.28, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "eur": "bearish", "gold": "neutral", "equities_europe": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{EZ,UK,EU}'::text[], 'EU 80% refill target is market anchor')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'agricultural_drought',
   '[{"driver": "prix_agricoles", "dir": 1, "intensity": 0.85}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "anticipations_inflation", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_agri": "bullish", "equities_food": "bearish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{US,BR,AU,UA,IN}'::text[], 'Food inflation particularly impactful in EM where food weight in CPI is higher')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'agricultural_surplus',
   '[{"driver": "prix_agricoles", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "inflation_headline", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_agri": "bearish"}'::jsonb,
   'low', 0.65,
   '1-4w', '1-6m',
   '{US,BR,AR}'::text[], 'Disinflation from food prices modest in DM where food weight is low')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'metals_shortage',
   '[{"driver": "prix_metaux", "dir": 1, "intensity": 0.85}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.34, "delay": "1-6m"}, {"driver": "investissement", "dir": -1, "intensity": 0.57, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bullish", "equities_mining": "bullish", "equities_ev": "bearish"}'::jsonb,
   'medium', 0.75,
   'immediate', '1-6m',
   '{GLOBAL,CN,DRC}'::text[], 'Critical minerals shortage increasingly geopolitical — China export controls risk')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-04', 'metals_surplus',
   '[{"driver": "prix_metaux", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "investissement", "dir": 1, "intensity": 0.26, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_mining": "bearish"}'::jsonb,
   'low', 0.65,
   '1-4w', '1-6m',
   '{GLOBAL,CN}'::text[], 'Chinese demand signal is primary driver of metals surplus/deficit cycle')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'tariff_hike',
   '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.65}, {"driver": "inflation_headline", "dir": 1, "intensity": 0.55}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.436, "delay": "1-6m"}, {"driver": "conditions_credit", "dir": -1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "usd_strength", "dir": 1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities_exporter": "bearish", "equities_domestic": "mixed"}'::jsonb,
   'high', 0.85,
   '1-4w', '1-6m',
   '{US,CN,EU}'::text[], 'Retaliation risk amplifies impact; affected sectors (autos, agri, tech) diverge')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'tariff_cut',
   '[{"driver": "balance_commerciale", "dir": 1, "intensity": 0.6}, {"driver": "inflation_headline", "dir": -1, "intensity": 0.35}]'::jsonb, '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bearish", "gold": "bearish", "equities_exporter": "bullish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{US,CN,UK,EU}'::text[], 'Impact depends on magnitude and strategic significance of goods targeted')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'tariff_threat',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.4}]'::jsonb, '[{"driver": "usd_strength", "dir": 1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "slightly_bullish", "gold": "neutral", "equities": "slightly_bearish"}'::jsonb,
   'low', 0.7,
   'immediate', '1-6m',
   '{US,CN,EU}'::text[], 'Markets increasingly desensitized to repeated threats')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'trade_agreement_signed',
   '[{"driver": "balance_commerciale", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "investissement", "dir": 1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_exporter": "bullish"}'::jsonb,
   'medium', 0.8,
   '1-6m', '1-6m',
   '{GLOBAL,US,EU,ASIA}'::text[], 'Markets often price in deal before signing; announcement effect may be limited')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'trade_agreement_collapsed',
   '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.436, "delay": "1-6m"}, {"driver": "investissement", "dir": -1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "risque_geopolitique", "dir": 1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities_exporter": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{US,EU,UK}'::text[], 'Uncertainty premium added; renegotiation risk vs clean break')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'export_restriction_tech',
   '[{"driver": "risque_geopolitique", "dir": 1, "intensity": 0.65}, {"driver": "balance_commerciale", "dir": -1, "intensity": 0.35}]'::jsonb, '[{"driver": "investissement", "dir": -1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "6m+"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_semiconductor_cn": "bearish", "equities_semiconductor_us": "mixed"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,CN,NL,JP}'::text[], 'Long-term supply chain restructuring impact dominates short-term')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'export_restriction_commodity',
   '[{"driver": "prix_agricoles", "dir": 1, "intensity": 0.7}, {"driver": "balance_commerciale", "dir": -1, "intensity": 0.4}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.469, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "neutral", "gold": "neutral", "equities_agri": "bullish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{IN,RU,CN,AU}'::text[], 'Particularly inflationary for food-importing EM countries')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'currency_manipulation_accused',
   '[{"driver": "usd_strength", "dir": 1, "intensity": 0.4}, {"driver": "risque_geopolitique", "dir": 1, "intensity": 0.35}]'::jsonb, '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities_cn": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{CN,VN,KR}'::text[], 'Accusation rarely leads to formal action; political signaling dominates')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'trade_war_escalation',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.8}, {"driver": "balance_commerciale", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "investissement", "dir": -1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "conditions_credit", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "mixed", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,CN,EU}'::text[], 'Global supply chain disruption adds persistence to impact')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-05', 'trade_war_deescalation',
   '[{"driver": "sentiment_marche", "dir": 1, "intensity": 0.7}, {"driver": "balance_commerciale", "dir": 1, "intensity": 0.4}]'::jsonb, '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "investissement", "dir": 1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bearish", "gold": "bearish", "equities": "bullish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{US,CN,EU}'::text[], 'Partial deals may boost sentiment without fundamentally resolving tensions')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'fiscal_stimulus_major',
   '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.85}, {"driver": "dette_publique", "dir": 1, "intensity": 0.65}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.57, "delay": "1-6m"}, {"driver": "taux_directeurs", "dir": 1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "spreads_souverains", "dir": 1, "intensity": 0.436, "delay": "1-4w"}, {"driver": "emploi_chomage", "dir": -1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "mixed", "gold": "bullish", "equities_cyclical": "bullish"}'::jsonb,
   'high', 0.85,
   '1-4w', '1-6m',
   '{US,EU,CN}'::text[], 'Multiplier depends on output gap; stimulus in full employment = inflation not growth')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'fiscal_stimulus_minor',
   '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.45}]'::jsonb, '[{"driver": "dette_publique", "dir": 1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_targeted": "bullish"}'::jsonb,
   'medium', 0.75,
   '1-4w', '1-6m',
   '{US,EU,UK}'::text[], 'Narrow impact; sector-specific rather than macro')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'fiscal_austerity',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.7}, {"driver": "dette_publique", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "emploi_chomage", "dir": 1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "consommation", "dir": -1, "intensity": 0.402, "delay": "1-4w"}, {"driver": "spreads_souverains", "dir": -1, "intensity": 0.402, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "neutral", "gold": "neutral", "equities": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{EZ,UK,EM}'::text[], 'Expansionary austerity theory empirically weak; typically contractionary short-term')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'tax_hike_corporate',
   '[{"driver": "investissement", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.26, "delay": "1-6m"}, {"driver": "dette_publique", "dir": -1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_corporate": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-6m', '1-6m',
   '{US,UK,EZ}'::text[], 'Market impact front-runs effective date; actual vs proposed rate matters')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'tax_cut_corporate',
   '[{"driver": "investissement", "dir": 1, "intensity": 0.7}]'::jsonb, '[{"driver": "dette_publique", "dir": 1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "spreads_souverains", "dir": 1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "croissance_pib", "dir": 1, "intensity": 0.28, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bearish", "equities_corporate": "bullish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{US,UK,IE}'::text[], 'Buyback activity surge often first market signal of corporate tax cuts')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'tax_hike_consumer',
   '[{"driver": "consommation", "dir": -1, "intensity": 0.7}, {"driver": "inflation_headline", "dir": 1, "intensity": 0.35}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.469, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_consumer": "bearish"}'::jsonb,
   'medium', 0.75,
   '1-4w', '1-6m',
   '{JP,UK,EZ,FR}'::text[], 'Japan VAT hikes historically triggered mini-recessions')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'financial_regulation_tighten',
   '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.6}, {"driver": "liquidite_bancaire", "dir": -1, "intensity": 0.4}]'::jsonb, '[{"driver": "spreads_credit", "dir": 1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "investissement", "dir": -1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_banks": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-6m', '1-6m',
   '{US,EU,GLOBAL}'::text[], 'Long implementation timelines; financial stocks react to announcement')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'financial_regulation_ease',
   '[{"driver": "conditions_credit", "dir": 1, "intensity": 0.55}, {"driver": "liquidite_bancaire", "dir": 1, "intensity": 0.35}]'::jsonb, '[{"driver": "spreads_credit", "dir": -1, "intensity": 0.22, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_banks": "bullish"}'::jsonb,
   'medium', 0.75,
   '1-6m', '1-6m',
   '{US,EU}'::text[], 'Moral hazard risk; short-term positive for banks, long-term systemic risk increase')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'sovereign_downgrade',
   '[{"driver": "spreads_souverains", "dir": 1, "intensity": 0.85}, {"driver": "dette_publique", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.402, "delay": "immediate"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bearish_if_us", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{US,EZ,EM}'::text[], 'US downgrade paradoxically can trigger UST rally (safe haven demand)')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'sovereign_upgrade',
   '[{"driver": "spreads_souverains", "dir": -1, "intensity": 0.7}]'::jsonb, '[{"driver": "conditions_credit", "dir": 1, "intensity": 0.28, "delay": "1-4w"}, {"driver": "investissement", "dir": 1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "neutral", "gold": "neutral", "equities_local": "bullish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{EZ,EM}'::text[], 'Often partially priced in; surprise upgrades have more impact')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-06', 'debt_ceiling_crisis',
   '[{"driver": "spreads_souverains", "dir": 1, "intensity": 0.85}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.8}]'::jsonb, '[{"driver": "liquidite_globale", "dir": -1, "intensity": 0.402, "delay": "immediate"}, {"driver": "usd_strength", "dir": -1, "intensity": 0.402, "delay": "immediate"}, {"driver": "dette_publique", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish_t_bills", "usd": "bearish", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{US}'::text[], 'T-bills near X-date trade at big discount; resolution produces sharp V-shaped reversal')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'bank_failure',
   '[{"driver": "liquidite_bancaire", "dir": -1, "intensity": 0.9}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.85}]'::jsonb, '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.9, "delay": "immediate"}, {"driver": "spreads_credit", "dir": 1, "intensity": 0.6, "delay": "immediate"}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.6, "delay": "immediate"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities_banks": "bearish", "equities_broad": "bearish"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{US,EU}'::text[], 'Contagion speed amplified by social media bank run dynamics (SVB 2023)')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'bank_rescue',
   '[{"driver": "sentiment_marche", "dir": 1, "intensity": 0.65}, {"driver": "liquidite_bancaire", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "conditions_credit", "dir": 1, "intensity": 0.402, "delay": "immediate"}, {"driver": "spreads_credit", "dir": -1, "intensity": 0.402, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bearish", "equities_banks": "mixed"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{US,EU,UK}'::text[], 'Rescue credibility depends on firepower; equity shareholders typically wiped out')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'credit_event_sovereign',
   '[{"driver": "spreads_souverains", "dir": 1, "intensity": 0.95}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.85}]'::jsonb, '[{"driver": "liquidite_globale", "dir": -1, "intensity": 0.6, "delay": "immediate"}, {"driver": "spreads_credit", "dir": 1, "intensity": 0.6, "delay": "immediate"}, {"driver": "conditions_credit", "dir": -1, "intensity": 0.6, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'high', 0.95,
   'immediate', '1-6m',
   '{EM,EZ}'::text[], 'Orderly restructuring vs disorderly default has very different contagion dynamics')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'credit_event_corporate',
   '[{"driver": "spreads_credit", "dir": 1, "intensity": 0.85}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.57, "delay": "1-4w"}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "neutral", "equities": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,CN,EU}'::text[], 'Sector contagion model matters: real estate vs crypto vs finance')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'market_crash',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.95}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.85}]'::jsonb, '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.6, "delay": "immediate"}, {"driver": "spreads_credit", "dir": 1, "intensity": 0.6, "delay": "immediate"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{GLOBAL,US}'::text[], 'Circuit breakers may pause market; Fed put probability high in severe crashes')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'flash_crash',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.6}]'::jsonb, '[]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities": "bearish_momentary"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{GLOBAL,US}'::text[], 'Flash crashes typically fully reverse; persistent fear signal if partial recovery only')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'contagion_spread_widening',
   '[{"driver": "spreads_souverains", "dir": 1, "intensity": 0.85}, {"driver": "spreads_credit", "dir": 1, "intensity": 0.85}]'::jsonb, '[{"driver": "conditions_credit", "dir": -1, "intensity": 0.85, "delay": "1-4w"}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.6, "delay": "immediate"}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.6, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign_core": "bullish", "bonds_sovereign_periph": "bearish", "usd": "bullish", "gold": "bullish", "equities": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{EZ,EM,GLOBAL}'::text[], 'Draghi ''whatever it takes'' showed CB can arrest contagion')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'systemic_risk_warning',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.4}]'::jsonb, '[{"driver": "liquidite_globale", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities": "slightly_bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{GLOBAL}'::text[], 'Official warnings often lagging; BIS early warnings more prescient')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-07', 'liquidity_crisis',
   '[{"driver": "liquidite_globale", "dir": -1, "intensity": 0.9}, {"driver": "liquidite_bancaire", "dir": -1, "intensity": 0.85}]'::jsonb, '[{"driver": "spreads_credit", "dir": 1, "intensity": 0.85, "delay": "immediate"}, {"driver": "conditions_credit", "dir": -1, "intensity": 0.9, "delay": "immediate"}, {"driver": "usd_strength", "dir": 1, "intensity": 0.6, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "mixed", "equities": "bearish"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{US,UK,GLOBAL}'::text[], 'Fed/ECB/BoE backstop credibility determines duration; swap lines resolve dollar shortage')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-08', 'port_blockage',
   '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.6}, {"driver": "inflation_headline", "dir": 1, "intensity": 0.35}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "prix_metaux", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_shipping": "bullish", "equities_retail": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{GLOBAL,EZ,CN}'::text[], 'Suez blockage added ~$200bn/week in supply chain delays')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-08', 'shipping_disruption',
   '[{"driver": "balance_commerciale", "dir": -1, "intensity": 0.65}, {"driver": "inflation_headline", "dir": 1, "intensity": 0.5}]'::jsonb, '[{"driver": "prix_agricoles", "dir": 1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "prix_metaux", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "bullish", "gold": "neutral", "equities_shipping": "bullish", "equities_consumer": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{GLOBAL,ME}'::text[], 'Drewry composite freight index is primary real-time indicator')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-08', 'factory_shutdown_major',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.45}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "balance_commerciale", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_sector": "bearish"}'::jsonb,
   'medium', 0.75,
   '1-4w', '1-6m',
   '{CN,JP,US,TW}'::text[], 'TSMC concentration risk = potential single-point failure for global semiconductor supply')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-08', 'semiconductor_shortage',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.65}, {"driver": "inflation_headline", "dir": 1, "intensity": 0.5}]'::jsonb, '[{"driver": "investissement", "dir": -1, "intensity": 0.402, "delay": "1-6m"}, {"driver": "balance_commerciale", "dir": -1, "intensity": 0.402, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bearish", "usd": "neutral", "gold": "neutral", "equities_auto": "bearish", "equities_semiconductor": "bullish"}'::jsonb,
   'medium', 0.8,
   '1-6m', '1-6m',
   '{GLOBAL,TW,KR,US}'::text[], 'Lead times 12-18m in automotive; capex super-cycle creates future oversupply risk')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-08', 'critical_material_shortage',
   '[{"driver": "prix_metaux", "dir": 1, "intensity": 0.7}, {"driver": "investissement", "dir": -1, "intensity": 0.55}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.22, "delay": "6m+"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "bullish", "equities_mining": "bullish", "equities_ev_tech": "bearish"}'::jsonb,
   'medium', 0.8,
   'immediate', '1-6m',
   '{CN,DRC,GLOBAL}'::text[], 'Energy transition creates structural demand for Li, Co, Ni, rare earths through 2040+')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-08', 'logistics_bottleneck',
   '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.4}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_logistics": "bullish"}'::jsonb,
   'low', 0.7,
   '1-4w', '1-6m',
   '{US,UK,EU}'::text[], 'PMI supply delivery times is best aggregate proxy')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-08', 'pandemic_supply_shock',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.9}, {"driver": "liquidite_globale", "dir": -1, "intensity": 0.8}]'::jsonb, '[{"driver": "emploi_chomage", "dir": 1, "intensity": 0.6, "delay": "immediate"}, {"driver": "consommation", "dir": -1, "intensity": 0.6, "delay": "immediate"}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.6, "delay": "immediate"}, {"driver": "inflation_headline", "dir": 1, "intensity": 0.402, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities": "bearish_initial"}'::jsonb,
   'high', 0.9,
   'immediate', '1-6m',
   '{GLOBAL,CN}'::text[], 'CB/fiscal response determines post-shock inflation trajectory')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'drought_major',
   '[{"driver": "prix_agricoles", "dir": 1, "intensity": 0.8}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.35}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.536, "delay": "1-4w"}, {"driver": "prix_gaz", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_agri": "bullish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{US,EU,AU,IN,BR}'::text[], 'Rhine low water impacted German industrial output directly in 2022')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'flood_major',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "dette_publique", "dir": 1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "prix_agricoles", "dir": 1, "intensity": 0.402, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_insurance": "bearish", "equities_reconstruction": "bullish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{GLOBAL,PK,CN,EU}'::text[], 'Reconstruction spending partially offsets GDP drag')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'hurricane_typhoon',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.55}, {"driver": "prix_petrole", "dir": 1, "intensity": 0.3}]'::jsonb, '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "dette_publique", "dir": 1, "intensity": 0.24, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_insurance": "bearish", "equities_energy": "bullish_if_gulf"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{US,JP,PH,CN}'::text[], 'Katrina hit Gulf oil infrastructure; 2022 hurricanes impacted Florida insurance market')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'earthquake_tsunami',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.65}, {"driver": "dette_publique", "dir": 1, "intensity": 0.55}]'::jsonb, '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.24, "delay": "1-4w"}, {"driver": "prix_gaz", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "mixed", "usd": "bullish", "gold": "bullish", "equities_local": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{JP,TR,TW,US}'::text[], 'Japan repatriated yen post-Fukushima → JPY strength despite disaster')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'wildfire_major',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.35}]'::jsonb, '[{"driver": "dette_publique", "dir": 1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "prix_agricoles", "dir": 1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_insurance": "bearish"}'::jsonb,
   'medium', 0.75,
   '1-4w', '1-6m',
   '{US,AU,CA,EU}'::text[], 'PG&E bankruptcy from California wildfires shows utility sector tail risk')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'climate_policy_new',
   '[{"driver": "investissement", "dir": 1, "intensity": 0.65}]'::jsonb, '[{"driver": "prix_petrole", "dir": -1, "intensity": 0.24, "delay": "6m+"}, {"driver": "prix_metaux", "dir": 1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_green": "bullish", "equities_fossil": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-6m', '1-6m',
   '{US,EU,UK,GLOBAL}'::text[], 'IRA $369bn triggered massive capex reallocation to US green manufacturing')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'carbon_tax_announced',
   '[{"driver": "inflation_headline", "dir": 1, "intensity": 0.4}, {"driver": "prix_petrole", "dir": 1, "intensity": 0.3}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "1-6m"}, {"driver": "investissement", "dir": 1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_carbon_intensive": "bearish", "equities_clean_energy": "bullish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{EU,CA,UK}'::text[], 'Carbon border adjustment (CBAM) creates new trade policy dimension')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'green_deal_regulation',
   '[{"driver": "investissement", "dir": 1, "intensity": 0.35}]'::jsonb, '[]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_esg_compliant": "bullish"}'::jsonb,
   'medium', 0.75,
   '1-6m', '1-6m',
   '{EU,US}'::text[], 'Compliance costs vs capital reallocation; long lag to economic impact')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-09', 'energy_transition_target',
   '[{"driver": "investissement", "dir": 1, "intensity": 0.6}, {"driver": "prix_metaux", "dir": 1, "intensity": 0.35}]'::jsonb, '[{"driver": "prix_petrole", "dir": -1, "intensity": 0.24, "delay": "6m+"}, {"driver": "croissance_pib", "dir": 1, "intensity": 0.24, "delay": "6m+"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_utilities": "bullish", "equities_oil_major": "bearish"}'::jsonb,
   'medium', 0.75,
   '1-6m', '1-6m',
   '{EU,US,UK,CN}'::text[], 'Target credibility depends on policy mechanism; EU has binding targets')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-10', 'ai_breakthrough_major',
   '[{"driver": "investissement", "dir": 1, "intensity": 0.8}]'::jsonb, '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.32, "delay": "6m+"}, {"driver": "emploi_chomage", "dir": 1, "intensity": 0.24, "delay": "6m+"}, {"driver": "prix_metaux", "dir": 1, "intensity": 0.402, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_tech": "bullish", "equities_semiconductor": "bullish", "equities_labor_intensive": "bearish"}'::jsonb,
   'medium', 0.8,
   '1-4w', '1-6m',
   '{US,CN,GLOBAL}'::text[], 'Productivity shock potential: general purpose technology multiplier ~5-10x direct effect')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-10', 'tech_antitrust_action',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.35}, {"driver": "investissement", "dir": -1, "intensity": 0.3}]'::jsonb, '[]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_targeted_tech": "bearish", "equities_broad_tech": "slightly_bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,EU}'::text[], 'EU DMA/DSA more impactful than US antitrust due to faster enforcement')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-10', 'tech_export_ban',
   '[{"driver": "risque_geopolitique", "dir": 1, "intensity": 0.65}, {"driver": "investissement", "dir": -1, "intensity": 0.6}]'::jsonb, '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "6m+"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_semiconductor_cn": "bearish", "equities_semiconductor_us": "mixed"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,CN}'::text[], 'NVIDIA H100/H800 controls most impactful for AI supply chain globally')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-10', 'productivity_shock_positive',
   '[{"driver": "croissance_pib", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "inflation_core", "dir": -1, "intensity": 0.24, "delay": "6m+"}, {"driver": "investissement", "dir": 1, "intensity": 0.402, "delay": "1-6m"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "bullish", "gold": "neutral", "equities_tech": "bullish", "equities_broad": "bullish"}'::jsonb,
   'low', 0.7,
   '6m+', '1-6m',
   '{US,GLOBAL}'::text[], 'Productivity shocks have long lags; market prices future earnings')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-10', 'cyber_attack_critical_infra',
   '[{"driver": "sentiment_marche", "dir": -1, "intensity": 0.6}, {"driver": "risque_geopolitique", "dir": 1, "intensity": 0.6}]'::jsonb, '[{"driver": "prix_petrole", "dir": 1, "intensity": 0.402, "delay": "immediate"}, {"driver": "croissance_pib", "dir": -1, "intensity": 0.24, "delay": "1-4w"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities_cyber_security": "bullish", "equities_targeted": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{US,UA,EU}'::text[], 'Colonial Pipeline: +30% east coast fuel prices in days')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-10', 'cyber_attack_financial',
   '[{"driver": "liquidite_bancaire", "dir": -1, "intensity": 0.6}, {"driver": "sentiment_marche", "dir": -1, "intensity": 0.65}]'::jsonb, '[{"driver": "liquidite_globale", "dir": -1, "intensity": 0.402, "delay": "immediate"}, {"driver": "spreads_credit", "dir": 1, "intensity": 0.24, "delay": "immediate"}]'::jsonb, '{"bonds_sovereign": "bullish", "usd": "bullish", "gold": "bullish", "equities_banks": "bearish"}'::jsonb,
   'high', 0.85,
   'immediate', '1-6m',
   '{GLOBAL,US}'::text[], 'Payment system disruption most systemic; SWIFT alternatives reduce concentration risk')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();

INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, secondary_drivers, asset_bias_fast, confidence_floor, authority_floor, horizon_primary, horizon_secondary, typical_geography, conflict_note) VALUES
  ('CAT-10', 'demographic_structural_shift',
   '[{"driver": "croissance_pib", "dir": -1, "intensity": 0.3}]'::jsonb, '[{"driver": "dette_publique", "dir": 1, "intensity": 0.24, "delay": "6m+"}, {"driver": "investissement", "dir": -1, "intensity": 0.24, "delay": "6m+"}]'::jsonb, '{"bonds_sovereign": "neutral", "usd": "neutral", "gold": "neutral", "equities_healthcare": "bullish", "equities_real_estate": "mixed"}'::jsonb,
   'low', 0.65,
   '6m+', '1-6m',
   '{JP,CN,EU,US}'::text[], 'Ultra-long horizon (decades); markets price via yield curve shape')
ON CONFLICT (cat_id, subtype_id) DO UPDATE SET
  primary_drivers = EXCLUDED.primary_drivers,
  secondary_drivers = EXCLUDED.secondary_drivers,
  asset_bias_fast = EXCLUDED.asset_bias_fast,
  updated_at = NOW();


-- ---------------------------------------------------------------------------
-- 4. Verification queries
-- ---------------------------------------------------------------------------
-- SELECT COUNT(*) FROM event_taxonomy; -- should be ~101
-- SELECT COUNT(*) FROM event_driver_lookup; -- should be ~101
-- SELECT cat_id, COUNT(*) FROM event_taxonomy GROUP BY cat_id ORDER BY cat_id;
-- SELECT * FROM event_driver_lookup WHERE cat_id='CAT-01' AND subtype_id='rate_decision_hike';
