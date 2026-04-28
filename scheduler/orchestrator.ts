import { scrapeFranceRssFeeds } from "@/services/scrape-france";
import { scrapeMacroGlobalSources } from "@/services/scrape-macro";

export async function orchestrateScrapeCycle() {
  const launchedAt = new Date().toISOString();

  const [franceResult, macroResult] = await Promise.allSettled([
    scrapeFranceRssFeeds(),
    scrapeMacroGlobalSources(),
  ]);

  const france =
    franceResult.status === "fulfilled"
      ? {
          status: "success",
          articles_collected: franceResult.value.articles_collected,
          sources_scraped: franceResult.value.sources_scraped,
        }
      : {
          status: "failed",
          error: franceResult.reason instanceof Error ? franceResult.reason.message : String(franceResult.reason),
        };

  const macro =
    macroResult.status === "fulfilled"
      ? {
          status: "success",
          articles_collected: macroResult.value.articles_collected,
          sources_attempted: macroResult.value.sources_attempted,
          sources_succeeded: macroResult.value.sources_succeeded,
          sources_failed: macroResult.value.sources_failed,
        }
      : {
          status: "failed",
          error: macroResult.reason instanceof Error ? macroResult.reason.message : String(macroResult.reason),
        };

  const totalArticles =
    (franceResult.status === "fulfilled" ? franceResult.value.articles_collected : 0) +
    (macroResult.status === "fulfilled" ? macroResult.value.articles_collected : 0);

  return {
    launched_at: launchedAt,
    finished_at: new Date().toISOString(),
    total_articles_persisted: totalArticles,
    results: { france, macro },
  };
}
