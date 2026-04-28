import { scrapeFranceRssFeeds } from "@/services/scrape-france";
import { scrapeMacroGlobalSources } from "@/services/scrape-macro";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST() {
  try {
    const [franceResult, macroResult] = await Promise.allSettled([
      scrapeFranceRssFeeds(),
      scrapeMacroGlobalSources(),
    ]);

    const france =
      franceResult.status === "fulfilled"
        ? { success: true, count: franceResult.value.articles_collected, sources_scraped: franceResult.value.sources_scraped }
        : { success: false, error: franceResult.reason instanceof Error ? franceResult.reason.message : String(franceResult.reason) };

    const macro =
      macroResult.status === "fulfilled"
        ? { success: true, count: macroResult.value.articles_collected, sources_scraped: macroResult.value.sources_attempted }
        : { success: false, error: macroResult.reason instanceof Error ? macroResult.reason.message : String(macroResult.reason) };

    const totalCount = (france.success ? (france as { count: number }).count : 0) + (macro.success ? (macro as { count: number }).count : 0);

    return Response.json(
      {
        success: true,
        count: totalCount,
        breakdown: { france, macro },
      },
      { status: 200 },
    );
  } catch (error) {
    return Response.json(
      {
        success: false,
        error: error instanceof Error ? error.message : "Unknown scrape error",
      },
      { status: 500 },
    );
  }
}
