# LL39 Host-App Latency Repeat

## Task

- Goal: measure run-to-run latency variance for the exact 170-tool post-F6
  host-app catalog and preserve probe-level distributions in the benchmark
  artifact.
- User-visible behavior: repeated benchmark artifacts summarize elapsed time
  and token usage for every attempted probe.
- Non-goals: changing probe prompts, scoring, tool residency, the model server,
  or claiming decode throughput from non-streaming probes.

## Context

- Affected components: the LL39 repeat-summary helper, benchmark artifact
  writer, focused canary tests, and live host-app catalog evidence.
- Related docs: `docs/ll39_host_app_catalog_parity_codex_task.md` and
  `docs/ll39_streaming_latency_followup_codex_task.md`.
- Reference pattern: the existing `streamingSummary` min/max/spread output.
- Known quirks: the two selected probes are sequential and share a warmed model
  and connected MCP clients. Elapsed time includes endpoint latency and is not
  a pure prompt-evaluation benchmark.

## Implementation Notes

- Add `probeSummaries`, keyed by stable probe id, only for non-skipped results.
- Record measured/passed/warning/failed run counts.
- Record min, median, max, and spread for elapsed milliseconds plus prompt and
  completion tokens. Preserve exact half-step medians for even repeat counts.
- Keep raw per-run results unchanged.
- Run three repetitions with the exact 170-total/48-initial/52-remote parity
  gate enabled.

## Acceptance Criteria

- Three values produce the expected median and spread.
- Even-sized samples preserve an exact fractional median.
- Skipped probes do not create zero-valued summaries.
- Mixed terminal statuses are counted independently.
- Existing streaming summaries and single-run artifacts remain valid.
- All three live repetitions pass both required probes against the exact
  host-app catalog.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/run_live_llm_benchmark_canary_test.dart \
  --test test/tool/live_llm_benchmark_app_tool_profile_test.dart
```

Live verification uses the managed loopback wrapper and the explicit
six-server MCP config against `qwen3.6-27b-vision`.

## Handoff Notes

- Summary: repeated artifacts now include `probeSummaries` for every attempted
  probe, with status counts and elapsed/prompt/completion distributions. Raw
  per-run results and the existing streaming summary remain unchanged.
- Tests run: `tool/codex_verify.sh --no-codegen --test
  test/tool/run_live_llm_benchmark_canary_test.dart --test
  test/tool/live_llm_benchmark_app_tool_profile_test.dart` passed
  project/package analysis, package tests, 17 focused tests, and
  notification-relay checks.
- Live evidence: all three `qwen3.6-27b-vision` repetitions preserved the exact
  170-total/48-initial/52-remote catalog and scored 80/80. The initial-harness
  probe took 11,153 ms on run 0, then 1,145 ms and 961 ms, for a 1,145 ms
  median and 10,192 ms spread. The tool-search probe stayed between 1,723 and
  1,812 ms with a 1,743 ms median and 89 ms spread. Prompt/completion usage was
  identical in every run: 8,974/15 tokens for initial selection and 8,977/35
  for tool search. Artifact directory suffix:
  `ll39_host_app_catalog_repeat_1786687074`.
- Risks or follow-ups: the follow-up protocol in
  `docs/ll39_host_app_prewarm_codex_task.md` confirmed that one discarded
  warm-up removes the large first-run penalty from the measured distribution:
  the next three initial-selection probes had a 970 ms median and 73 ms spread.
  A later reset-controlled A/B in `docs/ll39_cold_path_ab_codex_task.md`
  isolated the effect further: unrelated tool-free warm-up left an 8,429 ms
  median, while identical diagnostic warm-up reduced it to 851 ms. Exact
  request-prefix and tool-schema reuse is therefore the dominant observed
  factor, though the internal cache layer remains unidentified.
