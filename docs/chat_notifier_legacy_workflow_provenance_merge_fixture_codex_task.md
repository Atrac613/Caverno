# ChatNotifier Legacy Workflow Provenance-Merge Fixture Task

## Task

- Goal: Define a pure candidate that adds approved-plan provenance without
  replacing a valid legacy workflow source graph.
- User-visible behavior: None. This slice provides migration evidence only.
- Non-goals: Do not update conversations or checkpoints, connect persistence,
  resolve plan/progress conflicts, or remove the workflow editor.

## Context

- Affected files or components: Conversation contract provenance services,
  focused domain tests, and ChatNotifier renewal evidence.
- Related docs:
  `docs/chat_notifier_legacy_workflow_provenance_shape_audit_codex_task.md` and
  `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern:
  `ConversationContractProvenanceService.attachApprovedPlanSource` and
  `ConversationPlanProjectionService.deriveExecutionProjection`.
- Known quirks, compatibility rules, or release gates: Existing projection
  replaces sources and item provenance. The clean persisted cohort has 14
  records whose only blocker is this replacement behavior.

## Implementation Notes

- Preferred approach: Merge the approved-plan source and matching projected
  item source IDs into the existing graph while retaining legacy source order,
  item order, kinds, assumption flags, confirmation state, and clarification.
- Constraints: Return a typed blocked result for invalid legacy graphs, source
  ID collisions, projected graph shape errors, item-kind mismatches, or legacy
  provenance items that cannot be matched to the projection.
- Generated files needed: None.
- Migration or data compatibility concerns: The merge result must be immutable,
  deterministic, and must not mutate either input workflow specification.

## Similar-Pattern Search

- Search terms: `attachApprovedPlanSource`, `itemId`, `sourceIds`,
  `ConversationPlanProjection`, and `ConversationContractItemProvenance`.
- Files or modules inspected: Provenance attachment service, plan projection
  service, workflow entities, compatibility gate, and focused provenance tests.
- Follow-up tasks found: Apply the pure candidate aggregate-only to the 14 clean
  persisted records only after its graph invariants are fixed by tests.

## Acceptance Criteria

- Required behavior: A representative legacy graph round-trips with every
  source and item field intact while every projected item gains the approved
  plan source exactly once.
- Edge cases: Duplicate or empty IDs, orphan source references, approved-plan
  source collisions, mismatched item kinds, unmatched legacy items, projected
  items without a matching legacy item, and assumption metadata.
- Failure paths: Invalid inputs return deterministic blocker kinds and never a
  partial merged graph.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_workflow_provenance_merge_service_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: This fixture does not authorize a live migration.
