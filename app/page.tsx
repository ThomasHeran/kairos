import { getActiveCountries } from "@/lib/config";

export default function Home() {
  const countries = getActiveCountries();
  const configuredSources = countries.reduce(
    (total, country) => total + country.sources.filter((source) => source.active).length,
    0,
  );

  return (
    <main className="mx-auto flex min-h-screen w-full max-w-7xl flex-col gap-10 px-6 py-8 md:px-10 md:py-12">
      <section className="grid-panel overflow-hidden rounded-[2rem] p-8 md:p-12">
        <div className="flex flex-col gap-8 md:flex-row md:items-end md:justify-between">
          <div className="max-w-3xl space-y-5">
            <p className="eyebrow">Kairos / Global News Intelligence</p>
            <h1 className="max-w-2xl text-4xl font-semibold tracking-tight md:text-6xl">
              Squelette multi-pays pour orchestrer des agents de collecte de news.
            </h1>
            <p className="max-w-2xl text-base leading-8 text-[var(--muted)] md:text-lg">
              Cette base prépare la collecte mondiale par pays, la coordination
              d&apos;agents par type de source et l&apos;exposition d&apos;une API REST
              simple branchée sur PostgreSQL / Neon.
            </p>
          </div>
          <div className="grid min-w-[260px] gap-3 font-mono text-sm">
            <div className="rounded-3xl border border-[var(--border)] bg-[var(--surface-strong)] px-5 py-4">
              <div className="eyebrow">Countries</div>
              <div className="mt-2 text-3xl font-medium">{countries.length}</div>
            </div>
            <div className="rounded-3xl border border-[var(--border)] bg-[var(--surface-strong)] px-5 py-4">
              <div className="eyebrow">Active Sources</div>
              <div className="mt-2 text-3xl font-medium">{configuredSources}</div>
            </div>
          </div>
        </div>
      </section>

      <section className="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
        <div className="grid-panel rounded-[1.75rem] p-7">
          <div className="eyebrow">Architecture</div>
          <div className="mt-4 grid gap-4 text-sm leading-7 text-[var(--muted)] md:grid-cols-2">
            <article className="rounded-3xl border border-[var(--border)] bg-[var(--surface-strong)] p-5">
              <h2 className="text-lg font-semibold text-[var(--foreground)]">
                Agents
              </h2>
              <p>
                `agents/` contient un agent par type de source (`rss`, `reddit`,
                `twitter`, `forum`, `news`) avec une interface commune prête pour
                le scraping réel.
              </p>
            </article>
            <article className="rounded-3xl border border-[var(--border)] bg-[var(--surface-strong)] p-5">
              <h2 className="text-lg font-semibold text-[var(--foreground)]">
                Scheduler
              </h2>
              <p>
                `scheduler/orchestrator.ts` répartit les sources actives par pays
                et délègue chaque collecte à l&apos;agent adapté.
              </p>
            </article>
            <article className="rounded-3xl border border-[var(--border)] bg-[var(--surface-strong)] p-5">
              <h2 className="text-lg font-semibold text-[var(--foreground)]">
                API
              </h2>
              <p>
                Les endpoints `GET /api/health`, `GET /api/countries`,
                `GET /api/news` et `GET /api/news/:country` utilisent App Router.
              </p>
            </article>
            <article className="rounded-3xl border border-[var(--border)] bg-[var(--surface-strong)] p-5">
              <h2 className="text-lg font-semibold text-[var(--foreground)]">
                Database
              </h2>
              <p>
                `db/schema.sql` et `scripts/migrate.ts` fournissent une mise en
                place reproductible du schéma PostgreSQL / Neon.
              </p>
            </article>
          </div>
        </div>

        <div className="grid gap-6">
          <section className="grid-panel rounded-[1.75rem] p-7">
            <div className="eyebrow">Configured Countries</div>
            <div className="mt-4 space-y-3">
              {countries.map((country) => (
                <article
                  key={country.code_iso}
                  className="rounded-3xl border border-[var(--border)] bg-[var(--surface-strong)] px-5 py-4"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <h2 className="text-lg font-semibold">{country.name}</h2>
                      <p className="mt-1 text-sm text-[var(--muted)]">
                        {country.region} • {country.code_iso}
                      </p>
                    </div>
                    <span className="rounded-full bg-[var(--accent-soft)] px-3 py-1 font-mono text-xs text-[var(--accent)]">
                      {country.sources.filter((source) => source.active).length} sources
                    </span>
                  </div>
                </article>
              ))}
            </div>
          </section>

          <section className="grid-panel rounded-[1.75rem] p-7">
            <div className="eyebrow">Endpoints</div>
            <div className="mt-4 space-y-3 font-mono text-sm">
              {[
                "/api/health",
                "/api/countries",
                "/api/news",
                "/api/news/fr",
              ].map((route) => (
                <div
                  key={route}
                  className="rounded-2xl border border-[var(--border)] bg-[var(--surface-strong)] px-4 py-3"
                >
                  {route}
                </div>
              ))}
            </div>
          </section>
        </div>
      </section>
    </main>
  );
}
