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
- write artifact contents that match each target file's role and the saved task
  intent, not only the target file paths
- summarize completion evidence without reopening completed tasks
- handle the app's user-role tool-result workaround for models that are weak at
  native tool-role messages

## Risky Model Behaviors

Treat these as model compatibility risks before assuming app logic is broken:

- repeated malformed JSON proposals after retry and salvage
- reasoning-only responses with no workflow or task proposal
- duplicate or generic task proposals that ignore target-file boundaries
- content-incorrect artifacts written into otherwise valid target files
- tool calls that continue after a saved validation command has passed
- raw special-token tool-call fragments in assistant text, such as
  `<|tool_call>call:write_file{...}<tool_call|>`, when the endpoint does not
  expose them as executable tool calls
- final answers that acknowledge a required file update is missing but still
  claim the routine completed after another side effect succeeds
- future-task tool calls before the current saved task is terminally complete
- validation repair loops that repeat an identical failing command instead of
  editing the file that caused the validation failure
- long pauses that exceed planning, execution, or stall budgets
- final answers that contradict persisted task state

Mitigations include:

- keep `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1` enabled for release checks
- use the PM5 gate artifact index before reading raw logs
- inspect `warningSummary`, `reportQualitySummary`, and task drift before
  changing product logic
- inspect artifact content fit separately from task drift because task drift is
  primarily path-based and can miss wrong content in the right file
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
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779497444/canary_summary.json`
- focused PM5 gate tests in `test/tool/run_plan_mode_pm5_live_gate_test.dart`
- scenario classification tests in `test/integration/plan_mode_scenario_spec_test.dart`

Latest PM5 live evidence used:

- endpoint shape: OpenAI-compatible local endpoint
- endpoint: `http://192.168.100.241:1234/v1`
- model: `qwen3.6-27b-mtp-vision`
- live smoke result: `3/3` passed
- ping CLI canary result: `1/1` passed
- unexpected warnings: `0`
- allowed warnings: none
- report quality blockers: `0`
- task drift: none detected
- smoke suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497007635/plan_mode_live_suite_macos_report.json`
- ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779497444/canary_summary.json`
- latest focused README artifact refresh:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497602903/plan_mode_live_suite_macos_report.json`

Recent `gemma4-26b-vision` compatibility attempts:

- PM5 attempt:
  - date: 2026-05-22
  - PM5 live gate result: passed
  - live smoke result: `3/3` passed
  - ping CLI canary result: `1/1` passed
  - unexpected warnings: `0`
  - report quality blockers: `0`
  - task drift: none detected by the reports
  - artifact content fit: concern recorded
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
- focused README canary:
  - date: 2026-05-22
  - scenario: `live_readme_first_canary`
  - result: passed
  - report quality blockers: `0`
  - unexpected warnings: `0`
  - task drift: none detected
  - artifact content fit: README-only content matched the saved task
  - approval path: live harness approval fallback
  - convergence: one saved validation and one guard activation
  - notable behavior: workflow proposal again used empty `content` with
    `finishReason.length`, but the task proposal was valid JSON for a single
    `README.md` task
  - focused suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779450359095/plan_mode_live_suite_macos_report.json`
- post-fix comparison refresh:
  - date: 2026-05-22/23
  - smoke result: `3/3` passed
  - focused README canary result: passed
  - report quality blockers: `0`
  - unexpected warnings: `0`
  - allowed warnings: one smoke `recoveredCreateParseWarning`
  - task drift: none detected
  - artifact content fit: README-only content matched the saved task
  - approval path: live harness approval fallback
  - convergence: smoke had 3 saved validations, 2 guard activations, and 1
    natural stop; README had 2 saved validations, 1 guard activation, and 1
    natural stop
  - smoke suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779462479260/plan_mode_live_suite_macos_report.json`
  - focused README canary report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779461715586/plan_mode_live_suite_macos_report.json`
- latest full-surface candidate rerun:
  - date: 2026-05-23
  - PM5 live gate result: passed
  - live smoke result: `3/3` passed
  - ping CLI canary result: `1/1` passed
  - focused README canary result: passed
  - chat canary result: passed, `3/3`
  - tool-result budget canary result: passed, `1/1`
  - routine canary result: failed, `3/4`
  - unexpected warnings: `0`
  - report quality blockers: `0` in Plan Mode reports
  - task drift: none detected by the Plan Mode reports
  - artifact content fit: README-only content matched the saved task
  - comparison against the current qwen reference: failed with a routine hard
    regression and one README convergence watch signal
  - failure detail: the routine alias branch reached `read_file` and
    `lan_scan`, then the model emitted a raw
    `<|tool_call>call:write_file{...}<tool_call|>` fragment in recovered text
    instead of an executable `write_file` tool call with the `contents` alias
  - compatibility decision: not full-surface baseline-ready until the raw
    special-token tool-call shape is supported or no longer emitted
  - candidate reference report:
    `build/integration_test_reports/live_llm_reference_gemma4_1779546953/reference_report.json`
  - comparison report:
    `build/integration_test_reports/live_llm_compare_qwen_vs_gemma4_1779546953/reference_compare.json`
- post-routine-guard candidate rerun:
  - date: 2026-05-24
  - routine canary result before the guard: failed, `3/4`
  - failure shape: the model skipped the required `write_file`, posted to
    Google Chat, then noted in reasoning that the state-file update was missing
    while still returning a final answer
  - routine canary result after the guard: passed, `4/4`
  - generated reference report result: passed, `13/13`
  - comparison against the current qwen reference: passed with 0 hard
    regressions, 1 README convergence watch signal, and 1 PM5 cleanup
    improvement
  - compatibility decision: superseded mixed-artifact evidence. Keep qwen as
    the named reference because the later same-revision PM5 rerun failed the
    ping CLI canary.
  - routine canary summary:
    `build/integration_test_reports/routine_live_llm_canary_1779587391/canary_summary.json`
  - candidate reference report:
    `build/integration_test_reports/live_llm_reference_gemma4_post_routine_guard_1779587391/reference_report.json`
  - comparison report:
    `build/integration_test_reports/live_llm_compare_qwen_vs_gemma4_post_routine_guard_1779587391/reference_compare.json`
- same-revision PM5 rerun:
  - date: 2026-05-24
  - PM5 live gate result: failed
  - live smoke result: `3/3` passed
  - ping CLI canary result: `0/1` passed
  - failed scenario: `live_ping_cli_completion`
  - failure class: `workflowBlocked`
  - unexpected warnings: `0`
  - report quality blockers: `1`
  - task drift: none detected by the report
  - failure shape: the model wrote `return result.return` into `ping_cli.py`,
    validation failed with `SyntaxError`, then the model repeated
    `python3 ping_cli.py --help` instead of editing the file
  - compatibility decision: blocked for baseline promotion until a
    same-revision PM5 rerun passes the ping CLI canary without a workflow
    blocker
  - smoke suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779587820296/plan_mode_live_suite_macos_report.json`
  - ping canary summary:
    `build/integration_test_reports/plan_mode_ping_cli_canary_1779588202/canary_summary.json`
  - failure reference report:
    `build/integration_test_reports/live_llm_reference_gemma4_same_revision_pm5_failed_1779588202/reference_report.json`
- same-revision PM5 retry:
  - date: 2026-05-24
  - PM5 live gate result: passed
  - live smoke result: `3/3` passed
  - ping CLI canary result: `1/1` passed
  - generated PM5-only reference report result: passed, `4/4`
  - unexpected warnings: `0`
  - report quality blockers: `0`
  - task drift: none detected by the report
  - smoke convergence: 3 saved validations, 0 guard activations, 3 natural
    stops
  - ping convergence: 1 saved validation and 1 guard activation
  - remaining risks: task proposal retries, reasoning-only `finishReason.length`
    recovery, memory extraction fallback, tool-less recovery, and one cleanup
    cancellation
  - compatibility decision: the ping CLI syntax-error failure is not
    deterministic, but the model remains a recovery-heavy candidate rather than
    a replacement reference. Require a same-revision full-surface run before
    promotion.
  - smoke suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779590250215/plan_mode_live_suite_macos_report.json`
  - ping canary summary:
    `build/integration_test_reports/plan_mode_ping_cli_canary_1779590616/canary_summary.json`
  - retry reference report:
    `build/integration_test_reports/live_llm_reference_gemma4_pm5_retry_1779590616/reference_report.json`

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
- post-hardening full model-switch baseline:
  - date: 2026-05-23
  - PM5 live gate result: passed
  - live smoke result: `3/3` passed
  - ping CLI canary result: `1/1` passed
  - focused README canary result: passed
  - chat canary result: `3/3` passed
  - tool-result budget canary result: `1/1` passed
  - routine canary result: `4/4` passed
  - unexpected warnings: `0`
  - allowed warnings: none
  - report quality blockers: `0`
  - task drift: none detected
  - artifact content fit: README-only content matched the saved task
  - approval path: live harness approval fallback for all smoke, ping, and
    focused README scenarios
  - cleanup cancellation: used in `live_host_health_scaffold` and
    `live_clarify_recovery`
  - chat recovery: 0 wrapper recovery signals
  - budget recovery: one expected compaction retry for the oversized tool
    result path
  - routine recovery: 0 wrapper recovery signals after scoped-notification
    hardening
  - smoke suite report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779497007635/plan_mode_live_suite_macos_report.json`
  - ping canary summary:
    `build/integration_test_reports/plan_mode_ping_cli_canary_1779497444/canary_summary.json`
  - focused README canary report:
    `build/integration_test_reports/plan_mode_live_suite_macos_1779497602903/plan_mode_live_suite_macos_report.json`
  - chat canary summary:
    `build/integration_test_reports/chat_live_llm_canary_1779497744/canary_summary.json`
  - tool-result budget canary summary:
    `build/integration_test_reports/tool_result_budget_live_canary_1779497770/canary_summary.json`
  - routine canary summary:
    `build/integration_test_reports/routine_live_llm_canary_1779497791/canary_summary.json`

Interpretation: `qwen3.6-27b-mtp-vision` is the current full-surface comparison
baseline for this canary revision. It passed PM5, README artifact, chat,
tool-result budget, and routine canaries. Keep it under canary observation
because the first historical PM5 attempt failed, and the latest pass still
showed cleanup cancellation in two smoke scenarios.

Interpretation: `gemma4-26b-vision` is the previous Plan Mode comparison
baseline because it has a passing PM5 gate and a post-fix focused smoke and
README refresh. It should still remain under canary observation because proposal
salvage, cleanup cancellation, guarded convergence, and earlier file-content
mix-ups were required or observed during the recorded history. Run a fresh
single PM5 gate before using it as the active reference again.

Artifact content fit is tracked separately from task drift. A run can have
`taskDriftDetected=false` when all changed paths are expected, while still
having a content-fit concern if the generated text belongs to a different file
role or task slice.

This evidence supports the current MVP release gate. Broader compatibility
claims require PM12 long-run or matrix validation across additional endpoints
and models.
