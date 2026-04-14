# Kairos / Kairon

Squelette Next.js pour une plateforme de collecte mondiale de news, organisée par pays et par source.

## Stack

- Next.js App Router + TypeScript + Tailwind CSS
- PostgreSQL / Neon via `DATABASE_URL`
- API REST exposée sous `app/api/*`
- Architecture de collecte modulaire via `agents/` et `scheduler/`

## Commandes

```bash
npm install
npm run dev
npm run db:migrate
npm run scheduler:run
npm run build
```

## Endpoints

- `GET /api/health`
- `GET /api/countries`
- `GET /api/news`
- `GET /api/news/:country`

## Structure

- `app/` UI et routes API Next.js
- `api/` logique métier des endpoints
- `agents/` agents par type de source
- `config/countries.json` pays + sources de départ
- `db/schema.sql` schéma PostgreSQL
- `scheduler/` orchestration des cycles de scraping
- `scripts/migrate.ts` application reproductible du schéma

## Notes

- `/api/countries` lit la configuration déclarative actuelle.
- `/api/news` lit les articles en base si `DATABASE_URL` est disponible.
- Les agents sont volontairement des placeholders prêts à recevoir la logique de scraping réelle.
