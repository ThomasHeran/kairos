import { getHealthPayload } from "@/api/health";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const payload = await getHealthPayload();

  return Response.json(payload, { status: 200 });
}
