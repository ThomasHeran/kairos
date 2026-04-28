import { after } from "next/server";

import { scrapeFranceRssFeeds } from "@/services/scrape-france";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

async function triggerAnalyzeBatch(origin: string) {
  try {
    await fetch(`${origin}/api/analyze?limit=20`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-kairos-trigger": "post-scrape",
      },
      cache: "no-store",
    });
  } catch (error) {
    console.warn(
      JSON.stringify({
        scope: "pipeline",
        level: "warn",
        event: "post_scrape_analyze_trigger_failed",
        error: error instanceof Error ? error.message : "Unknown trigger error",
      }),
    );
  }
}

export async function POST(request: Request) {
  try {
    const payload = await scrapeFranceRssFeeds();
    const origin = new URL(request.url).origin;

    after(async () => {
      await triggerAnalyzeBatch(origin);
    });

    return Response.json(
      {
        success: true,
        count: payload.articles_collected,
        sources_scraped: payload.sources_scraped,
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
