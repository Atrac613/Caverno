# Live LLM Canary Coverage

This document maps Live LLM canary coverage across the current product
surfaces: chat, coding, and routines. Use it when deciding which canary to run
after changing prompts, tool orchestration, endpoint compatibility, model
settings, or feature-specific execution behavior.

## Coverage Summary

| Surface | Current canaries | Covered behavior | Main gaps | Priority |
|---------|------------------|------------------|-----------|----------|
| Chat | `tool/run_chat_live_llm_canary.sh`, `tool/run_tool_result_budget_live_canary.sh` | Plain chat streaming, memory extraction JSON, content-embedded tool-call execution, oversized tool-result compaction retry, final marker extraction | Native tool-role compatibility and multi-turn continuity beyond the memory extraction probe | Keep the chat canary suite in every model switch baseline |
| Coding | `tool/run_plan_mode_pm5_live_gate.sh`, `tool/run_plan_mode_ping_cli_live_canary.sh`, `live_readme_first_canary`, `tool/run_plan_mode_convergence_full_pass.sh` | Plan proposal, task proposal, decisions, approval fallback, saved task execution, validation guard, task drift, README content-fit marker, report quality | Native coding mode outside Plan Mode is not isolated, multi-file edits with tests are only indirectly covered | Keep PM5 as baseline; keep content-fit assertions on artifact-sensitive canaries |
| Routines | `tool/run_routine_live_llm_canary.sh` | Routine execution with workspace read/write, fake LAN scan, Google Chat side effect, no-new-IP branch, LAN failure branch, `contents` write-shape branch, persisted tool call evidence | Scheduled/background execution and routine plan artifact behavior | Keep routine canaries outside PM5 but run them for routine changes and broad model switches |

## Baseline Model Switch Flow

For each model switch, run this minimum set before comparing model quality:

1. Coding baseline:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 \
   tool/run_plan_mode_pm5_live_gate.sh
   ```

2. Artifact content check:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary \
   CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1 \
   tool/run_plan_mode_live_test.sh
   ```

3. Chat branch checks:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_chat_live_llm_canary.sh
   ```

4. Chat tool-result budget check:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_tool_result_budget_live_canary.sh
   ```

5. Routine branch checks, when routines are in scope:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_routine_live_llm_canary.sh
   ```

Record model-specific evidence in
[`plan_mode_live_llm_model_canary_matrix.md`](plan_mode_live_llm_model_canary_matrix.md)
when the run affects Plan Mode or coding compatibility.

## Latest Full-Surface Evidence

### 2026-05-22: `gemma4-26b-vision`

- Endpoint: `http://192.168.100.241:1234/v1`
- Model discovered from `/models`: `gemma4-26b-vision`
- API key: `no-key`

| Surface | Check | Result | Evidence | Notes |
|---------|-------|--------|----------|-------|
| Coding | `tool/run_plan_mode_pm5_live_gate.sh` with `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1` | Passed | Smoke 3/3, ping canary 1/1 | Smoke had no warnings and report quality was ready. Ping canary had one allowed `recoveredCreateParseWarning`, report quality ready, and no task drift. |
| Coding artifact | `live_readme_first_canary` | Failed | 0/1 focused canary | `README.md` with `CANARY_CONTENT_FIT: README_ONLY` was written, but the run produced no saved-validation success log. Report quality blockers: `streamDisconnect` and `missingExpectedSavedTaskTargetFiles`. |
| Chat | `tool/run_chat_live_llm_canary.sh` | Failed | 2/3 tests passed | Plain chat and embedded `<tool_call>` execution passed. Memory extraction failed because the live response ended with `FinishReason.length`, app-facing content was empty, and the parseable JSON appeared only inside reasoning text. |
| Chat budget | `tool/run_tool_result_budget_live_canary.sh` | Passed | 1/1 test passed | Oversized `read_file` result compacted successfully and the model returned `COMPACT_BUDGET_LIVE_OK`. |
| Routines | `tool/run_routine_live_llm_canary.sh` | Passed | 4/4 tests passed | New-IP post, no-new-IP no-post, LAN scan failure, and `contents` write-shape branches all passed. |

Artifacts:

- PM5 smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779459048707/plan_mode_live_suite_macos_report.json`
- PM5 ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779459449/canary_summary.json`
- PM5 ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779459449/run_01_suite_report.json`
- Focused README canary report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779458844245/plan_mode_live_suite_macos_report.json`

## Chat Coverage

The chat live canary suite covers the default and parser-sensitive paths:

- `chat_basic_response_live_canary`: sends one plain user message with no tool
  definitions and asserts a non-empty marker response.
- `chat_memory_extraction_live_canary`: asks the live model to produce the
  memory extraction JSON schema, parses it, and asserts bounded summary and
  memory evidence.
- `chat_embedded_tool_call_live_canary`: asks for one content-embedded
  `<tool_call>`, executes the test tool once, and asserts the result marker.

The separate tool-result budget canary forces a live model through this failure
mode:

- call `read_file`
- receive a tool result that is too large for the first retry
- compact the tool result
- answer from the compacted result with the expected marker

Together these canaries catch regressions in ordinary chat, memory extraction,
embedded tool parsing, and prompt-budget recovery. They still do not prove
native tool-role compatibility across every endpoint.

## Coding Coverage

Coding coverage is currently strongest through Plan Mode. The PM5 gate covers:

- `live_host_health_scaffold`: first-slice project scaffold and artifact
  creation.
- `live_cli_entrypoint_decision`: one planning decision before task approval.
- `live_clarify_recovery`: decision recovery and open-question handling.
- `live_ping_cli_completion`: longer single-file implementation, validation,
  and final completion behavior.

The focused `live_readme_first_canary` adds artifact convergence, the
saved-validation guard signal, and the `CANARY_CONTENT_FIT: README_ONLY`
content marker. It is the preferred canary for models that pass PM5 but show
content-fit problems.

Known gaps:

- Native coding mode outside Plan Mode is not isolated by a dedicated live
  canary.
- Git and shell approval paths are mostly covered by deterministic tests, not
  by a live model canary.
- Multi-file implementation with test execution is not a default live canary.

Recommended additions:

- Add a native coding-mode canary that selects a temporary coding project,
  reads a file, edits exactly one file, validates with a read-only command, and
  stops.
- Keep multi-file live coding as canary or long-run coverage, not smoke, until
  three consecutive clean runs exist for the target model.

## Routine Coverage

The current routine canary validates the LAN watcher branches:

- read previous `lan_devices.json`
- run `lan_scan`
- write the current IP list
- post only newly discovered IPs through the Google Chat completion action
- `routine_lan_no_new_ip_live_canary`: update the file without posting when
  there are no newly discovered IPs
- `routine_lan_tool_failure_live_canary`: record a LAN scan failure without
  posting to Google Chat
- `routine_workspace_write_shape_live_canary`: accept the `contents` write
  argument alias when it serializes to the expected JSON list

This verifies both routine tool execution and the side-effect boundary across
the high-risk branches.

Known gaps:

- Scheduled/background execution is not covered by the live model canary.
- Routine plan artifact behavior is not covered.

Recommended additions:

- Add scheduled/background execution coverage once the routine scheduler can run
  an isolated live canary without depending on wall-clock timing.
- Add routine plan artifact coverage when approved plans become part of the
  model-switch baseline.

Keep routine canaries outside the Plan Mode PM5 gate. They exercise a different
service and should not redefine coding smoke stability.

## Run Frequency

| Trigger | Required canaries |
|---------|-------------------|
| Model switch | PM5 gate, README first canary, chat live canary, tool-result budget canary |
| Plan Mode prompt or task execution change | PM5 gate, README first canary, ping CLI canary repeat when task completion changed |
| General chat tool-loop change | Chat live canary, tool-result budget canary |
| Memory extraction change | Chat live canary |
| Routine execution change | Routine LAN branch canaries |
| Release candidate | PM5 gate, selected canaries from this document, deterministic smoke, static analysis |

## Promotion Rules

A new Live LLM canary can become baseline only when all of these are true:

- It has a clear owner surface: chat, coding, or routines.
- It has deterministic setup and isolated side effects.
- It records pass/fail artifacts with enough diagnostic detail to classify
  model, endpoint, prompt, and app regressions separately.
- It has explicit positive and negative artifact or side-effect expectations.
- It has at least three consecutive clean runs against the target release model
  before smoke promotion is considered.
- Its failure adds new information that is not already covered by PM5 or an
  existing canary.
