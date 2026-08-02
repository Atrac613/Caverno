# Completed Tool-Result Recovery Telemetry: Codex Task

## Task

- Goal: Record whether completed-tool final-answer recovery was not evaluated,
  evaluated and skipped, or evaluated and allowed for every persisted
  `turn_exit` entry.
- User-visible behavior: None. The response, recovery decision, and UI content
  remain unchanged.
- Non-goals: Instrumenting another guard, collecting a private corpus, changing
  an action state, refactoring `ChatNotifier`, or wiring
  `ChatToolHandlerCatalog`.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/turn_finalization_state_registry.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_turn_finalization_recovery.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_turn_exit.dart`
  - `lib/features/chat/data/datasources/llm_session_log_store.dart`
  - Focused registry, notifier, and session-log tests
  - Guard inventory, telemetry selection manifest, and renewal status docs
- Related docs:
  - `docs/chat_notifier_phase_0b_telemetry_selection_codex_task.md`
  - `docs/chat_notifier_guard_reachability_inventory.md`
  - `docs/chat_notifier_architecture_renewal_plan.md`
- Reference implementation or pattern: Owner-scoped hints and transforms in
  `TurnFinalizationStateRegistry`, serialized by `recordTurnExit`.
- Known quirks, compatibility rules, or release gates:
  - The selected decision runs only after several finalization early exits, so
    `not_evaluated` must be represented explicitly.
  - Runtime turns dispose owner state immediately after terminalization. The
    decision must be read before disposal and late writes must not recreate it.
  - Both classified and unclassified `turn_exit` paths must emit the field.
  - Session-log payloads are sensitive; record only one finite enum value.
  - The checked-in selection validator must support the selected entry moving
    from `instrument` to `covered` when the guard inventory mapping lands.

## Implementation Notes

- Preferred approach:
  1. Add a typed three-state decision to `TurnFinalizationStateRegistry`, with
     `notEvaluated` as the state created by `begin` and owner-local updates.
  2. Evaluate the existing recovery policy exactly once as before, then record
     `skipRecovery` or `allowRecovery` without changing the returned boolean.
  3. Require `LlmSessionLogStore.recordTurnExit` callers to supply the decision
     value and serialize it at
     `turnExit.guardDecisions.completedToolResultFinalAnswerRecovery`.
  4. Supply `not_evaluated` when an unclassified exit has no active owner.
  5. Transition the selection entry to `covered`, map the guard inventory event,
     and let the validator retain one bounded first slice as either active
     `instrument` or completed `covered` work.
- Constraints:
  - Allowed serialized values are exactly `not_evaluated`, `skip_recovery`, and
    `allow_recovery`.
  - Store no prompt, response, tool result, tool argument, user content, or
    runtime path with the decision.
  - Do not increment the session-log schema version; this is an additive
    optional-object field within the existing v2 record.
  - Do not change recovery policy inputs, output, call ordering, or retry count.
  - Do not add notifier callbacks or longer-lived ambient state.
- Generated files needed: None.
- Migration or data compatibility concerns: Older v2 JSONL records omit
  `guardDecisions`; readers must continue to tolerate that.

## Similar-Pattern Search

- Search terms: `recordTurnExit`, `_recordTurnExitIfUnclassified`,
  `_turnEnd.transforms`, `setHint`, `not_evaluated`, `guardDecisions`.
- Files or modules inspected:
  - `chat_notifier_execution_runtime.dart`
  - `chat_notifier_response_finalization.dart`
  - `turn_finalization_state_registry.dart`
  - `llm_session_log_store.dart`
  - `triage_session_logs.py`
- Follow-up tasks found: Collect a hash-pinned matching-build corpus before
  selecting a second instrumentation candidate.

## Acceptance Criteria

- Required behavior:
  - Every newly recorded `turn_exit` contains
    `guardDecisions.completedToolResultFinalAnswerRecovery`.
  - A turn that exits before the selected guard records `not_evaluated`.
  - A true guard result records `skip_recovery`.
  - A false guard result records `allow_recovery`.
  - The existing recovery result, final response, and tool-call counts do not
    change.
  - The guard inventory maps the structured event and the selection manifest
    marks the first slice `covered`.
- Edge cases:
  - Equal generations in different conversations cannot exchange decisions.
  - Reset restores `not_evaluated`; disposal rejects late writes.
  - An unclassified exit without an owner still records `not_evaluated`.
  - Logging-disabled turns do not create session-log files.
  - Older records without `guardDecisions` remain readable.
- Failure paths: Session-log write failures retain the existing best-effort
  behavior and do not affect the response.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
fvm flutter test \
  test/features/chat/presentation/providers/turn_finalization_state_registry_test.dart \
  test/features/chat/data/datasources/session_logging_chat_datasource_test.dart \
  test/features/chat/presentation/providers/chat_notifier_test.dart
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --check-telemetry-selection tool/chat_notifier_guard_telemetry_selection.json
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Every newly persisted `turn_exit` now includes the metadata-only
  `completedToolResultFinalAnswerRecovery` decision. Turn-owned state starts at
  `not_evaluated`, records `skip_recovery` or `allow_recovery` after the
  existing policy evaluation, and remains isolated across equal-generation
  conversations. The Phase 0B selection is marked `covered`; no recovery
  behavior or session-log schema version changed.
- Tests run:
  - `python3 test/python/analyze_chat_notifier_inventory_test.py`: 20 passed.
  - Guard inventory and telemetry selection validation: 52 selected, zero
    instrument, one covered, and 51 deferred.
  - Focused registry, session-log, and `ChatNotifier` tests: 333 passed.
  - File-size and thread-scoped-state ratchets: 250 passed without raising a
    budget.
  - `fvm flutter analyze`: no issues.
  - `tool/codex_verify.sh`: dependency install, generated-file check, project
    and package analysis, and package tests passed. The full Flutter suite
    reached 6,475 passing tests and failed one unrelated existing assertion in
    `test/tool/run_coding_stalled_diagnostic_repair_live_canary_test.dart`; the
    test still requires the removed source text `.where(_isTodoVerifierCall)`.
- Coverage notes: Registry tests cover all three decision states, owner
  isolation, reset, disposal, and late writes. Session-log tests cover the
  exact `skip_recovery` and `not_evaluated` payloads. Existing notifier tests
  continue to cover both policy outcomes and turn-exit paths.
- Follow-up: Collect a hash-pinned matching-build corpus before selecting a
  second guard. Repair the stale canary-runner source assertion as a separate
  focused change.

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Cover the three serialized values and
  owner-isolation lifecycle directly.
- Risks or follow-ups: Do not select a second guard in this task.
