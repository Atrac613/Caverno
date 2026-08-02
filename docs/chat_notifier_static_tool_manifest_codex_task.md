# ChatNotifier Static Tool Manifest Validation

## Task

- Goal: Implement the finite `--check-tool-manifest` contract required by the
  ChatNotifier inventory investigation.
- User-visible behavior: Maintainers can re-run one command to prove that every
  statically discoverable tool definition and execution binding is represented
  by the checked-in manifest.
- Non-goals: Change tool exposure, dispatch behavior, dynamic MCP schemas, or
  runtime catalogue measurements.

## Context

- Affected files or components:
  `tool/analyze_chat_notifier_inventory.py`, its Python tests, and the new
  `tool/chat_notifier_tool_catalog_inventory.json` manifest.
- Related docs: `docs/chat_notifier_inventory_codex_task.md` and
  `docs/large_file_refactor_plan.md`.
- Reference implementation or pattern: The existing guard-manifest discovery
  and exact-schema validation in `tool/analyze_chat_notifier_inventory.py`.
- Known quirks, compatibility rules, or release gates: Static definitions are
  assembled by `McpToolService`, while specialized handlers, Computer Use,
  Browser, and generic MCP fallback are dispatched through separate paths.
  Dynamic MCP tool names must remain private snapshot data.

## Implementation Notes

- Preferred approach: Keep definition producers and binding sources in finite,
  checked discovery rules. Re-run those rules, validate an exact manifest
  schema, and reject missing, duplicate, stale, or invalid rows.
- Constraints: Preserve production behavior. Record platform and configuration
  gates as reviewed manifest metadata. Model dynamic MCP execution as one
  generic fallback binding without recording endpoint-provided names.
- Generated files needed: None.
- Migration or data compatibility concerns: The new manifest is schema version
  1 and is consumed only by the inventory analyser.

## Similar-Pattern Search

- Search terms: `getOpenAiToolDefinitions`, `ChatToolHandlerRegistry`,
  `isComputerUseTool`, `isBrowserTool`, and `executeFallbackTool`.
- Files or modules inspected: Static tool definition producers under
  `lib/features/chat/data/datasources`, the ChatNotifier handler registry,
  Computer Use and Browser policies, and `ChatToolDispatcher`.
- Follow-up tasks found: Use the validated manifest with private catalogue
  snapshots during the later catalogue-residency measurement slice.

## Acceptance Criteria

- Required behavior: `--check-tool-manifest` succeeds for the checked-in
  manifest and prints deterministic definition and binding counts.
- Edge cases: Definitions with zero observed calls, platform-gated tools,
  registry loop literals, intercepted tool families, and generic fallback are
  all represented.
- Failure paths: Validation fails for source drift, missing or stale discovery
  rows, duplicate names, unknown bindings, invalid gates, or malformed schema.
- Accessibility, localization, or platform expectations: Not applicable; this
  is repository tooling only.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --check-tool-manifest tool/chat_notifier_tool_catalog_inventory.json
tool/codex_verify.sh
git diff --check
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Focus tests must cover manifest success and
  representative drift failures for every discovery category.
- Risks or follow-ups: Lexical discovery is intentionally bounded to reviewed
  production source files; new definition producers require an explicit rule
  update rather than an open-ended repository scan.
