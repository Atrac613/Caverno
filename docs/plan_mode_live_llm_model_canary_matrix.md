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

## Evidence Fields

Record these fields for every model change:

- endpoint base URL
- exact model ID from `/models`
- preflight result
- PM5 smoke pass count
- ping CLI canary pass count and pass rate
- unexpected warning count
- task drift classification
- artifact content fit: whether each changed file's contents match the saved
  task intent and file role, even when task drift is 0
- archived report paths for the live suite and ping canary summary; avoid the
  top-level `plan_mode_live_suite_macos_report.*` files in long-lived notes
  because each new run overwrites them
- model-specific behavior differences, especially proposal parsing, task scope,
  artifact content fit, tool-call convergence, and final answer completion
