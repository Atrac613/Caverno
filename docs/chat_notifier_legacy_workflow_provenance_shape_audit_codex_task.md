# ChatNotifier Legacy Workflow Provenance-Shape Audit Task

## Task

- Goal: Classify the aggregate provenance shapes that block compatibility for
  persisted legacy-authored workflows and their legacy checkpoints.
- User-visible behavior: Maintainers can distinguish preservation-safe source
  graphs from malformed or assumption-bearing graphs without exposing record
  data or modifying persistence.
- Non-goals: Do not emit source IDs, item IDs, locators, hashes, questions,
  record identifiers, or content. Do not implement or run a migration.

## Context

- Affected files or components: The read-only legacy compatibility audit, its
  focused tests, and ChatNotifier renewal evidence.
- Related docs:
  `docs/chat_notifier_legacy_workflow_compatibility_audit_codex_task.md` and
  `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern: Aggregate current-versus-checkpoint
  blocker counts in `tool/audit_legacy_workflow_compatibility.dart`.
- Known quirks, compatibility rules, or release gates: Eighteen records require
  provenance preservation in both current and checkpoint scope; four also have
  dangling execution progress and an existing plan conflict.

## Implementation Notes

- Preferred approach: Extend the existing Dart audit with aggregate source-kind,
  item-kind, reference-integrity, assumption-state, and conflict-cohort counts.
- Constraints: Count records or snapshots containing a shape, not individual
  identifiers. Keep current workflows and legacy checkpoint snapshots in
  separate aggregate sections.
- Generated files needed: None.
- Migration or data compatibility concerns: Duplicate IDs, missing references,
  empty source lists, unreferenced sources, multi-source items, blocking
  assumptions, and inconsistent checkpoint projection metadata must remain
  distinguishable.

## Similar-Pattern Search

- Search terms: `ConversationContractSourceKind`,
  `ConversationContractItemKind`, `sourceIds`, `blockingAssumptions`,
  `workflowSourceHash`, and `workflowDerivedAt`.
- Files or modules inspected: Workflow entities, provenance attachment service,
  compatibility gate, persisted compatibility audit, and focused provenance
  tests.
- Follow-up tasks found: Define a pure preservation candidate only if source
  graphs are internally consistent and assumption semantics can remain intact.

## Acceptance Criteria

- Required behavior: Report current-record and legacy-checkpoint snapshot
  counts by source kind, item kind, graph-integrity condition, and assumption
  condition, plus provenance-only versus plan/progress conflict cohorts.
- Edge cases: Duplicate source and item IDs, orphan and unreferenced sources,
  empty or multiple source references, blocking and confirmed assumptions, and
  fresh or inconsistent projected checkpoints.
- Failure paths: Existing invalid-record and path-free operational failures
  remain fail closed; the database bytes remain unchanged.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test test/tool/audit_legacy_workflow_compatibility_test.dart
fvm dart run tool/audit_legacy_workflow_compatibility.dart --database <path>
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: This audit does not authorize a live migration.
