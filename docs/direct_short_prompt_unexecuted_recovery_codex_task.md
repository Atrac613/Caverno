# Recover Unexecuted Short-Prompt Work

## Task

- Goal: Ensure an active auto-continue goal recovers when a synthetic
  short-prompt turn claims coding work without executing any tool.
- User-visible behavior: Caverno should keep the unsupported completion claim
  hidden and issue one bounded hidden continuation that performs the work.
- Non-goals: Redesign Goal Auto-Continue budgets, change Live LLM canary
  fixtures, or broaden saved-workflow execution ownership.

## Context

- Affected files or components: `ChatNotifier` Goal Auto-Continue finalization,
  session-log decision markers, and provider regression tests.
- Related docs: `docs/session_logs.md`.
- Reference implementation or pattern: Existing diagnostic-evidence and saved
  workflow continuation tests in
  `chat_notifier_goal_auto_continue_part.dart`.
- Known quirks, compatibility rules, or release gates: A synthetic request
  contract remains owned by Goal Auto-Continue. A non-synthetic saved workflow
  remains owned by the saved-task runner and must not be dispatched twice.

## Implementation Notes

- Preferred approach: Reproduce the production short-prompt path at the
  provider boundary, preserve the existing bounded policy, and record
  actionable skip decisions with their safe-boundary veto.
- Constraints: Do not expose unsupported completion claims or add an unbounded
  retry path.
- Generated files needed: None.
- Migration or data compatibility concerns: Session-log additions must remain
  backward-compatible optional fields.

## Similar-Pattern Search

- Search terms: `hasUnexecutedActionClaim`, `goal_auto_continue`,
  `saved workflow execution owns pending task continuation`,
  `firstVetoReason`.
- Files or modules inspected: Goal Auto-Continue policy, notifier finalization,
  short-prompt contract builder, saved-task execution, and provider tests.
- Follow-up tasks found: None.

## Acceptance Criteria

- Required behavior: A zero-tool coding completion claim under an active
  synthetic auto-continue goal triggers a second hidden request.
- Edge cases: The second request is bounded by the configured turn budget and
  contains the previous unexecuted-action evidence.
- Failure paths: An actionable skip records the policy reason and safe-boundary
  veto in the coding session log.
- Accessibility, localization, or platform expectations: Existing localized
  visible guard text remains unchanged.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: No-tool command completion claims now contribute authoritative
  incomplete evidence before finalization, so an active synthetic request goal
  dispatches its bounded recovery turn. Active-goal policy skips are also
  recorded with unexecuted-claim and safe-boundary evidence.
- Tests run: Focused provider regressions, `fvm flutter analyze --no-pub`, and
  `tool/codex_verify.sh` (3,233 tests passed).
- Coverage or low-coverage notes: No coverage run was required; provider tests
  exercise the production no-tool finalization and session-log paths.
- Risks or follow-ups: Rebuild the desktop app before repeating the original
  short-prompt Live LLM scenario; an already-running app still uses its older
  build.
