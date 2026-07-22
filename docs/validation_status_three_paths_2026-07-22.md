# Three paths write `validationStatus`, and one of them let stderr outrank the exit code (2026-07-22)

Written to answer the prerequisite recorded on
`docs/ll36_validation_exit_code_wiring_codex_task.md`: before wiring the inert
`validationExitCode` parameter, establish how it relates to the mechanical
grounding that already exists. The answer is that it is redundant, and that
looking for it surfaced a real inversion.

## The three writers

`ConversationExecutionTaskProgress.validationStatus` has three producers, not
the two the task doc assumed.

| | Path | Judged by | Command it looks at |
|---|---|---|---|
| **A** | `CodingVerificationFeedbackService` → `_recordCodingVerificationValidationProgress` | `output.exitCode` (mechanical) | **its own** `dart test` batches over changed `.dart` files |
| **B** | `ConversationExecutionProgressInference` → `updateCurrentExecutionTaskProgressFromAssistantTurn` | assistant prose | none — reads the response text |
| **C** | `ConversationValidationToolResultInference` → `updateCurrentValidationProgressFromToolResults` | `exit_code` in the tool payload (mechanical) | **the task's** `validationCommand`, matched against the turn's tool results |

Path A is gated on `WorkspaceMode.coding`, desktop, a resolvable project root,
non-empty changed paths, and non-empty changed **Dart** files. It never runs the
task's declared validation command — it builds its own test commands. So it does
not cover non-Dart projects, mobile, or validation runs with no mutation.

Path A's trigger is `_shouldVerifyCodingCompletionClaim`, a prose completion-claim
detector. That is the intended shape, not a defect: a heuristic may trigger, it
may not judge. The verdict comes from the exit code.

## Which one wins

Path C runs first, at `workflow_task_run_coordinator.dart:2042`, and short-circuits
the turn (`return true`) when the task reaches a terminal status. Path B is the
fallback. Path B only writes `validationStatus` at all when `isValidationRun` is
true — on other turns it passes `null`, which leaves the stored value alone.

One asymmetry, noted but not changed: the gate at 2042 only persists path C's
verdict when it says *passed*/*completed*. A mechanical **failed** verdict is
computed and then dropped, and the turn falls through to the prose path plus the
separate guardrails (`missingTargetFileFromValidationFailure`,
`hasOnlyRecoverableMalformedFailures`, …). Those guardrails plausibly justify
it — a failed validation is where recovery logic lives — so this is recorded as
a question, not a bug. It needs a real log before anyone touches it.

## Answer to the prerequisite: the parameter is redundant

Path C already does what the wiring task proposed: it selects the tool result
matching the task's `validationCommand`, parses `exit_code`, and produces a
mechanical verdict. Threading `validationExitCode` into path B would add a
**fourth** derivation of the same fact, on the path that exists precisely as the
no-mechanical-evidence fallback.

The inert `validationExitCode` parameter on
`ConversationExecutionProgressInference` was therefore **removed**, not wired,
in the commit following this one. The class now carries a doc comment naming
the two paths that own the fact, so the same wiring idea is not re-derived from
scratch later — the parameter had already been added once and looked
reasonable in isolation.

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

## Coverage note

This changes only path C. Path B still judges by prose when no matching tool
result exists, which remains correct: with no mechanical evidence, prose is all
there is. The LL35 ordering applies — the fourth rung (ask the user) is where
that case should eventually land, once the shadow data justifies it.
