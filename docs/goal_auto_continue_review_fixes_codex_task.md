# Codex Task: Fix Review Findings in Goal Auto-Continuation

Follow-up to `docs/goal_auto_continue_codex_task.md`. A 12-finding code review
of the implementation (commits `5f935389..319ad9c5` on
`feature/coding-goal-slash-command`) surfaced correctness bugs concentrated in
the evidence/progress machinery. This task fixes them. Line numbers refer to
the current branch state.

Work the tiers in order; each tier should leave the tree green
(`tool/codex_verify.sh`).

## Task

- Goal: make the auto-continue evidence loop trustworthy (fresh verification
  results, sane progress accounting, no wrong auto-blocks), remove the
  destructive `/goal auto` parsing trap, and close the smaller UX/telemetry
  gaps found in review.
- Non-goals: no new evidence classes, no changes to the safe-boundary veto
  set, no reworking of the continuation dispatch (`sendHiddenPrompt`) beyond
  the fixes below, no changes to the live canary scenario itself (update its
  assertions only where a fix changes observable behavior).

## Tier 0 — evidence-loop correctness (must fix before merge)

### 0.1 Stale approval-cache results poison continuation verification

`sendHiddenPrompt` (`chat_notifier.dart:3050`) never calls
`_toolApprovalCache.clear()`, while `_sendMessageNow` does (line 2806). The
cache stores approval-backed tool **results** for a single turn
(`tool_approval_cache.dart:6`) and `_lookupToolApprovalResult`
(`chat_notifier_approval_handlers.dart:14`) replays them for identical calls.
A continuation turn that re-runs the identical verification command (the
normal case: `dart analyze`, a test command) therefore receives the stale
pre-fix output without executing anything — the model sees old errors, the
progress comparison sees no improvement, and the stall detector wrongly
blocks the goal.

**Fix**: clear `_toolApprovalCache` at the start of `sendHiddenPrompt`,
unconditionally (the cache is documented as per-turn; a hidden turn is a new
turn). Voice-mode hidden prompts do not rely on cached approvals, so the
behavior change is confined to what the cache doc already promises. Note the
consequence in a code comment: a continuation repeating a high-risk call will
re-enter the approval gate; in manual-approval mode that surfaces a pending
approval, which the next continuation evaluation correctly treats as a veto.

**Test**: notifier-level test that after a continuation dispatch the cache no
longer returns the previous turn's cached result (extend
`test/features/chat/presentation/providers/chat_notifier_goal_auto_continue_part.dart`).

### 0.2 Completion suppression is too broad — applies to every goal and to unverified-only evidence

`conversations_notifier.dart:1079`:
`if (inference.hasCompletion && !completionEvidence.hasIncompleteEvidence)`.
Because `hasIncompleteEvidence` includes `unverifiedChangePaths`, any goal
turn that edits files without running a command can never auto-complete —
including manual goals (autoContinue off) and inherently non-runnable work
(docs, config, translations). That is a regression: previously the completion
signal alone completed the goal.

**Fix**: split the evidence gate. Add
`bool get hasBlockingEvidence => boundedToolLoopExhausted || unresolvedErrorCount > 0;`
to `ToolResultCompletionEvidence` and use **that** in the completion
suppression. Unverified changes alone must not veto completion — they mean
"claims are unbacked", not "objectively broken". Keep
`hasIncompleteEvidence` (with unverified paths) as the **continuation
trigger** only: an auto-continue goal that edits without verifying still gets
a continuation prompting it to verify, but an honest completion claim on
non-runnable work completes the goal.

**Test**: extend `conversations_notifier_goal_test.dart`: completion signal +
unverified-only evidence ⇒ goal completes; completion signal + unresolved
errors ⇒ stays active.

### 0.3 Replace the stall check with an explicit no-progress streak

Two related defects:

- `conversation_goal_auto_continue_policy.dart:176` gates on
  `consecutiveAutoContinuations >= 2 && !improvement`, and the tracker
  counter (`chat_notifier_goal_auto_continue.dart:184`) only increments —
  it never resets on progress. After two continuations, a single plateau
  turn (e.g. the model reads code to plan its next fix; error count
  unchanged) blocks a steadily progressing goal. The blocked reason ("two
  continued turns made no diagnostic progress") is also factually wrong —
  only one comparison plateaued.
- `ToolResultCompletionEvidence.hasDiagnosticImprovementComparedTo`
  (`tool_result_prompt_builder.dart:56`) treats any path-set difference as
  improvement (a regression from 6 to 9 errors with a new file counts as
  progress) and returns `true` unconditionally when neither side has
  diagnostics or unverified paths — so exhaustion-only loops (cap hit while
  reading, no edits) never register as stalled and run until the turn
  budget.

**Fix** — replace the boolean comparison with a three-way classification and
a streak counter:

1. In `ToolResultCompletionEvidence`, replace
   `hasDiagnosticImprovementComparedTo` with
   `GoalEvidenceProgress compareProgress(ToolResultCompletionEvidence previous)`
   returning `improved` / `noProgress`:
   - both have diagnostics: count decreased ⇒ `improved`; count increased ⇒
     `noProgress` (a regression is not progress); count equal ⇒ `noProgress`
     regardless of path churn (fixed-one-broke-one is not net progress; the
     streak tolerance below absorbs legitimate plateaus).
   - diagnostics on one side only: errors appeared ⇒ `noProgress`; errors
     disappeared ⇒ `improved`.
   - no diagnostics on either side: unverified path sets differ ⇒
     `improved`; identical or both exhaustion-only ⇒ `noProgress`.
2. In `_GoalAutoContinueTracker`, add `int noProgressStreak`. After each
   continuation decision that had a `previousEvidence`, classify: `improved`
   ⇒ reset streak to 0; `noProgress` ⇒ increment. Keep
   `consecutiveAutoContinuations` for logging only.
3. Policy stall rule: stall fires when `noProgressStreak >= 2` (two
   consecutive no-progress comparisons — matching the original spec).
   Outcome depends on the evidence class:
   - latest evidence has diagnostics ⇒ `stopAndBlock` (current behavior,
     with an accurate blocked reason).
   - unverified-only or exhaustion-only evidence ⇒ **`skip`** with a
     distinct reason (e.g. `no measurable progress`), leaving the goal
     active. Blocking is reserved for objectively broken states; a docs
     goal editing the same file each turn must stop continuing but must not
     be marked blocked (review finding: healthy README goals were
     auto-blocked after two continuations).
4. Record the streak in the session-log evidence map for triage.

**Tests**: rewrite the stall cases in
`conversation_goal_auto_continue_policy_test.dart`: improve→improve→plateau
does NOT block; plateau→plateau blocks (diagnostics) or skips
(unverified/exhaustion-only); regression (count increase) counts as
no-progress; exhaustion-only pairs stall as skip.

### 0.4 `/goal auto` destructive parsing trap

`chat_page_goal_builders.dart:115` matches the exact lowercased strings
`'auto on'` / `'auto off'`. `/goal auto`, `/goal auto  on` (double space), or
`/goal auto onn` fall through to the objective branch (line 139) and silently
**replace the goal objective** with that text, resetting progress counters —
no confirmation, no undo.

**Fix**: tokenize the args (`trimmedArgs.toLowerCase().split(RegExp(r'\s+'))`)
before keyword matching:

- tokens == `['auto', 'on']` / `['auto', 'off']` ⇒ toggle (fixes the
  whitespace variant).
- tokens == `['auto']` or two tokens starting with `auto` whose second token
  is not on/off ⇒ `SlashCommandExecutionResult.keepInput` with a new usage
  hint key (e.g. `chat.slash_goal_auto_usage`: "Use /goal auto on or /goal
  auto off."), preserving the input.
- three or more tokens ⇒ objective, unchanged — a real objective like
  "auto scroll fix in the list view" must keep working (the established
  rule: only exact keyword forms are subcommands).

Add the key to both `en.json` and `ja.json`. **Tests**: extend
`chat_page_slash_commands_test.dart` for `auto`, `auto  on`, `auto onn`,
`Auto ON`, and a 3-token `auto ...` objective.

## Tier 1 — behavior and telemetry gaps

### 1.1 Deduplicate the evidence scanner

`ToolResultPromptBuilder.completionEvidence` (line 551) copy-pastes ~60 lines
of `completionBlockerInstructions`' scanning loop (lines 441–504): exhaustion
markers, diagnostic dedup keys, stale-mutation suppression, unverified-change
rule. **Fix**: make `completionBlockerInstructions` call
`completionEvidence(...)` once and derive its three guard messages from the
evidence fields (they map 1:1). Behavior-preserving refactor — the guard
strings must remain byte-identical (`tool_result_prompt_builder_test.dart`
already pins them).

### 1.2 Cancel leaves the auto-continue indicator stuck

`cancelStreaming` (`chat_notifier.dart:9476`) resets
`_isSchedulingGoalAutoContinue` and the persist flag but never clears
`state.goalAutoContinueCount/Budget`, so "Goal auto-continue N/M" stays in
the composer after the user stops a continuation. **Fix**: call
`_clearGoalAutoContinueIndicator()` in `cancelStreaming` after the state
finalization block. Test: cancel mid-continuation ⇒ indicator fields are 0.

### 1.3 Budget stop is invisible to the user

The budget path (`chat_notifier_goal_auto_continue.dart:122`) only writes
`appLog` + a session-log entry; the spec required a one-time user-visible
notice ("goal stays active, user notified once"). **Fix**: add a nullable
`String? goalAutoContinueNotice` to `ChatState`; set it (localized key, e.g.
`chat.goal_auto_continue_budget_reached`, both languages) on the
budget-stop path and on the new no-progress `skip` stop from 0.3; render it
once near the goal chip in `message_input.dart`; clear it in
`_sendMessageNow` alongside the indicator reset. Keep the existing one-time
guard (`_goalAutoContinueBudgetNotifiedConversations`) so it fires once per
conversation.

### 1.4 Null-arg tracker reset asymmetry

`_resetGoalAutoContinueTrackerForConversation(null)`
(`chat_notifier_goal_auto_continue.dart:21`) clears `_goalAutoContinueTrackers`
but not `_goalAutoContinueBudgetNotifiedConversations`. **Fix**: clear both
in the null branch.

## Tier 2 — coverage extensions (implement; flag in handoff if descoped)

### 2.1 Content-embedded tool turns produce no evidence

Evidence is captured only in the tool-aware batch path
(`chat_notifier.dart:6568`). Models that emit content-embedded `<tool_call>`
tags (common for local models) execute via `_latestContentToolResults`, so
evidence stays empty and auto-continue is silently inert for them. **Fix**:
at finalization, when `_latestGoalAutoContinueEvidence` is empty and content
tool results exist for the turn, compute evidence from those results before
`recordCurrentGoalTurn`. Test with a synthetic content-tool turn carrying an
error diagnostic payload.

### 2.2 Stale token usage recorded by usage-less endpoints

`_updateTokenUsage` (`chat_notifier.dart:8907` region) keeps the previous
value when the endpoint reports no usage, and `sendHiddenPrompt` never zeroes
`_accumulatedTokenUsage` — a continuation on such an endpoint re-records the
prior turn's total into `goal.tokenUsage`. **Fix**: reset
`_accumulatedTokenUsage = TokenUsage.zero` at the start of
`sendHiddenPrompt` (mirroring the turn-scoped semantics of the goal delta).

## Similar-Pattern Search

- After 0.1: grep other `sendHiddenPrompt`-style entry points or callers of
  `_sendWithTools` that skip the per-turn resets `_sendMessageNow` performs
  (`_toolApprovalCache.clear`, accumulator resets) and list any remaining
  asymmetries in the handoff notes.
- After 0.3: confirm nothing else consumed
  `hasDiagnosticImprovementComparedTo` (grep) before deleting it.
- After 0.4: check the other multi-token keyword ambiguity (`pause` /
  `resume` / `clear` remain single-token exact matches — do not change them).

## Acceptance Criteria

- Motivating scenario end-to-end: continuation turn re-runs the identical
  verify command and gets a **fresh** result; error count decreasing across
  continuations never blocks; plateau→plateau with remaining analyzer errors
  blocks with an accurate reason; docs-goal (unverified-only) plateau stops
  continuing but leaves the goal active with a visible notice.
- A manual goal completing honestly on doc edits auto-completes again.
- `/goal auto` never mutates the objective.
- All guard strings emitted by `completionBlockerInstructions` are unchanged.
- `flutter analyze` clean; all listed test suites green.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_goal_auto_continue_policy_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/tool_result_prompt_builder_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/conversations_notifier_goal_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/pages/chat_page_slash_commands_test.dart
tool/codex_verify.sh
```

Live re-check after green: rerun
`tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh` and confirm
in the session log that continuation turns execute (not replay) the verify
command and that `goal_auto_continue` entries show the streak resetting on
improvement.

## Handoff Notes

- Summary:
- Tests run:
- Coverage or low-coverage notes:
- Risks or follow-ups:
