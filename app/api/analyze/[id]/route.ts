import { analyzeArticleById } from "@/services/pipeline/analyze";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{ id: string }>;
};

export async function POST(_request: Request, context: RouteContext) {
  try {
    const { id } = await context.params;
    const articleId = Number.parseInt(id, 10);

    if (Number.isNaN(articleId)) {
      return Response.json({ error: "Invalid article id" }, { status: 400 });
    }

    const article = await analyzeArticleById(articleId);

    if (!article) {
      return Response.json({ error: "Article not found" }, { status: 404 });
    }

    return Response.json({ analyzed: 1, errors: 0, article }, { status: 200 });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}
