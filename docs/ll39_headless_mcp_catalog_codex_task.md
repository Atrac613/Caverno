# LL39 Headless MCP Catalog Configuration

## Task

- Goal: reproduce an app-sized remote MCP tool catalog in the headless LL39
  benchmark without reading personal application settings.
- User-visible behavior: an explicitly configured canary connects to trusted
  HTTP and stdio MCP servers before measuring the initial tool selection.
- Non-goals: importing the full Caverno settings file, persisting MCP servers,
  changing trust decisions, or embedding credentials in benchmark artifacts.

## Context

- Affected components: the LL39 benchmark runner, benchmark canary environment,
  managed loopback wrapper, MCP configuration parsing, and focused runner tests.
- Related docs: `docs/live_llm_canary_agent_runbook.md` and
  `docs/f6_initial_tool_budget_followup_codex_task.md`.
- Reference pattern: `McpServerConfig.fromJson` and the explicit
  `McpToolService.connect(overrideServers: ...)` test seam.
- Known quirks: the current canary hard-codes an empty MCP server list, and MCP
  configs may contain sensitive stdio environment values.

## Implementation Notes

- Add `CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH` as an optional explicit input.
- Accept either a JSON list of MCP servers or an object containing
  `mcpServers`.
- Require every supplied server to be enabled, valid, and trusted. Reject HTTP
  URLs containing user info, query parameters, or fragments because connection
  identifiers are retained as diagnostic evidence.
- Connect once before repeated benchmark runs and reuse the populated tool
  service.
- Relay each configured HTTP MCP endpoint through an independently allocated
  IPv4 loopback port when the managed live wrapper is used. Keep stdio server
  definitions unchanged and remove the rewritten config during cleanup.
- Record server/tool counts and sanitized connection labels through the existing
  report only; never copy the source config or stdio environment values.

## Similar-Pattern Search

- Search terms: `McpServerConfig.fromJson`, `overrideServers`,
  `CAVERNO_BENCHMARK_CANARY`, `enabledMcpServers`, and `mcpConnectionSummary`.
- Files inspected: benchmark canary, runner shell script, remote MCP connection
  manager, CLI tool-catalog snapshot, and external config documentation.
- Follow-up tasks found: override-created stdio clients rely on process teardown
  for cleanup because the connection manager has no public disconnect method;
  lifecycle ownership should be handled separately before supporting long-lived
  repeated stdio canaries.

## Acceptance Criteria

- No MCP config keeps the existing built-in-only behavior.
- A valid explicit config populates `settings.enabledMcpServers`, connects before
  probing, and preserves remote server/tool counts in the artifact.
- Invalid JSON, invalid server records, untrusted entries, and credential-like
  HTTP URLs fail before model requests.
- The runner forwards only the config path, not config contents.
- The managed wrapper rewrites HTTP endpoints without fixed ports, does not log
  stdio environment values, and cleans up every relay and temporary config.
- Focused tests cover list/object forms and all rejection paths.
- A six-server live run directly measures the post-F6 initial tool count.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/live_llm_benchmark_mcp_config_test.dart \
  --test test/tool/run_live_llm_benchmark_canary_test.dart \
  --test test/tool/live_llm_loopback_relay_test.dart
```

Live verification pins `initial_harness_selection` and `tool_search_catalog`
against `qwen3.6-27b-vision`, then restores the previously loaded model.

## Handoff Notes

- Summary: the headless benchmark now accepts an explicit trusted MCP config,
  relays every HTTP endpoint through a managed dynamic IPv4 loopback port, and
  preserves configured clients across diagnostic reconnects. The six-server
  live run connected all servers and discovered the expected 52 remote tools.
- Tests run: `tool/codex_verify.sh --no-codegen --test
  test/tool/live_llm_benchmark_mcp_config_test.dart --test
  test/tool/run_live_llm_benchmark_canary_test.dart --test
  test/tool/live_llm_loopback_relay_test.dart` passed project/package analysis,
  package tests, 27 focused tests, and notification-relay checks. After the
  live-only client lifecycle correction, focused analysis and the same 27 tests
  passed again.
- Live evidence: `qwen3.6-27b-vision` passed both required probes for 80/80
  points. The remote-enabled headless catalog measured 97 total, 32 initial,
  and 52 remote tools across six servers; `initial_harness_selection` used
  6,667 prompt tokens. Compared with the built-in-only headless run, this is
  45 to 97 total tools, 22 to 32 initial tools, and 5,260 to 6,667 prompt
  tokens. Artifact directory suffix: `ll39_six_server_post_f6_1786686226`.
- Coverage or low-coverage notes: parser rejection paths, dynamic relay port
  allocation, HTTP byte forwarding, stdio preservation, secret-free output,
  temporary-config cleanup, configured-client lifetime, and live six-server
  discovery are covered.
- Risks or follow-ups: this canary reproduces the full remote catalog but not
  the 73 app-service-dependent built-ins omitted by the headless tool service.
  The follow-up app-profile harness now covers that gap without activating
  hardware or UI services; see
  `docs/ll39_host_app_catalog_parity_codex_task.md` for the direct 170-tool
  evidence.
