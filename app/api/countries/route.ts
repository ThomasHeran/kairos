import { listCountries } from "@/services/countries";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const countries = await listCountries();

  return Response.json({ countries, total: countries.length });
}
