import { listNews } from "@/api/news";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const payload = await listNews();

  return Response.json(payload);
}
