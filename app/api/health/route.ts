import { getHealthPayload } from "@/services/health";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const payload = await getHealthPayload();

  return Response.json(payload, { status: 200 });
}
