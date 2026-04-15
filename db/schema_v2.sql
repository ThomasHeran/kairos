-- =============================================================================
-- Kairos — Schema v2 — Couches C2→C5 + Taxonomie + Graphe Causal
-- Migration à appliquer APRÈS schema.sql (tables countries, sources, articles, scrape_jobs)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. event_taxonomy
--    Tables de référence des 10 catégories + ~55 sous-types (taxonomy_v1.json)
--    Clé primaire composite (cat_id, subtype_id) pour intégrité référentielle.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS event_taxonomy (
  cat_id         VARCHAR(8)   NOT NULL,       -- ex: 'CAT-01'
  category       TEXT         NOT NULL,       -- ex: 'MONETARY_POLICY'
  label_fr       TEXT         NOT NULL,       -- ex: 'Politique monétaire'
  subtype_id     TEXT         NOT NULL,       -- ex: 'rate_decision_hike'
  subtype_label  TEXT         NOT NULL,       -- ex: 'Hausse de taux directeur'
  description    TEXT,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  PRIMARY KEY (cat_id, subtype_id)
);

CREATE INDEX IF NOT EXISTS idx_event_taxonomy_cat_id ON event_taxonomy(cat_id);
CREATE INDEX IF NOT EXISTS idx_event_taxonomy_category ON event_taxonomy(category);

COMMENT ON TABLE event_taxonomy IS 'Taxonomie fermée Kairos v1 — 10 catégories ~55 sous-types. Source vérité: config/taxonomy_v1.json';

-- Seed depuis taxonomy_v1.json — CAT-01 MONETARY_POLICY
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-01','MONETARY_POLICY','Politique monétaire','rate_decision_hike','Hausse de taux directeur','Relèvement du taux directeur par une banque centrale.'),
  ('CAT-01','MONETARY_POLICY','Politique monétaire','rate_decision_cut','Baisse de taux directeur','Réduction du taux directeur par une banque centrale.'),
  ('CAT-01','MONETARY_POLICY','Politique monétaire','rate_decision_hold','Maintien du taux directeur','Confirmation du statu quo sur les taux directeurs.'),
  ('CAT-01','MONETARY_POLICY','Politique monétaire','qe_launch','Lancement d''assouplissement quantitatif','Annonce ou démarrage d''un programme d''achats d''actifs.'),
  ('CAT-01','MONETARY_POLICY','Politique monétaire','qt_launch','Lancement de resserrement quantitatif','Annonce ou démarrage d''une réduction du bilan.'),
  ('CAT-01','MONETARY_POLICY','Politique monétaire','forward_guidance_dovish','Guidance accommodante','Signal explicite vers des taux plus bas ou politique plus souple.'),
  ('CAT-01','MONETARY_POLICY','Politique monétaire','forward_guidance_hawkish','Guidance restrictive','Signal explicite vers des taux plus élevés ou politique plus stricte.'),
  ('CAT-01','MONETARY_POLICY','Politique monétaire','emergency_action','Action d''urgence banque centrale','Intervention non planifiée : crise de liquidité, intervention change, etc.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-02 FISCAL_POLICY
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-02','FISCAL_POLICY','Politique budgétaire','budget_announcement','Annonce budgétaire','Présentation officielle du budget annuel ou pluriannuel.'),
  ('CAT-02','FISCAL_POLICY','Politique budgétaire','spending_increase','Hausse des dépenses publiques','Plan de stimulus, relance ou investissement public significatif.'),
  ('CAT-02','FISCAL_POLICY','Politique budgétaire','spending_cut','Réduction des dépenses publiques','Austérité, consolidation budgétaire ou coupe budgétaire majeure.'),
  ('CAT-02','FISCAL_POLICY','Politique budgétaire','tax_hike','Hausse fiscale','Augmentation d''impôts ou de taxes (revenu, société, TVA...).'),
  ('CAT-02','FISCAL_POLICY','Politique budgétaire','tax_cut','Baisse fiscale','Réduction d''impôts ou de taxes, crédit fiscal.'),
  ('CAT-02','FISCAL_POLICY','Politique budgétaire','debt_issuance','Émission de dette souveraine','Adjudication ou annonce d''emprunt d''État majeur.'),
  ('CAT-02','FISCAL_POLICY','Politique budgétaire','debt_ceiling_crisis','Crise du plafond de la dette','Risque ou négociation autour du plafond d''endettement légal.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-03 INFLATION
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-03','INFLATION','Inflation / Prix','cpi_release_above','CPI supérieur aux attentes','Publication IPC (CPI) dépassant le consensus.'),
  ('CAT-03','INFLATION','Inflation / Prix','cpi_release_below','CPI inférieur aux attentes','Publication IPC (CPI) sous le consensus.'),
  ('CAT-03','INFLATION','Inflation / Prix','cpi_release_inline','CPI conforme aux attentes','Publication IPC (CPI) dans les marges du consensus.'),
  ('CAT-03','INFLATION','Inflation / Prix','ppi_release','Publication IPP','Données d''inflation à la production (PPI/IPP).'),
  ('CAT-03','INFLATION','Inflation / Prix','pce_release','Publication PCE','Données PCE (mesure Fed de l''inflation core).'),
  ('CAT-03','INFLATION','Inflation / Prix','inflation_expectations','Anticipations d''inflation','Changement notable des breakevens ou surveys d''anticipations.'),
  ('CAT-03','INFLATION','Inflation / Prix','energy_price_shock','Choc de prix énergétiques','Mouvement brutal du pétrole/gaz répercuté sur l''IPC.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-04 GROWTH_ACTIVITY
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','gdp_release_above','PIB supérieur aux attentes','Croissance PIB battant le consensus.'),
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','gdp_release_below','PIB inférieur aux attentes','Croissance PIB décevante par rapport au consensus.'),
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','pmi_manufacturing','PMI manufacturier','Publication de l''indice PMI du secteur manufacturier.'),
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','pmi_services','PMI services','Publication de l''indice PMI du secteur des services.'),
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','employment_strong','Données emploi solides','Créations d''emplois/taux de chômage meilleures que prévu.'),
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','employment_weak','Données emploi faibles','Créations d''emplois/taux de chômage décevantes.'),
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','retail_sales','Ventes au détail','Publication des données de consommation des ménages.'),
  ('CAT-04','GROWTH_ACTIVITY','Croissance / Activité économique','recession_signal','Signal de récession','Indicateur ou annonce officielle de récession technique ou effective.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-05 FINANCIAL_STABILITY
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-05','FINANCIAL_STABILITY','Stabilité financière','bank_failure','Faillite / résolution bancaire','Effondrement ou résolution forcée d''un établissement bancaire.'),
  ('CAT-05','FINANCIAL_STABILITY','Stabilité financière','credit_crunch','Resserrement du crédit','Retrait significatif de l''offre de crédit bancaire.'),
  ('CAT-05','FINANCIAL_STABILITY','Stabilité financière','systemic_risk_warning','Alerte risque systémique','Publication de rapport ou déclaration sur un risque systémique.'),
  ('CAT-05','FINANCIAL_STABILITY','Stabilité financière','sovereign_debt_stress','Stress dette souveraine','Spreads ou CDS souverains en hausse significative.'),
  ('CAT-05','FINANCIAL_STABILITY','Stabilité financière','financial_regulation','Nouvelle réglementation financière','Adoption de Bâle, Dodd-Frank, DORA, ou autre règle prudentielle majeure.'),
  ('CAT-05','FINANCIAL_STABILITY','Stabilité financière','currency_crisis','Crise de change','Dépréciation brutale ou attaque spéculative sur une devise.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-06 GEOPOLITICAL_RISK
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','military_conflict','Conflit armé / escalade militaire','Déclenchement ou escalade d''un conflit armé à impact macro.'),
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','sanctions_imposed','Sanctions économiques imposées','Nouvelles sanctions contre un pays ou secteur.'),
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','sanctions_lifted','Levée de sanctions','Annonce de levée partielle ou totale de sanctions.'),
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','election_result','Résultat électoral majeur','Résultat d''élection avec impact sur la politique économique.'),
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','trade_war_escalation','Escalade guerre commerciale','Nouveaux tarifs, représailles douanières ou rupture d''accord.'),
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','trade_war_de_escalation','Désescalade guerre commerciale','Accord commercial, trêve tarifaire ou levée de barrières.'),
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','political_crisis','Crise politique intérieure','Instabilité gouvernementale, coup d''État, dissolution parlementaire.'),
  ('CAT-06','GEOPOLITICAL_RISK','Risque géopolitique','energy_supply_shock','Choc d''approvisionnement énergétique','Coupure ou menace sur les flux de pétrole/gaz à portée géo.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-07 CORPORATE_EARNINGS
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-07','CORPORATE_EARNINGS','Résultats d''entreprises','earnings_beat','Résultats supérieurs aux attentes','Publication de résultats EPS/CA dépassant le consensus.'),
  ('CAT-07','CORPORATE_EARNINGS','Résultats d''entreprises','earnings_miss','Résultats inférieurs aux attentes','Publication de résultats EPS/CA décevants par rapport au consensus.'),
  ('CAT-07','CORPORATE_EARNINGS','Résultats d''entreprises','guidance_upgrade','Révision à la hausse des prévisions','Relèvement de la guidance annuelle ou trimestrielle.'),
  ('CAT-07','CORPORATE_EARNINGS','Résultats d''entreprises','guidance_downgrade','Révision à la baisse des prévisions','Abaissement de la guidance annuelle ou trimestrielle.'),
  ('CAT-07','CORPORATE_EARNINGS','Résultats d''entreprises','merger_acquisition','Fusion / Acquisition','Annonce d''un M&A significatif affectant la valorisation sectorielle.'),
  ('CAT-07','CORPORATE_EARNINGS','Résultats d''entreprises','restructuring','Restructuration / Plan social','Annonce de réduction d''effectifs, cession d''actifs ou refonte stratégique.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-08 COMMODITY_MARKETS
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-08','COMMODITY_MARKETS','Marchés des matières premières','oil_price_surge','Flambée des prix du pétrole','Hausse rapide et significative du prix du Brent/WTI.'),
  ('CAT-08','COMMODITY_MARKETS','Marchés des matières premières','oil_price_drop','Effondrement des prix du pétrole','Baisse rapide et significative du prix du Brent/WTI.'),
  ('CAT-08','COMMODITY_MARKETS','Marchés des matières premières','opec_decision','Décision OPEC/OPEC+','Modification des quotas de production OPEC ou OPEC+.'),
  ('CAT-08','COMMODITY_MARKETS','Marchés des matières premières','gas_supply_disruption','Perturbation gaz naturel','Coupure, pénurie ou choc de prix sur le gaz naturel.'),
  ('CAT-08','COMMODITY_MARKETS','Marchés des matières premières','metals_price_move','Mouvement prix métaux','Variation forte sur l''or, le cuivre ou autres métaux industriels.'),
  ('CAT-08','COMMODITY_MARKETS','Marchés des matières premières','agricultural_shock','Choc agricole','Perturbation de l''offre ou des prix des matières premières agricoles.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-09 TRADE_FLOWS
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-09','TRADE_FLOWS','Flux commerciaux / Balance des paiements','trade_balance_release','Publication balance commerciale','Données officielles de balance commerciale (excédent/déficit).'),
  ('CAT-09','TRADE_FLOWS','Flux commerciaux / Balance des paiements','current_account_release','Publication balance courante','Données de balance courante (compte de transactions courantes).'),
  ('CAT-09','TRADE_FLOWS','Flux commerciaux / Balance des paiements','tariff_imposition','Imposition de droits de douane','Annonce ou entrée en vigueur de nouveaux tarifs douaniers.'),
  ('CAT-09','TRADE_FLOWS','Flux commerciaux / Balance des paiements','trade_agreement','Accord commercial','Signature ou ratification d''un accord de libre-échange.'),
  ('CAT-09','TRADE_FLOWS','Flux commerciaux / Balance des paiements','supply_chain_disruption','Rupture de chaîne d''approvisionnement','Perturbation majeure des flux logistiques mondiaux.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- CAT-10 MARKET_STRUCTURE
INSERT INTO event_taxonomy (cat_id, category, label_fr, subtype_id, subtype_label, description) VALUES
  ('CAT-10','MARKET_STRUCTURE','Structure de marché / Régulation / Technologie','ipo_major','IPO / Introduction en bourse majeure','Entrée en bourse d''une entreprise à impact sectoriel ou macro.'),
  ('CAT-10','MARKET_STRUCTURE','Structure de marché / Régulation / Technologie','market_circuit_breaker','Coupe-circuit de marché','Déclenchement d''un mécanisme d''arrêt des cotations.'),
  ('CAT-10','MARKET_STRUCTURE','Structure de marché / Régulation / Technologie','exchange_regulation','Nouvelle régulation marchés','Règle SEC, AMF, ESMA ou autre affectant la structure des marchés.'),
  ('CAT-10','MARKET_STRUCTURE','Structure de marché / Régulation / Technologie','crypto_regulatory','Régulation crypto / actifs numériques','Décision réglementaire sur les crypto-actifs (ETF, interdiction, etc.).'),
  ('CAT-10','MARKET_STRUCTURE','Structure de marché / Régulation / Technologie','central_bank_digital','CBDC / Monnaie numérique banque centrale','Annonce ou lancement d''une monnaie numérique de banque centrale.'),
  ('CAT-10','MARKET_STRUCTURE','Structure de marché / Régulation / Technologie','ai_tech_disruption','Disruption IA / Technologie','Annonce technologique majeure à impact sur les valorisations sectorielles.')
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. events — Articles qualifiés C2
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS events (
  event_id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  raw_article_ids   UUID[]       NOT NULL DEFAULT '{}',
  dedup_cluster_id  UUID,
  cluster_size      INTEGER      NOT NULL DEFAULT 1,
  event_timestamp   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  -- Source best
  source_name       TEXT         NOT NULL,
  source_authority  NUMERIC(4,3) NOT NULL CHECK (source_authority BETWEEN 0 AND 1),

  -- Classification taxonomie (FK)
  cat_id            VARCHAR(8)   NOT NULL,
  subtype_id        TEXT         NOT NULL,
  confidence        NUMERIC(4,3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  geography         TEXT[]       NOT NULL DEFAULT '{}',
  horizon           TEXT         NOT NULL CHECK (horizon IN ('immediate','weeks','months','structural')),

  -- Entités
  actors            TEXT[]       NOT NULL DEFAULT '{}',
  assets_mentioned  TEXT[]       NOT NULL DEFAULT '{}',
  key_figures       JSONB        NOT NULL DEFAULT '[]',

  -- Scoring et routing
  importance_score  NUMERIC(4,3) NOT NULL CHECK (importance_score BETWEEN 0 AND 1),
  routing           TEXT         NOT NULL CHECK (routing IN ('full_pipeline','archive')),

  -- Texte canonique
  text_en_canonical TEXT,

  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  FOREIGN KEY (cat_id, subtype_id) REFERENCES event_taxonomy(cat_id, subtype_id)
);

CREATE INDEX IF NOT EXISTS idx_events_cat_id        ON events(cat_id);
CREATE INDEX IF NOT EXISTS idx_events_subtype_id    ON events(subtype_id);
CREATE INDEX IF NOT EXISTS idx_events_timestamp     ON events(event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_routing       ON events(routing);
CREATE INDEX IF NOT EXISTS idx_events_importance    ON events(importance_score DESC);
CREATE INDEX IF NOT EXISTS idx_events_dedup_cluster ON events(dedup_cluster_id) WHERE dedup_cluster_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_geography     ON events USING GIN(geography);

COMMENT ON TABLE events IS 'Events qualifiés C2 — articles classifiés selon la taxonomie fermée Kairos v1.';

-- ---------------------------------------------------------------------------
-- 3. drivers — Variables pivot du graphe causal (15-20 drivers)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS drivers (
  driver_id    TEXT         PRIMARY KEY,         -- ex: 'taux_directeurs'
  label_fr     TEXT         NOT NULL,
  label_en     TEXT         NOT NULL,
  category     TEXT         NOT NULL CHECK (category IN (
                              'monetary','fiscal','prices','growth','credit',
                              'sovereign','fx','commodity','market','trade',
                              'financial','expectations'
                            )),
  unit         TEXT         NOT NULL,            -- ex: '%', 'index', 'bps'
  description  TEXT,
  active       BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE drivers IS '15-20 variables pivot du graphe causal Kairos. Source de vérité des driver_id utilisés dans causal_arcs.';

-- Seed: 18 drivers initiaux
INSERT INTO drivers (driver_id, label_fr, label_en, category, unit, description) VALUES
  ('taux_directeurs',       'Taux directeurs banques centrales',  'Policy rates',                'monetary',     '%',       'Taux directeur de la banque centrale principale de la zone considérée.'),
  ('conditions_credit',     'Conditions de crédit bancaire',      'Credit conditions',           'credit',       'index',   'Indice synthétique de la facilité d''accès au crédit bancaire.'),
  ('inflation_headline',    'Inflation headline (IPC)',            'Headline inflation (CPI)',    'prices',       '% yoy',   'Indice des prix à la consommation, variation annuelle.'),
  ('inflation_core',        'Inflation core',                     'Core inflation',              'prices',       '% yoy',   'IPC hors énergie et alimentation frais, variation annuelle.'),
  ('croissance_pib',        'Croissance PIB',                     'GDP growth',                  'growth',       '% qoq',   'Variation trimestrielle du PIB réel.'),
  ('emploi_chomage',        'Taux de chômage',                    'Unemployment rate',           'growth',       '%',       'Taux de chômage au sens BIT.'),
  ('investissement',        'Investissement privé',               'Private investment',          'growth',       '% gdp',   'Formation brute de capital fixe du secteur privé en % PIB.'),
  ('consommation',          'Consommation des ménages',           'Household consumption',       'growth',       '% gdp',   'Dépenses de consommation finale des ménages en % PIB.'),
  ('usd_strength',          'Force du dollar (DXY)',              'USD strength (DXY)',          'fx',           'index',   'Indice DXY du dollar américain pondéré des principaux partenaires.'),
  ('spreads_credit',        'Spreads de crédit (IG/HY)',          'Credit spreads (IG/HY)',      'credit',       'bps',     'Spreads OAS investment grade et high yield vs taux sans risque.'),
  ('spreads_souverains',    'Spreads souverains',                 'Sovereign spreads',           'sovereign',    'bps',     'Spreads de taux souverains par rapport au Bund allemand ou T-note.'),
  ('prix_petrole',          'Prix du pétrole (Brent)',            'Oil price (Brent)',           'commodity',    'USD/bbl', 'Prix spot du Brent en dollars par baril.'),
  ('prix_metaux',           'Prix des métaux industriels',        'Industrial metals prices',    'commodity',    'index',   'Indice composite des prix des métaux industriels (cuivre, aluminium...).'),
  ('sentiment_marche',      'Sentiment de marché (VIX proxy)',    'Market sentiment (VIX proxy)','market',       'index',   'Indice de volatilité implicite (VIX ou équivalent) comme proxy du sentiment.'),
  ('liquidite_bancaire',    'Liquidité du système bancaire',      'Banking system liquidity',    'financial',    'ratio',   'Ratio de couverture de liquidité moyen du système bancaire.'),
  ('dette_publique',        'Ratio dette publique/PIB',           'Public debt/GDP ratio',       'fiscal',       '% gdp',   'Encours de dette publique brute en % du PIB.'),
  ('balance_commerciale',   'Solde commercial',                   'Trade balance',               'trade',        'USD bn',  'Solde commercial mensuel en milliards de dollars.'),
  ('anticipations_inflation','Anticipations d''inflation (5y5y)', 'Inflation expectations 5y5y', 'expectations', '%',       'Breakeven d''inflation 5 ans dans 5 ans, proxy des anticipations long terme.')
ON CONFLICT (driver_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. causal_arcs — Graphe causal C3
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS causal_arcs (
  arc_id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  source_driver        TEXT         NOT NULL REFERENCES drivers(driver_id),
  target_driver        TEXT         NOT NULL REFERENCES drivers(driver_id),
  direction            SMALLINT     NOT NULL CHECK (direction IN (1, -1)),
  intensity            TEXT         NOT NULL CHECK (intensity IN ('low','moderate','strong')),
  intensity_coefficient NUMERIC(4,3) NOT NULL CHECK (intensity_coefficient BETWEEN 0 AND 1),
  delay                TEXT         NOT NULL CHECK (delay IN ('immediate','1-4w','1-6m','6m+')),
  conditions           JSONB        NOT NULL DEFAULT '[]',  -- [{driver, operator, threshold}]
  confidence           NUMERIC(4,3) NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  last_calibrated      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  active               BOOLEAN      NOT NULL DEFAULT TRUE,
  notes                TEXT,
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  UNIQUE (source_driver, target_driver)  -- un seul arc direct par paire
);

CREATE INDEX IF NOT EXISTS idx_causal_arcs_source ON causal_arcs(source_driver);
CREATE INDEX IF NOT EXISTS idx_causal_arcs_target ON causal_arcs(target_driver);
CREATE INDEX IF NOT EXISTS idx_causal_arcs_active ON causal_arcs(active) WHERE active = TRUE;

COMMENT ON TABLE causal_arcs IS 'Arcs orientés du graphe causal Kairos. Chaque arc représente une relation causale entre deux drivers. Calibrés via feedback C5.';

-- ---------------------------------------------------------------------------
-- 5. event_driver_lookup — Lookup table event_type → drivers primaires
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS event_driver_lookup (
  cat_id          VARCHAR(8)   NOT NULL,
  subtype_id      TEXT         NOT NULL,
  primary_drivers TEXT[]       NOT NULL DEFAULT '{}',  -- FK logique → drivers.driver_id
  driver_weights  JSONB        NOT NULL DEFAULT '{}',  -- {driver_id: weight_0_to_1}
  notes           TEXT,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  PRIMARY KEY (cat_id, subtype_id),
  FOREIGN KEY (cat_id, subtype_id) REFERENCES event_taxonomy(cat_id, subtype_id)
);

COMMENT ON TABLE event_driver_lookup IS 'Lookup: pour chaque sous-type d''event (C2), liste des drivers primaires activés et leurs poids dans le raisonnement C4.';

-- Quelques seeds représentatifs
INSERT INTO event_driver_lookup (cat_id, subtype_id, primary_drivers, driver_weights) VALUES
  ('CAT-01','rate_decision_hike',
    ARRAY['taux_directeurs','conditions_credit','spreads_credit','usd_strength','anticipations_inflation'],
    '{"taux_directeurs":1.0,"conditions_credit":0.85,"spreads_credit":0.70,"usd_strength":0.65,"anticipations_inflation":0.60}'::jsonb),
  ('CAT-01','rate_decision_cut',
    ARRAY['taux_directeurs','conditions_credit','spreads_credit','usd_strength','croissance_pib'],
    '{"taux_directeurs":1.0,"conditions_credit":0.85,"spreads_credit":0.65,"usd_strength":0.60,"croissance_pib":0.55}'::jsonb),
  ('CAT-03','cpi_release_above',
    ARRAY['inflation_headline','taux_directeurs','anticipations_inflation','spreads_souverains'],
    '{"inflation_headline":1.0,"taux_directeurs":0.80,"anticipations_inflation":0.75,"spreads_souverains":0.55}'::jsonb),
  ('CAT-06','military_conflict',
    ARRAY['prix_petrole','sentiment_marche','spreads_souverains','usd_strength'],
    '{"prix_petrole":0.85,"sentiment_marche":0.90,"spreads_souverains":0.70,"usd_strength":0.60}'::jsonb),
  ('CAT-08','opec_decision',
    ARRAY['prix_petrole','inflation_headline','prix_metaux'],
    '{"prix_petrole":1.0,"inflation_headline":0.65,"prix_metaux":0.40}'::jsonb)
ON CONFLICT (cat_id, subtype_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6. historical_episodes — Base historique des événements similaires passés
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS historical_episodes (
  episode_id      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  cat_id          VARCHAR(8)   NOT NULL,
  subtype_id      TEXT         NOT NULL,
  episode_date    DATE         NOT NULL,
  label           TEXT         NOT NULL,           -- description courte ex: "Fed hike Mar 2022"
  geography       TEXT[]       NOT NULL DEFAULT '{}',
  driver_impacts  JSONB        NOT NULL DEFAULT '{}', -- {driver_id: {direction, magnitude, delay_days}}
  asset_outcomes  JSONB        NOT NULL DEFAULT '{}', -- {asset_id: {direction, change_pct, horizon_days}}
  notes           TEXT,
  data_quality    TEXT         CHECK (data_quality IN ('high','medium','low')) DEFAULT 'medium',
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  FOREIGN KEY (cat_id, subtype_id) REFERENCES event_taxonomy(cat_id, subtype_id)
);

CREATE INDEX IF NOT EXISTS idx_hist_episodes_taxonomy ON historical_episodes(cat_id, subtype_id);
CREATE INDEX IF NOT EXISTS idx_hist_episodes_date     ON historical_episodes(episode_date DESC);
CREATE INDEX IF NOT EXISTS idx_hist_episodes_geo      ON historical_episodes USING GIN(geography);

COMMENT ON TABLE historical_episodes IS 'Base historique des épisodes similaires passés. Utilisée par C4 pour calibrer la confiance et la variance des chemins causaux.';

-- ---------------------------------------------------------------------------
-- 7. asset_sensitivity — Carte de sensibilité des actifs aux drivers
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS asset_sensitivity (
  asset_id        TEXT         NOT NULL,           -- ex: 'bonds_sovereign_us', 'equities_us'
  driver_id       TEXT         NOT NULL REFERENCES drivers(driver_id),
  sensitivity     NUMERIC(4,3) NOT NULL CHECK (sensitivity BETWEEN -1 AND 1),
  direction       SMALLINT     NOT NULL CHECK (direction IN (1,-1)),
  delay           TEXT         NOT NULL CHECK (delay IN ('immediate','1-4w','1-6m','6m+')),
  asset_class     TEXT         NOT NULL CHECK (asset_class IN (
                                  'bonds_sovereign','bonds_corporate','equities',
                                  'fx','commodities','real_estate','crypto'
                                )),
  asset_label_fr  TEXT         NOT NULL,
  notes           TEXT,
  last_reviewed   DATE         NOT NULL DEFAULT CURRENT_DATE,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  PRIMARY KEY (asset_id, driver_id)
);

CREATE INDEX IF NOT EXISTS idx_asset_sensitivity_driver ON asset_sensitivity(driver_id);
CREATE INDEX IF NOT EXISTS idx_asset_sensitivity_class  ON asset_sensitivity(asset_class);

COMMENT ON TABLE asset_sensitivity IS 'Carte de sensibilité des classes d''actifs aux drivers macro. Utilisée par C4 pour calculer les asset_scores.';

-- ---------------------------------------------------------------------------
-- 8. analyses — Outputs du moteur de raisonnement C4
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS analyses (
  analysis_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id          UUID         NOT NULL REFERENCES events(event_id),

  -- Snapshot taxonomie (dénormalisé)
  cat_id            VARCHAR(8)   NOT NULL,
  subtype_id        TEXT         NOT NULL,

  -- Résultats
  causal_paths      JSONB        NOT NULL DEFAULT '[]',
  asset_scores      JSONB        NOT NULL DEFAULT '{}',
  overall_confidence NUMERIC(4,3) NOT NULL CHECK (overall_confidence BETWEEN 0 AND 1),
  confidence_label  TEXT         NOT NULL CHECK (confidence_label IN ('low','medium','high','very_high')),
  narrative         TEXT         NOT NULL DEFAULT '',
  report_canonical  JSONB        NOT NULL DEFAULT '{}',

  -- Méta
  model_version     TEXT         NOT NULL DEFAULT 'v1',
  processing_time_ms INTEGER,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

  FOREIGN KEY (cat_id, subtype_id) REFERENCES event_taxonomy(cat_id, subtype_id)
);

CREATE INDEX IF NOT EXISTS idx_analyses_event_id   ON analyses(event_id);
CREATE INDEX IF NOT EXISTS idx_analyses_created_at ON analyses(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_analyses_confidence ON analyses(overall_confidence DESC);
CREATE INDEX IF NOT EXISTS idx_analyses_cat        ON analyses(cat_id, subtype_id);

COMMENT ON TABLE analyses IS 'Outputs C4 du moteur de raisonnement causal. Un event peut générer plusieurs analyses (recalibrations).';

-- ---------------------------------------------------------------------------
-- 9. predictions — Archive C5 (prédictions + vérification)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS predictions (
  prediction_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  analysis_id         UUID         NOT NULL REFERENCES analyses(analysis_id),
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  verification_due_at TIMESTAMPTZ  NOT NULL,
  status              TEXT         NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','verified','partially_verified','unverifiable')),

  -- Snapshot immuable de l'analyse C4
  prediction_snapshot JSONB        NOT NULL DEFAULT '{}',

  -- Données réelles collectées à vérification
  reality_data        JSONB        NOT NULL DEFAULT '{}',

  -- Métriques d'erreur
  direction_correct   BOOLEAN,
  intensity_error     NUMERIC(6,4),
  horizon_error_days  INTEGER,
  calibration_signal  TEXT         CHECK (calibration_signal IN ('recalibrate_up','recalibrate_down','ok')),

  -- Méta vérification
  verified_at         TIMESTAMPTZ,
  verified_by         TEXT         DEFAULT 'auto',  -- 'auto' ou identifiant humain

  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_predictions_analysis_id    ON predictions(analysis_id);
CREATE INDEX IF NOT EXISTS idx_predictions_status         ON predictions(status);
CREATE INDEX IF NOT EXISTS idx_predictions_due            ON predictions(verification_due_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_predictions_calibration    ON predictions(calibration_signal) WHERE calibration_signal IS NOT NULL;

COMMENT ON TABLE predictions IS 'Archive C5 des prédictions Kairos. Alimentation du feedback loop pour recalibration du graphe causal.';

-- ---------------------------------------------------------------------------
-- 10. feedback_records — Historique des recalibrations du graphe causal
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS feedback_records (
  feedback_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  prediction_id     UUID         NOT NULL REFERENCES predictions(prediction_id),
  arc_id            UUID         REFERENCES causal_arcs(arc_id),  -- null si recalibration globale

  -- Valeurs avant/après
  field_changed     TEXT         NOT NULL,  -- ex: 'intensity_coefficient', 'confidence', 'delay'
  old_value         JSONB        NOT NULL,
  new_value         JSONB        NOT NULL,

  -- Raison
  trigger_reason    TEXT         NOT NULL CHECK (trigger_reason IN (
                                    'direction_error','intensity_error','horizon_error','multi_signal','manual'
                                  )),
  recalibration_weight NUMERIC(4,3), -- poids donné à ce feedback dans la recalibration

  applied_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  applied_by        TEXT         NOT NULL DEFAULT 'auto',
  notes             TEXT
);

CREATE INDEX IF NOT EXISTS idx_feedback_prediction  ON feedback_records(prediction_id);
CREATE INDEX IF NOT EXISTS idx_feedback_arc         ON feedback_records(arc_id) WHERE arc_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_feedback_applied_at  ON feedback_records(applied_at DESC);

COMMENT ON TABLE feedback_records IS 'Journal des recalibrations du graphe causal déclenchées par les vérifications C5.';

-- ---------------------------------------------------------------------------
-- Triggers updated_at
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION kairos_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER events_updated_at
  BEFORE UPDATE ON events
  FOR EACH ROW EXECUTE FUNCTION kairos_set_updated_at();

CREATE OR REPLACE TRIGGER causal_arcs_updated_at
  BEFORE UPDATE ON causal_arcs
  FOR EACH ROW EXECUTE FUNCTION kairos_set_updated_at();

CREATE OR REPLACE TRIGGER event_driver_lookup_updated_at
  BEFORE UPDATE ON event_driver_lookup
  FOR EACH ROW EXECUTE FUNCTION kairos_set_updated_at();

CREATE OR REPLACE TRIGGER predictions_updated_at
  BEFORE UPDATE ON predictions
  FOR EACH ROW EXECUTE FUNCTION kairos_set_updated_at();
