# Command Diagnostic Streak-One Repair Focus

## Task

- Goal: Prevent an unchanged verifier replay after the first authoritative
  Error diagnostic without reducing completion reliability.
- User-visible behavior: The next coding request receives a soft repair focus
  after the first diagnostic; a repeated diagnostic receives stronger wording.
- Non-goals: Blocking verifier execution, changing tool-loop budgets, or
  adding fixture-specific entrypoint knowledge.

## Context

- Affected components: command-diagnostic focus tracking, execution snapshots,
  prompt projection, and generic live canary measurements.
- Related docs: `docs/repeated_command_diagnostic_repair_focus_codex_task.md`
  and `docs/command_diagnostic_repair_focus_observability_codex_task.md`.
- Evidence: Three TODO minimal-prompt runs each performed one unchanged verifier
  replay between streak 1 and streak 2, costing 17.4 to 21.3 seconds.
- Baseline: 3/3 passed, average duration 253.3 seconds, and one unchanged replay
  before repair focus in every run.

## Implementation Notes

- Activate transient repair focus at streak 1 for structured authoritative
  Error diagnostics.
- At streak 1, allow bounded inspection but require corrective action before
  rerunning unchanged validation.
- At streak 2 or above, state that the diagnostic repeated unchanged and use a
  stronger no-replay instruction.
- Use file-mutation wording only when at least one diagnostic identifies a
  path. Use generic corrective-action wording for pathless diagnostics.
- Preserve clarification and blocked boundaries, and keep existing focus-clear
  behavior after mutation, successful matching validation, or diagnostic reset.

## Similar-Pattern Search

- Search terms: `observation.streak >= 2`,
  `withCommandDiagnosticRepairFocus`, `Repeated command diagnostic streak`,
  and `CommandDiagnosticRepairFocus`.
- Files inspected: `stalled_diagnostic_repair_contract.dart`,
  `execution_snapshot_projector.dart`, `chat_notifier_goal_auto_continue.dart`,
  and the focused domain and notifier tests.
- Follow-up: Compare three new live runs against the committed observability
  baseline.

## Acceptance Criteria

- The first authoritative diagnostic activates repair focus at streak 1.
- The first focused prompt says inspection is allowed but unchanged validation
  must not be rerun before corrective action.
- Streak 2 uses stronger repeated-diagnostic wording.
- Path-backed diagnostics request a concrete file mutation.
- Pathless diagnostics request a corrective action without requiring a file
  mutation.
- Clarification and blocked actions remain stronger than repair.
- Focus clearing and command-diagnostic observability remain intact.
- Existing approval, tool-loop, and Goal Auto-Continue tests remain green.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/command_diagnostic_streak_tracker_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/execution_snapshot_projector_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --no-codegen
```

## Handoff Notes

- Summary: Repair focus now activates on the first authoritative Error
  diagnostic. Prompt strength increases for an unchanged repeated diagnostic,
  while pathless failures retain generic corrective-action guidance.
- Tests run: Focused domain, summary, and notifier tests passed (31 tests).
  `tool/codex_verify.sh --no-codegen` passed analysis and all 3,122 tests.
- Risks: A pathless diagnostic may require a non-file command, so its prompt
  must remain action-oriented rather than mutation-specific.
- Live comparison: Three clean-build TODO minimal-prompt runs passed in 279.7,
  197.8, and 229.3 seconds. The 235.6-second average is 17.7 seconds (7.0%)
  faster than the 253.3-second baseline. Every run activated repair focus at
  streak 1, recorded zero unchanged verifier replays before focus, and kept the
  maximum identical diagnostic streak at 1.
