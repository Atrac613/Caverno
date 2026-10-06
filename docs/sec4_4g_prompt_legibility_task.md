# SEC4.4g Prompt Legibility

Status: completed 2026-09-24.

## Task

- Goal: make SEC4.4g approval prompts distinguishable from one another, and
  stop offering an option the handler throws away.
- User-visible behavior:
  - A SEC4.4g prompt for a command with a known risk leads with that risk
    ("Recursive file deletion") instead of the shared host-wide sentence.
  - SEC4.4g and out-of-project prompts list what the command does that its
    text does not show. That covers an inline interpreter program, a script
    whose contents are not shown, a redirect target, run-time expansion,
    piped program text, and `sudo`.
  - "Always Allow" is hidden when the allow would not be remembered.
- Non-goals: changing any decision. The gate, its sources, and what reaches a
  person are untouched.

## Context

- Every one of the 255 audited `opaque_host_write` prompts carried the same
  heading and rationale, whether the command was `grep` or `bash -c`. The
  heading also overwrote the command's own risk warning, so `rm -rf` read like
  `ls`.
- `LocalCommandToolHandler` and the `process_start` path never persist an
  allow for a fresh-approval command (`requiresFreshManualApproval`), but the
  sheet still offered "Always Allow". Pressing it ran the command once and
  asked again the next time.

## Implementation Notes

- `ShellCommandEffectNotes` is a quote-aware single-pass scan. It is display
  only. It never reduces friction, and no prompt calls a command safe, so a
  construct it misses costs a hint, not a decision.
- `LocalCommandApprovalPrompt.compose` keeps the historical shape for every
  other source, with the gate heading first and its rationale leading the
  body. It replaced `_escalatedApprovalWarningTitle` and
  `_escalatedApprovalWarningMessage`, whose only callers were these two sites.
- `PendingLocalCommand.canRememberAllow` gates the button. To pay for the
  field without raising `pending_tool_approvals.dart`'s zero-slack ratchet,
  `LocalCommandApproval` moved to `local_command_approval.dart`, which is
  re-exported.
- Remote Coding renders `warningTitle` and `warningMessage` as-is, so the
  phone gets the same heading and notes.

## Verification

```bash
tool/flutter_test_quiet.sh \
  test/features/chat/domain/services/shell_command_effect_notes_test.dart \
  test/features/chat/domain/services/local_command_approval_prompt_test.dart \
  test/features/chat/presentation/widgets/approval/approval_widgets_tiny_test.dart \
  test/quality/file_size_ratchet_test.dart
tool/codex_verify.sh
```
