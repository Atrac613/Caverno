# Workflow Conflict Preservation Envelope

## Task

- Goal: Build a pure, lossless preservation envelope for the four legacy
  workflow conflicts before any persisted transformation is considered.
- User-visible behavior: None. This slice creates a domain fixture only.
- Non-goals: Persistence wiring, automatic stage selection, heuristic progress
  remapping, live migration, or workflow-editor removal.

## Context

- Affected files or components: A new chat-domain service and focused tests.
- Related docs:
  `docs/chat_notifier_plan_progress_conflict_policy_audit_codex_task.md` and
  `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern:
  `conversation_workflow_provenance_merge_service.dart` and
  `conversation_legacy_workflow_compatibility_service.dart`.
- Known quirks, compatibility rules, or release gates: The live conflict cohort
  has semantically equivalent workflow content, divergent stages, and
  meaningful progress referenced by no current, plan, or checkpoint task graph.

## Implementation Notes

- Preferred approach: Derive the existing plan projection, stabilize task IDs,
  require semantic equality and a successful provenance merge, then classify
  progress by exact task ID. Preserve progress owned by no graph in an immutable
  envelope and retain both stage values.
- Constraints: Require explicit workflow-versus-plan stage authority when the
  stages differ. Fail closed if dangling progress belongs to the conflicting
  plan or a checkpoint because those cases require separate policies. Never
  mutate inputs.
- Generated files needed: None; use plain immutable transient result helpers.
- Migration or data compatibility concerns: The envelope is not persisted and
  does not authorize dropping or rewriting orphan progress.

## Similar-Pattern Search

- Search terms: `ProvenanceMergeResult`, `CompatibilityBlocker`,
  `stabilizeTaskIds`, `executionProgress`, and `workflowStage`.
- Files or modules inspected: The provenance merge fixture, compatibility
  fixture, plan projection service, conversation checkpoint entity, and their
  focused tests.
- Follow-up tasks found: A read-only aggregate rehearsal against the four live
  records remains necessary before any transformer design.

## Acceptance Criteria

- Required behavior: Preserve merged workflow provenance, active progress,
  orphan progress, workflow stage, plan stage, and explicit selected authority
  without changing any input.
- Edge cases: Missing or invalid plans, semantic or provenance mismatch,
  matching stages, missing stage authority, plan-owned progress,
  checkpoint-owned progress, mixed active/orphan progress, and empty orphans.
- Failure paths: Return deterministic blockers and no ready candidate whenever
  any transformation precondition is absent.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_workflow_conflict_preservation_service_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a pure preservation service that projects the existing plan,
  requires semantic equality and a provenance merge, classifies progress by
  exact task ID, and retains active plus fully orphaned progress in an immutable
  envelope. Divergent stages require explicit workflow or approved-plan
  authority before the result becomes ready.
- Tests run: The focused preservation-service test passes 8/8.
  `tool/codex_verify.sh` completes generation, analysis, and package tests; the
  Flutter suite passes 6,515/6,516 tests. Its only failure is the pre-existing
  stale `run_coding_stalled_diagnostic_repair_live_canary` expectation for the
  removed `_isTodoVerifierCall` helper.
- Coverage or low-coverage notes: Fixtures cover input immutability, list
  immutability, both explicit authorities, matching stages, missing and invalid
  plans, semantic drift, exact merge blockers, and plan/checkpoint ownership.
- Risks or follow-ups: This fixture does not authorize a live migration. Add a
  privacy-safe read-only aggregate rehearsal against the four live records;
  stage authority must remain absent in that diagnostic.
