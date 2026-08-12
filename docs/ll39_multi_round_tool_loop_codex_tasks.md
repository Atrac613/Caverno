# LL39 Multi-Round Tool Loop Tasks

## Goal

Measure whether a model can complete a sequential Caverno tool workflow and
record the cost in physical units after bounded conformance has saturated.

## Task 1: Measurement Contract

- Goal: add a typed report contract for multi-round loop measurements.
- User-visible behavior: exported diagnostics retain model turns, tool calls,
  successful executions, token usage, elapsed time, and task completion.
- Non-goals: no live requests, score changes, or diagnostic-page UI in this
  task.
- Affected files:
  - `lib/features/settings/domain/entities/live_llm_diagnostic.dart`
  - `test/features/settings/domain/entities/live_llm_diagnostic_test.dart`
- Acceptance criteria:
  - Metrics serialize in physical units without a synthetic point total.
  - Failed or incomplete probes can retain partial measurements.
  - Existing reports omit the new block when it was not measured.
- Verification:

  ```bash
  tool/codex_verify.sh --test test/features/settings/domain/entities/live_llm_diagnostic_test.dart
  ```

## Task 2: Sequential Probe

- Goal: add a safe loop that requires two sequential tool rounds and a final
  answer.
- Preferred flow:
  1. Expose only `tool_search` and ask the model to find the current-datetime
     capability.
  2. Execute the local search and expose the discovered
     `get_current_datetime` definition on the next request.
  3. Execute the local datetime tool and require a final JSON answer that copies
     its marker fields.
- Constraints:
  - Use `createChatCompletionWithToolResults`, matching the production native
    tool-result continuation path.
  - Do not expose the datetime tool on turn one; otherwise the model can skip
    the multi-round contract.
  - Cap the probe at three model turns and two successful tool executions.
  - Use only read-only, local built-in tools and production-shaped task wording.
- Acceptance criteria:
  - Parallel calls, skipped search, skipped datetime, extra tool calls, and a
    missing final marker produce distinguishable terminal results.
  - Usage and elapsed measurements include every model turn.
  - Deterministic fakes cover success and each early exit.
- Verification:

  ```bash
  tool/codex_verify.sh --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart
  ```

## Task 3: Scoring, UI, And Live Evidence

- Goal: surface and validate the finished probe without weakening the fixed
  benchmark denominator.
- Affected components:
  - `LiveLlmDiagnosticSuite` versioned weight table
  - Live LLM diagnostic capability section and translations
  - LL39 headless canary artifact and coverage documentation
- Constraints:
  - Keep the conformance maximum at 1000 by rebalancing weights.
  - Keep turns, tokens, and elapsed time outside the weighted score.
  - Pin `multi_round_tool_loop` as required during focused live validation.
- Acceptance criteria:
  - The UI and JSON artifact show the same physical measurements.
  - A focused live canary proves two tool rounds and a final answer occurred.
  - A full live run retains the fixed denominator and records suite-version
    incompatibility with older reports.
- Verification:

  ```bash
  tool/codex_verify.sh
  CAVERNO_BENCHMARK_CANARY_PROBE_IDS=multi_round_tool_loop \
  CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS=multi_round_tool_loop \
  CAVERNO_BENCHMARK_CANARY_MIN_POINTS=80 \
  tool/run_live_llm_benchmark_canary.sh
  ```

- Progress:
  - Completed: `cavernobench` v4 scoring with the fixed 1000-point maximum.
  - Completed: UI and JSON expose the same multi-round physical measurements.
  - Completed: focused live validation against `qwen/qwen3-coder-next`.
  - Completed: full-suite v4 validation against the reference model endpoint.

## Similar-Pattern Search

- Search terms: `tool_result_integration`, `tool_search`,
  `createChatCompletionWithToolResults`, `activeToolNames`, `turnCount`,
  `toolCallCount`.
- Inspected:
  - `LiveLlmDiagnosticService._runToolResultProbe`
  - `ChatNotifier._sendWithTools` and its dynamic tool discovery loop
  - `ToolDefinitionSearchService.discoveredToolNamesFromResults`
  - Personal-eval physical-unit reporting
- Follow-up: edit-format recovery remains a separate LL39 slice; it must not be
  mixed into this deterministic loop.
