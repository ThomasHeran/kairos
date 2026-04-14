import countriesConfig from "@/config/countries.json";
import type { CountryConfig } from "@/agents/types";

type CountriesConfigFile = {
  countries: CountryConfig[];
};

const config = countriesConfig as CountriesConfigFile;

function normalizeCountrySlug(value: string) {
  return value.trim().toLowerCase();
}

export function getCountriesConfig() {
  return config.countries;
}

export function getActiveCountries() {
  return getCountriesConfig().filter((country) => country.active);
}

export function countConfiguredSources() {
  return getActiveCountries().reduce(
    (total, country) => total + country.sources.filter((source) => source.active).length,
    0,
  );
}

export function getCountryBySlug(slug: string) {
  const normalizedSlug = normalizeCountrySlug(slug);

  return getCountriesConfig().find((country) => {
    return (
      country.code_iso.toLowerCase() === normalizedSlug ||
      country.name.toLowerCase() === normalizedSlug
    );
  });
}
