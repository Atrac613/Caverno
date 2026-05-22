# Plan Mode Model and Endpoint Compatibility

This document records the product compatibility boundary for Plan Mode live
runs against OpenAI-compatible endpoints. Use it with the release readiness
checklist before treating a live failure as an app regression.

## Supported Endpoint Contract

Plan Mode live gates expect an endpoint that provides:

- an OpenAI-compatible base URL in `CAVERNO_LLM_BASE_URL`
- an API key or placeholder token in `CAVERNO_LLM_API_KEY`
- a model ID available from the endpoint in `CAVERNO_LLM_MODEL`
- a `/models` route for preflight, unless `CAVERNO_PLAN_MODE_PREFLIGHT=0` is
  intentionally set
- chat completion requests that accept the app's tool definitions
- streaming chat completion responses for tool-aware execution
- enough context length for workflow proposal, task proposal, tool result
  summaries, and final answer generation
- stable enough latency to finish the PM5 smoke phase and ping CLI canary within
  the configured planning and execution timeouts

Endpoint availability failures are classified as `blocked: environment` in the
release checklist. They are not Plan Mode workflow regressions unless the app
misreports the prerequisite failure.

## Recommended Live Environment

Use the PM5 live gate for product compatibility checks:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 \
tool/run_plan_mode_pm5_live_gate.sh
```

Recommended defaults:

- `CAVERNO_PLAN_MODE_DEVICE=macos`
- `CAVERNO_PLAN_MODE_REPORTER=compact`
- `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1`
- `CAVERNO_PLAN_MODE_PM5_SMOKE_TAGS=smoke`
- `CAVERNO_PLAN_MODE_PREFLIGHT=1`
- `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=5`

Use `CAVERNO_PLAN_MODE_PREFLIGHT=0` only when the endpoint is otherwise known
to be reachable and intentionally does not expose `/models`.

Record model-by-model runs in
[`docs/plan_mode_live_llm_model_canary_matrix.md`](plan_mode_live_llm_model_canary_matrix.md)
before switching to the next model.

## Product Settings Preflight

The General settings page uses the configured base URL and API key to fetch the
OpenAI-compatible `/models` route. Treat that result as the product-side
preflight before starting Plan Mode:

- `Endpoint preflight passed` means the endpoint responded and the selected
  model is available.
- `Selected model was not found` means the endpoint responded, but the current
  model name should be changed before Plan Mode starts.
- `Endpoint preflight failed` means the base URL, API key, server availability,
  or `/models` compatibility should be repaired before treating a Plan Mode
  generation failure as an app regression.

The settings UI shows the derived `/models` endpoint, selected model, and
non-secret API key status so user reports can distinguish environment failures
from workflow failures without exposing credentials.

For support reports, use the Plan Mode support snapshot in General settings.
It copies the same product-side preflight classification with canonical report
paths and excludes API key values.

## Model Behavior Assumptions

Plan Mode works best with models that can:

- produce parseable JSON workflow and task proposals after bounded retries
- keep saved task scope narrow after approval
- request tool calls with valid names and JSON arguments
- stop after saved validation succeeds, or tolerate the saved-validation
  convergence guard stopping duplicate follow-up tool calls
- preserve target-file boundaries when tool results mention extra workspace
  context
- summarize completion evidence without reopening completed tasks
- handle the app's user-role tool-result workaround for models that are weak at
  native tool-role messages

## Risky Model Behaviors

Treat these as model compatibility risks before assuming app logic is broken:

- repeated malformed JSON proposals after retry and salvage
- reasoning-only responses with no workflow or task proposal
- duplicate or generic task proposals that ignore target-file boundaries
- tool calls that continue after a saved validation command has passed
- future-task tool calls before the current saved task is terminally complete
- long pauses that exceed planning, execution, or stall budgets
- final answers that contradict persisted task state

Mitigations include:

- keep `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1` enabled for release checks
- use the PM5 gate artifact index before reading raw logs
- inspect `warningSummary`, `reportQualitySummary`, and task drift before
  changing product logic
- keep new model coverage in canary or long-run status before expanding smoke
  coverage

## Known Limitations

Unsupported or not-yet-productized boundaries:

- endpoints that are unreachable or require a non-OpenAI-compatible API shape
- models that cannot produce parseable workflow/task JSON after bounded retries
- models that cannot perform tool calling or tool-like JSON output
- models that regularly ignore single-task or target-file constraints
- endpoints that cannot finish the PM5 gate within configured timeouts
- compatibility claims based only on a ping-only run without a fresh smoke pass

Use the release decision `blocked: environment` for missing endpoint
prerequisites. Use `blocked` for app-side workflow regressions, unexpected
warnings, report quality blockers, unexplained task drift, or unknown approval
paths.

## Evidence Snapshot

Current compatibility evidence comes from:

- deterministic Plan Mode smoke and report-quality tests
- model-by-model live canary history in
  `docs/plan_mode_live_llm_model_canary_matrix.md`
- PM5 live gate evidence in `docs/roadmap.md`
- PM5 ping CLI canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1778555057/canary_summary.json`
- focused PM5 gate tests in `test/tool/run_plan_mode_pm5_live_gate_test.dart`
- scenario classification tests in `test/integration/plan_mode_scenario_spec_test.dart`

Latest PM5 live evidence used:

- endpoint shape: OpenAI-compatible local endpoint
- endpoint: `http://192.168.100.241:1234/v1`
- model: `gemma4-26b-vision`
- live smoke result: `3/3` passed
- ping CLI canary result: `1/1` passed
- unexpected warnings: `0`
- report quality blockers: `0`
- task drift: none detected
- smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779436941346/plan_mode_live_suite_macos_report.json`
- ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779437330/canary_summary.json`

Recent `gemma4-26b-vision` compatibility attempt:

- PM5 attempt:
  - date: 2026-05-22
  - PM5 live gate result: passed
  - live smoke result: `3/3` passed
  - ping CLI canary result: `1/1` passed
  - unexpected warnings: `0`
  - report quality blockers: `0`
  - task drift: none detected by the reports
  - approval path: live harness approval fallback for all smoke scenarios and
    the ping canary
  - cleanup cancellation: used in `live_host_health_scaffold` and
    `live_cli_entrypoint_decision`
  - proposal behavior: repeated empty `content` with `finishReason.length`;
    recovery depended on reasoning-field salvage and task proposal quality-gate
    fallback
  - file behavior: scaffold execution wrote README-style content into both
    `README.md` and `requirements.txt`; the report still classified task drift
    as not detected because changes stayed within target files
  - ping canary convergence: one saved validation and one guard activation
  - smoke suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779436941346/plan_mode_live_suite_macos_report.json`
  - ping canary summary:
    `build/integration_test_reports/plan_mode_ping_cli_canary_1779437330/canary_summary.json`

Recent `qwen3.6-27b-mtp-vision` compatibility attempts:

- initial PM5 attempt:
  - date: 2026-05-22
  - PM5 live gate result: failed
  - live smoke result: `2/3` passed
  - failed scenario: `live_clarify_recovery`
  - failure class: `unclassified`
  - failure detail: proposal approval completed, but execution did not start
    and the expected stream-with-tools log was absent
  - same-model standalone ping CLI canary result: `1/1` passed
  - unexpected warnings: `0`
  - task drift: none detected by the report
  - live suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779431068428/plan_mode_live_suite_macos_report.json`
  - standalone ping canary summary:
    `build/integration_test_reports/plan_mode_ping_cli_canary_1779418974/canary_summary.json`
- focused rerun:
  - date: 2026-05-22
  - scenario: `live_clarify_recovery`
  - result: passed
  - report quality blockers: `0`
  - unexpected warnings: `0`
  - task drift: none detected
  - approval path: live harness approval fallback
  - focused suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779432071837/plan_mode_live_suite_macos_report.json`
- PM5 retry:
  - date: 2026-05-22
  - PM5 live gate result: passed
  - live smoke result: `3/3` passed
  - ping CLI canary result: `1/1` passed
  - unexpected warnings: `0`
  - report quality blockers: `0`
  - task drift: none detected
  - approval path: live harness approval fallback for all smoke scenarios
  - cleanup cancellation: used in `live_cli_entrypoint_decision` and
    `live_clarify_recovery`
  - smoke suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779432319169/plan_mode_live_suite_macos_report.json`
  - ping canary summary:
    `build/integration_test_reports/plan_mode_ping_cli_canary_1779432707/canary_summary.json`

Interpretation: `qwen3.6-27b-mtp-vision` has a passing PM5 run, but it should
remain a provisional compatibility result because the first PM5 attempt failed
and the passing retry still showed cleanup-sensitive behavior.

Interpretation: `gemma4-26b-vision` has a passing PM5 run, but it should remain
under canary observation because proposal salvage, cleanup cancellation, and
file-content mix-ups were required or observed during the pass.

This evidence supports the current MVP release gate. Broader compatibility
claims require PM12 long-run or matrix validation across additional endpoints
and models.
