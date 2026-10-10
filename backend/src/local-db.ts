import EmbeddedPostgres from "embedded-postgres";
import { mkdir, access } from "node:fs/promises";
import { resolve, join } from "node:path";
import { createPool, migrate } from "./database.js";
import { createServer } from "node:net";

const directory = resolve(process.env.LOCAL_DATABASE_DIR ?? ".local/postgres");
const port = Number(process.env.LOCAL_DATABASE_PORT ?? 5432);
if (!Number.isInteger(port) || port < 1 || port > 65535)
  throw new Error("LOCAL_DATABASE_PORT must be a valid TCP port.");
// Fail before spawning a child when another database already owns the port.
await new Promise<void>((resolve, reject) => {
  const probe = createServer();
  probe.once("error", () =>
    reject(
      new Error(
        `Port ${port} is already in use. Stop the existing PostgreSQL process or choose LOCAL_DATABASE_PORT.`,
      ),
    ),
  );
  probe.listen(port, "127.0.0.1", () => probe.close(() => resolve()));
});
await mkdir(directory, { recursive: true, mode: 0o700 });
const postgres = new EmbeddedPostgres({
  databaseDir: directory,
  port,
  user: "kyc",
  password: "local-development-only",
  persistent: true,
  authMethod: "scram-sha-256",
  initdbFlags: ["--encoding=UTF8"],
  postgresFlags: ["-h", "127.0.0.1", "-c", "log_statement=none"],
  onLog: () => {},
  onError: () => {
    console.error(
      "Local PostgreSQL reported an error. Check whether its port is already in use.",
    );
  },
});
try {
  try {
    await access(join(directory, "PG_VERSION"));
  } catch {
    await postgres.initialise();
  }
  await postgres.start();
  const pool = createPool(
    `postgresql://kyc:local-development-only@localhost:${port}/postgres`,
  );
  const existing = await pool.query(
    "SELECT 1 FROM pg_database WHERE datname='kyc'",
  );
  if (!existing.rowCount) await pool.query("CREATE DATABASE kyc");
  await pool.end();
  const appPool = createPool(
    `postgresql://kyc:local-development-only@localhost:${port}/kyc`,
  );
  await migrate(appPool);
  await appPool.end();
  console.log(
    `Local PostgreSQL is ready on 127.0.0.1:${port}; database kyc. Keep this terminal running.`,
  );
} catch {
  console.error(
    "Unable to start local PostgreSQL. Check port availability and PostgreSQL binary support.",
  );
  process.exitCode = 1;
  await postgres.stop();
}
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.once(signal, async () => {
    await postgres.stop();
    process.exit(0);
  });
