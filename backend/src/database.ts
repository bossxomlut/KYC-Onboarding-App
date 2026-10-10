import { Pool, type PoolClient } from "pg";
import { readFile, readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

export function createPool(databaseUrl: string) {
  return new Pool({
    connectionString: databaseUrl,
    max: 10,
    connectionTimeoutMillis: 5000,
    idleTimeoutMillis: 30000,
  });
}
export async function transaction<T>(
  pool: Pool,
  operation: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await operation(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
export async function migrate(pool: Pool) {
  const directory = fileURLToPath(new URL("../migrations/", import.meta.url));
  await transaction(pool, async (client) => {
    await client.query("SELECT pg_advisory_xact_lock(784325191)");
    await client.query(
      "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())",
    );
    const files = (await readdir(directory))
      .filter((name) => name.endsWith(".sql"))
      .sort();
    for (const file of files) {
      const existing = await client.query(
        "SELECT 1 FROM schema_migrations WHERE name=$1",
        [file],
      );
      if (existing.rowCount) continue;
      await client.query(await readFile(join(directory, file), "utf8"));
      await client.query("INSERT INTO schema_migrations(name) VALUES($1)", [
        file,
      ]);
    }
  });
}
