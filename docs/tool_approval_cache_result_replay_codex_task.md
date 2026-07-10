# Codex Task: Stop ToolApprovalCache From Replaying Stale Execution Results

`ToolApprovalCache` exists to avoid re-prompting the user when the model
repeats an identical high-risk tool call after an approve/deny decision. It
currently caches the full `McpToolResult` and returns it on a same-turn
repeat, so the repeated call is **never re-executed**. For diagnostic
commands this replays stale output after the code has changed, breaking the
fix → re-verify pattern.

## Motivating Evidence (do not skip)

Session `~/.caverno/session_logs/coding/1b29b760-1962-4bd5-aca7-d9c1d3ccc7a4.jsonl`
(2026-07-09, build `c7e52afc`, CMVP-1 fixture, `tmp/todo`):

- Entry 13: `dart analyze` → exit 2, `warning - bin/todo.dart:1:8 - Unused
  import: 'dart:io'` (real at that moment).
- Entry 17: `edit_file` removes the import (`replacements: 1`).
- Entry 22: `read_file` confirms the import is gone.
- Entry 23: the model re-runs `dart analyze` to verify → receives a
  **byte-identical replay** of entry 13's stale result. The command was never
  executed: entry 13's args were `{command, reason}`, entry 23's were
  `{command, working_directory}`, but `_handleLocalExecuteCommand` resolves
  `working_directory` into the arguments *before* the cache lookup and the
  cache key strips `reason`, so both normalize to the same key.
- The model correctly suspected stale analyzer state, burned the remaining 6
  loop rounds chasing the phantom warning, hit
  `bounded_tool_loop_exhausted`, and the turn ended incomplete — while the
  project was already analyzer-clean on disk (verified afterwards:
  `dart analyze` → "No issues found").

Without this bug the run plausibly completes in one turn. Retroactive
suspicion (unverified): run 1's "Dart compile cache" misdiagnosis
(`73fa0bf3`, gen-6) and parts of run 2's pubspec flip-flop (`39ce9b0d`) may
be the same replay.

## Task

- Goal: cached **denials** keep replaying (that is the cache's purpose — an
  already-denied identical call must not re-prompt), but an
  allowed-and-executed command that the model repeats in the same turn is
  **re-executed**, skipping only the approval prompt (the identical call was
  already approved this turn).
- Non-goals:
  - Do not change `ToolCallExecutionPolicy` keys or the batch executor's
    success-dedup/failure-abort logic (`tool_call_batch_executor.dart`) —
    that layer governs *whether the loop proceeds*, not approval UX, and its
    semantics are deliberate (see `nonSemanticArgumentKeys` comments).
  - Do not weaken the approval gate itself; full-access / auto-review /
    manual flows stay as they are.
  - No TTL or cross-turn caching changes; the cache stays per-turn.

## Context

- `lib/features/chat/presentation/providers/tool_approval_cache.dart` — the
  cache. Key = toolName + JSON(arguments minus `reason`). Currently
  `Map<String, McpToolResult>`; it needs to distinguish "denied" entries
  (replayable) from "approved" entries (approval-skip only, re-execute).
  Suggested shape: store an entry type (denial result vs approval grant)
  instead of the raw result for approvals.
- `lib/features/chat/presentation/providers/chat_notifier_approval_handlers.dart`
  — `_lookupToolApprovalResult` / `_rememberToolApprovalResult`. All
  callers follow the pattern `cachedResult != null → return cachedResult;`.
- Call sites using the pattern (update all consistently):
  `chat_notifier_local_file_handlers.dart` (write_file ~177, edit_file ~269,
  rollback ~374, local_execute_command ~518),
  `chat_notifier_git_handlers.dart` (~48, ~158), plus the BLE /
  computer-use / SSH handlers that share the helper (grep
  `_lookupToolApprovalResult`). For each: a cached **denial** returns as
  today; a cached **approval** bypasses the gate but falls through to
  `_mcpToolService!.executeTool(...)`.
- Denial results are currently remembered via `_rememberToolApprovalResult(
  ..., McpToolResult(isSuccess: false, errorMessage: 'User denied ...'))`
  — keep those replaying verbatim so denial UX is unchanged.
- Note the read-only bypass: `LocalShellTools.isReadOnly(command)` executes
  without touching the cache at all; that path is unaffected.

## Similar-Pattern Search

Check the existing approval-cache tests (grep `ToolApprovalCache` under
`test/`) and extend them rather than writing a parallel suite. Check
`_recordApprovalAudit` call sites so the re-executed repeat is audited
sensibly (e.g. `decisionSource: 'cached_approval'`) instead of silently
skipping the audit trail.

## Acceptance Criteria

1. Unit test (cache): after remembering an approval for
   `local_execute_command {command: "dart analyze", working_directory: X}`,
   a lookup reports "approved, do not replay result"; after remembering a
   denial, lookup returns the denial result as today.
2. Notifier-level regression test reproducing the motivating sequence:
   approval-gated command fails (nonzero exit) → `edit_file` mutates the
   file → the *same* command re-runs and returns **fresh** output, without a
   second approval prompt. Follow the existing `sendMessage` repro-test
   patterns (see `chat_notifier_git_guardrails_part.dart` tests).
3. A denied command repeated in the same turn still does not re-prompt and
   still returns the denial.
4. Approval audit records the cached-approval re-execution.
5. `flutter analyze` and `flutter test` pass.

## Verification

Run the new tests plus the existing approval/auto-review suites. Manual
check: in coding mode with auto-review on, run `dart analyze` (failing),
apply a fix, re-run `dart analyze` — the second run must reflect the fix.

## Handoff Notes

If any handler intentionally relies on result replay for idempotence (none
found in review), call it out in the PR rather than special-casing silently.
English only in code/comments/commit messages (repo rule).
