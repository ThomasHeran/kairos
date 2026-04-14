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
