# LL39 Cold-Path A/B Isolation

## Task

- Goal: distinguish generic model/router cold-start cost from exact prompt and
  tool-catalog prefix reuse in the LL39 initial harness probe.
- User-visible behavior: the benchmark can select either an unrelated short
  completion or the selected diagnostic probes as its discarded warm-up.
- Non-goals: changing production chat behavior, changing diagnostic prompts,
  claiming a cache mechanism without server timing evidence, or leaving the
  configured model unloaded after the experiment.

## Context

- Affected components: benchmark warm-up orchestration, environment parsing,
  artifacts, runner forwarding, focused tests, and live evidence.
- Related docs: `docs/ll39_host_app_prewarm_codex_task.md` and
  `docs/ll39_host_app_latency_repeat_codex_task.md`.
- Reference pattern: the existing validated diagnostic warm-up and the LL22
  distinction between unrelated and prefix-identical warm-up requests.
- Known quirk: sequential arms are not independent because the router retains
  loaded model and prompt state. Every arm must begin after a confirmed
  unload/load cycle, and the original loaded model state must be restored.

## Experiment Arms

1. `none`: run the initial harness probe without a canary warm-up.
2. `unrelatedCompletion`: discard a short completion with no tools, then run
   the initial harness probe.
3. `diagnostic`: discard the initial harness probe itself, then measure it.

Run three blocks. Within each block, reset the model before every arm and keep
the model, endpoint, temperature, MCP catalog, probe prompt, and output limit
fixed. Record the arm order and every raw artifact.

## Implementation Notes

- Add `CAVERNO_BENCHMARK_CANARY_WARMUP_MODE` with `diagnostic` as the default
  for backward compatibility and `unrelatedCompletion` as the second value.
- The unrelated completion must expose no tools and use a fixed minimal prompt.
- Validate its exact marker response before accepting measured results.
- Preserve warm-up mode, elapsed time, finish reason, and usage separately from
  measured score and probe summaries.
- Keep diagnostic warm-up artifacts compatible with the existing report export.
- The live lifecycle step must confirm `unloaded`, confirm `loaded`, and restore
  `qwen3.6-27b-vision` to loaded on every exit path.

## Acceptance Criteria

- An omitted mode preserves current diagnostic warm-up behavior.
- Invalid modes fail before any LLM request.
- Unrelated warm-ups cannot access the tool catalog and cannot silently fail.
- Warm-up observations never enter measured points or probe distributions.
- All live arms preserve the exact 170-total/48-initial/52-remote/six-server
  catalog and pass the initial harness probe.
- Evidence distinguishes generic cold-start removal from exact-prefix reuse,
  or states that the sample is inconclusive.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/run_live_llm_benchmark_canary_test.dart \
  --test test/tool/live_llm_benchmark_warmup_test.dart \
  --test test/tool/live_llm_benchmark_app_tool_profile_test.dart
```

Live verification uses the managed loopback wrapper, the explicit six-server
MCP config, and the router lifecycle API for `qwen3.6-27b-vision`.

## Handoff Notes

- Summary: the canary supports a validated tool-free
  `unrelatedCompletion` warm-up in addition to the existing diagnostic warm-up.
  `tool/run_live_llm_cold_path_ab.sh` rotates the three arms across blocks,
  resets the target model before each arm, and restores a successfully
  preflighted loaded target on exit.
- Tests run: `tool/codex_verify.sh --no-codegen` with the four focused LL39 A/B
  test files passed project and package analysis, package tests, 23 focused
  tests, and 10 notification-relay tests. The preflight-state safety repair also
  passed `bash -n` and four focused runner tests.
- Live evidence: an initial preflight stopped at zero arms while another 35B
  workload was active. After the endpoint owner restored 27B, all nine
  reset-controlled arms passed with the exact
  170-total/48-initial/52-remote/six-server catalog, 45/45 points, and invariant
  8,974/15 prompt/completion usage.
  The no-warm-up probe measured 8,791/8,708/8,603 ms (8,708 ms median). The
  unrelated-completion arm measured 8,671/8,429/8,382 ms (8,429 ms median),
  only 279 ms or 3.2% below cold. The identical diagnostic arm measured
  817/878/851 ms (851 ms median), 7,857 ms or 90.23% below cold.
  Machine-readable evidence is in
  `docs/evidence/ll39_cold_path_ab_2026-08-14.json`.
- Risks or follow-ups: the controlled result supports exact request-prefix and
  tool-schema reuse as the dominant source of the first-run difference. It
  does not identify whether reuse occurs in the router, llama.cpp prompt cache,
  or another internal layer because the OpenAI-compatible response does not
  expose server prompt-timing fields. The run restored
  `qwen3.6-27b-vision` to loaded and left `qwen3.6-35b-a3b-vision` unloaded.
