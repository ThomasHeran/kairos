import { scrapeFranceRssFeeds } from "@/services/scrape-france";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST() {
  try {
    const payload = await scrapeFranceRssFeeds();

    return Response.json(payload, { status: 200 });
  } catch (error) {
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Unknown scrape error",
      },
      { status: 500 },
    );
  }
}
