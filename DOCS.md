# DOCS

## Diagnostic Git pour transfert vers ThomasHeran/kairos (2026-04-27)

### Exploration

- Le remote `origin` actuel est `git@github.com:nanocorp-hq/kairon.git`.
- Le compte GitHub actuel est `nanocorp-hq` et le nom du repo distant est `kairon`.
- La branche locale active est `main`, suivie par `origin/main`.
- L'état Git au moment du diagnostic est propre: `nothing to commit, working tree clean`.
- Les 10 derniers commits observés commencent par `d7b3177 Add C2 qualification pipeline`, `b90f058 feat: add C3 knowledge base v1 seed` et `abb4acc Add macro global C1 scraping pipeline`.
- Une archive complète hors `.git` et `node_modules` a été créée à `/home/worker/kairos_full_backup.tar.gz`.
- La taille observée de l'archive est `612K`.
- L'inventaire complet des fichiers du repo hors `.git` et `node_modules` a été relancé pour préparer un transfert vers un nouveau remote GitHub.

### Changements réalisés

- Aucun fichier applicatif n'a été modifié pour ce diagnostic.
- `DOCS.md` a été enrichi avec les informations de diagnostic Git et de sauvegarde afin de faciliter la reconfiguration du dépôt vers `ThomasHeran/kairos`.

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

---

## Knowledge Base C3 v1 (2026-04-27)

### Exploration

- Le repo ne contenait aucun artefact du travail non committe precedemment: pas de `/tmp/gen_kb.py`, pas de branche/commit/stash recuperable contenant `knowledge_base_v1`.
- `config/taxonomy_v1.json` et `docs/event_driver_lookup.json` sont plus recents que le texte historise dans `db/schema_v2.sql`:
  - la taxonomie actuelle contient `101` sous-types,
  - `event_taxonomy` dans Neon contient bien `101` lignes,
  - certains `subtype_id` effectifs sont `qe_announcement`, `qt_announcement`, `emergency_action_easing`, etc., pas les anciens libelles du commentaire SQL.
- `docs/event_driver_lookup.json` couvre `101` entrees sur les `10` categories et utilise `22` drivers uniques.
- La base Neon avant seed contenait deja `drivers=18` (seed historique), `causal_arcs=0`, `historical_episodes=0`, `asset_sensitivity=0`.
- Choix de design pour `knowledge_base_v1`:
  - conserver `20` drivers coeur alignes sur les slugs du lookup,
  - exclure `prix_gaz` et `prix_agricoles` du noyau v1,
  - verification faite: les `101` entrees du lookup touchent quand meme au moins un driver du noyau v1, donc la couverture par categorie reste complete.

### Fichiers crees

- `config/knowledge_base_v1.json`
  - `20` drivers coeur,
  - `50` arcs causaux,
  - `24` episodes historiques couvrant `CAT-01` a `CAT-10`,
  - `280` sensibilites d'actifs (`14` drivers principaux x `20` actifs),
  - metadata de couverture + attenuation Kairos `0.6` par niveau.
- `db/seed_knowledge_base_v1.sql`
  - upserts idempotents pour `drivers`, `causal_arcs`, `historical_episodes`, `asset_sensitivity`,
  - UUID stables pour les arcs et episodes.
- `scripts/generate_knowledge_base_v1.py`
  - generateur deterministe des deux livrables ci-dessus.

### Application DB

- Seed applique avec succes via `psql $DATABASE_URL < db/seed_knowledge_base_v1.sql`.
- Comptes verifies ensuite en Neon:
  - `drivers=20`
  - `causal_arcs=50`
  - `historical_episodes=24`
  - `asset_sensitivity=280`

### Points de reprise

- Ajouter un KB v2 si Kairos veut faire passer `prix_gaz` et `prix_agricoles` du statut "lookup-only" au statut de drivers coeur seeds en DB.
- Connecter le moteur C4 (`engine/branch_generator.py` / `lib/scenarios.ts`) a `causal_arcs` et `historical_episodes` pour des chemins dynamiques reels.
- Ajouter des tests d'integration qui valident la coherence `taxonomy_v1.json` ↔ `event_driver_lookup.json` ↔ `knowledge_base_v1.json` ↔ tables Neon.

---

## C2 Qualification Pipeline (2026-04-27)

### Exploration

- `DATABASE_URL` est bien provisionne localement et sur Vercel, mais `OPENAI_API_KEY` n'est present ni dans l'environnement local d'execution ni dans `nanocorp vercel env list`; le pipeline C2 doit donc tolerer l'absence d'OpenAI et degrader proprement au lieu de casser.
- La doc locale Next.js 16 impose toujours les Route Handlers dans `app/api/**/route.ts` avec Web `Request`/`Response`; `GET` n'est pas cache par defaut et les params dynamiques sont des `Promise`.
- `docs/classification_prompt_v1.md` est disponible et decrit la taxonomie fermee Kairos v1 avec `CAT-01..CAT-10`; il faut donc implementer la vraie classification taxonomique et non un fallback generique.
- La table `event_taxonomy` contient deja `101` lignes, `articles` contient `414` lignes et `events` est encore vide au debut de cette tache.
- Le schema `events` actuellement en base attend exactement les champs C2 canoniques utiles au pipeline: `raw_article_ids uuid[]`, `dedup_cluster_id`, `cluster_size`, `source_name`, `source_authority`, `cat_id`, `subtype_id`, `confidence`, `geography`, `horizon`, `actors`, `assets_mentioned`, `key_figures`, `importance_score`, `routing`, `text_en_canonical`.
- Les articles C1 existants n'etaient pas homogenes pour l'identite canonique: seuls `223/414` avaient `canonical.article_id`, alors que `events.raw_article_ids` attend des UUID. Une migration additive est necessaire pour fiabiliser `article_uuid` au niveau SQL.
- `pgvector` n'etait pas encore active dans Neon, mais `CREATE EXTENSION vector` passe correctement sur cette base.
- Les articles France RSS existants sont majoritairement de l'actualite generaliste; une part importante du lot doit donc etre archivee comme hors taxonomie macro plutot qu'inseree de force dans `events`.

### Fichiers crees

- `db/schema_v4.sql`
- `lib/openai.ts`
- `lib/taxonomy.ts`
- `lib/qualify.ts`
- `app/api/qualify/route.ts`
- `app/api/qualify/batch/route.ts`
- `app/api/events/route.ts`

### Fichiers modifies

- `scripts/migrate.ts`

### Changements realises

- Ajout d'une migration C2 `db/schema_v4.sql`:
  - activation `pgvector`,
  - ajout de `articles.article_uuid` avec backfill depuis `canonical.article_id` quand disponible,
  - ajout des colonnes de file de qualification `qualification_status`, `qualified_event_id`, `qualified_at`, `qualification_error`,
  - creation de la table `article_embeddings` en `vector(1536)`,
  - index sur `events.raw_article_ids` et la file d'articles.
- Ajout d'un helper taxonomie `lib/taxonomy.ts` qui indexe `taxonomy_v1.json` et expose les metadonnees de sous-types (label, geography typique, authority floor, horizon par defaut).
- Ajout d'un helper OpenAI `lib/openai.ts`:
  - appels `chat/completions` et `embeddings` si `OPENAI_API_KEY` est disponible,
  - fallback deterministic local embedding `1536` dimensions si la cle manque, pour garder la dedup operationnelle.
- Ajout du service metier `lib/qualify.ts`:
  - chargement des articles C1 et des events recents,
  - embeddings + stockage Neon,
  - clustering semantique sur fenetre `48h` avec seuil cosine `0.92`,
  - selection de la source la plus autoritaire du cluster,
  - classification taxonomique via `classification_prompt_v1.md` quand OpenAI est disponible,
  - fallback heuristique multi-regles quand OpenAI est absent,
  - extraction NER legere (acteurs, actifs, key figures),
  - scoring d'autorite, scoring composite d'importance, routage `full_pipeline` / `archive`,
  - insertion des events C2 dans `events`,
  - marquage des articles C1 en `pending/qualified/archived/failed`.
- Ajout des endpoints App Router:
  - `POST /api/qualify`
  - `POST /api/qualify/batch`
  - `GET /api/events`

### Verifications realisees

- `npm run db:migrate`
- `npx tsc --noEmit`
- `npm run lint` (reste 2 warnings historiques hors perimetre dans le moteur de scenarios)
- `npm run build`
- Verification HTTP locale sur `next start`:
  - `GET /api/events?limit=5`
  - `POST /api/qualify`
  - `POST /api/qualify/batch`
- Verification DB directe:
  - le lot de test a cree des events C2 en base,
  - repartition observee apres tests: `archive=17`, `full_pipeline=1`,
  - exemple `full_pipeline` observe: article BLS/CPI via `POST /api/qualify/batch` local.
- Test lot France demande:
  - execution de `50` articles RSS France,
  - resultat observe avec les heuristiques finales: `17` events qualifies, `32` archives, `0` echec,
  - les archives correspondent majoritairement a du sport / culture / actualite generaliste hors taxonomie macro.

### Points de reprise

- Provisionner `OPENAI_API_KEY` localement et sur Vercel pour activer la vraie classification LLM GPT-4o-mini et les embeddings `text-embedding-3-small`; aujourd'hui le pipeline degrade proprement mais repose sur des heuristiques/fallbacks.
- Raffiner les heuristiques de fallback pour reduire les faux negatifs sur certains macro releases officiels (`unemployment rate`, PPI, reports ECB/BOJ) et les faux positifs geographiques (`US/EZ/ME` parfois trop larges).
- Enrichir la NER avec un vrai passage structure (LLM ou modele dedie) pour extraire davantage d'acteurs, d'actifs et de chiffres.
- Ajouter des tests automatisees TypeScript sur `lib/qualify.ts` et sur les trois routes API C2.
