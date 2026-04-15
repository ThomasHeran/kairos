import { readFile } from "node:fs/promises";
import path from "node:path";
import { Pool } from "pg";

async function main() {
  const connectionString = process.env.DATABASE_URL;

  if (!connectionString) {
    throw new Error("DATABASE_URL is not configured.");
  }

  const pool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },
  });

  const migrations = ["schema.sql", "schema_v2.sql"];

  try {
    for (const filename of migrations) {
      const schemaPath = path.join(process.cwd(), "db", filename);
      const schemaSql = await readFile(schemaPath, "utf8");
      await pool.query(schemaSql);
      console.log(`✓ ${filename} applied.`);
    }
    console.log("All migrations applied successfully.");
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
