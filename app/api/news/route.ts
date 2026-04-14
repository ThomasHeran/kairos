import { listNews } from "@/api/news";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const country = url.searchParams.get("country") ?? undefined;
  const payload = await listNews(country);

  return Response.json(payload);
}
