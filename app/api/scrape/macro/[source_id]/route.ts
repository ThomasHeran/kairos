import { scrapeMacroSource } from "@/api/scrape-macro";
import { type MacroSourceId, getMacroSourceById } from "@/config/macro-sources";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{ source_id: string }>;
};

export async function POST(_request: Request, context: RouteContext) {
  const { source_id } = await context.params;

  if (!getMacroSourceById(source_id)) {
    return Response.json(
      {
        error: `Unknown macro source: ${source_id}`,
      },
      { status: 404 },
    );
  }

  const payload = await scrapeMacroSource(source_id as MacroSourceId);
  const statusCode = payload.status === "success" ? 200 : 502;

  return Response.json(payload, { status: statusCode });
}
