# LL39 Host-App Catalog Parity

## Task

- Goal: reproduce the diagnosed 170-tool host-app catalog in the headless LL39
  benchmark and directly measure the post-F6 initial schema count.
- User-visible behavior: an opt-in benchmark profile exposes the same tool
  definition groups as the enabled macOS app without starting hardware, UI, or
  command operations.
- Non-goals: executing the additional built-in tools, importing personal
  conversations or memories, changing production tool availability, or making
  the app-profile catalog the default for every benchmark.

## Context

- Affected components: the headless LL39 canary environment, a catalog-only
  app-service profile, runner forwarding, and focused profile tests.
- Related docs: `docs/f6_initial_tool_budget_followup_codex_task.md` and
  `docs/ll39_headless_mcp_catalog_codex_task.md`.
- Reference pattern: `mcpToolServiceProvider`, which injects repositories and
  lazily initialized services before `getOpenAiToolDefinitions()` registers
  their schemas.
- Known quirks: the verified six-server headless run has all 52 remote tools
  but only 45 built-ins. Dynamic remote collision suffixes contain the relay
  address, so parity must compare stable groups and counts rather than those
  three generated names.

## Implementation Notes

- Add `CAVERNO_BENCHMARK_CANARY_APP_TOOL_PROFILE=1` as an explicit opt-in.
- Build the profile from empty in-memory repositories and service constructors
  whose external resources are initialized only when a tool executes.
- Enable Browser definitions explicitly, add one inert usable Skill so both
  load and save schemas are present, and configure the SearXNG fallback without
  making a request.
- Own and dispose every created MCP client and disposable service at test
  teardown.
- Fail before model probes unless the app profile plus the six-server config
  produces exactly 170 total, 52 remote, and 48 initial definitions.

## Similar-Pattern Search

- Search terms: `mcpToolServiceProvider`, `isAvailable`,
  `canExposeDefinitions`, `supportsBackgroundProcesses`, and
  `getOpenAiToolDefinitions`.
- Files inspected: all conditional tool registration branches, service
  constructors, repository interfaces, and the original/current tool-name
  snapshots.
- Missing groups: Memory/Skills 4, Process 6, Python 1, SSH 3, BLE 16, Wi-Fi 3,
  LAN 2, Serial 6, Computer Use 20, Browser 14, and SearXNG fallback 1.

## Acceptance Criteria

- The profile is disabled by default and preserves the 45-tool built-in-only
  headless behavior.
- The app profile without remote MCP exposes 118 total and 38 initial tools.
- The same profile with the six-server catalog exposes 170 total, 52 remote,
  and 48 initial tools.
- No additional service performs hardware, UI, network, or process work merely
  to build definitions.
- Every owned resource is disposed after the canary.
- The two focused 27B probes pass against the 48-definition initial catalog.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/live_llm_benchmark_app_tool_profile_test.dart \
  --test test/tool/run_live_llm_benchmark_canary_test.dart \
  --test test/tool/live_llm_loopback_relay_test.dart
```

Live verification uses the existing explicit six-server config and managed
loopback wrapper against `qwen3.6-27b-vision`.

## Handoff Notes

- Summary: added an opt-in app-service profile that reproduces production tool
  definition availability with empty repositories and lazily initialized
  services. The canary fails before model requests unless the configured live
  catalog is exactly 170 total, 48 initial, and 52 remote tools.
- Tests run: `tool/codex_verify.sh --no-codegen --test
  test/tool/live_llm_benchmark_app_tool_profile_test.dart --test
  test/tool/live_llm_benchmark_mcp_config_test.dart --test
  test/tool/run_live_llm_benchmark_canary_test.dart --test
  test/tool/live_llm_loopback_relay_test.dart` passed project/package analysis,
  package tests, 30 focused tests, and notification-relay checks.
- Live evidence: `qwen3.6-27b-vision` passed both required probes for 80/80
  points against 170 total, 48 initial, and 52 remote tools across six servers.
  `initial_harness_selection` selected `get_current_datetime` and used 8,974
  prompt tokens. The original diagnosed catalog used 62 initial definitions and
  11,045 prompt tokens, so F6 directly reduced the initial catalog by 14 tools
  and this measured prompt by 2,071 tokens (18.8%). Artifact directory suffix:
  `ll39_host_app_catalog_post_f6_1786686738`.
- Risks or follow-ups: the profile proves schema selection and live model
  behavior but deliberately does not execute hardware/UI tools. Dynamic remote
  collision suffixes reflect loopback addresses rather than LAN addresses; the
  stable remote definitions, counts, and connection distribution are equal.
  A three-repeat follow-up preserved exact parity and separated the first-run
  initial-selection latency from the two steady-state runs; see
  `docs/ll39_host_app_latency_repeat_codex_task.md`.
