import { listNews } from "@/services/news";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const payload = await listNews({
    country: url.searchParams.get("country") ?? undefined,
    type: url.searchParams.get("type") ?? undefined,
    source: url.searchParams.get("source") ?? undefined,
    release_type: url.searchParams.get("release_type") ?? undefined,
  });

  return Response.json(payload);
}
