# LL36: Thread the Validation Exit Code Into the Progress Inference

Continues `04a71756`, which added an optional `validationExitCode` to
`ConversationExecutionProgressInference` and grounded the validation verdict in
it — but nothing passes it yet, so the LL34 grounding is inert in production.
This task wires the fact in.

> **RESOLVED 2026-07-22 — do not implement this task. The parameter should be
> removed, not wired.**
>
> The prerequisite below was answered in
> `docs/validation_status_three_paths_2026-07-22.md`. There are **three**
> writers of `validationStatus`, not one, and
> `ConversationValidationToolResultInference` (path C) already does exactly
> what this task proposes: it matches the task's `validationCommand` against
> the turn's tool results, parses `exit_code`, and produces a mechanical
> verdict. It runs *before* the prose inference and short-circuits it.
>
> Wiring `validationExitCode` into the prose inference would add a fourth
> derivation of the same fact, on the path that exists precisely as the
> no-mechanical-evidence fallback. Remove the inert parameter instead.
>
> The search was not wasted: path C's `isFailure` treated any stderr output as
> a failure, so `exit 0` + `"Switched to a new branch"` was recorded as
> blocked. Fixed and regression-tested; see the doc above.
>
> Everything below is kept as the record of the original (rejected) plan.

## Prerequisite: reconcile with the existing mechanical path — ANSWERED

1. **Which flows does each cover?** Path A (`CodingVerificationFeedbackService`)
   runs its *own* `dart test` over changed Dart files — coding mode, desktop,
   mutations present; it never runs the task's `validationCommand`. Path C
   (`ConversationValidationToolResultInference`) does cover the task's
   `validationCommand`, mechanically. Path B (the prose inference) is the
   fallback when neither has evidence.
2. **Which writes last?** Path C runs first and short-circuits the turn on a
   terminal status; path B only writes `validationStatus` when
   `isValidationRun` is true, and passes null otherwise.
3. **Is `validationExitCode` still needed?** No — remove it.

## Task

- **Goal:** Pass the validation command's actual exit code to
  `ConversationExecutionProgressInference.infer` on validation runs, so the
  mechanical fact decides `validationStatus` instead of the
  `_looksLikeValidationSuccessNarrative` prose heuristic.
- **User-visible behavior:** A validation run whose command failed (non-zero
  exit) is recorded as failed even if the response prose says it passed, and
  vice versa. No UI change.
- **Non-goals:**
  - Do not change the inference's fallback behavior when no command ran —
    `validationExitCode: null` must keep the current prose path exactly.
  - Do not change task-status (completed/blocked) logic; only `validationStatus`
    is grounded here.
  - Do not add a field to `ToolResultInfo`; its `result` string already carries
    `exit_code`, parseable with `CommandPayloadFacts`.

## Context

### Why this is not a one-line change

`_captureExecutionProgressFromLatestAssistantEvidence`
(`workflow_task_run_coordinator.dart:1786`) is the validation-run inference
path. It is called from **13 sites** and receives no tool results, and
`ConversationsNotifier.updateCurrentExecutionTaskProgressFromAssistantTurn`
(`conversations_notifier.dart:1305`) — the other infer caller — also has none.
So the exit code is not in scope where the inference runs. Threading it as a
parameter through 13 call sites in a budgeted 2380-line coordinator is the wrong
shape.

### The right shape: a state accessor, mirroring `_latestTurnChangedFilePaths`

The coordinator already reads latest-turn facts from conversation state without
threading — `_latestTurnChangedFilePaths()` (line 2361) reads
`currentConversation.effectiveTurnDiffs.lastOrNull`. Add a sibling
`_latestValidationExitCode(ConversationWorkflowTask task)` that:

1. Reads the current conversation's messages.
2. Finds the most recent command-execution tool result of this turn
   (`local_execute_command`, `run_tests`, and any other
   `ToolCallExecutionPolicy` command tool) whose command matches the task's
   `validationCommand`.
3. Parses its exit code with `CommandPayloadFacts.tryParse(result)?.exitCode`.
4. Returns null when no matching command ran (preserving the prose fallback).

Then pass it to the `infer(...)` call inside
`_captureExecutionProgressFromLatestAssistantEvidence` and inside the notifier
method (thread it as one optional parameter on that single method — it has two
callers, both in the coordinator).

### The correctness risk to get right

**Matching the wrong command result is worse than the prose fallback** — a wrong
mechanical verdict is asserted as fact. Be strict:

- Match the task's `validationCommand` against the tool call's command
  argument, normalized the way the coordinator already normalizes commands.
- Only consider the **latest** turn's results (a stale exit code from an earlier
  turn must not leak in).
- If more than one command matches, or the match is ambiguous, return null and
  fall back to prose rather than guess. A confident wrong answer is the failure
  mode; an honest "unknown" is safe.
- When the validation command is empty (`task.validationCommand` blank), return
  null.

### Affected files

- `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart`
  — add `_latestValidationExitCode`, pass it at the validation-run infer call.
  Budgeted (2380); the accessor is small but check the ratchet and lower/raise
  per the session's convention with a justification.
- `lib/features/chat/presentation/providers/conversations_notifier.dart` —
  add an optional `validationExitCode` parameter to
  `updateCurrentExecutionTaskProgressFromAssistantTurn`, forwarded to `infer`.
  Not budgeted.
- Reference: `lib/features/chat/data/datasources/command_payload_facts.dart`
  (the LL34 exit-code parser), `conversation_execution_progress_inference.dart`
  (the landed `validationExitCode` param).

## Similar-Pattern Search

- **Search terms:** `validationCommand`, `_latestTurnChangedFilePaths`,
  `CommandPayloadFacts`, `local_execute_command`, `run_tests`,
  `updateCurrentExecutionTaskProgressFromAssistantTurn`.
- Check whether `ConversationValidationToolResultInference`
  (the third lexical inference, which reads tool results directly) already has a
  cleaner exit-code path that this could reuse or converge with.

## Acceptance Criteria

- A validation run whose matched command exited non-zero yields
  `validationStatus == failed` even with success prose (coordinator-level test).
- A validation run whose matched command exited zero yields `passed` even with
  blocked/failure prose.
- No matching command in the latest turn → `validationExitCode` is null and the
  result is byte-identical to today (regression test over an existing
  validation fixture).
- An ambiguous or cross-turn match returns null, not a guessed verdict.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_execution_progress_inference_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/coordinators/workflow_task_run_coordinator_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- **Summary:** the mechanism (grounded `validationStatus`) is landed and tested
  in `conversation_execution_progress_inference.dart`; this task only sources
  the fact. Keep the default-null path exactly as-is.
- **Risks:** the command-matching correctness is the whole risk. Prefer null
  (prose fallback) over a confident wrong verdict. State in the handoff how you
  disambiguated multiple matches and cross-turn staleness.
