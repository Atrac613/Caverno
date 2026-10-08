# LL36 Final-Answer Transform Coverage (2026-08-09)

## Decision

LL36's additive instrumentation and structural enforcement are complete. Guard
deletion is still a No-Go until a model-varied post-provenance corpus exists.

## Gaps found

`FinalAnswerMessageNoticeService` could change the visible final answer without
always identifying the transform. The missing paths were:

- an unexecuted tool request;
- an unexecuted file side effect;
- a timed-out command success claim; and
- a failed command success claim.

The caller also recorded a transform only when an explicit owner was supplied,
although the normal call path has a generation-owned turn. Finally,
`_executeToolCalls` reset `TurnFinalizationStateRegistry` on every entry. A
pending-action transform recorded before a nested recovery loop therefore
disappeared before `turn_exit` serialization.

## Implementation

- Assign stable transform IDs to all four final-answer mutation paths.
- Resolve the active generation owner when the caller does not pass an explicit
  owner.
- Initialize turn-finalization state once at runtime turn start and remove the
  reset API, so transforms accumulate across nested tool loops.
- Stage the pending-action canary's failed verifier result at the real built-in
  command boundary.
- Give the staged failure one exact behavior-neutral source-marker repair so
  the mutation-before-reverification guard observes real progress before the
  full verifier runs.

The changes landed as four focused commits:

- `e4be9e0c` — stable final-answer transform telemetry and owner coverage;
- `b32a40ee` — built-in verifier-boundary staging;
- `fa69b083` — nested-loop turn-state preservation; and
- `4c0efc96` — deterministic behavior-neutral canary repair.

## Verification

Deterministic checks passed:

- all five final-answer notice service tests;
- generation-owned normal-path transform serialization;
- detached-turn owner isolation;
- turn-finalization registry re-entry preservation;
- 26 non-live TODO canary tests, with 9 live-only skips;
- the canary wrapper and summary tests;
- Flutter analysis; and
- the 279-test file-size and lexical-guard quality set.

The standard `tool/codex_verify.sh` gate also completed successfully: generated
files were clean, all package analysis and tests passed, and the root Flutter
suite passed all 6,919 tests.

The trusted local endpoint run used:

- endpoint: `http://192.168.100.241:1234/v1`;
- model: `qwen3.6-27b-vision`;
- clean build: `4c0efc96`;
- report: `build/integration_test_reports/coding_pending_action_length_recovery_live_canary_1786276525`;
- result: 1/1 passed in 55,881 ms, readiness `ready`.

The owner-scoped `turn_exit.transforms` sequence was:

1. `pending_action_length_recovery`
2. `coding_continuation_recovery_length_truncated_pending_action`

The verifier's typed exit status moved from 1 to 0. Triage reported two LL34
comparisons, both `agree` with typed provenance. LL35 reported the known
`goal_completion_tool_accepted_lexical_missed` disagreement: the accepted
`update_goal` completion was authoritative and the final prose omitted the
legacy lexical phrase, which is expected after LL35's lexical demotion.

## Remaining evidence gate

Do not delete a lexical guard from this one fixture. Collect normal coding goals
across multiple models and surfaces with build provenance at or after
`4c0efc96`, then evaluate each candidate's firing distribution together with
its grounded disagreement records. LL37 remains gated on that measurement, not
on additional LL36 telemetry code.
