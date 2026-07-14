# Repeated Command Diagnostic Repair Focus

## Task

- Goal: Carry a repeated authoritative command diagnostic into every
  subsequent coding request until a mutation, successful matching command, or
  changed diagnostic makes the focus stale.
- User-visible behavior: After the same verifier diagnostic appears twice, the
  execution snapshot tells the model to repair the sourced diagnostic instead
  of rediscovering the verifier or rerunning it unchanged.
- Non-goals: Blocking command execution, increasing tool-loop budgets,
  persisting transient verifier output across app restarts, or encoding
  fixture-specific paths and actions in the harness.

## Evidence

TODO minimal-prompt canaries repeatedly returned `todo_cli_missing` up to six
times in one run. Build `56fe82cc` now measures this accurately, but measurement
alone does not change the next request. The persisted workflow snapshot is
updated at turn boundaries, so command failures inside one tool loop are absent
from the refreshed per-request execution snapshot.

## Design

1. Build repair focus only from structured Error-severity diagnostics returned
   by an actionable command failure.
2. Activate the focus at an identical command diagnostic streak of two.
3. Overlay the focus on the immutable execution snapshot for each request,
   without mutating the persisted workflow contract.
4. Preserve clarification and blocked actions; otherwise project `repair` as
   the required next action.
5. Clear the focus after any successful file mutation, after a successful
   matching command, or when the command diagnostic changes.
6. Keep the existing command-failure behavior and iteration limits unchanged.

## Acceptance Criteria

- The second identical diagnostic produces a compact focus containing its
  relative path, code, and message.
- The next system prompt reports `Required next action: repair`, the repeated
  diagnostic streak, and a mutation-first instruction.
- Raw diagnostic payloads and absolute temporary workspace paths are not added
  to the focus.
- A diagnostic change does not retain the previous focus.
- A successful mutation or matching command removes the focus.
- Material clarification and blocked boundaries remain stronger than repair.
- Existing approval, command-failure, and Goal Auto-Continue tests remain green.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/command_diagnostic_streak_tracker_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/execution_snapshot_projector_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --no-codegen
```
