# Codex Task: Goal Auto-Continue Review Fixes, Round 2

Follow-up to `docs/goal_auto_continue_review_fixes_codex_task.md`. Commit
`94968146` implemented all ten Round-1 fixes correctly (verified in review).
A second review pass found 7 new issues, concentrated in code added *beyond*
the Round-1 scope. Line numbers refer to the branch state at `94968146`.

Work the tiers in order; keep the tree green (`tool/codex_verify.sh`) after
each tier.

## Tier 0 — correctness (fix before merge)

### 0.1 Positional completion inference completes on sub-item completion phrasing

`ConversationGoalProgressInference._looksComplete`
(`conversation_goal_progress_inference.dart:309`) was changed to positional
matching: a completion signal after the last incomplete signal marks the goal
complete. That correctly handles chronological narration ("was not complete
yet … verifier exited with code 0 … the goal is complete") but false-positives
on the extremely common progress phrasing where a *partial* completion follows
a remaining-work statement:

- `残り2件は未対応です。1件目の修正は完了しました。` → currently
  **completed** (wrong: two items remain). `残り` matches an incomplete
  signal, `完了しました` follows it, position wins. With no tool calls in the
  turn the `hasBlockingEvidence` gate does not protect this.

**Fix — two-tier completion signals.** Bare action-completion verbs cannot
positionally override an explicit remaining-work statement; only goal-scoped
or full-verification claims can. Split `_completionSignals`:

- `_goalScopedCompletionSignals` (may positionally override earlier
  incomplete narration): `'goal is complete'`, `'goal complete(d)'`,
  `'task is complete'`, `'all tasks are complete'`, `'all tasks completed'`,
  `'all checks passed'`, `'all verification checks passed'`,
  `'passes all verification checks'`, `'verifier exited with code 0'`,
  plus Japanese goal-scoped forms (e.g. `すべて完了`, `全て完了`,
  `すべてのチェックが通りました`, `検証がすべて通りました`).
- `_genericCompletionSignals` (everything else currently in the list:
  `'tests passed'`, `'completed successfully'`, `完了しました`, `実装しました`,
  `保存しました`, …): these keep the **old conservative rule** — they count
  only when NO incomplete signal appears anywhere in the response.

Logic: run the old whole-text check with generic signals; if it fails, run
the positional check (current code) restricted to the goal-scoped tier.
Failure-mode acceptance cases (all three must hold, add as tests in
`conversation_goal_progress_inference_test.dart`):

1. `残り2件は未対応です。1件目の修正は完了しました。` → NOT complete.
2. The existing canary narration (incomplete narration, then
   "verifier exited with code 0 … The goal is complete.") → complete
   (existing test keeps passing).
3. `残りのタスクはXですが、テストが通りました。` → NOT complete
   (`tests passed` is generic; remaining work stated).

Keep the positional recoverable/resolved-failure check as is.

### 0.2 sendHiddenPrompt wipes conversation-scoped content-tool dedup guards

`chat_notifier.dart:3066-3067` clears `_executedContentToolCalls` and
`_seenContentToolCallHashes` at continuation start. These two sets are
**conversation-scoped** duplicate-execution guards (cleared only in
`syncConversation` / `clearMessages`; `_sendMessageNow` deliberately
preserves them): if the model echoes an earlier turn's complete
`<tool_call>` tag text in new output, the hash check at line 6925 blocks
re-execution. Clearing them makes a continuation turn re-execute an echoed
side-effectful call that a normal turn would have blocked.

**Fix**: remove those two `clear()` calls from `sendHiddenPrompt`. Keep all
the other resets added in `94968146` (approval cache, pending buffers,
`_latestContentToolResults`, `_latestCompletedToolResults`,
`_contentToolContinuationCount`, `_contentToolExecutionTail`,
`_accumulatedTokenUsage`) — those are genuinely turn-scoped, matching
`_sendMessageNow`. Add a notifier test asserting the sets survive a hidden
continuation dispatch.

## Tier 1 — behavior hardening

### 1.1 Alternating edit/read turns defeat the no-progress stall stop

`ToolResultCompletionEvidence.compareProgress`
(`tool_result_prompt_builder.dart:61`) treats any unverified path-set
difference as `improved` — including transitions to/from an empty set. A goal
that alternates edit-only turns (unverified `[README.md]`) and read-only
cap-hit turns (exhaustion-only, empty set) registers "improvement" on every
comparison and runs to the full turn budget instead of stalling.

**Fix**: in the no-diagnostics branch, return `improved` only when **both**
path sets are non-empty and differ (real movement across files). Empty→
non-empty, non-empty→empty, identical sets, and exhaustion-only pairs are all
`noProgress`. Update the policy tests: edit→read→edit alternation reaches
streak 2 and stops; consecutive edit turns on *different* files still count
as improvement.

### 1.2 Streak mutation is a side effect of building the policy input

`_updateGoalAutoContinueProgressStreak`
(`chat_notifier_goal_auto_continue.dart:217`) mutates
`tracker.noProgressStreak` while the `GoalAutoContinuePolicyInput` is being
constructed, before the decision is known. Harmless today only because every
post-skip path resets the tracker via the next user message; any future
second evaluation or early-return corrupts the count silently.

**Fix**: make the helper pure — compute and return the candidate streak
without mutating; pass it to the policy; write
`tracker.noProgressStreak = candidateStreak` only on the paths that act on
the decision (continue dispatch, stopAndBlock, and the no-progress skip).

### 1.3 Stop-cause is string-coupled to policy reason text

`_goalAutoContinueNoticeKeyForStop` (`chat_notifier_goal_auto_continue.dart:243`)
and the `no_progress_stop` log label switch on the literal reason strings
(`'auto-continue turn budget reached'`, `'no measurable progress'`, …).
Rewording a reason in the policy compiles cleanly but silently drops the user
notice and mislabels session-log telemetry.

**Fix**: add an explicit
`enum GoalAutoContinueStopCause { turnBudget, goalBudget, noProgress }` field
to `GoalAutoContinueDecision` (null for other skips), set it in the policy,
and derive both the notice key and the session-log decision label from the
enum. Reason strings stay human-readable log text only.

## Tier 2 — cleanup

### 2.1 Dead `previousEvidence` field on the policy input

`GoalAutoContinuePolicyInput.previousEvidence`
(`conversation_goal_auto_continue_policy.dart:88`) is no longer read by
`decide()` after the streak refactor. Remove the field, the notifier call-site
plumbing, and the test fixtures that populate it.

### 2.2 completionEvidence computed twice per tool turn

The evidence scan (JSON-decoding every tool result) runs once inside
`completionBlockerInstructions` during final-prompt construction and again at
`chat_notifier.dart:6580` for `_latestGoalAutoContinueEvidence`. **Fix**:
compute it once where `finalToolResults` is assembled, store it, and change
`completionBlockerInstructions` to accept the precomputed
`ToolResultCompletionEvidence` (adjust its call site and tests; guard strings
must remain byte-identical).

## Similar-Pattern Search

- After 0.1: check `_looksBlocked` for the same sub-item ambiguity — it is
  still whole-text `containsAny`; confirm no change is needed and note why in
  the handoff.
- After 0.2: diff the reset lists of `_sendMessageNow` and `sendHiddenPrompt`
  side by side and record any remaining intentional differences as a code
  comment above the `sendHiddenPrompt` resets.
- After 1.3: grep for other reason-string comparisons
  (`decision.reason ==`) and migrate any stragglers to the enum.

## Acceptance Criteria

- The three phrasing cases in 0.1 behave as listed; existing inference tests
  stay green.
- A hidden continuation preserves `_executedContentToolCalls` /
  `_seenContentToolCallHashes`; approval cache is still cleared (Round-1 test
  keeps passing).
- Edit/read alternation stalls at streak 2 with the no-progress notice;
  multi-file doc progress does not stall.
- Notice + telemetry survive a policy reason-string reword (enum-driven).
- `flutter analyze` clean; guard strings unchanged.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_goal_progress_inference_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_goal_auto_continue_policy_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/tool_result_prompt_builder_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh
```

Live re-check after green: rerun
`tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh` — the
narration-completion path (0.1 case 2) is exercised there.

## Handoff Notes

- Summary:
- Tests run:
- Coverage or low-coverage notes:
- Risks or follow-ups:
