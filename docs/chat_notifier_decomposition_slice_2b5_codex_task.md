# ChatNotifier Decomposition Slice 2b5: Saved-Workflow Ownership

## Task

- Goal: make saved validation commands and saved-task target scope resolve from
  the owning interaction generation, never from the visible conversation.
- User-visible behavior: a background saved-workflow turn validates and mutates
  only its own task even while another task is visible.
- Destination API:
  - replace `_currentSavedValidationCommandForToolLoop()` with
    `_savedValidationCommandForGeneration(int interactionGeneration)`;
  - replace `_currentSavedTaskForToolLoop()` with
    `_savedTaskForGeneration(int interactionGeneration)`;
  - require the generation at every guard, success-detection, recovery, and
    `ask_user_question` call site.
- Non-goals:
  - changing saved-workflow task selection order;
  - changing validation command normalization or target-path matching;
  - changing plan persistence or workflow status transitions;
  - extracting guardrails, recovery, or question handling;
  - adding a notifier part.

## Context

- Affected production files:
  - `lib/features/chat/presentation/providers/chat_notifier.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_turn_finalization_recovery.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart`.
- Direct deterministic test file:
  `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`.
- Existing regression files:
  - `test/features/chat/presentation/providers/chat_notifier_saved_workflow_guardrails_part.dart`;
  - `test/features/chat/presentation/providers/chat_notifier_ask_user_question_part.dart`.
- Exact source methods and call sites:
  - `_currentSavedValidationCommandForToolLoop` reads visible
    `currentConversation`;
  - `_containsOnlyPreviouslySuccessfulCurrentSavedValidationToolCalls`,
    `_toolResultsContainSuccessfulCurrentSavedValidation`,
    `_buildModifiedSavedValidationCommandGuardResult`, and turn-finalization
    recovery call it without an owner;
  - `_currentSavedTaskForToolLoop` reads visible `currentConversation`;
  - `_buildSavedTaskTargetScopeGuardResult` and `_handleAskUserQuestion` call it
    without an owner;
  - `_executeToolLoopBatch` already has `interactionGeneration` when it invokes
    both guardrails;
  - `_executeToolCalls`, `_recoverBeforeTurnFinalizationIfNeeded`, and
    `_handleAskUserQuestion` already receive or can receive the same generation;
  - `_conversationForGeneration` is the established owner lookup used by other
    detached-turn fixes.
- Current gap: single-thread tests exercise the guard rules but never poison the
  visible conversation with a different validation command and target set.

## Implementation Notes

- Resolve the owning `Conversation` once from `interactionGeneration` through
  `_conversationForGeneration`.
- Pass only immutable derived values to decision helpers:
  - the trimmed saved-validation command;
  - an immutable `ConversationWorkflowTask` snapshot;
  - an immutable list preserving the existing stored target-file spellings.
    Keep normalization inside the existing path matcher and preserve the
    structured payload format.
- Tracked tool-loop paths must not fall back to the visible conversation.
  An untracked dispatcher path with no interaction generation must bypass
  saved-workflow policy resolution rather than consulting visible state.
- Thread `interactionGeneration` through:
  - `_buildModifiedSavedValidationCommandGuardResult`;
  - `_buildSavedTaskTargetScopeGuardResult`;
  - `_containsOnlyPreviouslySuccessfulCurrentSavedValidationToolCalls`;
  - `_toolResultsContainSuccessfulCurrentSavedValidation`;
  - `_hasTerminalGoalSuccessToolResults`;
  - `_shouldSkipCompletedToolResultFinalAnswerRecovery`;
  - `_shouldSkipCompletedToolResultCodingContinuationRecovery`;
  - `_handleAskUserQuestion`.
- Keep comparison and payload builders pure once the owner snapshot is supplied.
- Typed side-effect ports:
  - tool execution remains the existing tool-loop batch dispatcher;
  - question resolution remains the existing `McpToolResult` return path;
  - conversation lookup remains notifier-owned and occurs before policy logic.
- Generated files and migrations: none.

## Deterministic Two-Thread Cases

Configure:

- thread A with validation `dart test test/a_test.dart` and target
  `lib/a.dart`;
- thread B with validation `dart test test/b_test.dart` and target
  `lib/b.dart`;
- distinct task IDs and titles so structured payloads reveal contamination.

Cover:

1. Start A, make B visible, then let A execute its exact validation. A's command
   is accepted and success detection uses A's validation.
2. In the same interleave, have A attempt B's exact validation command.
   Preserve current compatibility: the different command may execute as an
   ordinary command, but it must not be credited as A's saved validation and
   must not trigger saved-validation success, duplicate-success, or recovery
   shortcuts. Follow-up tool definitions must remain available.

   Separately, have A attempt
   `dart test test/a_test.dart && echo poison`. The existing modified-command
   guard must block it with `saved_validation_command_modified`; the payload's
   `saved_validation_command` must be A's command, never B's.
3. A write to `lib/a.dart` is allowed while B is visible. A write to
   `lib/b.dart` is blocked with `saved_task_target_scope_violation` whose
   `task_id` and `allowed_target_files` belong to A.
4. Invert the owners and repeat the validation and mutation assertions for B.
5. A saved-workflow continuation question raised while B is visible is resolved
   from A's task and includes A's task ID and saved validation.
6. Duplicate-success and turn-finalization recovery decisions use the same
   owning generation.

Assert structured tool results and executed tool arguments, not only final
assistant text.

## Similar-Pattern Search

- Search terms:
  - `_currentSavedValidationCommandForToolLoop`;
  - `_currentSavedTaskForToolLoop`;
  - `validationTask`;
  - `executionFocusTask`;
  - `currentConversation`;
  - `saved_validation_command`;
  - `allowed_target_files`.
- Inspect every caller, including tool-loop duplicate handling,
  turn-finalization recovery, and policy-resolved questions.
- Record other saved-workflow helpers that read visible conversation as
  follow-ups; do not add unrelated behavior fixes.

## Measurement, Manifest, and Coverage

- Expected declared notifier-part delta: `0`; the count remains `42`.
- Target same-library aggregate delta: `0`; reductions are acceptable, but the
  aggregate must remain at or below `22,900` physical lines.
- Manifest records `command_guardrails`, `tool_loop_batch`,
  `turn_finalization_recovery`, and `ask_user_question` remain `remaining`.
- Collaborator records and discovery markers: none.
- No size budget may increase.
- Current coverage baselines include:
  - `chat_notifier_command_guardrails.dart`: `342/369` (`92.68%`);
  - `chat_notifier_tool_loop_batch.dart`: `223/239` (`93.31%`);
  - `chat_notifier_turn_finalization_recovery.dart`: `107/118` (`90.68%`);
  - `chat_notifier_ask_user_question.dart`: `148/169` (`87.57%`).
- Coverage expectation: no changed target regresses; the checked primary target
  remains at least `92.68%`, and all new owner-propagation branches are hit.

## Acceptance Criteria

1. Saved validation lookup is generation-owned on every tool-loop and recovery
   path.
2. Saved target-scope lookup is generation-owned on every mutation guard path.
3. Policy-resolved continuation questions use the owning saved task.
4. Visible-thread values cannot be injected into the owning turn's saved-task
   metadata. `saved_validation_command`, `saved_task_id`, `task_id`,
   `task_title`, and `allowed_target_files` must come from the owning
   generation. A value explicitly supplied in a tool call may appear only in
   fields such as `attempted_command` or `attempted_path`.
5. Existing normalization, allowed-path semantics, and single-thread guard
   behavior remain compatible.
6. No generation-aware call falls back to visible conversation state.
7. All exact call sites listed above receive the generation explicitly.
8. No part, manifest, marker, schema, generated file, or budget change.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart \
  lib/features/chat/presentation/providers/chat_notifier_turn_finalization_recovery.dart \
  lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --set-exit-if-changed
tool/codex_verify.sh \
  --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --write-baseline tool/chat_notifier_turn_scope_baseline.json
git diff -- tool/chat_notifier_turn_scope_baseline.json
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
tool/codex_verify.sh --coverage
awk -v target='lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart' \
  -v minimum=92.68 '
    /^SF:/ { selected = index(substr($0, 4), target) > 0 }
    selected && /^LF:/ { found = substr($0, 4) + 0 }
    selected && /^LH:/ { hit = substr($0, 4) + 0 }
    END {
      rate = 100 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      exit !(found > 0 && rate + 0.001 >= minimum)
    }
  ' coverage/lcov.info
git diff --check
```

The corrected Slice 2b1 live canary is required because this slice changes
production guardrail, recovery, and question code. Record the actually
reachable base URL and exact warmed model.

## Stop Conditions

- Stop if a generation-aware path cannot resolve its conversation before
  lifecycle cleanup.
- Stop if the implementation retains a visible-conversation fallback on a
  tracked turn.
- Stop if making validation owner-aware requires changing task-selection,
  normalization, or workflow progression semantics.
- Stop rather than redefining an arbitrary different validation command as a
  modified form of the owning task's saved validation command.
- Stop and record adjacent ambient saved-workflow reads as follow-ups rather
  than widening this slice.
- Stop if the fix requires a provider/schema migration, a new notifier part,
  production extraction, or aggregate budget increase.

## Handoff Notes

- Record both task IDs, validation commands, target lists, and interaction
  generations.
- Record accepted and blocked tool calls with structured result codes.
- Record coverage for every changed target and the aggregate line count.
- Record every call site updated to pass generation.
- Keep this slice in one focused Conventional Commit.

## Implementation Evidence

Specification correction `41fa59ea` separated a foreign ordinary validation
command from an owner-command suffix mutation. Implementation commit
`514497de` resolves saved validation and saved-task policy from the registered
interaction owner. Before the fix, all six poison fixtures failed. The fixed
fixtures prove bidirectional exact validation, owner-only mutation scope,
owner-derived structured payloads, owner-scoped continuation questions,
duplicate-success handling, and turn-finalization recovery. An untracked
question bypasses saved-workflow policy instead of reading visible state.

The combined target verification passed all 349 tests, the detached-turn file
passed all 35 tests, and the file-size ratchet passed all 80 tests. Analyze, the
refreshed audit-baseline check, and `git diff --check` passed. The audit removed
exactly three reviewed ambient reads. The primary file remained 9,376 lines,
the declared part count remained 42, and the aggregate fell to 22,887 lines.

Final focused LCOV reports command guardrails at `345/368` (`93.75%`), tool-loop
batch at `224/240` (`93.33%`), ask-user-question at `152/169` (`89.94%`), and
turn-finalization recovery at `106/119` (`89.08%`). The mechanically checked
`92.68%` command-guardrail floor passes. Because the current finalization
denominator differs from the planning baseline, this evidence does not claim
an unmeasured no-regression result for that file.

The later integrated full-coverage run completed generation, analysis, and
package tests before the root suite reached `+4208 -2`. Its only failures were
the pre-existing `M33 release packaging report validates static packaging lane`
and `M33 release packaging CLI writes JSON and Markdown outputs` tests. The
latter reported `Ready: false` with `sparkle_appcast_configuration`,
`sparkle_s3_public_read_config`, and `sparkle_public_release_verifier` failed.
Slice 2b5 changes no M33 path, so those failures are unrelated.

The exact-model corrected Slice 2b1 live canary passed on 2026-07-28 against
loaded `qwen3.6-27b-vision` at `http://192.168.100.241:1234/v1`. Its exact exit
maps and zero-busy-owner evidence are recorded in the Slice 2b1 handoff. This
completes Slice 2b5.
