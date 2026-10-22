# Tasks

- [ ] 1.1 Map all mobile routes, repository resources/actions, dedicated clients and local stores to `mobile/docs/api-surface-coverage.md`; classify each as HTTP, pending contract, Mock-only or local-only.
- [ ] 1.2 Compare every current/proposed operation with runtime `docs/openapi.json` and server controller mappings; record request/response mismatches, permission responsibility, pagination, error, idempotency and version needs.
- [ ] 1.3 Replace generic list/detail URL fallbacks with explicit resource mappings and explicit unavailable failures; retain only runtime-confirmed paths.
- [ ] 1.4 Prevent submitted-log `update` from being routed to `PUT /logs/draft`; keep pending direct-edit operation separately identified.
- [ ] 1.5 Update `mobile/docs/API_CONTRACT.md`, the coverage matrix, and `docs/backend-interface-gaps.md`; link each backend gap to named frontend operation, owner and acceptance condition.
- [ ] 1.6 Run targeted Dart analysis and API contract tests; verify unknown resource rejection does not send HTTP and existing route mappings remain stable.
- [ ] 1.7 Run `openspec.cmd validate --all --strict` and `git diff --check`; leave implementation tasks unchecked where backend/runtime evidence is absent.
