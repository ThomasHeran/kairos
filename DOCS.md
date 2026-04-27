# DOCS

## Exploration

- `2026-04-14`: le repo était quasi vide, avec seulement `.git`, `.agents/`, `.claude/` et un `README.md` de cadrage produit.
- La stack cible imposée par la plateforme est Next.js App Router au root du repo, déployée automatiquement sur Vercel depuis `main`.
- Les endpoints demandés doivent être servis via `app/api/*`, même si une couche métier dédiée `/api` est conservée pour organiser le code.
- La base PostgreSQL est accessible via `DATABASE_URL`; un schéma reproductible est attendu.
- `2026-04-14`: la base Neon contient bien les tables `countries`, `sources`, `articles` et `scrape_jobs`, mais aucune donnée seed n'était présente au début de cette tâche.
- `2026-04-14`: la config France pointait encore vers des sources placeholder (`reddit`, `news`) et l'agent `RSSAgent` renvoyait seulement un résultat factice sans fetch ni écriture DB.
- `2026-04-14`: la doc locale `node_modules/next/dist/docs/01-app/01-getting-started/15-route-handlers.md` confirme l'usage des Route Handlers Web `Request`/`Response` dans `app/api/*`; `GET` n'est pas caché ici car les routes utilisent `dynamic = "force-dynamic"`.
- `2026-04-14`: les flux testés (`Le Monde`, `BFM TV`, `Mediapart`) exposent du RSS 2.0 classique avec `item/title/link/pubDate/description`, ce qui permet une implémentation commune avec fallback Atom.
- `2026-04-14`: l'URL fournie pour `20 Minutes` (`/feeds/rss/`) répond en `404`; le feed officiel actuel répond sur `/feeds/rss-une.xml`.
- `2026-04-14`: l'URL fournie pour `L'Équipe` (`/rss/actu_rss.xml`) répond actuellement en `404/410`; le scraper la traite donc en best effort et la remonte comme échec source tant qu'un nouveau flux officiel n'est pas identifié.

## Changements réalisés

- Initialisation du projet Next.js TypeScript/Tailwind au root.
- Mise en place d’un squelette Kairos avec `config/countries.json`, `agents/`, `scheduler/`, `lib/`, `db/schema.sql` et les endpoints REST `app/api/*`.
- Ajout du script `npm run db:migrate` pour appliquer le schéma Neon.
- Ajout d’une page d’accueil de supervision légère avec aperçu de l’architecture.
- Migration exécutée avec succès sur Neon; tables confirmées: `countries`, `sources`, `articles`, `scrape_jobs`.
- Vérifications locales réussies:
  - `npm run lint`
  - `npm run build`
  - `GET /api/health`
  - `GET /api/countries`
  - `GET /api/news`
  - `GET /api/news/fr`
- Remplacement des sources France par 8 grands flux RSS français: Le Monde, Le Figaro, Libération, BFM TV, France Info, L'Équipe, 20 Minutes et Mediapart.
- Implémentation réelle de `RSSAgent` avec fetch réseau, parsing XML, extraction `title/url/date/résumé/tags`, nettoyage HTML et déduplication par URL.
- Ajout du service `api/scrape-france.ts` qui upsert `countries` et `sources`, insère les articles dans `articles`, crée/met à jour `scrape_jobs` et met à jour `sources.last_scraped_at`.
- L'upsert des `sources` a été rendu tolérant aux changements d'URL d'une source existante en s'appuyant aussi sur le nom de la source, pour éviter les doublons DB lors d'un changement de feed officiel.
- Ajout du endpoint manuel `POST /api/scrape/france`.
- Extension de `GET /api/news` pour supporter le filtre `?country=fr` en plus de la route existante `/api/news/[country]`.

## Points de reprise

- Vérifier et appliquer la migration sur la base Neon si nécessaire.
- Étendre le même pattern de persistance aux autres types d’agents (`reddit`, `twitter`, `forum`, `news`) ou factoriser un orchestrateur DB partagé.
- Ajouter le scheduling périodique effectif côté plateforme/external cron.
- Ajouter des tests automatisés sur le parsing RSS et sur les endpoints de scrape.

---

## Scenario Tree Engine C4 (2026-04-27)

### Fichiers créés

**Python engine/ (standalone + DB)**
- `engine/probability_calibrator.py` — Lookup table + ajustement contextuel, détection HIGH_UNCERTAINTY (CAT-05/06/08 + importance > 0.75), pruning rules
- `engine/branch_generator.py` — Génération des branches nœud par nœud, atténuation par profondeur, root node generator
- `engine/scenario_aggregator.py` — Consensus pondéré, dominant scenario, uncertainty flag, revision factors
- `engine/scenario_tree_engine.py` — Orchestrateur principal: BFS récursif, extraction paths root→leaf, persistance PostgreSQL
- `engine/scenario_report_generator.py` — Rapport Markdown via Anthropic Claude API (fallback structuré si API absent)

**Config**
- `config/probability_calibrations_v1.json` — 10 calibrations historiques: armed_conflict_hormuz, armed_conflict_general, sanctions, oil_supply_disruption, financial_stress, trade_war, energy_supply_shock, sovereign_debt, oil_price_surge, opec_decision

**DB (db/schema_scenario_v1.sql)**
- `probability_calibrations` — lookup bifurcations (10 seedings)
- `scenario_trees` — arbre complet par event (status, consensus, dominant_scenario)
- `scenario_nodes` — nœuds (probability, cumulative, drivers, asset_impacts, depth)
- `scenario_paths` — chemins root→feuille (terminal scenarios)
- `scenario_revisions` — tracking des révisions de probabilité

**TypeScript API (Next.js)**
- `lib/scenarios.ts` — business logic TS: détection HIGH_UNCERTAINTY, calibration lookup, DB queries, consensus computation
- `app/api/analyze/scenarios/route.ts` — POST /api/analyze/scenarios
- `app/api/scenarios/[tree_id]/route.ts` — GET /api/scenarios/:tree_id
- `app/api/scenarios/[tree_id]/path/[path_id]/route.ts` — GET /api/scenarios/:tree_id/path/:path_id
- `app/api/scenarios/[tree_id]/consensus/route.ts` — GET /api/scenarios/:tree_id/consensus

**Test**
- `scripts/test_scenario_engine.py` — 7/7 tests E2E passent

### Architecture du moteur

```
[Event HIGH_UNCERTAINTY: CAT-05/06/08 + importance > 0.75]
       ↓
[Root node: drivers primaires depuis event_type]
       ↓
[BranchGenerator: lookup calibrations + ajustement contextuel]
  → 2-4 branches niveau 1, probabilités normalisées
       ↓
[Récursion BFS jusqu’à depth=4]
  → Chaque branche: P_cumul = P_parent × P_branche
  → Pruning si P_cumul < 0.03 ou coefficient < 0.10
       ↓
[extract_paths: root→leaf paths (ScenarioPaths)]
  → terminal_asset_summary (agrégat pondéré du chemin)
       ↓
[ScenarioAggregator: consensus pondéré + dominant + uncertainty_flag]
       ↓
[ScenarioReportGenerator: rapport Markdown via LLM ou fallback]
       ↓
[Output: ScenarioTree JSON + persistance DB]
```

### Points de reprise suivants
- Implémenter le worker C2 (classification LLM → events table) pour tester avec de vrais events DB
- Connecter le C3 causal graph (causal_arcs) au branch_generator pour des bifurcations dynamiques
- Ajouter les narratifs LLM via ANTHROPIC_API_KEY (déjà implémenté, utilise `claude-haiku-4-5-20251001`)
- Implémenter `scenario_revisions` (révision des probabilités quand de nouveaux events arrivent)
- Ajouter une UI de visualisation de l’arbre (frontend)
- Écrire les tests d’intégration TypeScript pour les routes API

---

## Schéma canonique inter-couches C1→C2→C3→C4→C5 (2026-04-15)

### Fichiers créés
- `config/taxonomy_v1.json` — Taxonomie fermée Kairos v1 : 10 catégories, 55 sous-types. Source de vérité pour les champs `cat_id`/`subtype_id` dans tout le pipeline.
- `docs/CANONICAL_SCHEMA.md` — Documentation complète des 5 JSON Schemas (C1 article brut, C2 event qualifié, C3 arc causal, C4 analyse, C5 prédiction), avec exemples et tableau des 18 drivers.
- `db/schema_v2.sql` — Migration SQL complète : 10 tables nouvelles (event_taxonomy, events, drivers, causal_arcs, event_driver_lookup, historical_episodes, asset_sensitivity, analyses, predictions, feedback_records) + seeds taxonomy + seeds drivers.

### Architecture des tables
```
event_taxonomy (cat_id, subtype_id) PK
  ↑ FK de: events, event_driver_lookup, historical_episodes, analyses

drivers (driver_id) PK
  ↑ FK de: causal_arcs(source_driver, target_driver), asset_sensitivity(driver_id)

events (event_id) → analyses (analysis_id) → predictions (prediction_id) → feedback_records
```

### Principe taxonomie fermée
- Tout event C2 DOIT avoir `cat_id` ∈ {CAT-01..CAT-10} et `subtype_id` issu de `taxonomy_v1.json`.
- Les champs sont des FK vers `event_taxonomy(cat_id, subtype_id)`.
- Le script de migration inclut un seed complet des 55 sous-types.

### Migration
Appliquer `db/schema_v2.sql` après `db/schema.sql` via `psql $DATABASE_URL < db/schema_v2.sql`.

### Points de reprise suivants
- Appliquer `schema_v2.sql` sur la base Neon de prod (migration pas encore exécutée).
- Implémenter le worker C2 de qualification (classify articles → events avec cat_id/subtype_id).
- Implémenter le worker C3 (graphe causal) et seeder les arcs initiaux dans `causal_arcs`.
- Implémenter le worker C4 (moteur de raisonnement, asset_scores).
- Implémenter le worker C5 (archivage prédictions + boucle feedback).

---

## Macro Global C1 (2026-04-27)

### Exploration

- `node_modules` était absent au début de cette tâche; `npm ci` a été nécessaire avant toute lecture de la doc Next.js locale exigée par `AGENTS.md`.
- La doc pertinente Next.js 16 lue pour les endpoints est toujours `node_modules/next/dist/docs/01-app/01-getting-started/15-route-handlers.md`, complétée par `node_modules/next/dist/docs/01-app/03-api-reference/03-file-conventions/route.md`.
- Les flux Fed (`press_all.xml`, `press_monetary.xml`), ECB (`press.html`, `statpress.html`, `pub.html`), BOE (`/rss/news`), BIS (`/doclist/cbspeeches.rss?paging_length=15`), BLS (`/feed/bls_latest.rss`) et l’Atom custom Eurostat sont accessibles côté serveur et parsables.
- Le lien BOJ fourni dans la tâche (`https://www.boj.or.jp/en/rss/`) ne renvoie pas un flux exploitable; le flux RSS officiel fonctionnel est `https://www.boj.or.jp/en/rss/whatsnew.xml?id=1002`.
- Le lien BIS fourni dans la tâche (`https://www.bis.org/doclist/all_speeches.rss`) renvoie une 404; le feed officiel fonctionnel découvert via `https://www.bis.org/rss/index.htm` est `https://www.bis.org/doclist/cbspeeches.rss?paging_length=15`.
- Eurostat n’expose pas un RSS simple depuis la page HTML, mais la page `news/euro-indicators` contient un export Atom exploitable via `p_p_resource_id=atom`.
- IMF `https://www.imf.org/en/News/rss` renvoie une coquille HTML Next.js plutôt qu’un XML utile; la page `https://www.imf.org/en/news` contient toutefois une liste SSR `Latest News` exploitable en scraping HTML simple.
- OECD `https://www.oecd.org/newsroom/rss.xml` répond actuellement en `403` / challenge Cloudflare depuis un client serveur simple; le source handler est branché mais reste en échec best effort tant qu’un endpoint officiel sans challenge n’est pas identifié.
- `scripts/migrate.ts` échouait sur cette base Neon car `schema_v2.sql` avait déjà été appliqué dans une variante plus ancienne (`event_taxonomy` présent sans colonnes attendues par le fichier actuel); le script saute désormais `schema_v2.sql` si les tables taxonomy existent déjà.
- `db/schema.sql` n’était pas idempotent sur une base déjà migrée une fois les colonnes macro ajoutées en V3, car il créait des index sur des colonnes absentes; les index macro ont été déplacés en pratique vers `schema_v3.sql`.

### Changements réalisés

- Ajout d’un parseur de feed partagé `lib/feed.ts` réutilisable par les flux RSS/Atom/RDF, avec support explicite des feeds RSS 1.0 utilisés par BIS.
- Extension du modèle source côté TypeScript pour accepter `scraping` et `api` en plus des types existants.
- Ajout de `config/macro-sources.ts` avec 9 sources macro C1: `fed`, `ecb`, `imf`, `bis`, `eurostat`, `oecd`, `bls`, `boe`, `boj`.
- Ajout du service métier `api/scrape-macro.ts`:
  - collecte multi-sources,
  - scraping HTML dédié IMF,
  - extraction multi-publications depuis le flux BLS latest numbers,
  - normalisation C1 canonique en JSON,
  - détection `release_type` (`rate_decision`, `cpi`, `gdp`, `pmi`, `nfp`, `speech`, `report`),
  - enrichissement `is_scheduled_release`, `authority_score`, `news_type=macro_global`,
  - upsert DB dans `countries`, `sources`, `articles`, `scrape_jobs`.
- Ajout des endpoints:
  - `POST /api/scrape/macro-global`
  - `POST /api/scrape/macro/[source_id]`
- Extension de `GET /api/news` pour supporter les filtres:
  - `?type=macro_global`
  - `?source=<slug>`
  - `?release_type=<type>`
- Extension du schéma SQL:
  - `sources.slug`
  - nouveaux types `scraping` / `api`
  - `articles.news_type`
  - `articles.release_type`
  - `articles.is_scheduled_release`
  - `articles.authority_score`
  - `articles.canonical` (`jsonb`)
- Ajout de `db/schema_v3.sql` et mise à jour de `scripts/migrate.ts` pour appliquer cette migration de façon additive et idempotente.
- Correction des heuristiques de classification après observation réelle:
  - `address` dans un texte long ne classe plus à tort un article en `speech`
  - `interest rate statistics` ECB ne classe plus à tort un article en `rate_decision`

### Vérifications réalisées

- `npm run db:migrate`
- `npx tsc --noEmit`
- `npm run lint` (reste 2 warnings historiques hors périmètre dans le moteur de scénarios)
- `npm run build`
- Exécutions directes validées:
  - `fed` → success, 31 articles
  - `ecb` → success, 44 articles
  - `imf` → success, 8 articles
  - `bis` → success, 25 articles
  - `eurostat` → success, 11 articles
  - `bls` → success, 6 articles
  - `boe` → success, 50 articles
  - `boj` → success, 48 articles
  - `oecd` → failed, `403`
- Vérifications HTTP locales via Next App Router:
  - `POST /api/scrape/macro/fed`
  - `POST /api/scrape/macro-global`
  - `GET /api/news?type=macro_global&source=fed`
  - `GET /api/news?type=macro_global&source=ecb`
- Vérification DB directe:
  - des articles `macro_global` Fed et ECB sont présents en base,
  - avec `source_slug`, `release_type`, `is_scheduled_release`, `authority_score` et `canonical` renseignés.

### Points de reprise

- Trouver un endpoint OECD officiel exploitable sans challenge Cloudflare afin de faire passer la 9e source en succès réel.
- Étendre la même couche macro à la Banque mondiale, OMC et BEA si le périmètre doit couvrir toute la liste initiale de la tâche.
- Raffiner encore les heuristiques de `release_type` pour distinguer plus finement `speech` vs `report` et les publications de minutes/comptes rendus de banques centrales.
- Ajouter des tests automatisés ciblés pour `api/scrape-macro.ts` (par source et par classifieur).
