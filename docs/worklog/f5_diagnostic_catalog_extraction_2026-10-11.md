# F5 Diagnostic Catalog Extraction

## Task And Acceptance

Extract the pure diagnostic catalog transformation from acquired definitions.
Preserve raw definition identity/order/count, initial selection and selected
names, remote marker interpretation, duplicate/malformed-name handling and
connection summary. Keep MCP connection, definition acquisition, state summaries
and provider-capability probe filtering in the service. Run pre-extraction
service contracts, isolated boundary tests, focused analysis/coverage and
size/package/layer gates; update both roadmap indexes and commit locally.

## Context And Plan

Baseline: local main `f04cfaeb6`; diagnostic service 2,187 lines. Catalog
construction calls the existing `ToolDefinitionSearchService` and adds report
metadata; it does not filter definitions by provider capabilities. Upstream
MCP acquisition owns definition availability and later probe orchestration
owns capability skips. No new acquisition/execution port is needed. Empty
catalogs retain the existing disabled/unavailable summaries. Similar-pattern
search inspected shared initial-selection policy and remote exposure scoring.

## Verification

Eight pre-extraction service contracts passed. They assert connection before
acquisition, continued acquisition after connection failure, no model requests,
raw duplicate/missing-name counts, initial deduplication, publication, summaries
and identical snapshots for OpenAI-compatible and Foundation Models providers.
Nine isolated context tests cover empty/availability snapshots, configured
server evidence, definition identity/order, duplicates, missing names, strict
boolean remote markers, the 24/25 threshold and search/browser selection.
The browser fixture expectation was corrected to preserve deferred browser
exposure; the existing selection policy was not changed. The new fixture lint
was resolved before rerunning the final gate.

Initial selection and raw/remote name projection match the original after
helper rename and formatting. MCP state summary is acquired before the pure
projection; the projection performs no IO and reuses the unchanged shared
selection policy. Empty catalog construction retains all observable values.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_diagnostic_catalog_context_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/chat/domain/services/tool_definition_search_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 623 focused tests passed across six suites, including nine isolated context
  tests and eight pre-extraction service contracts.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Context: 27/27 executable lines covered (100%). Service: 582/651 (89.40%) in
  this focused run; this is not full-suite coverage.
- Service: 2,187 -> 2,122 physical lines. Context: 77 lines. Both budgets pass.
- Formatting, diff whitespace and new documentation references checked.
- No new domain-to-data dependency, reviewed-edge allowance, generated entity,
  dependency or tool execution/acquisition port.

## Follow-Up

Refresh cross-file size/churn/coverage ranking and identify a bounded
high-churn ChatNotifier concern with an explicit contract. The diagnostic
service's remaining request/report orchestration, video HTTP client lifecycle,
tool-search execution and sampler orchestration retain their owners.
F5 remains `current`; RC1 signed-device verification stays on hold.
No full Flutter suite, live-model, signed-device, release or push run.
The pre-existing `macos/Podfile.lock` change remains outside this task.
