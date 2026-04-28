import { analyzePendingArticles, resolveAnalyzeLimit } from "@/services/pipeline/analyze";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const url = new URL(request.url);
    const limit = resolveAnalyzeLimit(url.searchParams.get("limit"));
    const result = await analyzePendingArticles(limit);

    return Response.json(result, { status: 200 });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}
