import { getActiveCountries } from "@/lib/config";

export async function listCountries() {
  return getActiveCountries().map((country) => ({
    id: country.id,
    name: country.name,
    code_iso: country.code_iso,
    region: country.region,
    active: country.active,
    sources_count: country.sources.filter((source) => source.active).length,
  }));
}
