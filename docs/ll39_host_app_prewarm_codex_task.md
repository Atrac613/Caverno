# LL39 Host-App Pre-Warm Protocol

## Task

- Goal: separate the first-run cold-path penalty from steady-state LL39 probe
  distributions under the exact 170-tool host-app catalog.
- User-visible behavior: a benchmark may execute explicit warm-up repetitions,
  retain their evidence separately, and exclude them from measured summaries.
- Non-goals: hiding failed warm-ups, changing model prompts, clearing the model
  server cache, or attributing the cold-path cost to one subsystem without
  further evidence.

## Context

- Affected components: the LL39 benchmark canary environment, run orchestration,
  artifact schema, runner forwarding, and focused tests.
- Related docs: `docs/ll39_host_app_latency_repeat_codex_task.md` and
  `docs/ll39_host_app_catalog_parity_codex_task.md`.
- Reference pattern: `CAVERNO_BENCHMARK_CANARY_REPEAT_COUNT` and the existing
  per-run report export.
- Known quirks: the prior three-run artifact measured 11,153 ms for the first
  initial-selection probe and 1,145/961 ms afterward. Warm-up must use the same
  connected MCP service and exact catalog to be comparable.

## Implementation Notes

- Add `CAVERNO_BENCHMARK_CANARY_WARMUP_REPEAT_COUNT`, defaulting to zero.
- Execute warm-ups after MCP connection and exact parity validation but before
  measured repetitions.
- Apply the same terminal-state, attempted-probe, and required-probe checks to
  warm-ups. A failed or skipped required warm-up fails the canary.
- Store warm-up reports under `warmupRuns` with their own probe summaries and
  wall-clock values. Do not mix them into points, min/max score, or measured
  `probeSummaries`.
- Print warm-up and measured runs with unambiguous labels.

## Acceptance Criteria

- Zero warm-ups preserve the existing artifact shape apart from an explicit
  count field.
- Warm-up runs are retained but excluded from measured repeat summaries.
- Invalid warm-up counts fail environment parsing.
- Warm-up probe failures cannot be hidden by successful measured runs.
- One warm-up plus three measured runs preserve 170/48/52 catalog parity and
  80/80 measured scores.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/run_live_llm_benchmark_canary_test.dart \
  --test test/tool/live_llm_benchmark_app_tool_profile_test.dart
```

Live verification uses the managed loopback wrapper, the explicit six-server
MCP config, and `qwen3.6-27b-vision`.

## Handoff Notes

- Summary: the benchmark now supports explicit validated warm-up repetitions,
  stores their raw reports and probe summaries separately, and excludes them
  from measured points and latency distributions. The default remains zero
  warm-ups.
- Tests run: `tool/codex_verify.sh --no-codegen --test
  test/tool/run_live_llm_benchmark_canary_test.dart --test
  test/tool/live_llm_benchmark_app_tool_profile_test.dart` passed project and
  package analysis, package tests, 16 focused tests, and 10 notification-relay
  tests.
- Live evidence: one discarded warm-up and three measured
  `qwen3.6-27b-vision` runs all preserved the exact
  170-total/48-initial/52-remote/six-server catalog and scored 80/80. The
  initial-selection warm-up took 11,348 ms; measured runs took 1,030, 970, and
  957 ms, for a 970 ms median and 73 ms spread. Tool search took 1,781 ms in
  warm-up and 1,752, 1,716, and 1,762 ms when measured, for a 1,752 ms median
  and 46 ms spread. Prompt/completion usage was invariant at 8,974/15 tokens
  for initial selection and 8,977/35 for tool search. Artifact directory
  suffix: `ll39_host_app_catalog_prewarmed_1786687480`.
- Risks or follow-ups: the reset-controlled follow-up in
  `docs/ll39_cold_path_ab_codex_task.md` found that an unrelated tool-free
  completion reduced the cold median by only 3.2%, while an identical
  diagnostic warm-up reduced it by 90.23%. This supports exact request-prefix
  and tool-schema reuse as the dominant factor, without identifying the
  router or model server's internal cache implementation.
