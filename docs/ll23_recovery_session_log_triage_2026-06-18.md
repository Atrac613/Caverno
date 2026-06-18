# LL23 Recovery Session Log Triage - 2026-06-18

This note records the first post-LL23 triage pass for coding turns where the
model produced prose that promised a next coding action but did not emit a tool
call. The goal was to make the continuation-stall signature visible in bounded
session-log summaries before relying on Live LLM canaries alone.

## Tooling Update

`tool/caverno_session_log_summary.dart` now emits
`coding_action_promise_without_tool` when all of these are true:

- The entry is a final-answer candidate with no response tool calls.
- The request or operation indicates a coding/tool-enabled turn.
- The response text looks like a promise to inspect, edit, run, port, implement,
  or otherwise continue coding work.
- The response does not look like completed coding work.

The summary exposes the signal in JSON as
`codingActionPromiseWithoutToolWarning` and in Markdown as
`Coding action promise without tool`.

## Triage Inputs

Commands:

```bash
dart run tool/caverno_session_log_summary.dart --log /Users/noguwo/.caverno/session_logs/coding/a2644c4f-b2c3-4612-b953-c9e3eae58c40.jsonl
dart run tool/caverno_session_log_summary.dart --log /Users/noguwo/.caverno/session_logs/coding/7d0aa61c-63e0-4bb3-9402-7c384c9f6800.jsonl
dart run tool/caverno_session_log_summary.dart --log /Users/noguwo/.caverno/session_logs/coding/90f8edf9-47e0-4834-b513-22f0dffa9d89.jsonl
```

## Results

| Log | Result | Entries | Errors | Tool calls | Loop-limit prompt | Coding action promise warning | Notes |
|-----|--------|---------|--------|------------|-------------------|-------------------------------|-------|
| `a2644c4f-b2c3-4612-b953-c9e3eae58c40.jsonl` | `error` | 21 | 2 | 7 | no | yes, 2 warnings | Reproduces the continuation-stall signature while also showing two connection-refused secondary-call errors. |
| `7d0aa61c-63e0-4bb3-9402-7c384c9f6800.jsonl` | `complete` | 31 | 0 | 10 | no | no | Completed without the coding action-promise warning; only an unrelated ephemeral-memory draft warning was reported. |
| `90f8edf9-47e0-4834-b513-22f0dffa9d89.jsonl` | `loop_limit_recovered` | 57 | 0 | 53 | yes | yes, 4 warnings | Shows repeated continuation-stall signatures before loop-limit recovery produced a usable final answer. |

## Live Canary Follow-up

Command:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=qwen3.6-35b-a3b-vision CAVERNO_CODING_GOAL_LIVE_EDIT_REPEAT_COUNT=1 tool/run_coding_goal_live_edit_canary.sh
```

Report:

`build/integration_test_reports/coding_goal_live_edit_canary_1781761340/canary_summary.json`

Result:

- Overall status was `failed`; 5 of 6 tests passed.
- The Git lifecycle case recovered after two turn-finalization recovery
  requests and two recovery tool calls.
- The remaining failure was the package-like parser fixture. The model emitted a
  bracketed `[Tool: edit_file]` request in final-answer text after an
  `edit_file` mismatch, so the request was marked unexecuted instead of being
  re-entered into the tool loop.
- The next LL23 slice targeted that gap by treating bracketed coding tool
  requests as recoverable finalization candidates in coding mode.

Post-fix rerun:

`build/integration_test_reports/coding_goal_live_edit_canary_1781762065/canary_summary.json`

- Overall status was still `failed`; 3 of 6 tests passed.
- `assistantAuthoredToolBlockCount` dropped to `0`, which confirms the
  bracketed final-answer tool-block signature did not recur in this run.
- The remaining package-like parser failure ended with a field-name mismatch
  (`ipv6` vs. `useIpv6`) and no passing fixture-test tool result.
- The file lifecycle failure completed create, initial read, update, delete, and
  deletion verification, but missed the required second `read_file` after the
  update.
- The Git lifecycle failure completed the core init, commit, revert, and clean
  status sequence, then drifted into extra tool-plan text and redundant actions
  before the canary assertion.
- This keeps LL23 blocked, but narrows the next work to completion verification
  and required-step coverage rather than bracketed final-answer tool blocks.

## Terminal Goal Success Guard

The post-fix rerun showed that the Git lifecycle path could satisfy the
terminal tool evidence, ignore an immediate follow-up tool call, and then still
enter turn-finalization coding-continuation recovery because earlier assistant
preambles remained in the same assistant message.

The follow-up guard skips turn-finalization coding-continuation recovery when
the latest completed tool results already satisfy an existing terminal goal
success predicate:

- successful saved validation command
- successful Git lifecycle: init, file creation, add, commit, revert, and clean
  status after revert

Focused coverage:

```bash
fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart --name "sendMessage stops follow-up tools after git lifecycle succeeds"
```

This keeps the terminal completion response intact and prevents a recovery
request from restarting a completed lifecycle.

Post-guard live rerun:

`build/integration_test_reports/coding_goal_live_edit_canary_1781763052/canary_summary.json`

- Overall status was `passed`; 6 of 6 tests passed.
- Main readiness was `ready`.
- The Git lifecycle case passed without recreating the reverted file.
- The package-like parser and file lifecycle cases also passed in this run,
  leaving no visible blocker failures in the coding-goal live edit canary.

Repeat stability rerun:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=qwen3.6-35b-a3b-vision CAVERNO_CODING_GOAL_LIVE_EDIT_REPEAT_COUNT=2 tool/run_coding_goal_live_edit_canary.sh
```

`build/integration_test_reports/coding_goal_live_edit_canary_1781763710/canary_summary.json`

- Overall status was `passed`; 12 of 12 tests passed across two isolated runs.
- Main readiness was `ready`, with 0 blocker failures and 0 warning failures.
- The rerun covered direct edit-and-test, red-green repair, two-file
  coordination, package-like parser repair, file lifecycle, and Git lifecycle
  scenarios twice.
- Turn-finalization recovery still executed in 3 requests with 3 recovery tool
  calls, and coding-continuation recovery requests were observed 3 times
  without follow-up tool calls.
- Assistant-authored tool blocks were observed twice, but the canary still
  converged and the Git lifecycle guard ignored redundant post-success tool
  calls instead of restarting completed work.

Main-gate follow-up:

```bash
CAVERNO_QWEN36_MAIN_LLM_RUN_PM5=1 tool/run_qwen36_main_llm_gate.sh
```

Exact-preservation report:

`build/integration_test_reports/qwen36_main_llm_gate/plan_mode_live_suite_macos_1781765267725/plan_mode_live_suite_macos_report.json`

PM5 smoke report:

`build/integration_test_reports/qwen36_main_llm_gate/plan_mode_live_suite_macos_1781765349611/plan_mode_live_suite_macos_report.json`

- The initial exact-preservation scenario passed: 1 of 1 scenario passed,
  report quality was `ready`, and task drift was 0.
- The broader PM5 smoke suite failed: 0 of 3 scenarios passed, report quality
  was `blocked`, and task drift was detected in 2 scenarios.
- `live_host_health_scaffold` repeatedly transformed the saved validation
  command `test -f requirements.txt` into shell-wrapper variants with
  `&& echo ... || echo ...`; the live harness denied each modified command.
- `live_cli_entrypoint_decision` and `live_clarify_recovery` created
  `README.md` while the active saved task target was only `requirements.txt`,
  producing `unexpectedChangedFiles` task drift.
- This kept the focused LL23 coding-goal recovery evidence green, but blocked a
  broad main-gate promotion until saved validation command preservation and
  active-task target-scope enforcement were tightened.

Resolution follow-up:

```bash
CAVERNO_QWEN36_MAIN_LLM_RUN_PM5=1 tool/run_qwen36_main_llm_gate.sh
```

Exact-preservation recovery report:

`build/integration_test_reports/qwen36_main_llm_gate/plan_mode_live_suite_macos_1781770291875/plan_mode_live_suite_macos_report.json`

PM5 smoke recovery report:

`build/integration_test_reports/qwen36_main_llm_gate/plan_mode_live_suite_macos_1781770362512/plan_mode_live_suite_macos_report.json`

Ping canary recovery summary:

`build/integration_test_reports/qwen36_main_llm_gate/plan_mode_ping_cli_canary_1781770461/canary_summary.json`

Chat and budget recovery summaries:

- `build/integration_test_reports/qwen36_main_llm_gate/chat_background_process_live_canary_1781770518/canary_summary.json`
- `build/integration_test_reports/qwen36_main_llm_gate/qwen36_main_llm_chat_canary_1781770569/canary_summary.json`
- `build/integration_test_reports/qwen36_main_llm_gate/tool_result_budget_live_canary_1781770608/canary_summary.json`

- The rerun passed the exact-preservation scenario, PM5 smoke suite, Ping CLI
  canary, chat background-process canary, Chat live canary, and tool-result
  budget canary.
- PM5 smoke passed 3 of 3 scenarios with report quality `ready`, 0 warnings,
  0 task drift, and 4 saved validations reaching natural stops.
- The exact-preservation and PM5 smoke runs still exercised guard recovery:
  modified validation commands were blocked, then the model recovered to the
  exact saved validation command and completed.
- This clears the broad Qwen3.6 main-gate blocker created by the initial PM5
  run. Keep the saved-validation guard as an expected runtime rail rather than
  treating wrapper attempts as model-fatal when the model recovers to the exact
  saved command.

## Interpretation

The new summary signal separates the target failure class from ordinary
streaming completion and from unrelated memory-draft warnings:

- `a2644...` confirms the exact user-reported pattern: a final coding response
  promised more work without a tool call.
- `90f8...` confirms the same pattern can repeat across a longer exchange and
  still recover later through the loop-limit path.
- `7d0...` is a useful negative control because it exercised coding tools and
  finalization without triggering the new warning.

This evidence supports keeping the LL23 finalization gate and continuation
recovery stack, then using Live LLM canary runs to confirm that the warning count
stays at zero after the recovery path is active.
