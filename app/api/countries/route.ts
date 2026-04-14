import { listCountries } from "@/api/countries";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET() {
  const countries = await listCountries();

  return Response.json({ countries, total: countries.length });
}
