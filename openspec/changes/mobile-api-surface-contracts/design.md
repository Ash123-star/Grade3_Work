# Design

## Context and Current State

Flutter uses Riverpod providers and a `Repository` abstraction, with `MockRepository` selected only by explicit demo configuration and `HttpRepository` used in real mode. AI jobs, long-term memory and notification streams have dedicated clients. The existing API contract describes many paths, but is not a single coverage map. `HttpRepository` previously used `/$resource` and `/$resource/{id}` fallback paths, so unsupported UI resources could become plausible but nonexistent requests.

The current runtime OpenAPI snapshot and server controllers are authoritative for implemented server paths. `mobile/docs/API_CONTRACT.md` is the forward-looking client contract. Where those differ, the mismatch is recorded as a gap; this change does not silently rewrite server behavior.

## Options

1. Keep generic resource/action strings and rely only on prose documentation. This minimizes code churn but leaves typo-prone routing and makes unsupported requests easy to introduce.
2. Keep the existing Repository abstraction, enumerate supported HTTP resource routes, reject unknown routes, and publish a page-to-operation contract matrix. This preserves current provider and Mock compatibility while making the REST adapter fail closed; it is the recommended route.
3. Replace Repository with a separate typed repository per domain immediately. This improves compile-time typing but creates a wide migration across every page and tests, unrelated to determining backend contract readiness.

## Decisions

- Use option 2. No new dependency, endpoint, database table, permission rule, or server implementation is introduced here.
- The frontend coverage matrix names UI operations and current/proposed request shapes. Existing paths are marked implemented only when present in runtime OpenAPI/controller and the Flutter adapter. Mock-only or local-only actions are never presented as remote APIs.
- Unknown list/detail resources fail with `FailureKind.unavailable` before network I/O. Resource mapping is an explicit allowlist.
- Draft and submitted-log editing are distinct operations. `PUT /logs/draft` saves an unsubmitted draft only. The adapter rejects `logs/update` until a server contract for the 24-hour direct edit is implemented; it must not route it to draft storage.
- Existing server API gaps remain unresolved design decisions: feedback lifecycle, task return event transition, log-read roster privacy/pagination, selectable AI scope, atomic AI confirmation version, task tag dictionary/assignment, and comment reply/thread semantics. The coverage doc provides operation names and data intent while marking paths/DTO details pending where product/owner approval is needed.
- Task form currently emits `startAt`, `tagId`, `participantIds`; current server `TaskDraftNormalizer` accepts `deadline`, `group`, `collaborators` and does not accept those new fields. The frontend contract retains its approved fields; backend must implement/align the controller and normalizer before live task creation is considered integrated.
- Task comments are Mock-only; log comments are supported by the current server but do not support `parentCommentId`. The frontend contract records replies as an extension and current HTTP adapter must fail explicitly for reply submissions until server support exists.
- Service authorization remains server-side. Client route guards and adapter allowlists are UX/contract safeguards only.

## Compatibility and Rollback

Existing supported resource strings and REST paths remain unchanged. Unknown resource requests that previously fell through to guessed URLs now fail explicitly, which may expose undocumented consumers; search results and targeted contract tests must be checked before merge. Rollback is limited to restoring the generic fallback, which is not recommended because it recreates accidental requests.

## Verification

- Verify OpenSpec with `openspec.cmd validate --all --strict`.
- Run targeted Flutter API contract tests and Dart analysis for the changed adapter.
- Assert unknown feedback/team resources fail without an HTTP request and that existing tasks/logs/auth/reviews/notifications requests retain their paths.
- This is client contract verification only; backend integration, authorization and end-to-end behavior remain unverified until the server implements the listed gaps.
