# Assignment analysis

The assignment requires a Flutter iOS/Android app, a real backend in this repository, authentication, personal details validation, camera document/selfie capture, review/edit/upload/submit, result/rejection/resubmission and durable resume. It evaluates architecture, privacy, network/lifecycle resilience, useful tests, UX and documented decisions. Meaningful Git history and a short recording with synthetic identity data are deliverables.

The implementation plan adds candidate design choices: OTP email verification, registration and password reset, 15-minute access tokens, rotating refresh sessions, BLoC/Cubit, GoRouter, GetIt, Dio, secure platform token storage, Material 3 and green `#026220`. These are design decisions, not additional statements from the assignment. No dashboard or unrelated features are included.

Backend choice: TypeScript/NestJS 12.1.2 with the Express adapter and PostgreSQL. NestJS is a project decision, not a framework mandated by the assignment. Feature modules (`AuthModule`, `KycModule`), injectable shared infrastructure, controllers/services, DTO validation pipes, authentication/upload guards and a global error filter make backend responsibilities explicit. PostgreSQL transactions and row locks protect session rotation and KYC transitions. A privileged local CLI records a review decision; no unprotected reviewer endpoint or fake automated verification exists. This demonstrates the required state machine while leaving actual identity checks to a future service/reviewer system.

App feature structure combines the tightly coupled KYC steps into one flow feature with domain/data/presentation layers. It avoids separate globally retained step Cubits and preserves one flow owner. Authentication remains separate and app-scoped. Server persistence is the source of truth; unsubmitted form edits are held in memory, while saved details and uploaded photos survive restarts. Photos awaiting retry are confined to app-private temporary storage and cleared after upload or logout.

See `README.md` for reproducible setup, explicit security boundaries, tested evidence, remaining device checks and the recording.
