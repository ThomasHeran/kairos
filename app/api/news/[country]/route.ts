import { listNews } from "@/api/news";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type RouteContext = {
  params: Promise<{ country: string }>;
};

export async function GET(_request: Request, context: RouteContext) {
  const { country } = await context.params;
  const payload = await listNews({ country });

  return Response.json(payload);
}
