# LL39 Streaming Latency Follow-up

## Task

- Goal: distinguish cold-start latency from steady-state streaming delivery and
  make repeated streaming measurements directly comparable in benchmark
  artifacts.
- User-visible behavior: repeated Live LLM benchmark artifacts summarize TTFT,
  total streaming time, and buffered-delivery frequency across runs.
- Non-goals: changing the model server, synthesizing decode throughput for
  buffered responses, reducing the initial tool catalog, or changing benchmark
  scoring.

## Context

- Affected components: the LL39 headless benchmark canary and its focused tests.
- Related docs: `docs/live_llm_canary_agent_runbook.md` and
  `docs/live_llm_canary_coverage.md`.
- Reference pattern: the existing repeat score summary in
  `tool/canaries/live_llm_benchmark_canary_test.dart`.
- Known quirks: `likelyBuffered: true` is a measured delivery limitation, not a
  probe failure, and buffered runs must not receive a synthetic decode rate.

## Implementation Notes

- Slice 1: run the current streaming probe three times against the warmed 27B
  endpoint and retain the raw artifact as local evidence.
- Slice 2: add a repeat-level streaming summary containing measured-run count,
  buffered-run count, and min/max/spread values for TTFT and total time.
- Slice 3: rerun the same three-repeat probe and compare cold and steady-state
  runs from the generated artifact.
- Follow-up only when evidence supports it: investigate the 62-tool initial
  harness separately. Do not mix catalog policy changes into this slice.

## Similar-Pattern Search

- Search terms: `repeatCount`, `spread`, `streamingMetrics`,
  `timeToFirstToken`, and `likelyBuffered`.
- Files inspected: the benchmark canary, live canary summary, streaming metric
  entity, physical-metric profile mapping, and focused canary tests.
- Follow-up tasks found: sampler trials also omit per-trial latency, but sampler
  telemetry is outside this streaming-focused task.

## Acceptance Criteria

- A repeated artifact exposes aggregate TTFT and total-time ranges without
  removing the existing per-run reports.
- The summary reports how many measured runs were likely buffered.
- Missing streaming metrics produce an absent summary rather than zero-valued
  measurements.
- Single-run artifacts remain valid and report zero spread.
- Benchmark score, suite version, probe behavior, and profile import remain
  unchanged.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/run_live_llm_benchmark_canary_test.dart
```

Live verification uses the managed loopback wrapper and pins
`streaming_response` as the required probe with a repeat count of three.

## Handoff Notes

- Summary: repeated artifacts now include `streamingSummary` with measured and
  buffered run counts plus TTFT and total-time ranges. The pre-change live run
  isolated a freshly loaded first full-stream request at 38,680 ms TTFT from
  steady-state runs at 3,769 ms and 3,781 ms. The post-change warmed run
  reported a 3,711-4,202 ms TTFT range and a 3,730-4,227 ms total-time range.
- Tests run: `tool/codex_verify.sh --no-codegen --test
  test/tool/run_live_llm_benchmark_canary_test.dart` passed analysis, package
  tests, 12 focused tests, and notification-relay checks. The post-change live
  canary passed 1/1 with main readiness `ready` and 50/50 points in all three
  repeats.
- Coverage or low-coverage notes: the helper covers repeated, missing, and
  single-run metrics. Live artifacts remain local under
  `build/integration_test_reports/ll39_streaming_latency_baseline_1786683494/`
  and
  `build/integration_test_reports/ll39_streaming_latency_summary_1786683725/`.
- Risks or follow-ups: all six measured runs were likely buffered, so the
  endpoint still has no defensible decode-rate measurement. Initial
  tool-catalog cost and sampler latency remain separate evidence-driven
  follow-ups.
