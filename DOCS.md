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
