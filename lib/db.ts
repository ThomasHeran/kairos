import { Pool, type QueryResult, type QueryResultRow } from "pg";

declare global {
  var kairosPool: Pool | null | undefined;
}

function createPool() {
  if (!process.env.DATABASE_URL) {
    return null;
  }

  return new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
    max: 3,
  });
}

const pool = globalThis.kairosPool ?? createPool();

if (process.env.NODE_ENV !== "production") {
  globalThis.kairosPool = pool;
}

export function hasDatabaseUrl() {
  return Boolean(process.env.DATABASE_URL);
}

export async function query<T extends QueryResultRow>(
  text: string,
  params: unknown[] = [],
): Promise<QueryResult<T>> {
  if (!pool) {
    throw new Error("DATABASE_URL is not configured");
  }

  return pool.query<T>(text, params);
}

export async function getDatabaseHealth() {
  if (!pool) {
    return {
      configured: false,
      status: "missing_connection_string",
    };
  }

  try {
    await pool.query("SELECT 1");

    return {
      configured: true,
      status: "ok",
    };
  } catch (error) {
    return {
      configured: true,
      status: "unreachable",
      error: error instanceof Error ? error.message : "Unknown database error",
    };
  }
}
