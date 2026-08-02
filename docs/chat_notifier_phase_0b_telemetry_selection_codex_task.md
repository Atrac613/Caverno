# ChatNotifier Phase 0B Telemetry Selection: Codex Task

## Task

- Goal: Select a finite first Phase 0B telemetry slice from every guard
  inventory entry that lacks a structured event, and make that selection
  mechanically reviewable.
- User-visible behavior: None. This task changes measurement definitions and
  validation only.
- Non-goals: Adding production telemetry, changing session-log schemas,
  refactoring `ChatNotifier`, wiring `ChatToolHandlerCatalog`, collecting a
  private corpus, or deriving live/dead action states.

## Context

- Affected files or components:
  - `tool/chat_notifier_guard_telemetry_selection.json`
  - `tool/analyze_chat_notifier_inventory.py`
  - `test/python/analyze_chat_notifier_inventory_test.py`
  - `docs/chat_notifier_guard_reachability_inventory.md`
- Related docs:
  - `docs/chat_notifier_architecture_renewal_plan.md`
  - `docs/chat_notifier_inventory_codex_task.md`
- Reference implementation or pattern: The finite static inventory contract in
  `tool/chat_notifier_guard_inventory.json` and its
  `--check-guard-manifest` validation.
- Known quirks, compatibility rules, or release gates:
  - Phase 0A currently has 52 entries whose `telemetryEvent` is `null`.
  - Missing telemetry is never evidence that a path is dead.
  - The two statically unreachable proposal-parsing delegates remain unresolved
    until a matching-build corpus supplies the contradiction check.
  - Production logging must not change until this selection is complete.

## Implementation Notes

- Preferred approach:
  1. Add one checked-in selection manifest that covers exactly the guard
     inventory entries whose `telemetryEvent` is `null`.
  2. Classify every selected entry as `instrument`, `covered`, or `defer`.
  3. Limit the first instrumentation slice to exactly one entry. Select
     `_shouldSkipCompletedToolResultFinalAnswerRecovery` because its decision is
     load-bearing, its two static roots are already known, and an existing
     `turn_exit` record can eventually carry metadata-only evidence.
  4. Defer every other unmapped entry with an explicit prerequisite. This is a
     work-in-progress limit, not a claim that those entries are unimportant or
     unreachable.
  5. Extend the existing analyser with
     `--check-telemetry-selection`. Validation must join the selection to the
     guard manifest by stable inventory ID and reject incomplete, duplicate,
     stale, or over-broad selections.
- Constraints:
  - Store no prompts, tool arguments, tool results, runtime file paths, or user
    content in the selection manifest. Stable source IDs retain repository
    paths so they can join the guard inventory exactly.
  - Require `metadata_only` data classification for an `instrument` entry.
  - Require planned event, finite recorded values, and verification commands
    for an `instrument` entry.
  - Require an existing event and verification commands for a `covered` entry.
  - Require a non-empty prerequisite and no event or recorded values for a
    `defer` entry.
  - Resolve `sourceRevision` to a full commit and require it to match the
    classified guard manifest revision.
  - Keep product Dart files and session-log schemas unchanged.
- Generated files needed: None.
- Migration or data compatibility concerns: None. The new manifest is a
  development-time measurement definition.

## Similar-Pattern Search

- Search terms: `--check-guard-manifest`, `telemetryEvent`, `turn_exit`,
  `guardDecisions`, `sourceRevision`.
- Files or modules inspected:
  - `tool/analyze_chat_notifier_inventory.py`
  - `test/python/analyze_chat_notifier_inventory_test.py`
  - `tool/chat_notifier_guard_inventory.json`
  - `docs/chat_notifier_guard_reachability_inventory.md`
- Follow-up tasks found:
  - Add the selected metadata-only decision to the existing `turn_exit` record.
  - Collect a hash-pinned matching-build corpus after the first telemetry slice
    is available.
  - Re-run selection before instrumenting a second entry.

## Acceptance Criteria

- Required behavior:
  - The selection manifest covers all and only the guard inventory entries with
    no mapped `telemetryEvent`.
  - Every selection ID is unique and still exists in the guard manifest.
  - Exactly one entry has disposition `instrument`.
  - The first entry is
    `_shouldSkipCompletedToolResultFinalAnswerRecovery` and proposes the finite
    states `not_evaluated`, `skip_recovery`, and `allow_recovery` on the existing
    `turn_exit` event.
  - All other entries have a reviewable `covered` or `defer` disposition that
    satisfies the schema-specific evidence rules.
  - The inventory document records the selection counts and names the first
    instrumentation slice without claiming runtime observations.
- Edge cases:
  - Missing, duplicate, stale, and already-covered selection IDs fail.
  - An `instrument` entry without metadata-only classification, event, finite
    values, or verification fails.
  - A `covered` entry without an existing event fails.
  - A `defer` entry with an event or without a prerequisite fails.
  - More than one `instrument` entry fails the first-slice WIP limit.
- Failure paths: Validation exits with status 2 and a concise English error.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --check-telemetry-selection tool/chat_notifier_guard_telemetry_selection.json
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: The checked-in selection covers all 52 unmapped candidates, selects
  one metadata-only first slice, and defers 51 candidates behind explicit
  prerequisites.
- Tests run:
  - `python3 test/python/analyze_chat_notifier_inventory_test.py`: 18 passed.
  - `python3 tool/analyze_chat_notifier_inventory.py --source-revision HEAD
    --guard-manifest tool/chat_notifier_guard_inventory.json
    --check-telemetry-selection
    tool/chat_notifier_guard_telemetry_selection.json`: 52 selected, one
    instrument, zero covered, and 51 deferred.
  - `tool/codex_verify.sh`: dependency install, generation check, project and
    package analysis, and package tests passed. The full Flutter suite reached
    6,475 passing tests and failed one unrelated existing assertion in
    `test/tool/run_coding_stalled_diagnostic_repair_live_canary_test.dart`; the
    test still requires the removed source text `.where(_isTodoVerifierCall)`.
- Coverage or low-coverage notes: Python validation is covered by focused unit
  tests; no product Dart behavior changes in this slice.
- Risks or follow-ups: Do not add the planned `turn_exit` field in this task.
  Reconcile the stale canary-runner source assertion in a separate focused
  change.
