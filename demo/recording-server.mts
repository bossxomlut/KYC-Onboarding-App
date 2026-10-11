/** An isolated real API/database for recording; never reads backend/.env. */
import { randomBytes, randomUUID } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildApp } from "../backend/src/app.js";
import { passwordHash } from "../backend/src/auth/password.js";
import type { Config } from "../backend/src/config.js";
import { createPool, migrate } from "../backend/src/database.js";

const demoDir = dirname(fileURLToPath(import.meta.url));
const scenario = JSON.parse(
  await readFile(join(demoDir, "scenario.json"), "utf8"),
);
if (
  scenario.syntheticOnly !== true ||
  !scenario.applicant.email.endsWith("@kyc.example") ||
  !scenario.reviewer.email.endsWith("@kyc.example")
) {
  throw new Error("Recording requires the synthetic demo scenario.");
}
const require = createRequire(
  new URL("../backend/package.json", import.meta.url),
);
const { default: EmbeddedPostgres } = await import(
  require.resolve("embedded-postgres")
);
const runtime = join(demoDir, ".runtime");
await mkdir(runtime, { recursive: true, mode: 0o700 });
const directory = await mkdtemp(join(runtime, "recording-"));
const postgres = new EmbeddedPostgres({
  databaseDir: join(directory, "postgres"),
  port: 55462,
  user: "postgres",
  password: "isolated-demo-only",
  persistent: false,
  initdbFlags: ["--encoding=UTF8"],
  postgresFlags: ["-h", "127.0.0.1", "-c", "log_statement=none"],
  onLog: () => {},
  onError: () => {},
});
let pool: ReturnType<typeof createPool> | undefined;
let app: Awaited<ReturnType<typeof buildApp>> | undefined;
let stopping = false;
async function stop() {
  if (stopping) return;
  stopping = true;
  await app?.close();
  await pool?.end();
  await postgres.stop();
  await rm(directory, { recursive: true, force: true });
}
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => void stop().then(() => process.exit(0)));
}
try {
  await postgres.initialise();
  await postgres.start();
  const databaseUrl =
    "postgresql://postgres:isolated-demo-only@127.0.0.1:55462/postgres";
  pool = createPool(databaseUrl);
  // embedded-postgres also handles process signals; its shutdown may race with
  // the API closing idle connections. Avoid dumping connection internals.
  pool.on("error", () => {
    if (!stopping)
      console.error("The isolated demo database connection closed.");
  });
  await migrate(pool);
  const reviewerId = randomUUID();
  await pool.query(
    "INSERT INTO users(id,email_normalized,password_hash,email_verified_at,status,role) VALUES($1,$2,$3,now(),'active','reviewer')",
    [
      reviewerId,
      scenario.reviewer.email,
      await passwordHash(scenario.reviewer.password),
    ],
  );
  await pool.query("INSERT INTO kyc_profiles(id,user_id) VALUES($1,$2)", [
    randomUUID(),
    reviewerId,
  ]);
  const config: Config = {
    nodeEnv: "test",
    host: "127.0.0.1",
    port: 3300,
    databaseUrl,
    jwtSecret: randomBytes(32),
    tokenPepper: randomBytes(32),
    mediaKey: randomBytes(32),
    mediaDir: join(directory, "media"),
    smtpHost: "127.0.0.1",
    smtpPort: 1125,
    smtpSecure: false,
    mailFrom: "Identity Demo <no-reply@kyc.example>",
    rateLimitMax: 200,
    maxUploadBytes: 10 * 1024 * 1024,
  };
  app = await buildApp(config, pool);
  await app.listen(config.port, config.host);
  console.log("DEMO_API_READY http://127.0.0.1:3300");
} catch (error) {
  console.error(
    error instanceof Error ? error.message : "Recording API failed.",
  );
  await stop();
  process.exitCode = 1;
}
