# ChatNotifier Legacy Workflow Item-Identity Reconciliation Task

## Task

- Goal: Reconcile the documented positional legacy provenance IDs with current
  projected item IDs through a pure, fail-closed, one-to-one mapping.
- User-visible behavior: None. This slice extends migration evidence only.
- Non-goals: Do not write persistence, accept arbitrary legacy IDs, repair the
  four plan/progress conflict records, or remove the workflow editor.

## Context

- Affected files or components: The pure provenance merge service, focused
  domain tests, the read-only aggregate auditor, and ChatNotifier evidence.
- Related docs:
  `docs/chat_notifier_legacy_workflow_provenance_merge_audit_codex_task.md`
  and `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern: `ShortPromptContractBuilder` persists
  constraints as `constraint:<index>` and acceptance criteria as
  `acceptance:<index>`. Current plan provenance uses content-derived IDs.
- Known quirks, compatibility rules, or release gates: All 14 clean current
  workflows and 27 cohort checkpoints fail only because those item identities
  do not match. Goal and task identity formats remain stable.

## Implementation Notes

- Preferred approach: Require semantic workflow equality, validate the current
  projected provenance shape, preserve exact-ID matches, and recognize only
  the two historical positional formats. Resolve each positional index to the
  corresponding semantic constraint or acceptance criterion.
- Constraints: Every legacy and projected item must participate in exactly one
  match. Reject malformed indices, out-of-range indices, duplicate target
  matches, kind mismatches, semantic drift, and unsupported identity formats.
- Generated files needed: None.
- Migration or data compatibility concerns: Preserve legacy provenance item
  IDs, order, source references, and metadata in the candidate output. The
  mapping authorizes adding approved-plan provenance, not rewriting identity.

## Similar-Pattern Search

- Search terms: `constraint:$index`, `acceptance:$index`, `itemId`,
  `attachApprovedPlanSource`, and `ShortPromptContractBuilder`.
- Files or modules inspected: Provenance service history, short-prompt contract
  builder history and current implementation, merge service, compatibility
  auditor, plan projection, and workflow entities.
- Follow-up tasks found: Re-run the schema-v3 aggregate audit after the pure
  reconciliation fixture passes; proceed to conflict policy only if every
  clean current workflow and checkpoint becomes mergeable.

## Acceptance Criteria

- Required behavior: Exact current IDs and documented positional legacy IDs
  merge one-to-one while retaining every legacy provenance field and adding
  the approved-plan source exactly once.
- Edge cases: Multiple same-kind values, reordered provenance entries,
  malformed or out-of-range indices, duplicate target mappings, unsupported
  IDs, semantic workflow drift, and projected provenance drift.
- Failure paths: Return deterministic typed blockers and no partial candidate.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_workflow_provenance_merge_service_test.dart
fvm flutter test test/tool/audit_legacy_workflow_compatibility_test.dart
fvm dart run tool/audit_legacy_workflow_compatibility.dart --database <path>
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: This fixture does not authorize a live migration.
