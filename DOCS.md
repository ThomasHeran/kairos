# DOCS

## C1->C5 Article Analysis Pipeline (2026-04-27)

### Exploration

- Le repo tourne sous `next@16.2.3`; apres `npm ci`, la doc locale pertinente a bien ete lue dans `node_modules/next/dist/docs/01-app/01-getting-started/15-route-handlers.md` et `node_modules/next/dist/docs/01-app/03-api-reference/04-functions/after.md`.
- Les Route Handlers existants utilisent deja le modele Next 16 (`app/api/**/route.ts`, `Request`/`Response`, `params` en `Promise` pour les segments dynamiques), donc le nouveau pipeline devait suivre exactement ce pattern.
- `services/scrape-france.ts` est le point d'entree C1 actuel: il insere les articles en base avec dedup implicite via `ON CONFLICT (url) DO NOTHING`, mais n'appelait encore aucune analyse C2/C3/C4.
- Le schema `articles` ne contenait pas encore les colonnes d'enrichissement demandees: `category`, `category_confidence`, `summary`, `importance_score`, `urgency_score`, `market_impact_score`, `analyzed_at`.
- Le helper `lib/openai.ts` existe deja et supporte `gpt-4o-mini`; il manquait seulement une couche pipeline web/API avec retry/backoff et fallback sans `OPENAI_API_KEY`.
- Lors de la premiere tentative `npm run db:migrate`, une erreur d'idempotence est apparue: `schema.sql` essayait de creer l'index `idx_articles_analyzed_at` avant que `schema_v5.sql` n'ajoute la colonne sur une base existante. Le schema de base a ete rendu conditionnel pour rester rejouable en production.

### Fichiers crees

- `services/pipeline/types.ts`
- `services/pipeline/category-config.ts`
- `services/pipeline/common.ts`
- `services/pipeline/classify.ts`
- `services/pipeline/summarize.ts`
- `services/pipeline/score.ts`
- `services/pipeline/analyze.ts`
- `app/api/analyze/route.ts`
- `app/api/analyze/[id]/route.ts`
- `db/schema_v5.sql`

### Fichiers modifies

- `app/api/scrape/france/route.ts`
- `db/schema.sql`
- `scripts/migrate.ts`

### Changements realises

- Ajout d'un pipeline C2->C5 sous `services/pipeline/`:
  - classification taxonomique `CAT-01..CAT-10` via `gpt-4o-mini`,
  - fallback heuristique par dictionnaires de mots-cles si `OPENAI_API_KEY` est absent ou si l'appel OpenAI echoue apres retries,
  - resume 2-3 phrases via `gpt-4o-mini`,
  - fallback resume par extraction des 3 premieres phrases,
  - scoring `importance_score`, `urgency_score`, `market_impact_score` avec clamp `0..10`,
  - retry exponentiel max `3` sur erreurs OpenAI retryables (`429`, rate limit, timeout).
- Ajout du service principal `analyzeArticle(article)` qui chaine classification, resume, scoring puis persiste l'enrichissement dans `articles` avec `analyzed_at = NOW()`.
- Ajout de `POST /api/analyze`:
  - recupere les articles `WHERE analyzed_at IS NULL`,
  - batch clamp a `10` max pour rester compatible avec la contrainte timeout Vercel,
  - retourne `{ analyzed, errors }`.
- Ajout de `POST /api/analyze/[id]` pour re-analyser un article specifique par son `id`.
- Modification de `POST /api/scrape/france`:
  - import de `after` depuis `next/server`,
  - declenchement best-effort en arriere-plan de `POST /api/analyze?limit=20`,
  - echec du trigger logge mais non bloquant pour le scraping.
- Ajout de la migration `db/schema_v5.sql` et mise a jour du schema de base pour les colonnes d'analyse + index `idx_articles_analyzed_at`.
- Mise a jour de `scripts/migrate.ts` pour inclure `schema_v5.sql`.
- Correction d'idempotence dans `db/schema.sql`:
  - creation conditionnelle de l'index `idx_articles_analyzed_at` uniquement si la colonne existe deja, pour eviter de casser une migration incremental sur base existante.

### Verification

- `npm run lint` passe avec 2 warnings preexistants hors scope (`app/api/scenarios/[tree_id]/path/[path_id]/route.ts`, `lib/scenarios.ts`).
- `npm run build` passe; les nouvelles routes `'/api/analyze'` et `'/api/analyze/[id]'` sont bien generees.
- `npm run db:migrate` passe apres correction d'idempotence.
- Test fonctionnel reel execute sur la base:
  - `analyzePendingArticles(1)` retourne `{"analyzed":1,"errors":0}`
  - l'article `id=597` a ete enrichi en base avec `category='CAT-01'`, `category_confidence=0.35`, `importance_score=8.5`, `urgency_score=5`, `market_impact_score=9`, `analyzed_at IS NOT NULL`.
- Commit pousse sur `origin/main`: `5e32843 feat: add article analysis pipeline`.
- Verification deploiement:
  - tentative `agent-browser open https://kairon.nanocorp.app` echouee localement car Chrome n'est pas installe sur l'environnement worker (`Chrome not found`);
  - verification HTTP de secours via `curl -I -L https://kairon.nanocorp.app` renvoie `HTTP/2 200` apres push.

## Implémentation: agents Reddit / Hacker News / News / Twitter fallback (2026-04-27)

### Fichiers modifiés

- `agents/types.ts` — format `ScrapedArticle` aligné sur les champs attendus (`source`, `country`, `tags`, `lang`, `published_at` non optionnel, `content` nullable).
- `agents/base-agent.ts` — helpers normalisés pour états `success`, `failed`, `idle`.
- `agents/rss_agent.ts` — refactor pour utiliser les helpers communs et retourner le format d’article complet.
- `agents/reddit_agent.ts` — implémentation réelle Reddit avec tentative JSON `Kairos/1.0` puis fallback RSS Atom public si le JSON est bloqué.
- `agents/forum_agent.ts` — implémentation Hacker News RSS + HNRSS keyword feed.
- `agents/news_agent.ts` — implémentation RSS news générique pour sources premium publiques.
- `agents/twitter_agent.ts` — implémentation Nitter RSS best effort, sinon retour `idle` propre sans bloquer le pipeline.
- `lib/feed.ts` — lecture améliorée des attributs Atom (`@_term`, `@_label`) pour tags/subreddits.
- `lib/source-agent.ts` — nouveau module commun: fetch avec timeout 10s, normalisation d’articles, mapping feed→articles, détection de pages de protection.
- `config/countries.json` — ajout de sources `news`, `reddit` et `forum` exploitables, surtout pour la France.
- `services/scrape-france.ts` — scrape France généralisé à tous les types d’agents actifs; le job global reste `success` tant qu’au moins une source aboutit.

### Sources activées

- France:
- `news`: Le Monde, Les Echos, BFM Business
- `reddit`: `r/france`, `r/economics`
- `forum`: Hacker News top, HNRSS `economics`
- United States:
- `reddit`: `r/investing`
- `forum`: Hacker News top, HNRSS `economics`
- `news`: Bloomberg Markets
- Japan:
- `news`: The Japan Times
- `reddit`: `r/japannews`
- `forum`: HNRSS `japan`

### Détails d’implémentation

- Tous les fetch agents passent par un timeout de `10_000 ms`.
- `RedditAgent` envoie `User-Agent: Kairos/1.0` sur le JSON Reddit; comme l’environnement courant reçoit encore du `403` HTML, l’agent bascule automatiquement sur `https://www.reddit.com/r/<subreddit>/.rss`, qui répond correctement.
- `TwitterAgent` essaie plusieurs instances Nitter publiques et renvoie `status: "idle"` avec une note explicite si aucune instance n’est lisible; il n’émet pas d’erreur bloquante.
- `services/scrape-france.ts` ne limite plus la collecte aux seules sources `rss`; il utilise `getAgentForType(source.type)` pour tous les types actifs.
- Le statut du `scrape_job` n’est plus dégradé à `failed` pour un simple échec partiel de source. Il passe à `failed` seulement si toutes les sources actives échouent.

### Vérification

- `npm run build` passe.
- `npm run lint` passe avec 2 warnings préexistants hors périmètre:
- `app/api/scenarios/[tree_id]/path/[path_id]/route.ts` — import inutilisé `getScenarioNodes`
- `lib/scenarios.ts` — variable inutilisée `analogies`
- Vérification runtime locale via `next dev` + `POST /api/scrape/france`:
- 1er appel: `{"articles_collected":122,"sources_scraped":14,"sources_failed":2,"sources_idle":0}`
- 2e appel: `{"articles_collected":0,"sources_scraped":14,"sources_failed":2,"sources_idle":0,"job_status":"success"}` (doublons ignorés par `ON CONFLICT (url) DO NOTHING`)
- Vérification SQL sur les articles FR insérés dans les 5 dernières minutes après le 1er scrape:
- `forum|Hacker News Economics|19`
- `forum|Hacker News Top|30`
- `news|BFM Business|26`
- `news|Le Monde|19`
- `news|Les Echos|20`
- `reddit|Reddit Economics|25`
- plus les sources RSS historiques (`20 Minutes`, `BFM TV`, `France Info`, `Le Figaro`, `Libération`, `Mediapart`)

### Limites constatées

- Reddit JSON public renvoie `403` HTML depuis cet environnement malgré le `User-Agent`; le fallback RSS couvre néanmoins le besoin fonctionnel.
- Les feeds demandés Reuters/AP n’ont pas été ajoutés en sources actives faute d’endpoint RSS public fiable et lisible depuis cet environnement au moment du test.
- L’instance `nitter.net` répond vide et plusieurs autres instances publiques testées renvoient une page de challenge ou une erreur réseau; le fallback `idle` reste donc le comportement le plus robuste pour `TwitterAgent`.

## Exploration: agents sources gratuits et pipeline de scrape (2026-04-27)

### Constat d'exploration

- `DOCS.md` existait déjà et a été relu avant toute nouvelle exploration, conformément aux consignes du dépôt.
- Les 4 agents `agents/reddit_agent.ts`, `agents/forum_agent.ts`, `agents/news_agent.ts` et `agents/twitter_agent.ts` sont encore des stubs locaux et publics; la vérification sur `raw.githubusercontent.com/ThomasHeran/kairos/main/...` retourne les mêmes placeholders.
- `agents/rss_agent.ts` est la seule implémentation réelle d'agent; elle s'appuie sur `lib/feed.ts` pour parser RSS/Atom/RDF via `fast-xml-parser` et `he`.
- `agents/types.ts` expose actuellement un `ScrapedArticle` minimal (`title`, `content?`, `url`, `published_at?`, `lang?`, `tags?`) qui ne couvre pas encore `source` ni `country`.
- `services/scrape-france.ts` contourne le registry d'agents et instancie directement `RSSAgent`; le endpoint `POST /api/scrape/france` scrape donc seulement les sources `type === "rss"` malgré l'existence des autres types dans le système.
- `scheduler/orchestrator.ts` utilise bien `getAgentForType`, mais ne persiste rien en base; il sert surtout de vue d'ensemble sur le registry.
- `config/countries.json` contient aujourd'hui:
- France: uniquement des sources `rss`.
- United States: `rss`, `reddit`, `forum`.
- Japan: `rss`, `news`, `twitter` inactif.
- `db/schema.sql` stocke déjà `title`, `content`, `url`, `published_at`, `lang`, `tags`, `source_id`, `country_id`; aucun changement de schéma n'est nécessaire pour brancher les nouveaux agents.
- `node_modules/next/dist/docs/01-app/01-getting-started/15-route-handlers.md` a été relu après `npm ci`; la version locale confirme que les Route Handlers App Router utilisent les APIs Web `Request`/`Response`, que `POST` n'est pas caché par défaut, et que les handlers peuvent rester dynamiques via `dynamic = "force-dynamic"`.

## Homepage Redesign: Dynamic News Dashboard (2026-04-27)

### Files changed
- `app/page.tsx` — full rewrite as Client Component

### Features implemented
- `"use client"` directive + React hooks (`useState`, `useEffect`, `useCallback`)
- Header: "Kairos / Multi-Country News Intelligence Platform", live stats (countries, sources, articles), last-updated timestamp
- Dynamic fetch from `/api/countries` → country filter bar with emoji flags and source counts
- Dynamic fetch from `/api/news?country=XX` → news article feed sorted by recency
- Article cards: title (linked), source name, flag, time-ago, release_type badge, excerpt
- Loading spinners for countries, articles, scrape operation
- Error state and empty state with contextual guidance
- Manual "Scrape Now" button → `POST /api/scrape/france` → auto-refresh
- Staggered card entrance animations; hover interactions
- Preserves existing CSS design system (CSS variables, `.grid-panel`, `.eyebrow`, Tailwind v4)
- `npm run build` passes cleanly (16 routes, 0 errors)
- Pushed to `nanocorp-hq/kairon` main and force-pushed to `ThomasHeran/kairos` main
- Vercel live URL returns HTTP 200 ✓

---

## Diagnosis: Kairos live deployment "inutilisable" (2026-04-27)

### Investigation Summary

**Live URL**: https://kairos-7b20lwqwt-thomasherans-projects.vercel.app/
- HTTP status: 401
- Response: Vercel SSO Authentication wall (redirects to `vercel.com/sso-api`)
- `/api/health`, `/api/countries`, `/api/news` all return 401 for the same reason

**Root Cause: Vercel Deployment Protection is ON**

The 401 is NOT a code error — it's Vercel's built-in Deployment Protection feature. Any visitor who is not logged into a Vercel account authorized for ThomasHeran's project sees the SSO gate instead of the actual page.

**Code audit result: HEALTHY**
- `ThomasHeran/kairos` cloned and compared against `nanocorp-hq/kairon` — repos are essentially identical (same code)
- `app/page.tsx` uses only static config (`getActiveCountries()` from `lib/config.ts`) — no DB dependency, no async crash
- All `app/api/` routes correctly import from `@/services/` (the prior `/api/` → `/services/` rename is fully applied)
- `app/layout.tsx` is valid; `globals.css` uses Tailwind v4 with all CSS variables and custom classes defined
- Local `npm run build` passes cleanly: 16 routes, 0 errors, `/` statically pre-rendered

**Fix required**: ThomasHeran must go to his Vercel Dashboard → Project Settings → Deployment Protection → Disable protection (or set to "Vercel Authentication" only for preview URLs, not all deployments).

**No code changes are needed.** The app is correct and will work once the Vercel protection is disabled.

---

## Fix Vercel build collision: /api/ → /services/ (2026-04-27)

### Root Cause

The project had a top-level `/api/` directory containing business logic modules (`news.ts`, `health.ts`, `countries.ts`, `scrape-france.ts`, `scrape-macro.ts`). Vercel auto-detects any top-level `/api/*.ts` files as serverless Functions. Since Next.js App Router also builds `app/api/**` routes as Functions, Vercel tried to create `.vc-config.json` for the same path twice → build collision.

### Fix

- Renamed `/api/` → `/services/` (business logic modules; Vercel ignores this directory)
- Updated all 7 route files in `app/api/` to import from `@/services/` instead of `@/api/`
- `npm run build` passes cleanly: 16 App Router routes, 0 collision
- Committed as `b6455f7`, pushed to `main`

---

# DOCS

## Fix commit author email on ThomasHeran/kairos (2026-04-27)

### Exploration

- Repo cible cloné séparément dans `/tmp/kairos-history-fix.iLcnV9/repo` pour éviter toute modification du dépôt NanoCorp local.
- Le dépôt `ThomasHeran/kairos` ne contient qu'une seule branche distante active: `main`.
- L'historique inspecté au départ contenait un seul commit avec l'email invalide `thomas@kairos.ai`, et ce commit était le `HEAD` de `main`: `d7dc87921b75d7e427e64c6e8ee43f9394182701`.
- Tous les autres commits récents utilisaient déjà des adresses `noreply` GitHub ou `users.noreply.github.com`; aucun autre commit n'utilisait `thomas@kairos.ai`.
- Comme le seul commit fautif était le dernier commit de `main`, une réécriture ciblée par `git commit --amend` suffisait et évitait une réécriture complète et inutile de tout l'historique.

### Changements réalisés

- Réécriture du commit `HEAD` en conservant le contenu et le message, avec auteur et committer définis sur `ThomasHeran <thomas_heran@hotmail.fr>`.
- Nouveau SHA du commit de tête après réécriture: `b13f63f126e840890b882ca328a85caadfc6431e`.
- Force-push exécuté avec succès sur `origin/main`: `d7dc879...b13f63f main -> main (forced update)`.
- Vérification faite sur un clone frais `/tmp/kairos-verify.3PlviP/repo`:
- `git log --format='%ae' | head -5` commence bien par `thomas_heran@hotmail.fr`.
- `git log --all --format='%H %ae %ce' | grep 'thomas@kairos.ai'` ne retourne aucun résultat.
- Le commit réécrit visible à distance est bien `b13f63f126e840890b882ca328a85caadfc6431e ThomasHeran <thomas_heran@hotmail.fr>`.

## Re-push vers ThomasHeran/kairos (2026-04-27)

### Exploration

- La branche locale active est `main`, propre et alignée sur `origin/main` au moment de l'inspection.
- Le remote existant observé avant transfert est uniquement `origin -> git@github.com:nanocorp-hq/kairon.git`.
- Le HEAD local inspecté avant le nouveau push est `feb53c3` (`docs: add git transfer diagnostic`).
- Le commit métier de référence demandé dans la tâche (`b90f058` — `feat: add C3 knowledge base v1 seed`) est bien présent dans l'historique récent.
- Les dossiers/fichiers majeurs confirmés dans le repo incluent `agents/`, `api/`, `app/`, `config/`, `db/`, `docs/`, `engine/`, `lib/`, `scheduler/`, `scripts/`, `package.json`, `next.config.ts` et `README.md`.
- Les artefacts métier attendus sont bien présents côté repo worker: `config/taxonomy_v1.json`, `config/knowledge_base_v1.json`, `db/schema_v2.sql`, `db/seed_knowledge_base_v1.sql`, `scripts/generate_knowledge_base_v1.py`, `engine/scenario_tree_engine.py`.
- Divergences constatées par rapport à la structure cible fournie dans la tâche:
- `docs/event_driver_lookup.json` existe, mais pas `config/event_driver_lookup.json`.
- Il n'existe pas de dossier `pipeline/` autonome; la logique C2 vit principalement dans `lib/qualify.ts`, `docs/classification_prompt_v1.md` et les routes/services associés.

### Changements réalisés

- Ajout de cette note d'exécution dans `DOCS.md` pour tracer l'inventaire du repo et l'opération de transfert vers `ThomasHeran/kairos`.
- Remote `thomas` ajouté sur `https://github.com/ThomasHeran/kairos.git`.
- Push tenté via `git push thomas main` puis vérification SSH directe; les deux ont échoué faute d'authentification/autorisation sur le repo privé cible.
- Archive de fallback créée avec l'état courant du dépôt: `/home/worker/kairos_thomasheran_export_2026-04-27.tar.gz`.
- Taille observée de l'archive de fallback: `281K`.
- SHA256 de l'archive de fallback: `013fcd4946367ad178e088c8bb66bbd75f248f28cb31badebd1d59350d9eb0f2`.

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

---

## FIX CRITIQUE — /api/scrape/france + persistance DB + migrate schema (2026-04-27)

### Fichiers modifiés

- `app/api/scrape/france/route.ts` — response format changed to `{ success: true, count: N, sources_scraped: N }`
- `app/api/scrape/all/route.ts` — NEW: calls `scrapeFranceRssFeeds()` + `scrapeMacroGlobalSources()` in parallel, returns `{ success, count, breakdown: { france, macro } }`
- `scheduler/orchestrator.ts` — rewritten to call service functions with DB persistence; returns `{ total_articles_persisted, results: { france, macro } }`
- `scripts/migrate.ts` — added `schema_scenario_v1.sql` to migrations list with idempotent guard (skips if `scenario_trees` table already exists)

### Statut après fix

| Route | Méthode | État |
|-------|---------|------|
| `POST /api/scrape/france` | POST | ✅ retourne `{ success: true, count: N }` |
| `POST /api/scrape/all` | POST | ✅ NEW — orchestre FR + macro en parallèle |
| `POST /api/scrape/macro-global` | POST | ✅ inchangé |
| `npm run db:migrate` | CLI | ✅ inclut désormais `schema_scenario_v1.sql` |
| `orchestrateScrapeCycle()` | CLI | ✅ persiste en DB via services |

### Notes

- `DATABASE_URL` est configuré sur Vercel (vérifié via `nanocorp vercel env list`)
- `schema_scenario_v1.sql` tables (`scenario_trees`, etc.) étaient déjà présentes en DB — le guard de migration les skip correctement
- Build: 17 routes, 0 erreurs

---

## AUDIT COMPLET — État du code Kairos (2026-04-27)

> **Source auditée :** Clone HTTPS de `https://github.com/ThomasHeran/kairos` (branch `main`)
> **Objectif :** Audit lecture seule pour planifier la réécriture du pipeline scraping + analyse.

---

### 1. Arbre des fichiers

```
kairos/
├── agents/
│   ├── base-agent.ts          ← Classe abstraite BaseSourceAgent
│   ├── forum_agent.ts         ← STUB
│   ├── index.ts               ← Registre des agents (registry)
│   ├── news_agent.ts          ← STUB (aussi pour scraping + api)
│   ├── reddit_agent.ts        ← STUB
│   ├── rss_agent.ts           ← ✅ IMPLÉMENTÉ
│   ├── twitter_agent.ts       ← STUB
│   └── types.ts               ← Types TS
├── app/api/
│   ├── analyze/scenarios/route.ts       ← POST /api/analyze/scenarios
│   ├── countries/route.ts               ← GET /api/countries
│   ├── events/route.ts                  ← GET /api/events
│   ├── health/route.ts                  ← GET /api/health
│   ├── news/route.ts                    ← GET /api/news
│   ├── news/[country]/route.ts          ← GET /api/news/:country
│   ├── qualify/route.ts                 ← POST /api/qualify
│   ├── qualify/batch/route.ts           ← POST /api/qualify/batch
│   ├── scenarios/[tree_id]/route.ts     ← GET /api/scenarios/:tree_id
│   ├── scenarios/[tree_id]/consensus/   ← GET /api/scenarios/:tree_id/consensus
│   ├── scenarios/[tree_id]/path/[path_id]/ ← GET /api/scenarios/:tree_id/path/:path_id
│   ├── scrape/france/route.ts           ← POST /api/scrape/france ✅
│   ├── scrape/macro-global/route.ts     ← POST /api/scrape/macro-global ✅
│   └── scrape/macro/[source_id]/route.ts ← POST /api/scrape/macro/:source_id ✅
├── config/
│   ├── countries.json          ← 3 pays : FR(8), US(3), JP(3)
│   ├── macro-sources.ts        ← 9 sources macro institutionnelles
│   ├── probability_calibrations_v1.json
│   ├── taxonomy_v1.json
│   └── knowledge_base_v1.json
├── db/
│   ├── schema.sql              ← v1 (countries, sources, articles, scrape_jobs)
│   ├── schema_v2.sql           ← v2 (events, taxonomy, drivers, causal_arcs, etc.)
│   ├── schema_v3.sql           ← v3 (ALTER TABLE migrations)
│   ├── schema_v4.sql           ← v4 (article_uuid, article_embeddings/pgvector, qualification)
│   ├── schema_scenario_v1.sql  ← scenario_trees, scenario_nodes, scenario_paths
│   └── seed_knowledge_base_v1.sql
├── engine/                     ← Moteur Python (NON appelé depuis Next.js)
│   ├── branch_generator.py
│   ├── probability_calibrator.py
│   ├── scenario_aggregator.py
│   ├── scenario_report_generator.py
│   └── scenario_tree_engine.py
├── lib/
│   ├── config.ts               ← Lecture countries.json
│   ├── db.ts                   ← Pool PostgreSQL (pg)
│   ├── feed.ts                 ← Parsing RSS/Atom (fast-xml-parser)
│   ├── openai.ts               ← Client OpenAI REST natif (fetch)
│   ├── qualify.ts              ← Pipeline C2 complet (embed + classify + dedup)
│   ├── scenarios.ts            ← Logique arbres de scénarios TS
│   └── taxonomy.ts             ← Lecture taxonomy_v1.json
├── scheduler/
│   ├── orchestrator.ts         ← orchestrateScrapeCycle() — NE persiste PAS en DB
│   └── run.ts                  ← CLI: tsx scheduler/run.ts
├── scripts/
│   └── migrate.ts              ← Applique schema.sql → schema_v4.sql (PAS scenario_v1)
└── services/
    ├── countries.ts, health.ts, news.ts
    ├── scrape-france.ts        ← ✅ RSS France + persist DB
    └── scrape-macro.ts         ← ✅ 9 sources macro + persist DB
```

---

### 2. État de chaque agent

| Agent | Source | Pays | Méthode | État |
|-------|--------|------|---------|------|
| `rss_agent.ts` | RSS/Atom | Multi | `fetch()` + fast-xml-parser | ✅ Implémenté |
| `reddit_agent.ts` | Reddit | US | — | ⚠️ Stub (placeholder, 0 articles) |
| `twitter_agent.ts` | Twitter/X | JP (désactivé) | — | ⚠️ Stub |
| `forum_agent.ts` | HN/Forums | US | — | ⚠️ Stub |
| `news_agent.ts` | Générique + scraping + api | Multi | — | ⚠️ Stub |

**Note critique :** `scraping` et `api` types sont mappés vers `NewsAgent` (stub) dans le registre. Ces types retournent `status: "idle"`, 0 articles.

---

### 3. État du scheduler

| Composant | État | Notes |
|-----------|------|-------|
| `orchestrator.ts` | ⚠️ Partiel | Scrape mais NE persiste PAS en DB — retourne JSON seulement |
| `run.ts` | ✅ CLI | `tsx scheduler/run.ts` — print JSON |
| Cron automatique | ❌ Manquant | Aucun trigger Vercel Cron configuré |

**Fonctionnement de l'orchestrateur :**
- Lit `getActiveCountries()` → countries.json (FR, US, JP)
- `Promise.all` sur toutes les sources actives par pays
- Dispatche vers l'agent selon `source.type`
- **Ne persiste PAS en DB** — retourne seulement métadonnées
- Pas d'endpoint API dédié — CLI uniquement (`npm run scheduler:run`)

---

### 4. API Routes — inventaire complet

| Route | Méthode | État | Notes |
|-------|---------|------|-------|
| `GET /api/health` | GET | ✅ | Statut DB + nb pays/sources |
| `GET /api/countries` | GET | ✅ | Lit countries.json (pas DB) |
| `GET /api/news` | GET | ✅ | Query DB, filtres: country, type, source, release_type |
| `GET /api/news/:country` | GET | ✅ | Articles par pays |
| `GET /api/events` | GET | ✅ | Events qualifiés C2 (filtres: limit, routing, cat_id) |
| `POST /api/scrape/france` | POST | ✅ | Scrape 8 RSS FR + insert DB |
| `POST /api/scrape/macro-global` | POST | ✅ | Scrape 9 sources institutionnelles |
| `POST /api/scrape/macro/:source_id` | POST | ✅ | Source individuelle |
| `POST /api/qualify` | POST | ✅ | Qualifie 1 article (nécessite OPENAI_API_KEY) |
| `POST /api/qualify/batch` | POST | ✅ | Batch articles pending |
| `POST /api/analyze/scenarios` | POST | ✅ | Génère arbre scénarios probabilistes |
| `GET /api/scenarios/:tree_id` | GET | ✅ | Lit arbre + nodes + paths depuis DB |
| `GET /api/scenarios/:tree_id/consensus` | GET | ✅ | Agrégat pondéré impacts actifs |
| `GET /api/scenarios/:tree_id/path/:path_id` | GET | ✅ | Détail d'un scénario |
| `/api/scrape/all` | — | ❌ N'existe pas | Pas de route "scrape tout" |

**`/api/scrape/france` détail :**
- Upsert country FR, crée scrape_job
- Scrape 8 flux RSS (Le Monde, Le Figaro, Libération, BFM TV, France Info, L'Équipe, 20 Minutes, Mediapart)
- Insert articles en DB (`ON CONFLICT (url) DO NOTHING`)
- Retourne `{ articles_collected, sources_scraped }`

---

### 5. Sources configurées

#### Sources pays — countries.json (11 actives + 1 inactive)

| ID | Nom | Type | Pays | Actif | Agent |
|----|-----|------|------|-------|-------|
| 101 | Le Monde | rss | FR | ✅ | RSSAgent ✅ |
| 102 | Le Figaro | rss | FR | ✅ | RSSAgent ✅ |
| 103 | Libération | rss | FR | ✅ | RSSAgent ✅ |
| 104 | BFM TV | rss | FR | ✅ | RSSAgent ✅ |
| 105 | France Info | rss | FR | ✅ | RSSAgent ✅ |
| 106 | L'Équipe | rss | FR | ✅ | RSSAgent ✅ |
| 107 | 20 Minutes | rss | FR | ✅ | RSSAgent ✅ |
| 108 | Mediapart | rss | FR | ✅ | RSSAgent ✅ (paywall probable) |
| 201 | New York Times RSS | rss | US | ✅ | RSSAgent ✅ |
| 202 | Reddit News | reddit | US | ✅ | RedditAgent ⚠️ STUB |
| 203 | Hacker News | forum | US | ✅ | ForumAgent ⚠️ STUB |
| 301 | NHK RSS | rss | JP | ✅ | RSSAgent ✅ |
| 302 | The Japan Times | news | JP | ✅ | NewsAgent ⚠️ STUB |
| 303 | NHK News X | twitter | JP | ❌ | TwitterAgent STUB |

#### Sources macro — macro-sources.ts (9 sources)

| ID | Nom | Authority | Mode | Zone |
|----|-----|-----------|------|------|
| fed | Federal Reserve | 0.99 | feed (RSS) | US |
| ecb | European Central Bank | 0.99 | feed (RSS, 3 URLs) | EZ |
| imf | International Monetary Fund | 0.98 | imf_news (HTML scraping) | GL |
| bis | Bank for International Settlements | 0.97 | feed (RSS) | GL |
| eurostat | Eurostat | 0.98 | feed (Atom custom) | EZ |
| oecd | OECD | 0.97 | oecd_rss (Cloudflare 403) | GL |
| bls | U.S. Bureau of Labor Statistics | 0.99 | bls_latest (parsing custom) | US |
| boe | Bank of England | 0.98 | feed (RSS) | UK |
| boj | Bank of Japan | 0.98 | feed (RSS) | JP |

---

### 6. Schéma de base de données

#### Tables principales

| Table | Colonnes clés | Migration |
|-------|--------------|-----------|
| `countries` | id, name, code_iso UNIQUE, region, active | schema.sql |
| `sources` | id, country_id FK, type CHECK, slug UNIQUE, url, name, active, last_scraped_at | schema.sql + v3 |
| `articles` | id, source_id FK, country_id FK, title, url UNIQUE, published_at, news_type, release_type, is_scheduled_release, authority_score, canonical JSONB, article_uuid UUID UNIQUE, qualification_status, qualified_event_id | schema.sql + v3 + v4 |
| `article_embeddings` | article_uuid PK FK, embedding `vector(1536)`, embedding_model, embedding_text_hash | schema_v4.sql |
| `scrape_jobs` | id, country_id FK, status (queued/running/success/failed), articles_count | schema.sql |
| `event_taxonomy` | cat_id + subtype_id PK, category, label_fr, subtype_label | schema_v2.sql (seeded, 101 entrées) |
| `events` | event_id UUID PK, raw_article_ids UUID[], cat_id+subtype_id FK, confidence, geography[], horizon, importance_score, routing (full_pipeline/archive), text_en_canonical | schema_v2.sql |
| `drivers` | driver_id PK, label_fr, label_en, category, unit | schema_v2.sql (seeded, 18-20 entrées) |
| `causal_arcs` | arc_id UUID PK, source_driver+target_driver FK drivers UNIQUE, direction ±1, intensity, intensity_coefficient, delay | schema_v2.sql |
| `event_driver_lookup` | cat_id+subtype_id PK FK taxonomy, primary_drivers[], driver_weights JSONB | schema_v2.sql |
| `historical_episodes` | episode_id UUID PK, cat_id+subtype_id FK, episode_date, driver_impacts JSONB, asset_outcomes JSONB | schema_v2.sql |
| `asset_sensitivity` | asset_id+driver_id PK, sensitivity [-1,1], direction, delay, asset_class | schema_v2.sql |
| `analyses` | analysis_id UUID PK, event_id FK, causal_paths JSONB, asset_scores JSONB, narrative | schema_v2.sql |
| `predictions` | prediction_id UUID PK, analysis_id FK, status, prediction_snapshot JSONB, reality_data JSONB | schema_v2.sql |
| `feedback_records` | feedback_id UUID PK, prediction_id FK, arc_id FK, field_changed, old_value JSONB, new_value JSONB | schema_v2.sql |
| `probability_calibrations` | calibration_id UUID PK, bifurcation_id UNIQUE, cat_id, subtype_id, branches JSONB | schema_scenario_v1.sql |
| `scenario_trees` | tree_id UUID PK, event_id FK, total_scenarios, dominant_scenario, consensus_asset_impacts JSONB, uncertainty_flag | schema_scenario_v1.sql |
| `scenario_nodes` | node_id UUID PK, tree_id FK, parent_node_id FK, depth, probability, probability_cumulative, drivers_activated JSONB, asset_impacts JSONB, is_terminal | schema_scenario_v1.sql |
| `scenario_paths` | path_id+tree_id PK, probability_path, node_ids UUID[], terminal_asset_summary JSONB, narrative_terminal | schema_scenario_v1.sql |
| `scenario_revisions` | revision_id UUID PK, tree_id FK, node_id FK, old_probability, new_probability, revision_reason | schema_scenario_v1.sql |

**Statut migrations :**
- `migrate.ts` applique : schema.sql → schema_v2.sql → schema_v3.sql → schema_v4.sql ✅
- `schema_scenario_v1.sql` ❌ **NON inclus dans migrate.ts** — doit être appliqué manuellement

---

### 7. Services (`services/`)

| Fichier | Fonctions | État | Notes |
|---------|-----------|------|-------|
| `countries.ts` | `listCountries()` | ✅ | Lit countries.json (pas DB) |
| `health.ts` | `getHealthPayload()` | ✅ | Test connexion DB + comptage |
| `news.ts` | `listNews(filters)` | ✅ | Query DB avec joins countries+sources |
| `scrape-france.ts` | `scrapeFranceRssFeeds()` | ✅ | Complet: upsert pays/sources/jobs/articles |
| `scrape-macro.ts` | `scrapeMacroSource(id)`, `scrapeMacroGlobalSources()` | ✅ | 4 modes: feed, imf_news, bls_latest, oecd_rss |

---

### 8. Dépendances (`package.json`)

| Lib | Version | Rôle |
|-----|---------|------|
| `fast-xml-parser` | ^5.5.12 | Parsing RSS/Atom XML |
| `he` | ^1.2.0 | Décodage HTML entities |
| `pg` | ^8.16.3 | Client PostgreSQL |
| `next` | 16.2.3 | Framework Web |
| `react` | 19.2.4 | UI |
| `tsx` | ^4.21.0 | CLI TypeScript (scheduler) |

**Absences notables :**
- ❌ Pas d'OpenAI SDK (`openai` npm) — client REST natif via `lib/openai.ts`
- ❌ Pas de Puppeteer — pas de scraping headless browser
- ❌ Pas de Cheerio — scraping HTML via regex uniquement (IMF, BLS)
- ❌ Pas d'Axios — fetch natif uniquement
- ❌ Pas de rss-parser — fast-xml-parser
- ❌ Pas de librairie NLP — classification via GPT-4o-mini (REST)
- pgvector : en DB mais manipulé comme texte `[x,y,z,...]` côté JS

---

### 9. Points bloquants identifiés

1. **`DATABASE_URL` manquant** → Tout `/api/scrape/*` et `/api/qualify/*` échouent. Vérifier config Vercel.

2. **`OPENAI_API_KEY` manquant** → C2 qualification dégrade vers heuristiques (embeddings locaux SHA256 + règles). Pas de classification LLM réelle.

3. **`pgvector` extension requise** → schema_v4.sql `CREATE EXTENSION IF NOT EXISTS vector`. Si non installé, migration échoue.

4. **`schema_scenario_v1.sql` absent de `migrate.ts`** → Tables `scenario_trees`, `scenario_nodes`, `scenario_paths`, `probability_calibrations`, `scenario_revisions` non créées automatiquement. L'API `/api/analyze/scenarios` crashera si ces tables manquent.

5. **Agents stubs (reddit, forum, twitter, news)** → Sources US (Reddit News, Hacker News) et JP (Japan Times) retournent 0 articles. Seul RSSAgent est fonctionnel.

6. **Scheduler ne persiste pas en DB** → `orchestrator.ts` scrape mais ne sauvegarde pas. La persistance est accessible uniquement via les routes API POST.

7. **Pas de cron automatique** → Aucun Vercel Cron Job configuré. Les scraping sont manuels uniquement.

8. **Mediapart paywall** → flux RSS probablement vide ou 403 sans abonnement.

9. **OECD source en 403** → Cloudflare challenge, source toujours en échec.

---

### 10. Recommandations pipeline complet

**Priorité 1 — Bloquants infrastructuraux**
1. Configurer `DATABASE_URL` (PostgreSQL + pgvector) sur Vercel
2. Configurer `OPENAI_API_KEY` sur Vercel
3. Appliquer `schema_scenario_v1.sql` manuellement (`psql $DATABASE_URL < db/schema_scenario_v1.sql`)
4. Ajouter `schema_scenario_v1.sql` dans `scripts/migrate.ts`
5. Configurer Vercel Cron : `/api/scrape/france` toutes les heures, `/api/scrape/macro-global` toutes les 4h, `/api/qualify/batch` toutes les 2h

**Priorité 2 — Compléter les agents stubs**
6. RedditAgent → utiliser le JSON feed (`/r/news.json`) sans auth
7. ForumAgent (HN) → HN RSS public fonctionnel avec RSSAgent
8. NewsAgent (Japan Times) → RSS standard

**Priorité 3 — Connecter le scheduler à la DB**
9. Refactoriser `orchestrator.ts` pour appeler les services de persistance, ou déclencher les routes API

**Priorité 4 — Couverture géographique**
10. Ajouter pays manquants : DE, UK, CN, IN, BR dans countries.json
11. Ajouter sources macro : PBOC, Bundesbank, RBA, BoC

**Priorité 5 — Pipeline C3/C4/C5**
12. Ajouter routes API pour les causal_arcs (C3)
13. Implémenter les routes pour valider les prédictions (C5) et déclencher les recalibrations
