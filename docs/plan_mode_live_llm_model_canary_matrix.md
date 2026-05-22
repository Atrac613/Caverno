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

## Current Comparison Baseline

Use `qwen3.6-27b-mtp-vision` as the current reference model after the
2026-05-23 full model-switch pass. `gemma4-26b-vision` remains the previous
reference for comparison against the same app and canary revision. If the
harness, prompts, parser recovery, task-drift classification, or saved
validation expectations change again, rerun the current reference before
judging a new model.

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
7. Classify the candidate as baseline-ready, provisional, blocked by model
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

## Per-Model Notes

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
  - Unlike the initial PM5 attempt, the 2026-05-23 PM5 gate passed in one run
    and produced no unexpected warnings, no task drift, and no report-quality
    blockers.
  - Plan Mode still used live harness approval fallback for every smoke, ping,
    and focused README scenario in the latest baseline.
  - Cleanup cancellation still occurred in `live_cli_entrypoint_decision` and
    `live_clarify_recovery`, so long-running background completion remains a
    behavior to watch.
  - The focused README canary passed with `README.md` as the saved target and
    actual changed file, plus the `CANARY_CONTENT_FIT: README_ONLY` marker.
  - The chat canary passed, including memory JSON parsing and embedded
    content-tool execution. Embedded-tool continuation needed non-streaming
    recovery after a transient streaming disconnect.
  - The routine canary passed all recorded branches, including the `contents`
    write argument alias.

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
  - Compare future models against the post-fix baseline refresh and the full PM5
    gate, not against superseded pre-fix canary failures.

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
