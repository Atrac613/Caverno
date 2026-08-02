# ChatNotifier Legacy Workflow Compatibility Audit Task

## Task

- Goal: Apply the checked-in legacy workflow compatibility gate to persisted
  legacy-authored records through a deterministic read-only aggregate audit.
- User-visible behavior: Maintainers can see compatibility and blocker counts
  without modifying the conversation database or exposing record data.
- Non-goals: Do not migrate, backfill, rewrite, delete, or identify any
  conversation, and do not remove or change the workflow editor.

## Context

- Affected files or components: A Dart audit CLI, focused CLI tests, a
  development-only SQLite dependency, and ChatNotifier renewal evidence.
- Related docs:
  `docs/chat_notifier_legacy_workflow_compatibility_fixture_codex_task.md` and
  `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern:
  `ConversationLegacyWorkflowCompatibilityService` and the path-free,
  aggregate-only output contract in `tool/audit_conversation_workflow_origins.py`.
- Known quirks, compatibility rules, or release gates: The database must be
  opened with SQLite read-only mode and `query_only`; the audit must use the
  Dart entity decoder and compatibility service rather than duplicating the
  gate in Python.

## Implementation Notes

- Preferred approach: Read `conversations.payload` through `package:sqlite3`,
  select only legacy-authored workflow entities, evaluate each with the existing
  pure gate, and emit deterministic aggregate JSON.
- Constraints: Emit no database path, conversation ID, title, messages, plan or
  workflow content, checkpoint identifiers, or individual-record result.
- Generated files needed: None.
- Migration or data compatibility concerns: Invalid payloads must fail closed,
  the database bytes must remain unchanged, and compatibility evidence does not
  authorize persistence writes.

## Similar-Pattern Search

- Search terms: `OpenMode.readOnly`, `PRAGMA query_only`, `Conversation.fromJson`,
  `legacy_authored`, and `ConversationLegacyWorkflowCompatibilityService`.
- Files or modules inspected: Existing Python origin audit, Dart tool patterns,
  conversation entity decoding, compatibility gate, `pubspec.yaml`, and the
  resolved SQLite package API.
- Follow-up tasks found: Use the aggregate blocker distribution to decide
  whether a candidate transformer can be designed or a narrower preservation
  contract is required.

## Acceptance Criteria

- Required behavior: Report database-row, legacy-candidate, compatible,
  blocked, checkpoint, and blocker-kind counts with a fail-closed readiness
  decision.
- Edge cases: Invalid JSON, invalid entities, non-legacy workflows, multiple
  blockers on one record, missing databases, and missing tables.
- Failure paths: Operational errors are path-free and return a non-zero exit
  code; invalid records are counted and keep readiness false.
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
