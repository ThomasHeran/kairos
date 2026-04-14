import { countConfiguredSources, getActiveCountries } from "@/lib/config";
import { getDatabaseHealth } from "@/lib/db";

export async function getHealthPayload() {
  const database = await getDatabaseHealth();

  return {
    ok: true,
    service: "kairos-api",
    checked_at: new Date().toISOString(),
    countries_configured: getActiveCountries().length,
    sources_configured: countConfiguredSources(),
    database,
  };
}
