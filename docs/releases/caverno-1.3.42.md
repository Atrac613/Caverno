# Caverno v1.3.42

> Release date: 2026-09-23

## Summary

A release centered on live LLM diagnostics: the diagnostic now pins its own reasoning controls instead of inheriting the composer's, records the thinking mode each probe response actually carried, and the benchmark canary can select its thinking mode so in-app and canary scores stay comparable. Also new: a background process tab in the right sidebar, KC1 environment-exposure scoring with corrected measurement semantics, and a system prompt cleanup that removes dated guidance.

## Changes

### Features

- **Background process tab** — The right sidebar now lists the current conversation's `process_start` jobs (owned and carried) with their output tail and a stop control. Reading goes through a read-only conversation view on `BackgroundProcessTools` so it never adopts a carried job, and the list polls only while the tab is mounted. (`lib/features/chat/`)
- **Pinned diagnostic reasoning controls** — The live LLM diagnostic previously shared the chat datasource, so the composer's thinking and effort decided what it measured. It now builds its datasource with pinned reasoning controls (Qwen3.8 thinking on at medium effort, server default elsewhere) and records the measured mode in the profile. A weightless `thinking_control` probe sends one prompt per mode and classifies whether `enable_thinking` actually reaches the model, surfacing routers that override it.
- **Observed thinking in diagnostics** — The report now counts the reasoning each probe response actually carried and reports it next to the requested value, flagging a mismatch in the JSON and the UI so thinking on/off runs can be compared.
- **Benchmark canary thinking mode** — `CAVERNO_BENCHMARK_CANARY_THINKING=on|off` routes through the same `LiveLlmDiagnosticRequestShape` and is recorded in the artifact, so the canary and the in-app diagnostic measure the same mode. It defaults to off, which is byte-identical to the previous requests, so existing artifacts stay comparable.
- **KC1 environment exposure scoring** — KC1 now scores environment exposure, with corrected measurement semantics and preserved grounding evidence coverage.

### Fixes

- **`update_goal` boolean arguments** — The model was sending `completed` as the string `"True"` because the schema did not require a boolean. The tool is now forced when it is the sole advertised function, and non-boolean arguments are rejected instead of coerced.
- **Production release approval** — Production release approval is now bound to the exact execution.
- **Tool result diagnostic follow-ups** — Clarified the diagnostic follow-up behavior for tool results.

### Documentation

- **Tool contracts** — Documented `find_files` name-and-path matching, excluded directories, result cap and truncation flag, and `ble_write_characteristic` prerequisites, write-type semantics, return value and side-effect caveat.
- **CLAUDE.md rules** — Stated the commit and language rules plainly, removing stacked priority markers and duplicate enforcement blocks.
- **KC1 measurement record** — Recorded the KC1 class 3 paired measurement.

### Refactoring

- **System prompt cleanup** — Removed dated guidance: the Claude-derived "treat tool_search as free" booster was rewritten into the deferred-tools fact, the prompt-construction token budget and goal token/turn countdowns were dropped (both are enforced in code), and the per-request execution snapshot moved below the stable tool guidance so tool-loop requests stop invalidating the prefix cache.

## Version

- `1.3.42+56`