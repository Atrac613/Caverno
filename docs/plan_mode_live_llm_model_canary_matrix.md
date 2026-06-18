# Plan Mode Live LLM Model Canary Matrix

This document tracks live Plan Mode compatibility by model. Use it when
switching local or remote OpenAI-compatible models so behavior differences are
recorded with the canary artifacts that prove them.

## How To Run

Use the PM5 live gate for each model baseline:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20 \
CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 \
tool/run_plan_mode_pm5_live_gate.sh
```

The PM5 gate runs:

- the live smoke suite (`live_host_health_scaffold`,
  `live_cli_entrypoint_decision`, `live_clarify_recovery`)
- the ping CLI live canary (`live_ping_cli_completion`)
- the chat background-process live canary (`chat_background_process`)

For stability-focused background-process checks, increase
`CAVERNO_PLAN_MODE_PM5_BACKGROUND_PROCESS_REPEAT_COUNT` or run the focused
helper directly:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_REPEAT_COUNT=3 \
tool/run_chat_background_process_live_canary.sh
```

For quick rediscovery after a fresh full PM5 pass, use the narrower ping canary:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_REPEAT_COUNT=1 \
tool/run_plan_mode_ping_cli_live_canary.sh \
  "Create a Python CLI script that pings a specific host. Generate a reviewable plan first. The approved plan must contain exactly one implementation task. That task must create only the root-level ping_cli.py file. Do not create README.md, requirements.txt, test files, or any other project files. Implement until that single approved task finishes, validate with python3 ping_cli.py --help, then provide a final answer summarizing ping_cli.py and validation evidence unless you are genuinely blocked."
```

## Result Matrix

| Date | Endpoint | Model | Check | Result | Smoke | Ping Canary | Unexpected Warnings | Task Drift | Artifact Content Fit | Notes |
|------|----------|-------|-------|--------|-------|-------------|---------------------|------------|----------------------|-------|
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | PM5 live gate | Failed | 2/3; `live_clarify_recovery` failed | Not reached by PM5; same-model standalone ping canary passed 1/1 | 0 | 0 detected | Not reviewed | Failed before execution in clarify recovery because no stream-with-tools log was observed after approval. |
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | Focused `live_clarify_recovery` rerun | Passed | 1/1 focused scenario | Not applicable | 0 | 0 detected | No issue recorded | The PM5 failure did not reproduce when the scenario ran alone; approval used live harness fallback and execution reached tool-aware streaming. |
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | PM5 live gate retry | Passed | 3/3 | 1/1 | 0 | 0 detected | No issue recorded | Provisional pass after one failed PM5 attempt; smoke used live harness fallback for all scenarios and cleanup cancellation occurred in two smoke scenarios. |
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | PM5 live gate | Passed | 3/3 | 1/1 | 0 | 0 detected | Concern: content mixed across target files | First PM5 pass; all scenarios used live harness approval fallback. Planning often returned empty content with `finishReason.length` and useful text only in reasoning. |
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Focused `live_readme_first_canary` | Passed | 1/1 focused canary | Not applicable | 0 | 0 detected | Pass: README-only content | Artifact convergence passed; saved validation guard stopped a duplicate follow-up `write_file` after `ls README.md` succeeded. |
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | PM5 live gate rerun | Passed | 3/3 | 1/1 | 0 | 0 detected | Concern: follow-up tasks appeared in smoke logs | Second PM5 pass; smoke report quality was ready. Ping canary had one allowed recovered-create warning and no task drift. |
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Focused `live_readme_first_canary` rerun | Failed | 0/1 focused canary | Not applicable | 0 | 1 detected | README-only content was written but convergence failed | Report quality blocked on missing saved-validation success and missing expected saved task target files. |
| 2026-05-22 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Focused `live_readme_first_canary` post-fix rerun | Passed | 1/1 focused canary | Not applicable | 0 | 0 detected | Pass: README-only content | Previous artifact baseline. Report quality was ready, saved target tracking matched `README.md`, and convergence used one guard activation plus one natural stop. |
| 2026-05-23 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Smoke suite post-fix rerun | Passed | 3/3 | Not run in this focused rerun | 0 unexpected; 1 allowed `recoveredCreateParseWarning` | 0 detected | No artifact-content issue recorded | Previous smoke comparison baseline. Report quality was ready; all scenarios used live harness approval fallback; tool-loop convergence had 3 saved validations, 2 guard activations, and 1 natural stop. |
| 2026-05-23 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | Full model-switch baseline | Passed | 3/3 | 1/1 | 0 | 0 detected | Pass: README-only content | Current full-surface pass: README 1/1, chat 3/3, budget 1/1, routine 4/4. Smoke used live harness fallback for all scenarios; cleanup cancellation occurred in two smoke scenarios; chat embedded-tool continuation recovered after a transient stream disconnect. |
| 2026-05-23 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | Post-hardening full-surface rerun | Passed | 3/3 | 1/1 | 0 | 0 detected | Pass: README-only content | Current reference rerun after routine scoped-notification hardening: README 1/1, chat 3/3, budget 1/1, routine 4/4. Chat and routine had 0 recovery signals; budget had the expected single compaction retry. |
| 2026-05-23 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Full-surface candidate rerun | Failed | 3/3 | 1/1 | 0 | 0 detected | Pass: README-only content | PM5, README, chat, and budget passed, but routine passed only 3/4. The `contents` argument alias branch failed after the model emitted a raw special-token tool-call shape instead of an executable tool call. |
| 2026-05-24 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Post-routine-guard candidate rerun | Passed | 3/3 | 1/1 | 0 | 0 detected | Pass: README-only content | Routine rerun passed 4/4 after the missing required write guard. The regenerated reference report passed 13/13 and qwen comparison had 0 hard regressions, with README guard activation remaining as a watch signal. |
| 2026-05-24 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Same-revision PM5 rerun | Failed | 3/3 | 0/1 | 0 | 0 detected | Not rerun after PM5 failure | PM5 smoke passed, but the ping CLI canary failed with `workflowBlocked`. The model wrote a syntax error (`return result.return`) in `ping_cli.py`, then repeated the same failing validation command instead of repairing the file. |
| 2026-05-24 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Same-revision PM5 retry | Passed | 3/3 | 1/1 | 0 | 0 detected | Not rerun in this PM5 retry | The immediate PM5 retry passed, so the ping CLI failure is not deterministic. Keep this as recovery-heavy evidence: smoke still needed task-proposal recovery, memory fallback, tool-less recovery, and one cleanup cancellation; ping finished with a saved-validation guard. |
| 2026-05-24 | `http://192.168.100.241:1234/v1` | `gemma4-26b-vision` | Same-revision full-surface rerun after PM5 retry | Passed | 3/3 | 1/1 | 0 | 0 detected | Pass: README-only content | README 1/1, chat 3/3, budget 1/1, and routine 4/4 passed on the same app revision after the PM5 retry. The generated reference report passed 13/13; comparison against qwen had 0 hard regressions, 1 README guard watch signal, and 1 PM5 cleanup improvement. Keep qwen as the named reference until gemma has repeat clean same-revision evidence or the team accepts the prior PM5 instability. |
| 2026-05-26 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | Focused coding goal edit repeat | Passed | Not applicable | Not applicable | 0 | 0 detected | Not applicable | `CAVERNO_CODING_GOAL_LIVE_EDIT_REPEAT_COUNT=3 tool/run_coding_goal_live_edit_canary.sh` passed 9/9. Direct edit-and-test, red-green repair, and two-file helper/caller coordination each passed in three isolated workspaces with 0 Live LLM recovery signals. |
| 2026-05-26 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | Focused package-like coding goal edit | Passed | Not applicable | Not applicable | 0 | 0 detected | Not applicable | `tool/run_coding_goal_live_edit_canary.sh` passed 4/4 after adding the package-like parser fixture. The model repaired production parser and command-builder files, left the test runner unchanged, ran validation successfully, and goal completion handled "successfully completed" narration. |
| 2026-05-30 | `http://192.168.100.241:1234/v1` | `qwen3.6-27b-mtp-vision` | Focused diagnostic feedback repeat | Passed | Not applicable | Not applicable | 0 | 0 detected | Not applicable | `CAVERNO_CODING_DIAGNOSTIC_FEEDBACK_LIVE_REPEAT_COUNT=3 tool/run_coding_diagnostic_feedback_live_canary.sh` passed 6/6 across root package and nested package Dart repairs. Analyzer feedback was observed with 11 feedback packets, 17 diagnostics, and feedback files `lib/main.dart` and `packages/nested_app/lib/main.dart`; recovery signals were all 0. |
| 2026-06-18 | `http://192.168.100.241:1234/v1` | `qwen3.6-35b-a3b-vision` | Qwen3.6 main LLM gate with PM5 | Passed | 3/3 | 1/1 | 0 | 0 detected | Pass: exact-preservation README content | `CAVERNO_QWEN36_MAIN_LLM_RUN_PM5=1 tool/run_qwen36_main_llm_gate.sh` passed exact preservation 1/1, PM5 smoke 3/3, ping 1/1, chat background-process 2/2, chat 11/11, and tool-result budget 1/1 after LL23 saved-validation and active-task scope hardening. |

## Current Comparison Baseline

Use `qwen3.6-35b-a3b-vision` as the current main-local-LLM candidate for chat
and coding surfaces after the 2026-06-18 Qwen3.6 main gate passed exact
preservation, PM5, chat background-process, chat, and tool-result budget checks.
Keep `qwen3.6-27b-mtp-vision` as the historical routine-inclusive comparison
reference until a 35B routine live canary is recorded, because the Qwen3.6 main
gate wrapper does not run routines. `gemma4-26b-vision` remains a passing but
recovery-heavy candidate: its same-revision full-surface candidate eventually
passed, but the same app revision also produced a preceding PM5 ping failure
where the model did not repair invalid generated code. If the harness, prompts,
parser recovery, task-drift classification, routine scoped-notification
guidance, or saved validation expectations change again, rerun the current 35B
main gate before judging a new model.

Minimum comparison criteria for the next model:

- PM5 live gate passes with smoke `3/3`, ping CLI `1/1`, no report-quality
  blockers, and no unexpected warnings.
- Focused `live_readme_first_canary` passes with `README.md` as the saved target,
  the actual changed file, and the only artifact containing
  `CANARY_CONTENT_FIT: README_ONLY`.
- Task drift remains `0 detected` in both PM5 smoke and focused artifact runs.
- Allowed warnings are recorded by reason; unexpected warnings block promotion.
- Tool-loop convergence is classified as natural stop or guarded stop, not left
  unobserved for artifact-sensitive scenarios.
- The run notes capture proposal parsing, reasoning-only recovery, approval
  path, cleanup cancellation, content-fit issues, and final completion behavior.
- Chat background-process monitoring must pass with clean final process state counts
  (`failed=0`, `still_running=0`, `status_unverified=0`).

## Next Model Task Breakdown

Use this checklist when switching from the current reference model to the next
candidate:

1. Capture endpoint metadata from `/models`: exact model ID, owner, context
   length, capabilities, parameter count, and size when available.
2. Run the full PM5 live gate with `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
   and archive the smoke report plus ping canary summary paths.
3. Run the focused `live_readme_first_canary` to confirm artifact content fit,
   saved target tracking, and convergence behavior.
4. Run the chat live canary and tool-result budget canary so chat, memory
   extraction, embedded tool-call parsing, and compaction recovery are covered.
5. Run routine live canaries when the model switch is intended to validate the
   full product surface, not only coding.
6. Add a result-matrix row and a run-evidence subsection before moving to the
   next candidate model.
7. Archive the PM5 background-process artifacts and include
   `canary_summary.json` and `canary_summary.md` under the model evidence block.
8. Classify the candidate as baseline-ready, provisional, blocked by model
   behavior, or blocked by environment. Do not mark it baseline-ready with
   unexpected warnings, report-quality blockers, task drift, or unreviewed
   artifact content-fit concerns.

## Run Evidence

### 2026-05-22: `qwen3.6-27b-mtp-vision`

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-27b-mtp-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- PM5 live suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779431068428/plan_mode_live_suite_macos_report.json`
- PM5 live suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779431068428/plan_mode_live_suite_macos_report.md`
- PM5 suite archive:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779431068428`
- Standalone same-model ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779418974/canary_summary.json`
- Standalone same-model ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779418974/run_01_suite_report.json`
- Outcome:
  - live smoke: 2 passed, 1 failed
  - failed smoke scenario: `live_clarify_recovery`
  - failure class: `unclassified`
  - report quality: blocked, 1 blocker
  - unexpected warnings: 0
  - task drift: 0 detected
  - approval paths: 1 UI approval, 2 live harness approval fallbacks
- Failure detail:
  `live_clarify_recovery` approved the proposal through the UI, but did not
  enter the first task. The test then failed because it expected at least one
  `[LLM] ========== streamChatCompletionWithTools ==========` log entry and
  found none.
- Same-model ping canary:
  - scenario: `live_ping_cli_completion`
  - result: passed 1/1
  - report quality: ready
  - task drift: none detected
  - tool-loop convergence: one saved validation, natural stop

### 2026-05-22: Focused `live_clarify_recovery` Rerun

- Command:
  `tool/run_plan_mode_live_test.sh`
- Environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-27b-mtp-vision`
  - `CAVERNO_PLAN_MODE_SCENARIOS=live_clarify_recovery`
  - `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
- Focused suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779432071837/plan_mode_live_suite_macos_report.json`
- Focused suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779432071837/plan_mode_live_suite_macos_report.md`
- Outcome:
  - focused scenario: 1 passed, 0 failed
  - report quality: ready
  - unexpected warnings: 0
  - task drift: 0 detected
  - approval path: live harness approval fallback
  - tool-loop convergence: one saved validation, natural stop
- Comparison with PM5 failure:
  The focused rerun reached `[LLM] ========== streamChatCompletionWithTools ==========`
  after approval and completed the first saved task. This suggests the PM5
  failure is not a deterministic inability of this model to run
  `live_clarify_recovery`; it is more likely tied to consecutive-suite state,
  approval-path timing, or carryover from earlier scenarios.

### 2026-05-22: PM5 Live Gate Retry

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-27b-mtp-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779432319169/plan_mode_live_suite_macos_report.json`
- Smoke suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779432319169/plan_mode_live_suite_macos_report.md`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779432707/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779432707/run_01_suite_report.json`
- Ping canary live suite archive:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779432738786`
- Outcome:
  - live smoke: 3 passed, 0 failed
  - ping canary: 1 passed, 0 failed
  - report quality: ready
  - unexpected warnings: 0
  - task drift: 0 detected
  - approval paths: 3 live harness approval fallbacks in smoke; 1 live harness
    approval fallback in ping canary
  - cleanup cancellation: used in `live_cli_entrypoint_decision` and
    `live_clarify_recovery`
  - smoke tool-loop convergence: one saved validation, natural stop
  - ping canary tool-loop convergence: one saved validation, guard activation
- Comparison with earlier attempts:
  The PM5 retry passed after the first PM5 attempt failed and after the focused
  `live_clarify_recovery` rerun passed. Treat the model as a provisional pass
  with observed order-sensitive or cleanup-sensitive behavior until it has at
  least two consecutive PM5 passes.

### 2026-05-22: `gemma4-26b-vision`

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779436941346/plan_mode_live_suite_macos_report.json`
- Smoke suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779436941346/plan_mode_live_suite_macos_report.md`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779437330/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779437330/run_01_suite_report.json`
- Ping canary live suite archive:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779437359668`
- Outcome:
  - live smoke: 3 passed, 0 failed
  - ping canary: 1 passed, 0 failed
  - report quality: ready
  - unexpected warnings: 0
  - task drift: 0 detected
  - approval paths: 3 live harness approval fallbacks in smoke; 1 live harness
    approval fallback in ping canary
  - cleanup cancellation: used in `live_host_health_scaffold` and
    `live_cli_entrypoint_decision`
  - smoke tool-loop convergence: not observed by the report
  - ping canary tool-loop convergence: one saved validation, guard activation
- Notable behavior:
  The PM5 gate passed, but proposal generation was fragile. Several workflow
  and task proposals returned empty `content` with `finishReason.length`, while
  useful structured intent appeared only in the reasoning field. The harness
  recovered via truncated-reasoning or quality-gate fallback paths, then reached
  tool-aware streaming.

### 2026-05-22: `gemma4-26b-vision` Focused README Canary

- Command:
  `tool/run_plan_mode_live_test.sh`
- Environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary`
  - `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
- Focused suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779450359095/plan_mode_live_suite_macos_report.json`
- Focused suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779450359095/plan_mode_live_suite_macos_report.md`
- Outcome:
  - focused canary: 1 passed, 0 failed
  - report quality: ready
  - unexpected warnings: 0
  - task drift: 0 detected
  - artifact content fit: README-only content fit the saved task
  - approval path: live harness approval fallback
  - tool-loop convergence: one saved validation, guard activation
- Notable behavior:
  Workflow proposal generation again returned empty `content` with
  `finishReason.length`, but task proposal generation produced valid JSON for a
  single `README.md` task. After `ls README.md` succeeded, the model attempted a
  duplicate follow-up `write_file`; the saved-validation guard stopped it.

### 2026-05-22: `gemma4-26b-vision` PM5 Live Gate Rerun

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779459048707/plan_mode_live_suite_macos_report.json`
- Smoke suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779459048707/plan_mode_live_suite_macos_report.md`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779459449/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779459449/run_01_suite_report.json`
- Ping canary live suite archive:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779459478439`
- Outcome:
  - live smoke: 3 passed, 0 failed
  - ping canary: 1 passed, 0 failed
  - smoke report quality: ready
  - smoke unexpected warnings: 0
  - ping unexpected warnings: 0; one allowed `recoveredCreateParseWarning`
  - task drift: 0 detected in smoke and ping reports
  - approval paths: 3 live harness approval fallbacks in smoke; 1 live harness
    approval fallback in ping canary
  - smoke tool-loop convergence: one saved validation, guard activation
  - ping canary tool-loop convergence: two saved validations, two guard
    activations
- Notable behavior:
  The PM5 gate passed, but `live_cli_entrypoint_decision` and
  `live_clarify_recovery` logs showed execution continuing into follow-up tasks
  after the initial saved task. The structured smoke report still marked task
  drift as not detected because those scenario rows had no explicit expected
  target files. Keep artifact inspection in the model comparison checklist.

### 2026-05-22: `gemma4-26b-vision` Focused README Canary Rerun

- Command:
  `tool/run_plan_mode_live_test.sh`
- Environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary`
  - `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
- Focused suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779458844245/plan_mode_live_suite_macos_report.json`
- Focused suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779458844245/plan_mode_live_suite_macos_report.md`
- Outcome:
  - focused canary: 0 passed, 1 failed
  - failure class: `streamDisconnect`
  - report quality: blocked, 2 blockers
  - blocker reasons: `streamDisconnect`, `missingExpectedSavedTaskTargetFiles`
  - unexpected warnings: 0
  - allowed warnings: 2 recovered memory-phase transport warnings
  - task drift: 1 detected
  - artifact content fit: `README.md` was written with
    `CANARY_CONTENT_FIT: README_ONLY`, but saved validation was not observed
- Failure detail:
  The model created `README.md` in the temporary project, including the
  required content-fit marker. The test still failed because no
  `[Tool] Saved validation command succeeded` log appeared, and the saved task
  target file list was empty while the scenario expected `README.md`.

### 2026-05-22/23: `gemma4-26b-vision` Post-Fix Baseline Refresh

- Focused README command:
  `tool/run_plan_mode_live_test.sh`
- Focused README environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary`
  - `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
- Focused README report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779461715586/plan_mode_live_suite_macos_report.json`
- Smoke command:
  `tool/run_plan_mode_live_test.sh`
- Smoke environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_TAGS=smoke`
  - `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
- Smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779462479260/plan_mode_live_suite_macos_report.json`
- Outcome:
  - focused README canary: 1 passed, 0 failed
  - focused README report quality: ready
  - focused README unexpected warnings: 0
  - focused README task drift: 0 detected
  - focused README artifact content fit: `README.md` matched the saved task and
    contained `CANARY_CONTENT_FIT: README_ONLY`
  - focused README convergence: two saved validations, one guard activation, and
    one natural stop
  - smoke suite: 3 passed, 0 failed
  - smoke report quality: ready
  - smoke warnings: one allowed `recoveredCreateParseWarning`, 0 unexpected
  - smoke task drift: 0 detected
  - smoke approval paths: 3 live harness approval fallbacks
  - smoke convergence: 3 saved validations, 2 guard activations, and 1 natural
    stop
- Baseline note:
  This is the previous coding comparison baseline for `gemma4-26b-vision`. The
  earlier failed README rerun and drift-heavy smoke rerun remain historical
  evidence because they led to canary expectation and task-drift classification
  fixes. Do not compare a new model against those superseded failures unless
  intentionally investigating pre-fix behavior.

### 2026-05-23: `qwen3.6-27b-mtp-vision` Full Model-Switch Baseline

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-27b-mtp-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779493076831/plan_mode_live_suite_macos_report.json`
- Smoke suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779493076831/plan_mode_live_suite_macos_report.md`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779493422/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779493422/run_01_suite_report.json`
- Ping canary live suite archive:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779493451792`
- Focused README command:
  `tool/run_plan_mode_live_test.sh`
- Focused README environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-27b-mtp-vision`
  - `CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary`
  - `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
- Focused README report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779493552331/plan_mode_live_suite_macos_report.json`
- Chat command:
  `tool/run_chat_live_llm_canary.sh`
- Tool-result budget command:
  `tool/run_tool_result_budget_live_canary.sh`
- Routine command:
  `tool/run_routine_live_llm_canary.sh`
- Outcome:
  - live smoke: 3 passed, 0 failed
  - ping canary: 1 passed, 0 failed
  - focused README canary: 1 passed, 0 failed
  - chat canary: 3 passed, 0 failed
  - tool-result budget canary: 1 passed, 0 failed
  - routine canary: 4 passed, 0 failed
  - report quality: ready for smoke, ping, and focused README reports
  - unexpected warnings: 0 in smoke, ping, and focused README reports
  - task drift: 0 detected in smoke, ping, and focused README reports
  - approval paths: 3 live harness approval fallbacks in smoke; 1 live harness
    approval fallback in ping; 1 live harness approval fallback in focused
    README
  - smoke convergence: 3 saved validations, 0 guard activations, and 3 natural
    stops
  - ping convergence: one saved validation and one guard activation
  - focused README convergence: one saved validation and one guard activation
  - cleanup cancellation: used in `live_cli_entrypoint_decision` and
    `live_clarify_recovery`
  - chat recovery: embedded content-tool continuation recovered with a
    non-streaming fallback after a transient streaming transport disconnect
  - routine branches: new IP post, no-new-IP no-post, LAN scan failure, and
    `contents` write-shape all passed
- Baseline note:
  This is the cleanest recorded `qwen3.6-27b-mtp-vision` model-switch run so
  far. It upgrades the model from provisional PM5-only compatibility to a
  full-surface pass for this canary revision, while preserving
  cleanup-sensitive and recovered-stream notes for future comparisons.

### 2026-05-23: `qwen3.6-27b-mtp-vision` Post-Hardening Reference Rerun

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-27b-mtp-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497007635/plan_mode_live_suite_macos_report.json`
- Smoke suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497007635/plan_mode_live_suite_macos_report.md`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779497444/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779497444/run_01_suite_report.json`
- Ping canary live suite archive:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497473182`
- Focused README report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497602903/plan_mode_live_suite_macos_report.json`
- Chat canary summary:
  `build/integration_test_reports/chat_live_llm_canary_1779497744/canary_summary.json`
- Tool-result budget canary summary:
  `build/integration_test_reports/tool_result_budget_live_canary_1779497770/canary_summary.json`
- Routine canary summary:
  `build/integration_test_reports/routine_live_llm_canary_1779497791/canary_summary.json`
- Outcome:
  - live smoke: 3 passed, 0 failed
  - ping canary: 1 passed, 0 failed
  - focused README canary: 1 passed, 0 failed
  - chat canary: 3 passed, 0 failed
  - tool-result budget canary: 1 passed, 0 failed
  - routine canary: 4 passed, 0 failed
  - unexpected warnings: 0 in smoke, ping, and focused README reports
  - task drift: 0 detected in smoke, ping, and focused README reports
  - recovery signals: chat 0, routine 0, budget one expected compaction retry
  - approval paths: live harness approval fallback in all Plan Mode scenarios
  - cleanup cancellation: used in `live_host_health_scaffold` and
    `live_clarify_recovery`
  - routine scoped-notification hardening held across new-IP post, no-new-IP
    no-post, LAN scan failure, and `contents` write-shape branches
- Baseline note:
  This is the current comparison reference because it reran the full surface
  after routine scoped-notification hardening and after the shared Live LLM
  canary summaries were added.

### 2026-05-23: `gemma4-26b-vision` Full-Surface Candidate Rerun

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546363391/plan_mode_live_suite_macos_report.json`
- Smoke suite Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546363391/plan_mode_live_suite_macos_report.md`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779546717/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779546717/run_01_suite_report.json`
- Ping canary live suite archive:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546746368`
- Focused README report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546851868/plan_mode_live_suite_macos_report.json`
- Chat canary summary:
  `build/integration_test_reports/chat_live_llm_canary_1779546901/canary_summary.json`
- Tool-result budget canary summary:
  `build/integration_test_reports/tool_result_budget_live_canary_1779546936/canary_summary.json`
- Routine canary summary:
  `build/integration_test_reports/routine_live_llm_canary_1779546953/canary_summary.json`
- Candidate reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_1779546953/reference_report.json`
- Comparison against the current reference:
  `build/integration_test_reports/live_llm_compare_qwen_vs_gemma4_1779546953/reference_compare.json`
- Outcome:
  - live smoke: 3 passed, 0 failed
  - ping canary: 1 passed, 0 failed
  - focused README canary: 1 passed, 0 failed
  - chat canary: 3 passed, 0 failed
  - tool-result budget canary: 1 passed, 0 failed
  - routine canary: 3 passed, 1 failed
  - generated reference report: 12 passed checks, 1 failed check
  - comparison against `qwen3.6-27b-mtp-vision`: failed with a routine hard
    regression and one README convergence watch signal
  - report quality: ready for smoke and focused README reports
  - unexpected warnings: 0 in smoke and focused README reports
  - task drift: 0 detected in smoke and focused README reports
  - recovery signals: chat 0, routine 0, budget one expected compaction retry
  - approval paths: live harness approval fallback in all Plan Mode scenarios
  - cleanup cancellation: used only in `live_clarify_recovery` during the smoke
    suite
  - focused README convergence: one saved validation and one guard activation
- Failure detail:
  The routine `contents` argument alias test failed after `read_file` and
  `lan_scan` executed. The model reasoned correctly that it should call
  `write_file` with the `contents` argument and then post only the newly
  discovered IP. It then emitted a raw special-token tool-call fragment
  (`<|tool_call>call:write_file{...}<tool_call|>`) in recovered text instead
  of an executable tool call. The write and Google Chat post were not executed,
  leaving the state file unchanged.
- Candidate note:
  This run is useful comparison evidence but is not baseline-ready. Treat the
  model as acceptable for chat and most Plan Mode canaries, and blocked for
  full-surface promotion until the routine alias tool-call shape is supported
  or the model stops emitting the raw special-token form.

### 2026-05-24: `gemma4-26b-vision` Post-Routine-Guard Candidate Rerun

- Routine command:
  `tool/run_routine_live_llm_canary.sh`
- Routine environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
- Routine canary summary:
  `build/integration_test_reports/routine_live_llm_canary_1779587391/canary_summary.json`
- Candidate reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_post_routine_guard_1779587391/reference_report.json`
- Comparison against the current qwen reference:
  `build/integration_test_reports/live_llm_compare_qwen_vs_gemma4_post_routine_guard_1779587391/reference_compare.json`
- Outcome:
  - routine canary before the fix: 3 passed, 1 failed
  - routine canary after the missing required write guard: 4 passed, 0 failed
  - generated reference report: 13 passed checks, 0 failed checks
  - comparison against `qwen3.6-27b-mtp-vision`: passed with 0 hard regressions
  - watch signals: focused README still needed one saved-validation guard
  - improvements: PM5 smoke cleanup cancellations remained lower than the qwen
    reference in the regenerated comparison
  - recovery signals: routine 0
- Evaluation:
  The hard routine regression is fixed for the observed `gemma4-26b-vision`
  failure mode where the model posted to Google Chat before saving the required
  routine state file. The candidate is now provisionally full-surface
  compatible, but the reference report combines earlier PM5, README, chat, and
  budget evidence with the new routine rerun. Promote it to a new model
  reference only after rerunning the full model-switch flow on one app revision
  or after accepting that mixed-artifact evidence is sufficient for the current
  decision.

### 2026-05-24: `gemma4-26b-vision` Same-Revision PM5 Rerun

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779587820296/plan_mode_live_suite_macos_report.json`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779588202/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779588202/run_01_suite_report.json`
- Ping canary live suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779588231132/plan_mode_live_suite_macos_report.json`
- Failure reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_same_revision_pm5_failed_1779588202/reference_report.json`
- Outcome:
  - PM5 smoke: 3 passed, 0 failed
  - PM5 ping canary: 0 passed, 1 failed
  - generated PM5-only reference report: 3 passed checks, 1 failed check
  - failed scenario: `live_ping_cli_completion`
  - failure class: `workflowBlocked`
  - report-quality blockers: 1
  - unexpected warnings: 0
  - task drift: 0 detected
  - smoke approval path: 3 live harness approval fallbacks
  - smoke cleanup cancellation: 3
- Failure detail:
  The model created only the expected `ping_cli.py` target file, but the file
  contained invalid Python: `return result.return`. The saved validation
  `python3 ping_cli.py --help` failed with `SyntaxError`. After reading the
  file, the model claimed the implementation was already working and repeated
  the identical validation command, so duplicate-call recovery skipped it and
  the workflow ended blocked.
- Evaluation:
  The app and harness correctly surfaced the syntax error and blocked workflow;
  the remaining issue is model repair behavior after a validation failure. This
  run blocks immediate promotion, but it is not the final PM5 classification
  because the immediate retry below passed.

### 2026-05-24: `gemma4-26b-vision` Same-Revision PM5 Retry

- PM5 command:
  `tool/run_plan_mode_pm5_live_gate.sh`
- PM5 environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
  - `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1`
- Smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779590250215/plan_mode_live_suite_macos_report.json`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779590616/canary_summary.json`
- Ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779590616/run_01_suite_report.json`
- Ping canary live suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779590645533/plan_mode_live_suite_macos_report.json`
- PM5 retry reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_pm5_retry_1779590616/reference_report.json`
- Outcome:
  - PM5 smoke: 3 passed, 0 failed
  - PM5 ping canary: 1 passed, 0 failed
  - generated PM5-only reference report: 4 passed checks, 0 failed checks
  - report-quality blockers: 0
  - unexpected warnings: 0
  - task drift: 0 detected
  - smoke convergence: 3 saved validations, 0 guard activations, 3 natural
    stops
  - ping convergence: 1 saved validation, 1 guard activation
  - smoke approval path: 3 live harness approval fallbacks
  - smoke cleanup cancellation: 1
- Evaluation:
  The previous ping CLI syntax-error failure did not reproduce on the immediate
  retry, so classify it as a flaky model/harness interaction rather than a
  deterministic PM5 blocker. This retry is still not enough for promotion:
  smoke logs include task-proposal retries, reasoning-only `finishReason.length`
  recovery, memory extraction fallback, tool-less recovery, and a cleanup
  cancellation. Require a same-revision full-surface rerun before considering
  `gemma4-26b-vision` as a replacement reference.

### 2026-05-24: `gemma4-26b-vision` Same-Revision Full-Surface Rerun

- Baseline commands:
  - `tool/run_plan_mode_live_test.sh`
  - `tool/run_chat_live_llm_canary.sh`
  - `tool/run_tool_result_budget_live_canary.sh`
  - `tool/run_routine_live_llm_canary.sh`
- Baseline environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=gemma4-26b-vision`
  - `CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary`
  - `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
  - `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20`
- README canary report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779591453357/plan_mode_live_suite_macos_report.json`
- Chat canary summary:
  `build/integration_test_reports/chat_live_llm_canary_1779591554/canary_summary.json`
- Tool-result budget canary summary:
  `build/integration_test_reports/tool_result_budget_live_canary_1779591586/canary_summary.json`
- Routine canary summary:
  `build/integration_test_reports/routine_live_llm_canary_1779591602/canary_summary.json`
- Candidate reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_full_surface_1779591602/reference_report.json`
- Comparison against the current qwen reference:
  `build/integration_test_reports/live_llm_compare_qwen_vs_gemma4_full_surface_1779591602/reference_compare.json`
- Outcome:
  - generated reference report: 13 passed checks, 0 failed checks
  - PM5 smoke and ping: reused the same-revision PM5 retry above, 4/4 passed
  - README artifact canary: 1 passed, 0 failed
  - chat canary: 3 passed, 0 failed, 0 recovery signals
  - tool-result budget canary: 1 passed, 0 failed, 1 expected compaction retry
  - routine canary: 4 passed, 0 failed, 0 recovery signals
  - comparison result: passed
  - hard regressions against qwen: 0
  - watch signals against qwen: 1, README guard activations increased from 0
    to 1
  - improvements against qwen: 1, PM5 smoke cleanup cancellations decreased
    from 2 to 1
- Evaluation:
  This closes the requested same-revision full-surface candidate run for
  `gemma4-26b-vision`: all current canary surfaces pass and there is no hard
  regression against the qwen reference. The promotion decision remains
  conservative because the same app revision had an immediately preceding PM5
  ping failure caused by invalid code and failed repair. Treat this as a strong
  candidate pass, but require repeat clean same-revision evidence before
  replacing qwen as the named reference.

### `chat_background_process` canary evidence

- Command:
  `tool/run_chat_background_process_live_canary.sh`
- Environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-27b-mtp-vision`
- One-run artifacts:
  - `build/integration_test_reports/chat_background_process_live_canary_1780910078/canary_summary.json`
  - `build/integration_test_reports/chat_background_process_live_canary_1780910078/canary_summary.md`
- Repeat artifacts:
  - `build/integration_test_reports/chat_background_process_live_canary_1780910146/canary_summary.json`
  - `build/integration_test_reports/chat_background_process_live_canary_1780910146/canary_summary.md`
- Progress-report artifacts:
  - `build/integration_test_reports/chat_background_process_live_canary_1780913499/canary_summary.json`
  - `build/integration_test_reports/chat_background_process_live_canary_1780913499/canary_summary.md`
- Prose-only recovery artifacts:
  - `build/integration_test_reports/chat_background_process_live_canary_1780914959/canary_summary.json`
  - `build/integration_test_reports/chat_background_process_live_canary_1780914959/canary_summary.md`
- Outcome:
  - one-run canary: 1/1 passed, 0 failed, 0 skipped
  - three-run repeat canary: 3/3 passed, 0 failed, 0 skipped
  - progress-report canary: 1/1 passed, 0 failed, 0 skipped
  - prose-only recovery canary: 2/2 passed, 0 failed, 0 skipped
  - process execution counts in the repeat summary:
    `process_start=3`, `process_wait=3`
  - progress-report execution counts:
    `process_start=1`, `process_wait=2`
  - prose-only recovery execution counts:
    `process_start=2`, `process_wait=4`,
    `background_process_still_running=1`
  - progress-report coverage: first wait observed a running process with
    `PHASE_ONE_PROGRESS`; the assistant then reported `PROGRESS_OBSERVED`
    before the second wait observed zero-exit completion.
  - prose-only recovery coverage: monitor feedback blocked a premature
    completion claim; the model replied with `PROSE_WAIT_OBSERVED` instead of a
    tool call; Caverno forced follow-up `process_wait` checks until the final
    `BACKGROUND_PROCESS_PROSE_CANARY_DONE` marker.
  - final process states: `failed=0`, `still_running=0`,
    `status_unverified=0`
  - report quality: ready, no unexpected warnings

### 2026-06-18: `qwen3.6-35b-a3b-vision` Main Gate Recovery Pass

- Command:
  `CAVERNO_QWEN36_MAIN_LLM_RUN_PM5=1 tool/run_qwen36_main_llm_gate.sh`
- Environment:
  - `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1`
  - `CAVERNO_LLM_API_KEY=no-key`
  - `CAVERNO_LLM_MODEL=qwen3.6-35b-a3b-vision`
- Exact-preservation suite report:
  `build/integration_test_reports/qwen36_main_llm_gate/plan_mode_live_suite_macos_1781770291875/plan_mode_live_suite_macos_report.json`
- PM5 smoke suite report:
  `build/integration_test_reports/qwen36_main_llm_gate/plan_mode_live_suite_macos_1781770362512/plan_mode_live_suite_macos_report.json`
- PM5 smoke Markdown:
  `build/integration_test_reports/qwen36_main_llm_gate/plan_mode_live_suite_macos_1781770362512/plan_mode_live_suite_macos_report.md`
- PM5 ping canary summary:
  `build/integration_test_reports/qwen36_main_llm_gate/plan_mode_ping_cli_canary_1781770461/canary_summary.json`
- PM5 ping canary suite report:
  `build/integration_test_reports/qwen36_main_llm_gate/plan_mode_ping_cli_canary_1781770461/run_01_suite_report.json`
- PM5 chat background-process summary:
  `build/integration_test_reports/qwen36_main_llm_gate/chat_background_process_live_canary_1781770518/canary_summary.json`
- Chat live canary summary:
  `build/integration_test_reports/qwen36_main_llm_gate/qwen36_main_llm_chat_canary_1781770569/canary_summary.json`
- Tool-result budget canary summary:
  `build/integration_test_reports/qwen36_main_llm_gate/tool_result_budget_live_canary_1781770608/canary_summary.json`
- Outcome:
  - exact preservation: 1 passed, 0 failed
  - PM5 smoke: 3 passed, 0 failed
  - PM5 smoke report quality: ready, 0 blockers
  - PM5 smoke warnings: 0 total, 0 allowed, 0 unexpected
  - PM5 smoke task drift: 0 detected
  - PM5 smoke tool-loop convergence: 4 saved validations, 0 guard
    activations, 4 natural stops across 3 scenarios
  - PM5 ping canary: 1 passed, 0 failed
  - chat background-process canary: 2 passed, 0 failed
  - chat live canary: 11 passed, 0 failed
  - tool-result budget canary: 1 passed, 0 failed
- Evaluation:
  This closes the LL23 broad main-gate blocker for
  `qwen3.6-35b-a3b-vision`. The exact-preservation and PM5 smoke runs still
  exercised runtime rails: the model attempted modified validation commands,
  the guard blocked them, and the model recovered to the exact saved validation
  commands. Treat this as a clean main-gate pass because the final changed
  files matched the saved task targets and every saved validation completed.

## Per-Model Notes

### `qwen3.6-35b-a3b-vision`

- Endpoint: `http://192.168.100.241:1234/v1`
- Endpoint owner from `/models`: `llamacpp`
- Context from `/models`: `65536`
- Training context from `/models`: `262144`
- Embedding width from `/models`: `2048`
- Parameters from `/models`: `35505251456`
- Size from `/models`: `22652396032`
- Modalities from `/models`: text and image input, text output
- Runtime notes from `/models`:
  - `reasoning=off`
  - `spec-type=draft-mtp`
  - `spec-draft-n-max=2`
  - `parallel=1`
  - `tensor-split=3,2`
- Observed behavior notes:
  - Passed the Qwen3.6 main LLM gate with PM5 enabled after LL23 guardrail
    hardening.
  - Exact preservation passed after the model first rewrote the saved
    validation path, received `saved_validation_command_modified`, and then
    recovered to the exact saved command with `working_directory`.
  - PM5 smoke passed with 0 warnings and 0 task drift across
    `live_host_health_scaffold`, `live_cli_entrypoint_decision`, and
    `live_clarify_recovery`.
  - PM5 smoke still showed benign first-attempt validation wrappers such as
    added `echo` branches or absolute paths. The runtime guard blocked these
    wrappers, and the model recovered to the exact saved validation command in
    the same task turn.
  - Chat live canary passed all 11 checks. Recovery signals were limited to
    one incomplete content-tool recovery and two ignored assistant-authored
    `tool_result` packets.
  - Tool-result budget canary passed with the expected single compaction retry.
  - Routine live canary evidence has not yet been recorded for this 35B alias;
    keep `qwen3.6-27b-mtp-vision` as the routine-inclusive comparison baseline
    until that surface is covered.

### `qwen3.6-27b-mtp-vision`

- Endpoint: `http://192.168.100.241:1234/v1`
- Endpoint owner from `/models`: `llamacpp`
- Context from `/models`: `65536`
- Parameters from `/models`: `27320697856`
- Size from `/models`: `17095778304`
- Observed behavior notes:
  - Can pass the narrow ping CLI completion canary and naturally stop after
    saved validation.
  - Passed `live_host_health_scaffold` and `live_cli_entrypoint_decision` in
    the PM5 smoke suite, but both used the live harness approval fallback path.
  - In scaffold-style planning, the first task proposal split
    `requirements.txt` and `README.md`; retry recovered to a bundled proposal.
  - In CLI entrypoint planning, it repeated the decision step and favored the
    user's original CLI preference over the saved task target. It created
    `requirements.txt` as a support file while the saved task target was
    `main.py`.
  - In clarify recovery, after the JSON report decision, the first task
    proposal expanded beyond the first-slice `requirements.txt` and `README.md`
    constraint. Retry recovered to a `main.py`-centered plan, then the scenario
    failed before execution because the expected stream-with-tools log never
    appeared.
  - A focused `live_clarify_recovery` rerun passed, which makes the PM5 failure
    order-sensitive rather than fully reproducible in isolation.
  - A full PM5 retry also passed, so the initial `live_clarify_recovery` failure
    is currently classified as a flaky PM5/model interaction rather than a hard
    compatibility block.
  - During the focused rerun, the model still repeated the reporting-format
    decision inside the implementation response even though the harness had
    already selected `JSON Report`.
  - During the PM5 retry, `live_cli_entrypoint_decision` and
    `live_clarify_recovery` needed cleanup cancellation after background
    execution remained active at scenario settle time.
  - The clarify recovery logs included session-memory context from the previous
    CLI scenario, so compare future models on whether they resist or amplify
    that carryover.
  - The 2026-05-23 full model-switch baseline passed PM5 smoke, ping, focused
    README, chat, tool-result budget, and routine canaries on the same app and
    canary revision.
  - The post-hardening reference rerun also passed PM5 smoke, ping, focused
    README, chat, tool-result budget, and routine canaries on the same app and
    canary revision.
  - Unlike the initial PM5 attempt, the 2026-05-23 PM5 gate passed in one run
    and produced no unexpected warnings, no task drift, and no report-quality
    blockers.
  - Plan Mode still used live harness approval fallback for every smoke, ping,
    and focused README scenario in the latest baseline.
  - Cleanup cancellation occurred in `live_host_health_scaffold` and
    `live_clarify_recovery` in the post-hardening reference rerun, so
    long-running background completion remains a behavior to watch.
  - The focused README canary passed with `README.md` as the saved target and
    actual changed file, plus the `CANARY_CONTENT_FIT: README_ONLY` marker.
  - The latest chat canary passed, including memory JSON parsing and embedded
    content-tool execution, with 0 recovery signals.
  - The latest tool-result budget canary passed with one expected compaction
    retry for the oversized tool result path.
  - The latest routine canary passed all recorded branches, including scoped
    new-IP notification, no-new-IP no-post, LAN scan failure, and the
    `contents` write argument alias, with 0 recovery signals.
  - The 2026-05-30 focused diagnostic feedback repeat passed 6/6 across root
    package and nested package Dart repairs. Analyzer feedback was observed for
    `lib/main.dart` and `packages/nested_app/lib/main.dart`, with 11 feedback
    packets, 17 diagnostics, and 0 recovery signals.
  - The 2026-06-08 chat background-process canary passed both the focused
    one-run check and the three-run repeat check, with clean
    `process_start`/`process_wait` execution counts and no failed,
    still-running, or unverified final process states.

### `gemma4-26b-vision`

- Endpoint: `http://192.168.100.241:1234/v1`
- Endpoint owner from `/models`: `llamacpp`
- Context from `/models`: `65536`
- Training context from `/models`: `262144`
- Embedding width from `/models`: `2816`
- Parameters from `/models`: `25233142046`
- Size from `/models`: `16780192888`
- Capabilities from `/models`: `completion`, `multimodal`
- Observed behavior notes:
  - Passed the full PM5 gate on the first recorded attempt for this model.
  - All smoke scenarios and the ping canary used the live harness approval
    fallback path.
  - Workflow proposal calls repeatedly returned empty `content` with
    `finishReason.length`; salvage depended on reasoning-field recovery.
  - Task proposal generation sometimes recovered through truncated reasoning
    fallback and sometimes through the task proposal quality gate.
  - `live_host_health_scaffold` and `live_cli_entrypoint_decision` required
    cleanup cancellation after background execution remained active at scenario
    settle time.
  - In scaffold-style execution, the model mixed file contents: one final
    report showed the README-style body written into both `README.md` and
    `requirements.txt`, even though task drift stayed at 0 because only target
    files changed.
  - In CLI entrypoint execution, it created `main.py` while the saved task
    target set in the report was `README.md` and `requirements.txt`; the report
    still classified task drift as not detected because that scenario did not
    have explicit expected target files.
  - Session-memory extraction fell back to rule-based extraction at least once
    after the model returned unparseable memory JSON.
  - The ping CLI canary produced the correct single `ping_cli.py` target and
    validated `python3 ping_cli.py --help`, but convergence required the saved
    validation guard instead of a natural stop.
  - The focused `live_readme_first_canary` passed with only `README.md`
    changed and no artifact content-fit issue. It still required the
    saved-validation guard because the model attempted another `write_file`
    after `ls README.md` had already succeeded.
  - A later focused `live_readme_first_canary` failed before the canary accepted
    natural-stop convergence. The post-fix rerun passed with saved target
    tracking, README-only content, and guarded convergence.
  - A later smoke rerun initially flagged unexpected changed files in scenarios
    that had no explicit saved target expectations. After task-drift
    classification was scoped to started tasks, the post-fix smoke rerun passed
    with report quality ready, 0 task drift, and one allowed recovered-create
    warning.
  - Chat canaries originally exposed a memory-extraction weakness where useful
    JSON appeared only in reasoning text. The current parser and live chat
    canary baseline cover that shape, and the chat suite now passes for this
    model.
  - The latest full-surface candidate rerun passed PM5, focused README, chat,
    and budget checks, but failed the routine `contents` argument alias branch.
  - In the failed routine branch, the model correctly planned a `write_file`
    call with the `contents` alias, then emitted the call as a raw
    `<|tool_call>call:write_file{...}<tool_call|>` fragment in recovered text
    instead of an executable tool call.
  - A 2026-05-24 routine rerun found a second failure shape: the model skipped
    the required `write_file`, posted to Google Chat, and then acknowledged in
    reasoning that the state update was missing while still answering.
  - After adding the missing required write guard, the routine live canary
    passed all four branches for this model. The regenerated candidate
    reference report passed 13/13 and the qwen comparison had no hard
    regressions.
  - The later same-revision PM5 rerun failed the ping CLI canary. The model
    wrote a syntax error in `ping_cli.py`, then repeated the same failed
    validation command instead of repairing the file, leaving the saved task in
    `workflowBlocked`.
  - The immediate PM5 retry passed smoke and ping, so the syntax-error repair
    failure is not deterministic. The retry still depended on recovery-heavy
    paths, including reasoning-only proposal recovery, task proposal quality
    retries, memory fallback, tool-less recovery, and a ping saved-validation
    guard.
  - The same-revision full-surface rerun after that PM5 retry passed README,
    chat, tool-result budget, and routine canaries. The generated candidate
    reference report passed 13/13 and comparison against qwen had 0 hard
    regressions, 1 README guard watch signal, and 1 PM5 cleanup improvement.
  - Compare future models against the current `qwen3.6-27b-mtp-vision`
    post-hardening reference. For this model, use the same-revision
    full-surface rerun as the current candidate-pass evidence and the
    fail-then-pass PM5 pair as the remaining promotion risk.

## Evidence Fields

Record these fields for every model change:

- endpoint base URL
- exact model ID from `/models`
- preflight result
- PM5 smoke pass count
- ping CLI canary pass count and pass rate
- unexpected warning count
- allowed warning reasons
- task drift classification
- artifact content fit: whether each changed file's contents match the saved
  task intent and file role, even when task drift is 0
- report-quality readiness and blocker reasons
- tool-loop convergence status, including saved validation count, guard
  activations, and natural stops
- whether the evidence came from a single full PM5 gate or a split set of
  focused reruns after a harness or parser change
- archived report paths for the live suite and ping canary summary; avoid the
  top-level `plan_mode_live_suite_macos_report.*` files in long-lived notes
  because each new run overwrites them
- model-specific behavior differences, especially proposal parsing, task scope,
  artifact content fit, tool-call convergence, and final answer completion
