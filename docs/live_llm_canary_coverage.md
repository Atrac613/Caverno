# Live LLM Canary Coverage

This document maps Live LLM canary coverage across the current product
surfaces: chat, coding, and routines. Use it when deciding which canary to run
after changing prompts, tool orchestration, endpoint compatibility, model
settings, or feature-specific execution behavior.

## Coverage Summary

| Surface | Current canaries | Covered behavior | Main gaps | Priority |
|---------|------------------|------------------|-----------|----------|
| Chat | `tool/run_tool_result_budget_live_canary.sh` | General chat tool loop after an oversized tool result, compacted retry, final marker extraction | Plain non-tool chat streaming, memory extraction quality, native tool-role compatibility, content-embedded tool-call parsing, multi-turn continuity | Add one basic chat canary and one memory/tool-call canary |
| Coding | `tool/run_plan_mode_pm5_live_gate.sh`, `tool/run_plan_mode_ping_cli_live_canary.sh`, `live_readme_first_canary`, `tool/run_plan_mode_convergence_full_pass.sh` | Plan proposal, task proposal, decisions, approval fallback, saved task execution, validation guard, task drift, artifact expectations, report quality | Artifact content fit is mostly reviewed manually, native coding mode outside Plan Mode is not isolated, multi-file edits with tests are only indirectly covered | Keep PM5 as baseline; add automated content-fit checks before promoting more scenarios |
| Routines | `tool/run_routine_live_llm_canary.sh` | Routine execution with workspace read/write, fake LAN scan, Google Chat side effect, persisted tool call evidence | No-new-IP branch, missing/failing tool recovery, malformed tool arguments, routine memory/plan artifact behavior, scheduled/background execution | Add branch canaries before treating routines as release-complete |

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

3. Chat tool-result budget check:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_tool_result_budget_live_canary.sh
   ```

4. Routine branch check, when routines are in scope:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_routine_live_llm_canary.sh
   ```

Record model-specific evidence in
[`plan_mode_live_llm_model_canary_matrix.md`](plan_mode_live_llm_model_canary_matrix.md)
when the run affects Plan Mode or coding compatibility.

## Chat Coverage

Current chat coverage is narrow but important. The tool-result budget canary
forces a live model through this failure mode:

- call `read_file`
- receive a tool result that is too large for the first retry
- compact the tool result
- answer from the compacted result with the expected marker

This catches regressions in the general chat tool loop and prompt budget
recovery path. It does not prove that ordinary chat is healthy.

Recommended additions:

- `chat_basic_response_live_canary`: send one plain user message with no tools
  and assert that a non-empty final assistant message is produced without tool
  calls.
- `chat_memory_extraction_live_canary`: run a two-turn conversation with a
  preference statement, then assert memory extraction produces parseable,
  bounded structured memory or a documented fallback classification.
- `chat_embedded_tool_call_live_canary`: force a content-embedded tool call and
  assert the parser executes the tool once and does not repeat it after success.

Do not promote chat coverage based only on the tool-result budget canary. That
canary intentionally exercises an exceptional recovery path, not the default
chat path.

## Coding Coverage

Coding coverage is currently strongest through Plan Mode. The PM5 gate covers:

- `live_host_health_scaffold`: first-slice project scaffold and artifact
  creation.
- `live_cli_entrypoint_decision`: one planning decision before task approval.
- `live_clarify_recovery`: decision recovery and open-question handling.
- `live_ping_cli_completion`: longer single-file implementation, validation,
  and final completion behavior.

The focused `live_readme_first_canary` adds artifact convergence and the
saved-validation guard signal. It is the preferred canary for models that pass
PM5 but show content-fit problems.

Known gaps:

- Task drift is path-oriented. It can pass when the model writes wrong content
  into the right file.
- Native coding mode outside Plan Mode is not isolated by a dedicated live
  canary.
- Git and shell approval paths are mostly covered by deterministic tests, not
  by a live model canary.
- Multi-file implementation with test execution is not a default live canary.

Recommended additions:

- Add content-fit expectations to artifact-sensitive scenarios where the
  expected file role is strict.
- Add a native coding-mode canary that selects a temporary coding project,
  reads a file, edits exactly one file, validates with a read-only command, and
  stops.
- Keep multi-file live coding as canary or long-run coverage, not smoke, until
  three consecutive clean runs exist for the target model.

## Routine Coverage

The current routine canary validates the LAN watcher success path:

- read previous `lan_devices.json`
- run `lan_scan`
- write the current IP list
- post only newly discovered IPs through the Google Chat completion action

This is the right first routine canary because it verifies both routine tool
execution and the side-effect boundary. It is still one branch.

Known gaps:

- No-new-IP branch is not covered; the model might post when it should remain
  quiet.
- Tool failure recovery is not covered.
- Malformed write arguments are covered only as a possible failure class, not as
  a deliberate canary.
- Scheduled/background execution is not covered by the live model canary.
- Routine plan artifact behavior is not covered.

Recommended additions:

- `routine_lan_no_new_ip_live_canary`: same scan shape, but no new IPs; assert
  `write_file` runs and `routine_google_chat_post` does not run.
- `routine_lan_tool_failure_live_canary`: make `lan_scan` fail once; assert the
  run records the failure clearly without posting.
- `routine_workspace_write_shape_live_canary`: accept both `content` and
  `contents` only when they serialize to the expected JSON list.

Keep routine canaries outside the Plan Mode PM5 gate. They exercise a different
service and should not redefine coding smoke stability.

## Run Frequency

| Trigger | Required canaries |
|---------|-------------------|
| Model switch | PM5 gate, README first canary, tool-result budget canary |
| Plan Mode prompt or task execution change | PM5 gate, README first canary, ping CLI canary repeat when task completion changed |
| General chat tool-loop change | Tool-result budget canary, then the basic chat canary once it exists |
| Memory extraction change | Memory extraction live canary once it exists |
| Routine execution change | Routine LAN success canary plus branch-specific routine canary once available |
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
