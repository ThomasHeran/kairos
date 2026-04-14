import { getAgentForType } from "@/agents";
import { getActiveCountries } from "@/lib/config";

export async function orchestrateScrapeCycle() {
  const countries = getActiveCountries();

  const countryRuns = await Promise.all(
    countries.map(async (country) => {
      const activeSources = country.sources.filter((source) => source.active);

      const sources = await Promise.all(
        activeSources.map(async (source) => {
          const agent = getAgentForType(source.type);
          const result = await agent.scrape(country, source);

          return {
            source_id: source.id,
            source_name: source.name,
            type: source.type,
            status: result.status,
            articles_count: result.articles.length,
            notes: result.notes,
          };
        }),
      );

      return {
        country_id: country.id,
        country_code: country.code_iso,
        country_name: country.name,
        sources,
      };
    }),
  );

  return {
    launched_at: new Date().toISOString(),
    countries_count: countries.length,
    countries: countryRuns,
  };
}
