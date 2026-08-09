# Validation progress paths and their terminal-evidence boundary (updated 2026-08-10)

Originally written to answer the prerequisite recorded on
`docs/ll36_validation_exit_code_wiring_codex_task.md`: before wiring the inert
`validationExitCode` parameter, establish how it relates to the mechanical
grounding that already exists. The answer is that it is redundant, and that
looking for it surfaced a real inversion. LL36 later tightened the boundary:
assistant prose is now advisory and cannot write a task or validation verdict.

## The three writers

Three paths observe validation progress, but only the two mechanically grounded
paths may now write a terminal verdict.

| | Path | Judged by | Command it looks at |
|---|---|---|---|
| **A** | `CodingVerificationFeedbackService` → `_recordCodingVerificationValidationProgress` | `output.exitCode` (mechanical) | **its own** `dart test` batches over changed `.dart` files |
| **B** | `ConversationExecutionProgressInference` → `updateCurrentExecutionTaskProgressFromAssistantTurn` | assistant prose, advisory only | none — reads the response text |
| **C** | `ConversationValidationToolResultInference` → `updateCurrentValidationProgressFromToolResults` | `exit_code` in the tool payload (mechanical) | **the task's** `validationCommand`, matched against the turn's tool results |

Path A is gated on `WorkspaceMode.coding`, desktop, a resolvable project root,
non-empty changed paths, and non-empty changed **Dart** files. It never runs the
task's declared validation command — it builds its own test commands. So it does
not cover non-Dart projects, mobile, or validation runs with no mutation.

Path A's trigger is `_shouldVerifyCodingCompletionClaim`, a prose
completion-claim detector. That is the intended shape, not a defect: a
heuristic may trigger, it may not judge. The verdict comes from the exit code.

Path B retains useful claim extraction for summaries and recovery routing. Its
result type contains booleans such as `reportsCompletion` and
`reportsBlocker`, but it cannot import workflow entities or return task or
validation status. The notifier preserves an existing terminal state and only
promotes a pending task to `inProgress` when assistant narration is the sole
new evidence.

## Which one wins

Path C runs before prose progress is stored and short-circuits the turn when a
grounded result reaches a terminal state. A successful typed validation result
may complete the task. A failed result for the task's non-empty saved
`validationCommand` is persisted as blocked only when no bounded recovery route
applies. Missing targets, unavailable dependencies, malformed tool calls, and
other explicitly recoverable failures still enter their existing recovery
paths first.

If a grounded tool failure remains unresolved after that bounded recovery and
the recovery produces narration but no tool result, the coordinator records a
stable grounded blocker reason. The narration supplies only the summary. This
closes the old asymmetry without letting prose outrank a tool outcome.

## Answer to the prerequisite: the parameter is redundant

Path C already does what the wiring task proposed: it selects the tool result
matching the task's `validationCommand`, parses `exit_code`, and produces a
mechanical verdict. Threading `validationExitCode` into path B would add a
**fourth** derivation of the same fact, on the path that exists precisely as the
no-mechanical-evidence fallback.

The inert `validationExitCode` parameter on
`ConversationExecutionProgressInference` was therefore **removed**, not wired.
LL36 then removed every status field from that inference result. The class now
carries a doc comment naming the grounded paths that own the fact, so the same
wiring idea is not re-derived from scratch later.

## What the search actually found

Path C's verdict was not grounded in the exit code the way it looked:

```dart
bool get isFailure =>
    failureDetail != null || (exitCode != null && exitCode != 0);
```

with `failureDetail: error ?? stderr`. So **exit 0 plus any stderr output was a
failure**. Reproduced before fixing:

```
git checkout -b feature/x   exit 0, stderr "Switched to a new branch"  -> failed / blocked
dart test                   exit 0, stderr "Warning: …"                -> failed / blocked
dart test                   exit 0, stderr ""                          -> passed
```

git writes routine output to stderr; so do `dart test`, `npm`, and most build
tools. A task validated by any of them was recorded as blocked while its command
had actually succeeded.

This is the LL34 inversion in miniature, on the one path that had the ground
truth in hand: a text signal outranking a mechanical one.

### The fix

`isFailure` now consults the exit code first, with two carve-outs that keep the
existing behaviour honest:

- **A null exit code is not exit 0.** It means the process never exited (denied,
  timed out, failed to spawn) or the tool reports no exit status at all (`ping`,
  `dns_lookup`, `http_*`). Only then does failure text decide. This is the same
  `ToolOutcome` invariant from LL34.
- **`forcedFailure`** marks the two cases where the failure holds regardless of
  exit status: a guardrail issue (output judged unusable, so it is not evidence
  either way) and the tool's own `error` field (the invocation failed, as
  distinct from the process writing to stderr).

Only three of the seventeen `_ParsedValidationToolResult` constructions carry an
exit code, so the other parsers are untouched.

`stderr` is still surfaced — as `successDetail` when stdout is empty — so the
"Switched to a new branch" text survives as detail rather than as a verdict.

## Current coverage note

Focused inference, notifier, coordinator, widget-recovery, and structural
quality tests lock the current boundary. Post-change live TODO and Markdown TOC
canaries on `qwen3.6-27b-vision` and `qwen3.6-35b-a3b-vision` all passed on
clean build `137a74df`. When no mechanical evidence exists, the task stays
non-terminal; the existing continuation or LL35 user-confirmation path owns the
next decision.
