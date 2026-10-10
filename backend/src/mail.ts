import nodemailer from "nodemailer";
import type { Config } from "./config.js";
import type { Pool, PoolClient } from "pg";
import { randomUUID } from "node:crypto";
import { transaction } from "./database.js";
import { encrypt, decrypt } from "./security.js";
export interface Mail {
  to: string;
  subject: string;
  text: string;
  id?: string;
}
export interface Mailer {
  send(mail: Mail): Promise<void>;
}
export function createMailer(config: Config): Mailer {
  const transport = nodemailer.createTransport({
    host: config.smtpHost,
    port: config.smtpPort,
    secure: config.smtpSecure,
    auth: config.smtpUser
      ? { user: config.smtpUser, pass: config.smtpPassword }
      : undefined,
    connectionTimeout: 5000,
    greetingTimeout: 5000,
    socketTimeout: 10000,
    logger: false,
    debug: false,
  });
  return {
    async send(mail) {
      await transport.sendMail({ ...mail, from: config.mailFrom });
    },
  };
}

export async function queueMail(
  client: PoolClient,
  config: Config,
  userId: string,
  kind: "verification" | "reset",
  mail: Mail,
): Promise<Mail> {
  const id = randomUUID();
  await client.query("DELETE FROM email_outbox WHERE user_id=$1 AND kind=$2", [
    userId,
    kind,
  ]);
  await client.query(
    "INSERT INTO email_outbox(id,user_id,kind,encrypted_payload,expires_at) VALUES($1,$2,$3,$4,now()+CASE WHEN $3='verification' THEN interval '10 minutes' ELSE interval '30 minutes' END)",
    [
      id,
      userId,
      kind,
      encrypt(Buffer.from(JSON.stringify(mail)), config.mediaKey).toString(
        "base64",
      ),
    ],
  );
  return { ...mail, id };
}

export async function deliverQueued(
  pool: Pool,
  config: Config,
  mailer: Mailer,
  id?: string,
): Promise<boolean> {
  return transaction(pool, async (client) => {
    await client.query("DELETE FROM email_outbox WHERE expires_at<=now()");
    const result = await client.query(
      "SELECT * FROM email_outbox WHERE expires_at>now() AND next_attempt_at<=now() AND ($1::uuid IS NULL OR id=$1) ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED",
      [id ?? null],
    );
    const row = result.rows[0];
    if (!row) return false;
    const mail = JSON.parse(
      decrypt(
        Buffer.from(row.encrypted_payload, "base64"),
        config.mediaKey,
      ).toString("utf8"),
    ) as Mail;
    try {
      await mailer.send(mail);
      await client.query("DELETE FROM email_outbox WHERE id=$1", [row.id]);
      return true;
    } catch {
      await client.query(
        "UPDATE email_outbox SET attempt_count=attempt_count+1,next_attempt_at=now()+interval '1 second'*LEAST(300,POWER(2,attempt_count+1)) WHERE id=$1",
        [row.id],
      );
      // Event text is fixed; no recipient, SMTP configuration or message contents are logged.
      if (config.nodeEnv !== "test")
        console.warn("Email delivery deferred; queued for retry.");
      return false;
    }
  });
}

export function startOutboxWorker(pool: Pool, config: Config, mailer: Mailer) {
  let busy = false;
  const timer = setInterval(async () => {
    if (busy) return;
    busy = true;
    try {
      for (let count = 0; count < 10; count++)
        if (!(await deliverQueued(pool, config, mailer))) break;
    } catch {
      console.warn("Email queue retry is temporarily unavailable.");
    } finally {
      busy = false;
    }
  }, 5000);
  timer.unref();
  return () => clearInterval(timer);
}
