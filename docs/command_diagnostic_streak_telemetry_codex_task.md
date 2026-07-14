# Command Diagnostic Streak Telemetry

## Task

- Goal: Measure repeated authoritative command diagnostics inside a tool loop,
  including repetitions that occur before Goal Auto-Continue runs.
- User-visible behavior: Live canary summaries report the actual maximum
  identical diagnostic streak instead of zero when a model repeatedly runs the
  same verifier without repairing the reported issue.
- Non-goals: Changing tool-loop budgets, blocking verifier calls, injecting a
  repair contract, or adding fixture-specific instructions.

## Evidence

Three TODO minimal-prompt live canaries passed on build `f15cfad8`, but the
verifier ran 4, 4, and 8 times. The third run returned `todo_cli_missing` six
times consecutively. Every summary still reported a maximum identical
diagnostic signature streak of zero because the existing metric only observes
Diagnostic Repair Contract activation at a Goal Auto-Continue boundary.

## Implementation

1. Track authoritative Error-severity diagnostic signatures per normalized
   command key.
2. Start a new streak at one, increment identical observations, and reset the
   command key after a successful result.
3. Log only the streak number and whether the signature changed; do not log the
   signature or raw diagnostic payload.
4. Include command-diagnostic streak events in the existing live canary maximum
   while preserving Repair Contract activation metrics.

## Acceptance Criteria

- Repeated equivalent diagnostics increment the same command streak.
- Diagnostic ordering and volatile locations do not split a streak.
- A substantive diagnostic change starts a new streak at one.
- A successful result resets only the matching command key.
- Non-authoritative or empty diagnostic payloads are ignored.
- Live canary summary parsing reports the maximum observed command or Repair
  Contract diagnostic streak.
- Existing repair and approval behavior remains unchanged.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/command_diagnostic_streak_tracker_test.dart
tool/codex_verify.sh --no-codegen --test test/tool/live_llm_canary_summary_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --no-codegen
```
