# Chat Tool Catalogue Snapshot: Codex Task

## Task

- Goal: Add a read-only capture path for the complete effective chat tool
  catalogue so Phase 0B inventory measurements can pin configuration-specific
  snapshots to clean build provenance.
- User-visible behavior: `caverno catalogue snapshot --output <path>` connects
  configured MCP servers, exports the definitions exposed by
  `McpToolService.getOpenAiToolDefinitions()`, and exits without sending an LLM
  request or executing a tool.
- Non-goals: Do not change chat tool selection, tool execution, session log
  behavior, corpus analysis, or Phase 1 architecture.

## Context

- Affected files or components: terminal CLI argument parsing and bootstrap,
  `McpToolService`, a focused snapshot encoder/writer, and their tests.
- Related docs: `docs/chat_notifier_inventory_codex_task.md` and
  `docs/chat_notifier_pinned_corpus_contract_codex_task.md`.
- Reference implementation or pattern: Use the existing terminal bootstrap for
  persisted settings and provider wiring, and use
  `McpToolService.getOpenAiToolDefinitions()` as the single composition source.
- Known quirks, compatibility rules, or release gates: Request-level `tools`
  arrays can be subsets and are not valid full catalogues. Dynamic MCP
  definitions exist only after connection. Build provenance is injected by
  `tool/safe-flutter`.

## Implementation Notes

- Preferred approach: Add a `catalogue snapshot` utility command. Connect the
  configured MCP clients, fail closed if any configured server fails, then
  canonicalize and atomically write a versioned JSON snapshot. Derive a
  non-secret configuration fingerprint from the redacted canonical tool
  definitions rather than serializing endpoint or credential settings.
- Constraints: The command must not issue an LLM request, execute a tool, or
  mutate persisted application state. Snapshot output must exclude configured
  API keys and MCP environment values. The summary printed to stdout must not
  reveal the private output path in JSON mode.
- Generated files needed: None.
- Migration or data compatibility concerns: None. Introduce a versioned schema
  so later corpus readers can reject unsupported formats.

## Similar-Pattern Search

- Search terms: `getOpenAiToolDefinitions`, `mcpToolServiceProvider`,
  `CavernoCliUtilityCommand`, `BuildInfo.toJson`, `CavernoCliRedactor`.
- Files or modules inspected: MCP provider/service, remote connection manager,
  terminal CLI parser/process, build provenance wrapper, and pinned corpus
  contract.
- Follow-up tasks found: Teach the inventory analyser to validate and consume
  the versioned snapshot schema when dynamic measurements are implemented.

## Acceptance Criteria

- Required behavior: The command captures built-in and successfully fetched
  remote definitions from the exact runtime composition method, records clean
  build provenance, exporter revision, capture time, tool count, and a stable
  configuration fingerprint, and writes JSON atomically.
- Edge cases: Reject a missing output path, an unknown build revision, a dirty
  build, duplicate or malformed tool names, and incomplete MCP connection
  results. Refuse to overwrite an existing snapshot unless explicitly allowed.
- Failure paths: Return a non-zero CLI failure without leaving a partial output
  file. Redact configured secrets from definitions and diagnostics.
- Accessibility, localization, or platform expectations: CLI-only English
  output; desktop runtime because configured stdio MCP discovery is
  desktop-only.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/chat_tool_catalogue_snapshot_test.dart
tool/codex_verify.sh --test test/features/terminal/application/caverno_cli_arguments_test.dart
tool/codex_verify.sh
git diff --check
```

Run one clean-provenance capture through `tool/safe-flutter` to a private or
temporary path and validate the emitted JSON without committing it.

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: The exporter proves catalogue completeness only for the
  runtime configuration present during capture; the private corpus manifest
  must still join every log record to the correct snapshot segment.
