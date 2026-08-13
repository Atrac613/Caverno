# LL24 Task-Based Primary-Model Routing

## Task

- Goal: Route each primary chat turn to an explicit model and endpoint chosen
  for its resolved assistant mode while preserving primary-endpoint fallback.
- User-visible behavior: General, Coding, and Plan turns can each use a pinned
  endpoint/model. Empty pins preserve today's main-model behavior, and an
  unavailable pin never prevents the turn from completing on the primary
  endpoint.
- Non-goals: Automatic difficulty inference, mid-request model switching,
  parallel Best-of-N selection, or a general model-eviction policy.

## Context

- Affected files or components: `AppSettings`, `SettingsNotifier`, model-routing
  settings, `PrimaryModelRouter`, `ChatNotifier`, LL9 model preparation, model
  usage attribution, and LLM session logs.
- Related docs: LL24 in `docs/local_llm_agent_roadmap.md`,
  `docs/session_logs.md`, and `docs/large_file_refactor_plan.md`.
- Reference implementation or pattern: LL1 per-role model fields,
  `MeshEndpointRouter`, `MeshSecondaryCompletionRunner`, the owner-scoped
  `TurnReleaseScope`, and `PrimaryModelPreparationService`.
- Known quirks, compatibility rules, or release gates: Apple Foundation Models
  has one fixed on-device model. A mesh-only assigned model must not be sent to
  the primary endpoint after demotion. Streaming fallback is safe only before
  the assigned endpoint emits visible content.

## Implementation Notes

- Preferred approach: Resolve one immutable route after the runtime turn owner
  is established and after Plan-mode entry is known. Store it by turn owner,
  read it from every primary request path, and release it through the existing
  turn scope.
- Constraints: Keep secondary-role routing unchanged. Do not mutate global
  connection settings during a turn. Preserve the ChatNotifier and aggregate
  file-size ratchets by placing routing behavior in domain/data collaborators
  and a small same-library part.
- Generated files needed: Regenerate `app_settings.freezed.dart` and
  `app_settings.g.dart` after adding persisted fields.
- Migration or data compatibility concerns: All six new pins default to empty.
  Existing JSON therefore remains behavior-preserving. Endpoint-id migration
  and endpoint deletion must remap or clear the new pins with the existing role
  pins.

## Workstreams

### A. Settings and persistence

Status: `completed`

- Add General, Coding, and Plan primary model/endpoint pins.
- Add effective per-mode model resolution and selected endpoint lookup.
- Add notifier updates, JSON compatibility, endpoint migration, and tests.

### B. Pure route decision

Status: `completed`

- Implement `PrimaryModelRouter` as a pure
  `PrimaryRouteContext -> PrimaryRouteResolution` service.
- Emit a stable reason for main-model default, explicit model, explicit
  endpoint, endpoint-catalog model, and primary demotion.
- Add a no-op escalation checkpoint reserved for LL25.

### C. Turn-owned runtime route

Status: `completed`

- Capture the resolved route at the turn boundary and release it with the turn.
- Route plain streaming, native tools, embedded tool tags, tool-result
  continuations, final-answer recovery, and participant primary calls through
  the same captured data source/model.
- Resolve LL3 capability profiles and LL23 harness config from the selected
  endpoint/model instead of the global main model.

### D. Lifecycle and fallback

Status: `completed`

- Prepare the selected model through LL9 before its first request.
- On same-endpoint model switches, unload the previous selected primary model,
  confirm it is unloaded, and start the selected model when supported.
- Treat unsupported lifecycle metadata as a no-op. Retry a failed assigned
  request on the primary endpoint only when no visible stream content was
  emitted, and mark endpoint health.

### E. Settings UI and route evidence

Status: `completed`

- Add localized per-mode rows to Model Routing settings.
- Record a `primary_model_route` marker with turn id, mode, endpoint/model,
  reason, and demotion state only when session logging is enabled.
- Attribute all primary-route requests to `ModelUsageRole.chat` under the
  selected endpoint/model.

### F. Verification and roadmap closure

Status: `completed`

- Run focused settings, router, data-source, notifier, UI, logging, translation,
  and ratchet tests.
- Run `tool/codex_verify.sh` and update LL24 only when all acceptance criteria
  pass.

## Similar-Pattern Search

- Search terms: `_dataSource`, `_settings.model`,
  `effectiveModelCapabilityProfile`, `effectiveModelHarnessConfig`,
  `MeshSecondaryCompletionRunner`, `PrimaryModelPreparationService`,
  `TurnReleaseScope`, and `recordTurnExit`.
- Files or modules inspected: primary and secondary chat request paths,
  AppSettings routing fields and endpoint migration, model-routing settings,
  LL9 lifecycle providers, and session-log marker APIs.
- Follow-up tasks found: LL25 can supply a difficulty signal to the reserved
  checkpoint; LL26 can reuse the resolved primary-route context for mesh
  Best-of-N placement after LL24 closes.

## Acceptance Criteria

- Required behavior: Each turn resolves exactly once from its effective
  assistant mode. Every primary request in that turn uses the captured route,
  selected model profile, and selected harness config.
- Edge cases: Empty pins, endpoint-only pins, model-only pins, stale/disabled/
  unhealthy endpoints, Apple Foundation Models, queued turns, Plan-mode entry,
  navigation during a turn, and settings changes during a turn preserve owner
  and route consistency.
- Failure paths: A pre-emission assigned-endpoint failure retries on the main
  endpoint/model. A failure after visible content does not replay content.
  Unsupported model lifecycle operations do not fail the turn.
- Accessibility, localization, or platform expectations: All three routing rows
  are keyboard accessible and localized in English and Japanese.

## Verification

```bash
fvm dart run build_runner build --delete-conflicting-outputs
tool/codex_verify.sh
git diff --check
```

## Handoff Notes

- Summary: Completed after LL40 closed. The implementation reuses
  LL1/LL8/LL9/LL23 boundaries, captures one route per owner-scoped turn, and
  keeps request call sites free of per-mode branches.
- Tests run: `tool/codex_verify.sh` completed successfully with 7,336 Flutter
  tests, all root and package analyzers, generated-file verification, three
  internal package suites, and 10 notification-relay tests passing.
- Coverage or low-coverage notes: Deterministic router, transport, notifier,
  lifecycle, logging, settings, localization, teardown, turn-scope, and
  file-size tests cover the LL24 acceptance surface.
- Risks or follow-ups: Live endpoint availability and managed-model lifecycle
  support remain provider-specific. Unsupported lifecycle metadata is a no-op,
  and LL25 owns automatic difficulty escalation.
