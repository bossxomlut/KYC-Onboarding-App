# Backend setup and decisions

The mobile app uses this real NestJS 12.1.2 API (Express adapter) and PostgreSQL database. API URLs start with `/api/v1`; the unauthenticated readiness endpoint is `GET /health`. The API listens on `0.0.0.0:3000` by default. PostgreSQL and email catcher ports are bound to localhost.

## Run locally

For first-time tool installation, separate service terminals, OTP access and restart instructions, see the [complete macOS setup guide in Vietnamese](local-setup.md).

Use Node.js **22.12 or newer**; Node 22 LTS is recommended and selected by root `.nvmrc`. Use npm and Docker with Compose, or the real embedded PostgreSQL alternative below. From the repository root (run `nvm use` first if using nvm):

```sh
node scripts/init-env.mjs
docker compose up -d
docker compose ps
# Wait until postgres shows healthy before continuing.
cd backend
npm ci
npm run migrate
npm run admin:bootstrap
npm run dev
```

The environment initializer creates the ignored `backend/.env` only when it is absent, generates three distinct random secrets without printing them, and preserves existing configuration. Keep the data-encryption key across restarts to read existing encrypted drafts and images. Wait for Docker PostgreSQL to become healthy before running migrations.

Open Mailpit at <http://localhost:8025> to read OTP and reset emails. Email does not leave the machine. Register a synthetic email address in the mobile app, read its six-digit code in Mailpit, and verify it. The reset link is `kycapp://app/reset-password?token=...`; open it on the simulator or device, or paste the reset token into the app's reset form. OTPs and reset links are secrets: do not include them in screenshots or logs.

For a phone on the same Wi-Fi, use `http://<MAC_LAN_IP>:3000/api/v1` as the Flutter API base URL. `localhost` on a phone addresses the phone. Android emulator can use `http://10.0.2.2:3000/api/v1`; iOS simulator can use `http://127.0.0.1:3000/api/v1`.

### PostgreSQL without Docker

The optional development command launches a real bundled PostgreSQL process, persists its data under ignored `backend/.local/postgres`, and applies migrations. It does not replace the database with an in-memory mock:

```sh
node scripts/init-env.mjs
cd backend
npm ci
npm run db:local
```

Keep that terminal running. Its default connection matches `.env.example`: `postgresql://kyc:local-development-only@localhost:5432/kyc`. Use either this process or the Docker PostgreSQL service, since they share a port. `LOCAL_DATABASE_PORT=5433 npm run db:local` changes the port; update `DATABASE_URL` accordingly. Start a real local SMTP catcher separately on port 1025, then run `npm run dev` in another terminal. The bundled database is a development dependency and never starts as part of production API startup.

### Synthetic demo account and review

`npm run demo` creates a verified synthetic email account with an empty KYC profile. It is disabled when `NODE_ENV=production` and does not reset existing data. Its demo-only credentials are `demo@kyc.example` / `DemoOnlyPass123!`. Use registration in the recording if email verification is part of the flow.

Create the initial super admin with `npm run admin:bootstrap`. Development defaults to `admin@kyc.com` and writes a randomly generated password to ignored `.local/super-admin.json` with mode 600. It never prints the password or resets an existing owner. See the [admin and reviewer guide](admin-access.md) for setup and production bootstrap requirements.

Sign in as the super admin to create user/reviewer accounts and approve access requests. Managed accounts verify email through the existing OTP flow. Reviewers and the super admin can open pending profiles of other users and record approval/rejection in the app. The old `npm run review` command no longer changes the database.

## NestJS architecture

`AppModule` composes feature modules and registers the global filter and rate-limit guard. `AuthModule` owns authentication DTOs, controller, service and `AuthenticationGuard`; it exports the service and authentication/role guards for protected features. `AccessModule` manages accounts and permission requests; `ReviewsModule` owns the authorized review queue, detail/media reads and decisions. `KycModule` owns the profile controller/service, schemas, upload fields pipe and upload guard. `InfrastructureModule` is global and injects `APP_CONFIG`, `DATABASE_POOL` and `MAILER` into providers; the email outbox worker starts and stops through Nest lifecycle hooks. Database pool ownership remains with application startup/shutdown.

Controllers contain route/status-code declarations and HTTP input/output. Services contain the existing authentication/KYC operations and PostgreSQL transactions. Strict schemas are applied by `ZodValidationPipe`; Auth has named request DTOs. Explicit injection tokens make dependency resolution work both in production builds and the TypeScript development/test runner.

Nest executes guards before interceptors. Protected uploads run `AuthenticationGuard` and `KycUploadGuard` before `FileInterceptor("file")`; Multer uses bounded in-memory upload parsing, and the upload fields pipe validates the parsed multipart fields. Media bytes still go through signature/decoding checks and encrypted private storage in the KYC service. `ApiExceptionFilter` maps application, validation, multipart and HTTP failures into the stable error contract. `RateLimitGuard` uses per-handler/IP counters: configured auth POST limits and 120 requests/minute for other handlers. The auth policy is attached to Nest controller metadata rather than matched against URL text, so case-insensitive routing cannot bypass it. The guard emits rate-limit/retry headers, and proxy trust is disabled by default.

API paths, success bodies, status/error codes, database migrations and existing user/profile/session data remain compatible. Migration 004 adds account roles and audit tables. Privileged routes check live roles; the shared review operation also checks the actor inside its transaction and records the reviewer.

## Security and state behavior

- Passwords use Argon2id with 19 MiB memory, two iterations, and one lane. New passwords are 12–128 characters with an uppercase letter, lowercase letter, and digit. Unknown-account login verifies a precomputed dummy hash to avoid skipping password-hashing work.
- Email OTPs last 10 minutes, allow five wrong attempts, and become single-use. Resend has a 30-second per-account cooldown; auth endpoints also enforce per-IP limits. Forgot and resend respond generically for unknown/known accounts, including SMTP outages.
- Access JWTs expire after 15 minutes and have a fixed issuer, audience, and HS256 algorithm. Every authenticated call also checks its server-side session. Refresh tokens last 30 days and rotate in a transaction. User locks and a family advisory lock serialize refresh, reset, and logout. Replaying an old refresh token revokes the whole family; logout with an old known token also revokes its descendants. Reset tokens last 30 minutes, become single-use, and revoke all sessions after a successful reset.
- OTP, reset, and refresh values are stored only as keyed HMAC hashes. `TOKEN_PEPPER` is distinct from the JWT signing key and data-encryption key.
- Personal details, private image files, and pending email payloads use authenticated AES-256-GCM encryption. Filenames are random UUIDs and file permissions are private. Images have no public URL and are only returned through authenticated owner endpoints or reviewer endpoints for pending profiles of other users with `Cache-Control: no-store`. Email is stored normalized in PostgreSQL because authentication must look it up; production storage encryption and restricted DB roles still matter.
- Uploads accept one genuine JPEG or PNG image of at most 10 MiB and at most 20 million decoded pixels. The API checks its signature, decodes and re-encodes it to JPEG, and removes EXIF/GPS metadata. It never trusts a filename to determine file type. Replacing an image or resubmitting removes obsolete files on a best-effort basis.
- Applicant KYC queries derive ownership from the authenticated user. Reviewer routes accept target user IDs only after checking the live reviewer/super admin role, pending state and self-review prohibition. Pending, verified, and rejected profiles are locked against editing. Submit is idempotent while pending. Reopening rejection clears only the requested data/assets, preserves accepted steps, and derives the next step from server data.
- Optional multipart `captureId` identifies one capture across retries. Media metadata echoes it, allowing the app to recognize a successfully uploaded image after interruption. Repeating a capture ID for the same user and image kind keeps the existing media ID under the profile lock. The identifier is 16–128 URL-safe characters; clients without it continue to work.
- Logs contain fixed infrastructure events and omit request bodies, credentials, recipient addresses, PII, image contents, and SMTP details. Local PostgreSQL suppresses ordinary SQL error logging to prevent constraint diagnostics from printing email addresses. Errors returned to the client always have `{error:{code,message,requestId}}`.
- Email enqueueing and token creation are atomic. The durable encrypted outbox retries failed delivery every five seconds with exponential backoff, up to five minutes between attempts, until expiry. Register reports `EMAIL_DELIVERY_FAILED` if the first attempt fails, while retaining the account and queued OTP. Verify after delivery or request a replacement code. Forgot and resend only enqueue; they return generically without contacting or waiting for SMTP, including during outages. Their email normally arrives within the next worker interval.

These are assignment design choices rather than legal KYC policy: adults 18–120, personal name/address/document-number length constraints, manual verification, JPEG/PNG-only images, and a 30-day refresh lifetime. This app collects a single document image and does not perform OCR, face matching, liveness, or third-party identity verification.

## Checks and limitations

```sh
cd backend
npm run check
npm test
npm run build
npm audit --omit=dev
```

The backend test cases launch disposable real PostgreSQL instances, run actual migrations, and exercise the actual Nest application over HTTP with Supertest. They inject only the mail delivery transport so codes can be inspected and outages simulated. Coverage prioritizes OTP expiry/attempt limits, login restrictions, refresh concurrency/replay, logout and reset revocation, single-use resets, encrypted storage, image limits, authorization, and KYC rejection/resubmission. Four Nest-specific cases check injectable module resolution, stable JSON/validation/404 errors, guard execution before multipart parsing and upload limits, and safe errors on private-media filesystem failures. The original Nest migration cases passed on Node 22.23.2 and Node 24.19.0; current permission checks are recorded in the verification document. The mobile integration test also passed against the compiled NestJS API, real PostgreSQL and Mailpit; see [verification evidence](verification.md) for scope and commands.

Development uses a single API instance with in-process IP rate limiting and local media files. Production needs a TLS reverse proxy, trusted proxy configuration, a shared rate-limit store, external private object storage, managed keys and key rotation, storage cleanup/retention, backups, and monitoring that redacts sensitive values. Preserve the data-encryption key across restarts or saved drafts/files cannot be decrypted. This setup does not implement an assignment-specific legal retention policy. SMTP must use TLS in production. The HTTP and known database credentials in `.env.example` and Compose are for local development only.
