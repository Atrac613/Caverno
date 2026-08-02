# ChatNotifier Workflow-Origin Audit Task

## Task

- Goal: Add a deterministic read-only audit that classifies persisted
  workflows by provenance before the legacy authored-workflow path is changed.
- User-visible behavior: Maintainers can inspect aggregate workflow-origin
  counts without modifying the conversation database or exposing record data.
- Non-goals: Do not migrate, backfill, delete, or rewrite any conversation, and
  do not change the workflow editor or plan projection behavior.

## Context

- Affected files or components: A standalone audit tool, focused tool tests,
  and the ChatNotifier renewal ranking.
- Related docs: `docs/chat_notifier_renewal_candidate_ranking.md` and
  `docs/chat_notifier_concept_overlap_inventory.md`.
- Reference implementation or pattern: Read the authoritative conversation
  JSON payloads from the drift `conversations` table using SQLite read-only
  mode and reproduce the entity's execution-document hash contract.
- Known quirks, compatibility rules, or release gates: Manual workflow saves
  can create a plan artifact through reverse backfill while leaving projection
  provenance empty, so plan-artifact presence alone cannot prove plan origin.

## Implementation Notes

- Preferred approach: Classify records as no workflow, legacy authored,
  plan-derived fresh, plan-derived stale, plan-derived source missing,
  incomplete projection metadata, approved-plan provenance without projection,
  or invalid. Emit aggregate counts and a fail-closed retirement decision.
- Constraints: Open SQLite with `mode=ro` and `query_only`; emit no database
  path, conversation ID, title, message, plan text, or workflow content.
- Generated files needed: None.
- Migration or data compatibility concerns: Treat unparseable rows and
  incomplete provenance as blockers rather than guessing an origin.

## Similar-Pattern Search

- Search terms: `workflowSourceHash`, `workflowDerivedAt`,
  `ensureCurrentPlanArtifactBackfilled`, `approvedPlan`, and
  `effectiveExecutionDocumentHash`.
- Files or modules inspected: Conversation entities, plan artifacts,
  projection service, workflow editor actions, repositories, drift schema, and
  migration bootstrap.
- Follow-up tasks found: Define a compatible backfill only if the audit finds
  legacy-authored or provenance-incomplete records.

## Acceptance Criteria

- Required behavior: The audit deterministically reports every database row in
  exactly one class and distinguishes reverse-backfilled legacy workflows from
  plan-derived projections.
- Edge cases: Stale projections, missing source documents, partial metadata,
  approved-plan provenance without markers, empty workflows, and invalid JSON
  are classified explicitly.
- Failure paths: Missing databases or tables fail clearly; invalid records
  block retirement without exposing their contents.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/audit_conversation_workflow_origins_test.py
python3 tool/audit_conversation_workflow_origins.py --database <path>
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a path-free SQLite read-only audit and classified the current
  local database as 391 rows without workflow context, 29 fresh plan-derived
  workflows, and 19 legacy-authored workflows. All other classifications were
  zero, so direct workflow-authoring retirement is blocked.
- Tests run: All 5 focused Python tests pass, including every origin class,
  UTF-16 hash compatibility, read-only byte preservation, and failure paths.
  `tool/codex_verify.sh` passed generation, analysis, package tests, and 6,481
  of 6,482 Flutter tests; the only failure is the pre-existing stale
  `run_coding_stalled_diagnostic_repair_live_canary_test.dart` expectation for
  the removed `_isTodoVerifierCall` filtering expression.
- Coverage or low-coverage notes: Synthetic SQLite fixtures cover every origin
  class and verify that the database bytes remain unchanged.
- Risks or follow-ups: Aggregate evidence can determine whether M3 needs a
  legacy backfill, but it does not authorize that migration.
