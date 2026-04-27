import { listQualifiedEvents } from "@/lib/qualify";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const limitValue = url.searchParams.get("limit");
    const routing = url.searchParams.get("routing");
    const catId = url.searchParams.get("cat_id");
    const limit = limitValue ? Number.parseInt(limitValue, 10) : undefined;

    const result = await listQualifiedEvents({
      limit: Number.isFinite(limit) ? limit : undefined,
      routing: routing === "full_pipeline" || routing === "archive" ? routing : undefined,
      cat_id: catId ?? undefined,
    });

    return Response.json(result);
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}
