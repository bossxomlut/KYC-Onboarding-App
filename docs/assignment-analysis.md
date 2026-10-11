# Assignment analysis

The assignment requires a Flutter iOS/Android app, a real backend in this repository, authentication, personal details validation, camera document/selfie capture, review/edit/upload/submit, result/rejection/resubmission and durable resume. It evaluates architecture, privacy, network/lifecycle resilience, useful tests, UX and documented decisions. Meaningful Git history and a short recording with synthetic identity data are deliverables.

The implementation plan adds candidate design choices: OTP email verification, registration and password reset, 15-minute access tokens, rotating refresh sessions, BLoC/Cubit, GoRouter, GetIt, Dio, secure platform token storage, Material 3 and green `#026220`. These are design decisions, not additional statements from the assignment. No dashboard or unrelated features are included.

Backend choice: TypeScript/NestJS 12.1.2 with the Express adapter and PostgreSQL. NestJS is a project decision, not a framework mandated by the assignment. Feature modules, injectable shared infrastructure, controllers/services, DTO validation pipes, authentication/upload guards and a global error filter make backend responsibilities explicit. PostgreSQL transactions and row locks protect session rotation and KYC transitions. Authorized reviewers record decisions through the app and authenticated API; the old direct-database review CLI is disabled. Optional local OCR/face comparison assists manual review and does not provide liveness detection.

App feature structure combines the tightly coupled KYC steps into one flow feature with domain/data/presentation layers. It avoids separate globally retained step Cubits and preserves one flow owner. Authentication remains separate and app-scoped. Server persistence is the source of truth; unsubmitted form edits are held in memory, while saved details and uploaded photos survive restarts. Photos awaiting retry are confined to app-private temporary storage and cleared after upload or logout.

See `README.md` for reproducible setup, explicit security boundaries, tested evidence, remaining device checks and instructions for recording the current app.
