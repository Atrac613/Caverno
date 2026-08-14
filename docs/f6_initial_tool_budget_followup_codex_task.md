# F6 Initial Tool Budget Follow-up

## Task

- Goal: reduce the default initial tool-schema cost while keeping common entry
  points and the complete catalog reachable through `tool_search`.
- User-visible behavior: large catalogs expose a smaller initial tool set, and
  specialized network operations are discovered on demand.
- Non-goals: changing tool execution, removing tools, changing small-catalog
  behavior, or reducing Coding, Skills, Process, Goal, and primary health tools
  in this slice.

## Context

- Affected components: `BuiltInToolRegistry`,
  `ToolDefinitionSearchService`, its classification guard, and LL39 live
  diagnostic evidence.
- Related docs: F6 in `docs/local_llm_agent_roadmap.md` and
  `docs/ll39_streaming_latency_followup_codex_task.md`.
- Reference pattern: existing intentional deferral for mutating HTTP tools and
  platform-specific tool categories.
- Known quirks: built-in tools must remain explicitly classified, and an exact
  catalog name is not a substitute for proving `tool_search` can rediscover a
  deferred definition.

## Implementation Notes

- Slice 1: retain `ping`, `dns_lookup`, and `http_get` as common network entry
  points; defer 14 specialized network tools by explicit name.
- Slice 2: cover classification, initial selection, and on-demand discovery for
  the deferred network set.
- Slice 3: run focused LL39 initial-harness and tool-search probes against the
  same 27B endpoint and compare initial count and prompt tokens with the
  62-tool, 11,045-token baseline.
- Follow-up only when separately measured: consider Wi-Fi/LAN scan details,
  remote health detail tools, or mode-aware Coding tool residency.

## Similar-Pattern Search

- Search terms: `toolSearchDeferredToolNames`, `shouldLoadInitially`,
  `_forcedInitialNonRegistryToolNames`, `initialToolCount`, and
  `initial_harness_selection`.
- Files inspected: built-in registry metadata, tool-definition search service,
  F6 classification tests, LL39 diagnostic probes, and the tool catalog
  residency inventory.
- Follow-up tasks found: prefix-based remote Wi-Fi/LAN forcing can grow with
  server catalogs, but changing remote-tool policy is outside this first slice.

## Acceptance Criteria

- The diagnosed 170-tool catalog falls from 62 initial tools to at most 48.
- `ping`, `dns_lookup`, `http_get`, `get_current_datetime`, `tool_search`, and
  existing coding/skill/process entry points remain initial-loaded.
- Every newly deferred network tool remains searchable by its capability or
  exact name.
- The F6 exhaustive classification guard remains green.
- Focused LL39 probes still select `get_current_datetime` directly and invoke
  `tool_search` successfully.
- Benchmark scoring and suite version remain unchanged.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/domain/services/tool_definition_search_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart
```

Live verification uses `initial_harness_selection` and `tool_search_catalog`
through the managed loopback wrapper against `qwen3.6-27b-vision`.

## Handoff Notes

- Summary: 14 specialized network tools now defer behind `tool_search`, while
  `ping`, `dns_lookup`, and `http_get` remain initial-loaded. Applying the same
  classification to the diagnosed 62-name initial list yields 48 names.
- Tests run: `tool/codex_verify.sh --no-codegen --test
  test/features/chat/domain/services/tool_definition_search_service_test.dart
  --test
  test/features/settings/domain/services/live_llm_diagnostic_service_test.dart`
  passed analysis, package tests, 48 focused tests, and notification-relay
  checks. The focused 27B live canary passed both required probes for 80/80
  points with main readiness `ready`.
- Coverage or low-coverage notes: classification, retained entry points,
  initial exclusion, exact-name rediscovery for all 14 tools, and F6
  exhaustiveness are covered. The headless live catalog had no configured
  remote MCP servers, so it measured 22 initial tools from 45 total and 5,260
  prompt tokens rather than reproducing the app export's 170-tool catalog.
  Artifact:
  `build/integration_test_reports/f6_initial_tool_budget_live_1786684303/`.
- Host-app parity evidence: the opt-in app-service profile plus the same six
  remote MCP servers reproduced 170 total and 52 remote tools, directly
  measured 48 initial tools, and passed both required probes for 80/80 points.
  `initial_harness_selection` used 8,974 prompt tokens versus the diagnosed
  11,045-token baseline, a 2,071-token (18.8%) reduction. Artifact directory
  suffix: `ll39_host_app_catalog_post_f6_1786686738`.
- Risks or follow-ups: prefix-based remote Wi-Fi/LAN forcing and mode-aware
  Coding residency remain separate follow-ups. The catalog-only profile does
  not execute hardware or UI tools.
