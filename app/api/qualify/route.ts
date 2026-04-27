import { qualifyStoredArticle } from "@/lib/qualify";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const { article_id, article_uuid, url, force = false } = body as {
      article_id?: number;
      article_uuid?: string;
      url?: string;
      force?: boolean;
    };

    if (article_id === undefined && !article_uuid && !url) {
      return Response.json(
        { error: "Provide article_id, article_uuid, or url." },
        { status: 400 },
      );
    }

    const result = await qualifyStoredArticle({
      article_id,
      article_uuid,
      url,
      force,
    });

    return Response.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Internal server error";
    const status = message === "Article not found" ? 404 : 500;

    return Response.json({ error: message }, { status });
  }
}
