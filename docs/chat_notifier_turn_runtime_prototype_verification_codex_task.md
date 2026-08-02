# ChatNotifier TurnRuntime Prototype Verification: Codex Task

## Task

- Goal: Bind the mechanically selected `TurnRuntime` prototype part to one
  focused test and one live canary, then validate that mapping before any
  production extraction begins.
- User-visible behavior: None. This task adds development-time verification
  metadata and validation only.
- Non-goals: Creating `TurnRuntime`, moving goal auto-continue behavior, changing
  task-status ownership, moving conversation-scoped trackers, running the live
  canary, implementing prototype comparison, or wiring the tool catalogue.

## Context

- Affected files or components:
  - `tool/chat_notifier_turn_runtime_prototype_verification.json`
  - `tool/measure_chat_notifier_turn_runtime_prototype.py`
  - `test/python/measure_chat_notifier_turn_runtime_prototype_test.py`
  - `docs/chat_notifier_turn_runtime_prototype_verification_codex_task.md`
- Related docs:
  - `docs/chat_notifier_architecture_renewal_plan.md`
  - `docs/chat_notifier_turn_runtime_prototype_selection_codex_task.md`
- Reference implementation or pattern:
  - `tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh`
  - `tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart`
  - `test/features/chat/presentation/providers/chat_notifier_test.dart`
  - `test/features/chat/presentation/providers/chat_notifier_goal_auto_continue_part.dart`
- Known quirks, compatibility rules, or release gates:
  - The clean-revision selector chose
    `chat_notifier_goal_auto_continue.dart` with 14 turn-reachable identity
    entrypoints.
  - The focused tests are declared in a Dart part file but executed through
    `chat_notifier_test.dart`.
  - The live canary requires `CAVERNO_LLM_BASE_URL`, `CAVERNO_LLM_API_KEY`, and
    `CAVERNO_LLM_MODEL`; this slice validates its static contract but does not
    claim a new live run.
  - Task status and conversation-scoped goal trackers must remain outside the
    first extraction until their explicit boundaries are ready.

## Implementation Notes

- Preferred approach:
  1. Add one checked-in schema-v1 verification manifest for the selected part.
  2. Record the exact focused-test command, declaring part, test name, contract,
     and source-backed expected evidence.
  3. Record the exact live-canary command, runner, test source, test name,
     contract, and source-backed expected evidence.
  4. Identify at least one selected identity entrypoint exercised by the
     verification path and bind it to the selected production source file.
  5. Add `validate-gates` to join a fresh selector output to the manifest and
     write a validated selection artifact atomically.
- Constraints:
  - Require the selected part and production source path to match exactly.
  - Require both commands, contracts, test names, and evidence lists.
  - Require every migrated-path symbol to be one of the selector's resolved
    turn-reachable identity entrypoints and to exist in the selected source.
  - Require the focused command to name its executable test and exact plain
    test name.
  - Require the live runner to name its canary test source and exact plain test
    name.
  - Require every evidence token to exist in its declared repository source.
  - Reject placeholder evidence and never treat a static gate validation as a
    successful live-canary run.
  - Keep all Dart production and test files unchanged.
- Generated files needed: None.
- Migration or data compatibility concerns: None. The manifest is a
  development-time contract.

## Similar-Pattern Search

- Search terms: `validate-gates`, `plain-name`, `goal_auto_continue`,
  `turn_exit`, `_hasOrderedTriple`, `expected evidence`.
- Files or modules inspected:
  - `docs/chat_notifier_architecture_renewal_plan.md`
  - `tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh`
  - `tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart`
  - `test/features/chat/presentation/providers/chat_notifier_goal_auto_continue_part.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
- Follow-up tasks found:
  - Complete M1 task-status single ownership before task state crosses the
    runtime boundary.
  - Design a conversation-scoped goal-tracker port before the selected part is
    prototyped.
  - Add `compare` only after the isolated production prototype exists.

## Acceptance Criteria

- Required behavior:
  - `validate-gates` accepts a fresh selection whose selected part matches the
    verification manifest.
  - The validated output preserves the selection SHA and selected metrics and
    adds a SHA-256 binding to the verification manifest.
  - The focused gate identifies the hidden goal auto-continuation path.
  - The live gate identifies ordered `turn_exit`, `goal_auto_continue`, and
    continuation-request evidence plus a terminal goal condition.
- Edge cases:
  - A selected-part or source-path mismatch fails.
  - Missing focused or live commands fail.
  - Missing contracts, test names, migrated symbols, or evidence fail.
  - A symbol outside the selected identity-entrypoint set fails.
  - A command that does not name its test path and exact test name fails.
  - Missing evidence text in a declared source file fails.
- Failure paths: Validation exits with status 2 and does not write a partial
  output artifact.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/measure_chat_notifier_turn_runtime_prototype_test.py
python3 tool/measure_chat_notifier_turn_runtime_prototype.py select \
  --audit tool/chat_notifier_turn_scope_baseline.json \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --source-revision HEAD \
  --require-clean \
  --output /tmp/chat_notifier_turn_runtime_candidate.json
python3 tool/measure_chat_notifier_turn_runtime_prototype.py validate-gates \
  --selection /tmp/chat_notifier_turn_runtime_candidate.json \
  --verification-manifest tool/chat_notifier_turn_runtime_prototype_verification.json \
  --output /tmp/chat_notifier_turn_runtime_selection.json
git diff --check
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run:
  - Existing focused Flutter test passed before implementation:
    `goal auto-continue dispatches one hidden continuation from current evidence`.
- Coverage or low-coverage notes: Pending implementation.
- Risks or follow-ups: The live canary is statically bound in this slice but is
  not rerun or claimed as current runtime evidence.
