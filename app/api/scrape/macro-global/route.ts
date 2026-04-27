import { scrapeMacroGlobalSources } from "@/api/scrape-macro";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST() {
  try {
    const payload = await scrapeMacroGlobalSources();
    return Response.json(payload, { status: 200 });
  } catch (error) {
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Unknown macro scrape error",
      },
      { status: 500 },
    );
  }
}
