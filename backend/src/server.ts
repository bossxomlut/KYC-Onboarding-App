import { loadConfig } from "./config.js";
import { createPool } from "./database.js";
import { buildApp } from "./app.js";

const config = loadConfig();
const pool = createPool(config.databaseUrl);
const app = await buildApp(config, pool);
try {
  await app.listen({ host: config.host, port: config.port });
  console.log(`KYC API listening on ${config.host}:${config.port}`);
} catch {
  await pool.end();
  console.error(
    "API could not start. Check port, configuration and database availability.",
  );
  process.exitCode = 1;
}
for (const signal of ["SIGINT", "SIGTERM"] as const)
  process.once(signal, async () => {
    await app.close();
    await pool.end();
    process.exit(0);
  });
