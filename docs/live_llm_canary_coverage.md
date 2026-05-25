# Live LLM Canary Coverage

This document maps Live LLM canary coverage across the current product
surfaces: chat, coding, and routines. Use it when deciding which canary to run
after changing prompts, tool orchestration, endpoint compatibility, model
settings, or feature-specific execution behavior.

## Coverage Summary

| Surface | Current canaries | Covered behavior | Main gaps | Priority |
|---------|------------------|------------------|-----------|----------|
| Chat | `tool/run_chat_live_llm_canary.sh`, `tool/run_tool_result_budget_live_canary.sh` | Plain chat streaming, memory extraction JSON, content-embedded tool-call execution, incomplete inline tool-call recovery, assistant-authored `tool_result` rejection, oversized tool-result compaction retry, final marker extraction | Native tool-role compatibility and broad multi-turn continuity beyond focused parser recovery | Keep the chat canary suite in every model switch baseline |
| Coding | `tool/run_plan_mode_pm5_live_gate.sh`, `tool/run_plan_mode_ping_cli_live_canary.sh`, `live_readme_first_canary`, `tool/run_coding_goal_live_canary.sh`, `tool/run_plan_mode_convergence_full_pass.sh` | Plan proposal, task proposal, decisions, approval fallback, saved task execution, validation guard, task drift, README content-fit marker, coding goal prompt injection, multi-turn goal persistence, budget prompt context, exhausted-budget guidance, automatic goal completion, completed/disabled goal prompt suppression, negative-completion guard, repeated-blocker auto-blocking, report quality | Native coding mode multi-file edits with tests are still only indirectly covered outside Plan Mode | Keep PM5 as baseline; run the focused coding-goal canary after changing goal state, coding prompts, budget handling, or completion/blocker inference |
| Routines | `tool/run_routine_live_llm_canary.sh` | Routine execution with workspace read/write, fake LAN scan, Google Chat side effect, no-new-IP branch, LAN failure branch, `contents` write-shape branch, persisted tool call evidence | Scheduled/background execution and routine plan artifact behavior | Keep routine canaries outside PM5 but run them for routine changes and broad model switches |

## Baseline Model Switch Flow

For each model switch, run this minimum set before comparing model quality:

1. Coding baseline:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20 \
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
   CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS=20 \
   tool/run_plan_mode_live_test.sh
   ```

3. Coding goal check:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_coding_goal_live_canary.sh
   ```

4. Chat branch checks:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_chat_live_llm_canary.sh
   ```

5. Chat tool-result budget check:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_tool_result_budget_live_canary.sh
   ```

6. Routine branch checks, when routines are in scope:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_routine_live_llm_canary.sh
   ```

Record model-specific evidence in
[`plan_mode_live_llm_model_canary_matrix.md`](plan_mode_live_llm_model_canary_matrix.md)
when the run affects Plan Mode or coding compatibility.

Use the same app and canary revision for the reference model and the candidate
model. If parser recovery, task-drift classification, warning allow rules, or
saved-validation expectations change between runs, rerun the reference model
before comparing model behavior.

After completing the run set, generate a local reference report from the
artifacts before updating the model matrix:

```bash
dart run tool/live_llm_canary_reference_report.dart \
  --out-dir build/integration_test_reports/live_llm_reference_<timestamp> \
  --label "qwen3.6-27b-mtp-vision post-hardening" \
  --report-root build/integration_test_reports
```

The `--report-root` mode discovers the latest available PM5 smoke, PM5 ping,
README, coding goal, chat, tool-result budget, and routine artifacts. Use
explicit paths when reconstructing an older run set or overriding one
discovered artifact:

The generated report fails if selected artifacts with non-empty model IDs or
base URLs disagree. When that happens, rerun the missing surfaces on the same
model and endpoint, or pass explicit artifact paths from a consistent run set.

```bash
dart run tool/live_llm_canary_reference_report.dart \
  --out-dir build/integration_test_reports/live_llm_reference_<timestamp> \
  --label "qwen3.6-27b-mtp-vision post-hardening" \
  --pm5-smoke-report build/integration_test_reports/<smoke>/plan_mode_live_suite_macos_report.json \
  --pm5-ping-summary build/integration_test_reports/<ping>/canary_summary.json \
  --readme-report build/integration_test_reports/<readme>/plan_mode_live_suite_macos_report.json \
  --coding-goal-summary build/integration_test_reports/<coding-goal>/canary_summary.json \
  --chat-summary build/integration_test_reports/<chat>/canary_summary.json \
  --budget-summary build/integration_test_reports/<budget>/canary_summary.json \
  --routine-summary build/integration_test_reports/<routine>/canary_summary.json
```

The generated `reference_report.md` is a compact handoff artifact for comparing
overall pass counts, task-drift or warning risk, cleanup cancellation, approval
fallback use, and Live LLM recovery signals before writing narrative docs.

When comparing a candidate model against the current reference, compare the two
generated reference reports before reading raw logs:

```bash
dart run tool/live_llm_canary_reference_compare.dart \
  --reference build/integration_test_reports/<reference>/reference_report.json \
  --candidate build/integration_test_reports/<candidate>/reference_report.json \
  --out-dir build/integration_test_reports/live_llm_compare_<timestamp> \
  --label "reference vs candidate"
```

The comparison exits non-zero for hard regressions such as failed checks,
unexpected warnings, task drift, report-quality blockers, transport disconnects,
stream fallback, or memory fallback increases. Approval fallback, cleanup
cancellation, guard activation, allowed-warning, and compaction-retry increases
are recorded as watch signals instead of hard failures.

## Latest Full-Surface Evidence

### 2026-05-23: `qwen3.6-27b-mtp-vision`

- Endpoint: `http://192.168.100.241:1234/v1`
- Model discovered from `/models`: `qwen3.6-27b-mtp-vision`
- API key: `no-key`
- Baseline status: current post-hardening full-surface comparison reference
- Scope note: all required model-switch canaries ran on the same app and canary
  revision after routine scoped-notification hardening. Chat, chat-budget, and
  routine wrappers write `canary_summary.json`, `canary_summary.md`, and a
  captured Flutter JSON log.

| Surface | Check | Result | Evidence | Notes |
|---------|-------|--------|----------|-------|
| Coding PM5 | `tool/run_plan_mode_pm5_live_gate.sh` with `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1` | Passed | Smoke 3/3, ping canary 1/1 | Report quality ready, 0 unexpected warnings, 0 task drift. Smoke used live harness approval fallback for all scenarios; cleanup cancellation occurred in `live_host_health_scaffold` and `live_clarify_recovery`. |
| Coding artifact | `live_readme_first_canary` | Passed | 1/1 focused canary | `README.md` was the saved target and actual changed file, contained `CANARY_CONTENT_FIT: README_ONLY`, and ended with natural-stop convergence after saved validation. |
| Chat | `tool/run_chat_live_llm_canary.sh` | Passed | 3/3 tests passed | Plain chat, memory extraction JSON, and embedded `<tool_call>` execution passed with 0 recovery signals. |
| Chat budget | `tool/run_tool_result_budget_live_canary.sh` | Passed | 1/1 test passed | Oversized `read_file` result compacted successfully with the expected single compaction retry. |
| Routines | `tool/run_routine_live_llm_canary.sh` | Passed | 4/4 tests passed after prompt hardening | New-IP post, no-new-IP no-post, LAN scan failure, and `contents` write-shape branches passed with 0 recovery signals. |

Artifacts:

- PM5 smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497007635/plan_mode_live_suite_macos_report.json`
- PM5 smoke Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497007635/plan_mode_live_suite_macos_report.md`
- PM5 ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779497444/canary_summary.json`
- PM5 ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779497444/run_01_suite_report.json`
- PM5 ping live suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497473182/plan_mode_live_suite_macos_report.json`
- Focused README canary report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779497602903/plan_mode_live_suite_macos_report.json`
- Chat wrapper refresh:
  `build/integration_test_reports/chat_live_llm_canary_1779497744/canary_summary.json`
- Tool-result budget wrapper refresh:
  `build/integration_test_reports/tool_result_budget_live_canary_1779497770/canary_summary.json`
- Routine wrapper post-hardening refresh:
  `build/integration_test_reports/routine_live_llm_canary_1779497791/canary_summary.json`
- Historical routine scoped-notification failure before prompt hardening:
  `build/integration_test_reports/routine_live_llm_canary_1779496133/canary_summary.json`

### 2026-05-23 Candidate: `gemma4-26b-vision`

- Endpoint: `http://192.168.100.241:1234/v1`
- Model discovered from `/models`: `gemma4-26b-vision`
- API key: `no-key`
- Baseline status: superseded blocked candidate
- Scope note: the full model-switch canary set ran on the same app and canary
  revision as the current reference comparison flow. The generated candidate
  reference report is useful for comparison, but it is failed evidence rather
  than a promotable baseline. Use the 2026-05-24 post-routine-guard candidate
  below for the current gemma evaluation.

| Surface | Check | Result | Evidence | Notes |
|---------|-------|--------|----------|-------|
| Coding PM5 | `tool/run_plan_mode_pm5_live_gate.sh` with `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1` | Passed | Smoke 3/3, ping canary 1/1 | Report quality ready, 0 unexpected warnings, 0 task drift. Smoke used live harness approval fallback for all scenarios; cleanup cancellation occurred only in `live_clarify_recovery`. |
| Coding artifact | `live_readme_first_canary` | Passed | 1/1 focused canary | `README.md` was the saved target and actual changed file, contained `CANARY_CONTENT_FIT: README_ONLY`, and required one saved-validation guard after validation succeeded. |
| Chat | `tool/run_chat_live_llm_canary.sh` | Passed | 3/3 tests passed | Plain chat, memory extraction JSON, and embedded `<tool_call>` execution passed with 0 recovery signals. |
| Chat budget | `tool/run_tool_result_budget_live_canary.sh` | Passed | 1/1 test passed | Oversized `read_file` result compacted successfully with the expected single compaction retry. |
| Routines | `tool/run_routine_live_llm_canary.sh` | Failed | 3/4 tests passed | New-IP post, no-new-IP no-post, and LAN scan failure passed. The `contents` write-shape branch failed when the model emitted a raw special-token `write_file` call in recovered text instead of an executable tool call. |

Artifacts:

- PM5 smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546363391/plan_mode_live_suite_macos_report.json`
- PM5 smoke Markdown:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546363391/plan_mode_live_suite_macos_report.md`
- PM5 ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779546717/canary_summary.json`
- PM5 ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779546717/run_01_suite_report.json`
- PM5 ping live suite report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546746368/plan_mode_live_suite_macos_report.json`
- Focused README canary report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779546851868/plan_mode_live_suite_macos_report.json`
- Chat wrapper refresh:
  `build/integration_test_reports/chat_live_llm_canary_1779546901/canary_summary.json`
- Tool-result budget wrapper refresh:
  `build/integration_test_reports/tool_result_budget_live_canary_1779546936/canary_summary.json`
- Routine wrapper refresh:
  `build/integration_test_reports/routine_live_llm_canary_1779546953/canary_summary.json`
- Candidate reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_1779546953/reference_report.json`
- Comparison against the current qwen reference:
  `build/integration_test_reports/live_llm_compare_qwen_vs_gemma4_1779546953/reference_compare.json`

### 2026-05-24 Candidate: `gemma4-26b-vision` Post-Routine Guard

- Endpoint: `http://192.168.100.241:1234/v1`
- Model discovered from `/models`: `gemma4-26b-vision`
- API key: `no-key`
- Baseline status: superseded mixed-artifact candidate pass
- Scope note: the routine hard regression was fixed by rejecting final answers
  while a required routine workspace write is still missing. The regenerated
  reference report combines the previous PM5, README, chat, and budget
  artifacts with the new routine rerun. A later same-revision PM5 rerun failed
  in the ping CLI canary, so this remains historical evidence rather than a
  promotable model baseline.

| Surface | Check | Result | Evidence | Notes |
|---------|-------|--------|----------|-------|
| Coding PM5 | `tool/run_plan_mode_pm5_live_gate.sh` with `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1` | Passed | Smoke 3/3, ping canary 1/1 | Reused from the candidate full-surface rerun. Report quality ready, 0 unexpected warnings, 0 task drift, and one cleanup cancellation in `live_clarify_recovery`. |
| Coding artifact | `live_readme_first_canary` | Passed | 1/1 focused canary | Reused from the candidate full-surface rerun. `README.md` was the saved target and actual changed file, with one saved-validation guard. |
| Chat | `tool/run_chat_live_llm_canary.sh` | Passed | 3/3 tests passed | Reused from the candidate full-surface rerun with 0 recovery signals. |
| Chat budget | `tool/run_tool_result_budget_live_canary.sh` | Passed | 1/1 test passed | Reused from the candidate full-surface rerun with the expected single compaction retry. |
| Routines | `tool/run_routine_live_llm_canary.sh` | Passed | 4/4 tests passed | Rerun after the missing required write guard. The model recovered the `contents` alias branch and produced 0 recovery signals. |

Artifacts:

- Routine wrapper post-guard refresh:
  `build/integration_test_reports/routine_live_llm_canary_1779587391/canary_summary.json`
- Candidate reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_post_routine_guard_1779587391/reference_report.json`
- Comparison against the current qwen reference:
  `build/integration_test_reports/live_llm_compare_qwen_vs_gemma4_post_routine_guard_1779587391/reference_compare.json`

### 2026-05-24 Candidate: `gemma4-26b-vision` Same-Revision PM5 Pair

- Endpoint: `http://192.168.100.241:1234/v1`
- Model discovered from `/models`: `gemma4-26b-vision`
- API key: `no-key`
- Baseline status: inconsistent PM5 candidate, not reference-ready
- Scope note: these reruns were started after the routine required-write guard
  was committed, using one app revision. The first PM5 run failed in the ping
  CLI canary, while the immediate retry passed PM5 smoke and ping. The remaining
  README, chat, budget, and routine canaries were not rerun in this pair.

| Surface | Check | Result | Evidence | Notes |
|---------|-------|--------|----------|-------|
| Coding PM5 first run | `tool/run_plan_mode_pm5_live_gate.sh` | Failed | Smoke 3/3, ping canary 0/1 | `live_ping_cli_completion` ended `workflowBlocked`. The model wrote `return result.return` in `ping_cli.py`, validation failed with `SyntaxError`, and the model repeated the same validation command instead of repairing the file. |
| Coding PM5 retry | `tool/run_plan_mode_pm5_live_gate.sh` | Passed | Smoke 3/3, ping canary 1/1 | Report quality ready, 0 unexpected warnings, 0 task drift. Smoke had natural-stop convergence but still showed task proposal retries, reasoning-only recovery, memory fallback, tool-less recovery, and one cleanup cancellation. Ping completed with one saved-validation guard. |

Artifacts:

- First PM5 smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779587820296/plan_mode_live_suite_macos_report.json`
- First PM5 ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779588202/canary_summary.json`
- First PM5 ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779588202/run_01_suite_report.json`
- First PM5-only failure reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_same_revision_pm5_failed_1779588202/reference_report.json`
- Retry PM5 smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779590250215/plan_mode_live_suite_macos_report.json`
- Retry PM5 ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779590616/canary_summary.json`
- Retry PM5 ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779590616/run_01_suite_report.json`
- Retry PM5-only reference report:
  `build/integration_test_reports/live_llm_reference_gemma4_pm5_retry_1779590616/reference_report.json`

### 2026-05-24 Candidate: `gemma4-26b-vision` Same-Revision Full Surface

- Endpoint: `http://192.168.100.241:1234/v1`
- Model discovered from `/models`: `gemma4-26b-vision`
- API key: `no-key`
- Baseline status: candidate pass, not the named replacement reference
- Scope note: this rerun completed the same-revision evidence requested after
  the PM5 retry. PM5 smoke and ping evidence comes from the immediate retry in
  the pair above; README, chat, budget, and routine were rerun on the same app
  revision. The qwen comparison has no hard regression, but the prior PM5 ping
  failure keeps this model in recovery-heavy candidate status.

| Surface | Check | Result | Evidence | Notes |
|---------|-------|--------|----------|-------|
| Coding PM5 | `tool/run_plan_mode_pm5_live_gate.sh` with `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1` | Passed | Smoke 3/3, ping canary 1/1 | Reused from the immediate PM5 retry. Report quality ready, 0 unexpected warnings, 0 task drift, and one ping saved-validation guard. |
| Coding artifact | `live_readme_first_canary` | Passed | 1/1 focused canary | `README.md` was the saved target and actual changed file, contained `CANARY_CONTENT_FIT: README_ONLY`, and required one saved-validation guard after validation succeeded. |
| Chat | `tool/run_chat_live_llm_canary.sh` | Passed | 3/3 tests passed | Plain chat, memory extraction JSON, and embedded `<tool_call>` execution passed with 0 recovery signals. |
| Chat budget | `tool/run_tool_result_budget_live_canary.sh` | Passed | 1/1 test passed | Oversized `read_file` result compacted successfully with the expected single compaction retry. |
| Routines | `tool/run_routine_live_llm_canary.sh` | Passed | 4/4 tests passed | New-IP post, no-new-IP no-post, LAN scan failure, and `contents` write-shape branches passed with 0 recovery signals. |

Artifacts:

- PM5 retry smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779590250215/plan_mode_live_suite_macos_report.json`
- PM5 retry ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779590616/canary_summary.json`
- Focused README canary report:
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

### Previous Reference: `gemma4-26b-vision`

- Endpoint: `http://192.168.100.241:1234/v1`
- Model discovered from `/models`: `gemma4-26b-vision`
- API key: `no-key`
- Baseline status: previous comparison reference
- Scope note: PM5 and ping evidence came from the last full PM5 gate rerun.
  Focused smoke, README artifact, and chat evidence were refreshed after the
  latest canary expectation and parser fixes. Use the qwen baseline above for
  the current model-switch comparison unless intentionally comparing against
  the previous reference model.

| Surface | Check | Result | Evidence | Notes |
|---------|-------|--------|----------|-------|
| Coding PM5 | `tool/run_plan_mode_pm5_live_gate.sh` with `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1` | Passed | Smoke 3/3, ping canary 1/1 | Full gate passed. Smoke report quality was ready, ping had one allowed `recoveredCreateParseWarning`, and task drift was 0 in both reports. |
| Coding smoke refresh | `tool/run_plan_mode_live_test.sh` with `CAVERNO_PLAN_MODE_TAGS=smoke` | Passed | 3/3 focused smoke | Report quality ready, 0 task drift, 0 unexpected warnings, and one allowed `recoveredCreateParseWarning`. |
| Coding artifact | `live_readme_first_canary` | Passed | 1/1 focused canary | `README.md` was the saved target and actual changed file, contained `CANARY_CONTENT_FIT: README_ONLY`, and converged with one guard activation plus one natural stop. |
| Chat | `tool/run_chat_live_llm_canary.sh` | Passed | 3/3 tests passed | Plain chat, memory extraction JSON, and embedded `<tool_call>` execution passed after reasoning-field JSON parser coverage. |
| Chat budget | `tool/run_tool_result_budget_live_canary.sh` | Passed | 1/1 test passed | Oversized `read_file` result compacted successfully and the model returned `COMPACT_BUDGET_LIVE_OK`. |
| Routines | `tool/run_routine_live_llm_canary.sh` | Passed | 4/4 tests passed | New-IP post, no-new-IP no-post, LAN scan failure, and `contents` write-shape branches all passed. |

Artifacts:

- Previous smoke refresh report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779462479260/plan_mode_live_suite_macos_report.json`
- Previous focused README canary report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779461715586/plan_mode_live_suite_macos_report.json`
- PM5 smoke report:
  `build/integration_test_reports/plan_mode_live_suite_macos_1779459048707/plan_mode_live_suite_macos_report.json`
- PM5 ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779459449/canary_summary.json`
- PM5 ping canary suite report:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1779459449/run_01_suite_report.json`

The chat, chat-budget, and routine live scripts write
`canary_summary.json`, `canary_summary.md`, and `flutter_test.jsonl` under
`build/integration_test_reports/<canary_name>_<timestamp>/`. The summary records
pass/fail counts plus recovery signals such as non-streaming fallback after a
streaming disconnect, incomplete content-tool recovery, ignored
assistant-authored `tool_result` tags, and tool-result compaction retry counts.

## Chat Coverage

The chat live canary suite covers the default and parser-sensitive paths:

- `chat_basic_response_live_canary`: sends one plain user message with no tool
  definitions and asserts a non-empty marker response.
- `chat_memory_extraction_live_canary`: asks the live model to produce the
  memory extraction JSON schema, parses it, and asserts bounded summary and
  memory evidence.
- `chat_embedded_tool_call_live_canary`: asks for one content-embedded
  `<tool_call>`, executes the test tool once, and asserts the result marker.
- `chat_inline_tool_recovery_live_canary`: injects one deliberately incomplete
  `<tool_use>` stream chunk, verifies the recovered tool executes once, and
  asks the live model to finish from the trusted tool result without raw tool
  artifacts in model history.
- `chat_assistant_tool_result_rejection_live_canary`: injects one
  assistant-authored `<tool_result>`, verifies the untrusted result is ignored
  without executing a tool, and asks the live model to finish from the recovery
  notice.

The separate tool-result budget canary forces a live model through this failure
mode:

- call `read_file`
- receive a tool result that is too large for the first retry
- compact the tool result
- answer from the compacted result with the expected marker

Together these canaries catch regressions in ordinary chat, memory extraction,
embedded tool parsing, focused inline tool recovery, untrusted tool-result
rejection, and prompt-budget recovery. They still do not prove native tool-role
compatibility across every endpoint.

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
| Model switch | PM5 gate, README first canary, chat live canary, tool-result budget canary; add routine LAN branch canaries for broad cross-surface comparison |
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
- The reference model and candidate model were run on the same app and canary
  revision, or the reference model was rerun after the harness change.
