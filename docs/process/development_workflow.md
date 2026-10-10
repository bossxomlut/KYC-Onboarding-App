# Development workflow

This assignment is a new feature across domain, data, presentation, core, DI, routing, backend and tests. Source requirements are the supplied assignment PDF and implementation plan. The server is the source of truth for persisted KYC progress. No mock API is used by the running app.

Before changing behavior, specify its contract and write a focused failing test. Tests prioritize session restore, network failure recovery, refresh rotation, authorization, upload validation, KYC transitions and resubmission. Generated scaffold and purely visual styling do not require test-first changes.

Domain is pure Dart. Data maps infrastructure exceptions to typed results. Presentation calls use cases only. App-scoped auth is owned at the app root; KYC state is owned at the authenticated flow shell; page forms use page providers. Factories create Cubits. DI is the composition root.

Done means formatting/analyzer and focused tests pass, runtime checks are actually performed, setup and limitations are documented, no secrets/real PII are committed, and changes have meaningful commits. Device-only checks are recorded separately from automated evidence.
