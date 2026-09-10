# Anabasis delegation admission regression

## Goal and evidence

Prevent an addressed parent from recreating a completed saved task through
freeform delegation. Session `de0bc079-9b0b-4b4a-90a7-046c5a12d0f2`
showed a working CLI being overwritten after successful verification. The
parent's direct write was refused, but its subsequent child delegation had no
binding to a ready saved task. The child then returned three failed commands
inside a shell list whose trailing `echo` made the overall exit status zero.

Later records correct the initial triage: the child's `update_goal` request
was rejected because no goal was active, and the parent recognized the broken
CLI and requested a repair. A completed child run was not an accepted result.
No session-log payload or project fixture is committed here.

## Changes

- Planned Anabasis delegation requires an exact `workflow_task_id` from the
  current ready candidates. Missing, completed, running, blocked, unknown, or
  unmet-precondition selections are refused before either foreground or
  background child startup. The check uses the owner conversation, not the
  currently displayed conversation.
- The parent sees ready task IDs, including an explicitly empty queue. A ready
  selection appends its saved files, validation command and confirmed premises
  to the child instructions. Ordinary delegation and parents without saved
  tasks retain their existing behavior.
- Child catalogs and both dispatch adapters refuse parent goal updates, even
  if a model emits a hidden tool or rediscovers it through tool search.
- Foreground command observations no longer accumulate success with boolean
  OR. A later failure, compound shell expression or file mutation invalidates
  earlier success. Compound expressions are conservatively omitted rather than
  deriving command outcomes from prose. A returned run remains unaccepted.
- Tool schemas and foreground result construction are extracted to keep the
  existing notifier and catalog line ceilings; their budgets are lowered.

## Scope and limits

This is admission at spawn time, not a task reservation or an acceptance-state
implementation. It does not implement the separate worktree runner mapping,
post-dispatch premise invalidation, or enforce child file scope from prose.
A ready task ID is required to select planned work; it is not proof that the
result fulfills the task. Live model behavior has not been rerun.

## Verification

`tool/codex_verify.sh --no-codegen` with the ten affected delegation, prompt,
parser, observation and failure-classification suites passed 136 tests and
static analysis. The follow-up catalog, notifier, boundary and ratchet run
passed 480 of 483 tests. Its three failures already exist in base `9333d25f0`:

- `model_switch_settings_policy.dart`: 72 lines against 71.
- `composer_model_selector.dart`: 289 lines against 260.
- `chat_remote_datasource.dart`: 1,133 lines against 1,129.

Adjacent paths inspected: foreground/background spawn, the extracted
`SubagentToolHandler` dispatcher, inherited tool filtering, prompt projection,
readiness derivation, and structured refusal classification. Generated entities
and serialization are unchanged; no code generation is required.

## Child mutation and parent read replay follow-up

Session `49ef4b73-beca-450c-9929-66b06aea5e64` exposed another boundary:
a child read the repaired CLI at entry 59, while the parent received the old
file hash at entry 67. Child dispatch bypassed the outer tool-loop mutation
bookkeeping, so the parent read-replay cache still used its old generation.

The shared foreground/background child dispatcher now records workspace
mutations against the owning conversation immediately after each tool result,
before asking the child model for another completion. Confirmed file-mutation
outcomes also invalidate reads when the tool reports partial failure. Refused
writes and successful inspections do not advance the generation. A later child
failure cannot erase earlier side effects.

Regression coverage exercises foreground and background children, each with
successful completion and a model failure after mutation. It verifies the live
conversation generation and the read-replay cache's rejection of old content.
This follow-up does not change inline tool-tag parsing or final-answer recovery.

Follow-up verification: app and all three workspace-package analyzers passed;
20 tests across the subagent runtime, mutation observation and read-replay
suites passed, as did both Notifier line-budget checks. The suites were run
sequentially for the final report because the quiet wrapper uses a shared
report path. No live endpoint or application build was run.

## Saved-validation final response follow-up

The same session ended with a printed CLI tool call after all 14 tests passed.
The final request exposed no tools, and the response contained no native tool
calls. The existing content parser recognizes the printed call; accepting that
response as terminal text left an unexecuted action promise in the answer.

After saved validation succeeds, the terminal response policy now replaces
printed complete or incomplete tool calls with a validation-success report.
It also replaces pending action promises when native follow-up calls are
suppressed. Ordinary completion summaries remain intact. The existing native
post-validation evidence-call path is preserved; printed calls do not acquire
execution authority through this change.

Regression coverage includes the session's inline function-call shape,
incomplete tags, suppressed action promises, preserved summaries, and a saved
workflow integration check that the printed CLI command is never dispatched.
Adjacent paths inspected include native follow-up suppression, final text
recovery, and post-validation evidence filtering.

Final-response verification: app and all three workspace-package analyzers
passed, along with 348 tests in the terminal-response policy and ChatNotifier
suites. No live model replay was performed.

## Main integration verification

Integration with `36ee2a41c` required import-order conflict resolution only.
App and package analyzers and 430 tests across eight affected suites passed.
Three of five focused line-budget checks passed. The two Notifier checks
already exceeded their limits on main (8,740 primary lines and 19,731 aggregate
lines); integration reduces those counts to 8,737 and 19,718. Existing ceilings
remain tightened rather than being raised to accommodate upstream growth.
