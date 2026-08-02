# ChatNotifier Legacy Workflow Provenance-Merge Audit Task

## Task

- Goal: Apply the pure provenance-preserving merge candidate read-only to the
  persisted provenance-only cohort and report aggregate compatibility.
- User-visible behavior: Maintainers can determine whether the 14 clean legacy
  records and their legacy checkpoints accept the additive candidate without
  exposing record data or changing persistence.
- Non-goals: Do not write conversations, emit identifiers or content, repair
  the four plan/progress conflict records, or remove the workflow editor.

## Context

- Affected files or components: The legacy workflow compatibility auditor, its
  focused tests, and ChatNotifier renewal evidence.
- Related docs:
  `docs/chat_notifier_legacy_workflow_provenance_merge_fixture_codex_task.md`
  and `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern:
  `ConversationWorkflowProvenanceMergeService`, the existing compatibility
  cohort counts, and aggregate provenance-shape reporting.
- Known quirks, compatibility rules, or release gates: Four records have
  dangling progress and conflicting plan documents and must remain outside the
  candidate cohort. Legacy checkpoints require separate aggregate accounting.

## Implementation Notes

- Preferred approach: Rebuild the deterministic approved plan projection for
  each provenance-only current workflow and legacy checkpoint, stabilize task
  IDs, apply the pure merge service, and accumulate typed blocker counts.
- Constraints: Open SQLite read-only, keep current and checkpoint results
  separate, emit no paths, identifiers, content, hashes, locators, or
  individual results, and return no transformed records from the auditor.
- Generated files needed: None.
- Migration or data compatibility concerns: Candidate validation must preserve
  the existing graph while proving that every matching item gains one
  approved-plan source. A blocked candidate remains evidence, not a repair.

## Similar-Pattern Search

- Search terms: `provenanceOnlyRecordCount`,
  `ConversationWorkflowProvenanceMergeService`, `buildApprovedArtifact`,
  `deriveExecutionProjection`, and `stabilizeTaskIds`.
- Files or modules inspected: Compatibility auditor and tests, compatibility
  service, plan projection service, merge fixture, and workflow entities.
- Follow-up tasks found: Define a separate conflict-policy investigation only
  after the 14-record candidate cohort passes aggregate validation.

## Acceptance Criteria

- Required behavior: Report evaluated, mergeable, and blocked counts plus
  typed merge blockers for current workflows and legacy checkpoints belonging
  to provenance-only records.
- Edge cases: Invalid legacy graphs, projection failure, records outside the
  clean cohort, fresh or inconsistent checkpoints, and empty cohorts.
- Failure paths: Operational database failures stay path-free; candidate
  blockers are aggregated without producing partial transformations.
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
