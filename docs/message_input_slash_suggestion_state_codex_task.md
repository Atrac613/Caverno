# MessageInput Slash Suggestion State Refactor Task

## Task

- Goal: Extract the slash-command suggestion state calculation from
  `MessageInput` into a small, pure presentation helper.
- User-visible behavior: Slash-command suggestions, keyboard selection,
  dismissal, tab completion, and command submission behavior must remain
  unchanged.
- Non-goals: Do not change slash-command parsing semantics, command execution,
  prompt template behavior, attachment handling, input history, voice recording,
  worktree session sending, or coding-goal controls.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/widgets/message_input.dart`
  - `lib/features/chat/presentation/widgets/message_input_slash_suggestion_state.dart`
  - `test/features/chat/presentation/widgets/message_input_slash_suggestion_state_test.dart`
  - `test/features/chat/presentation/widgets/message_input_test.dart`
- Related docs:
  - `docs/large_file_refactor_plan.md`
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference implementation or pattern:
  - Existing pure presentation helpers in `lib/features/chat/presentation/`
    keep state derivation testable without widget pumping.
- Known quirks, compatibility rules, or release gates:
  - The repo requires English-only code, docs, comments, and commit messages.
  - Use `tool/codex_verify.sh` for verification.
  - Large-file refactors should move one concern at a time and update ratchets.

## Implementation Notes

- Preferred approach:
  - Add an immutable value object that owns the current suggestions, selected
    index, and dismissed text.
  - Keep `MessageInput` responsible for text controller mutation, snack bars,
    executing commands, and rebuilding widgets.
  - Delegate suggestion filtering and selected-index clamping to the helper.
- Constraints:
  - Preserve identity-based suggestion equality to avoid unnecessary widget
    rebuilds.
  - Preserve attachment and slash-command-enabled guards.
  - Preserve the exact dismissal behavior for Escape and tab completion.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

Before finishing, inspect adjacent `MessageInput` concerns to confirm this
slice does not accidentally merge unrelated composer behavior.

- Search terms:
  - `_slashSuggestions`
  - `_selectedSlashSuggestionIndex`
  - `_dismissedSlashSuggestionsForText`
  - `_buildSlashSuggestions`
- Files or modules inspected:
  - `lib/features/chat/presentation/widgets/message_input.dart`
  - `lib/features/chat/presentation/slash_commands/slash_command.dart`
  - `test/features/chat/presentation/widgets/message_input_test.dart`
- Follow-up tasks found:
  - Re-characterize another independent composer action before extracting
    input history, attachments, or goal controls.

## Acceptance Criteria

- Required behavior:
  - Suggestions appear only when slash commands are enabled, no attachment is
    selected, and the current text has not been dismissed.
  - Selection index clamps when the suggestion list shrinks.
  - Arrow navigation wraps through suggestions.
  - Applying a suggestion clears suggestions, resets selection, and records the
    completed command text as dismissed.
  - Dismissing suggestions clears suggestions, resets selection, and records the
    current text when requested.
- Edge cases:
  - Empty suggestion lists reset selection to zero.
  - Negative or out-of-range indexes clamp to valid values.
  - Equivalent suggestion lists should preserve state without forcing mutation.
- Failure paths:
  - Unknown commands, missing required arguments, and unexpected arguments stay
    in `MessageInput` because they depend on localized feedback and execution.
- Accessibility, localization, or platform expectations:
  - No user-facing strings move in this slice.

## Verification

Use focused tests first:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/widgets/message_input_slash_suggestion_state_test.dart \
  --test test/features/chat/presentation/widgets/message_input_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Use the default gate before handoff:

```bash
tool/codex_verify.sh --no-codegen
```

## Handoff Notes

- Summary: Extracted `MessageInputSlashSuggestionState` so slash suggestion
  refresh, selected-index clamping, wrapping, tapped index selection, dismiss
  state, and completed-command suppression are covered by pure tests. Kept
  controller mutation, localized feedback, command execution, attachments,
  history, worktree sending, voice recording, and coding-goal controls in
  `MessageInput`.
- Tests run:
  - `tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/widgets/message_input_slash_suggestion_state_test.dart --test test/features/chat/presentation/widgets/message_input_test.dart`
- Coverage or low-coverage notes: Focused verification passed analysis, 31 root
  tests, and 13 internal-package tests. `message_input.dart` fell from 2,374 to
  2,332 lines, and the extracted helper is ratcheted at 131 lines.
- Risks or follow-ups: Re-characterize one remaining MessageInput composer
  action before extracting more code. Do not widen this helper into execution,
  history, attachments, or goal controls.
