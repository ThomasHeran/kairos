import { qualifyPendingBatch } from "@/lib/qualify";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const { limit, country, force = false } = body as {
      limit?: number;
      country?: string;
      force?: boolean;
    };

    const result = await qualifyPendingBatch({ limit, country, force });
    return Response.json(result);
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Internal server error" },
      { status: 500 },
    );
  }
}
