# F5 Remote MCP Exposure Probe Extraction

## Task

- Goal: isolate the snapshot-only remote MCP exposure diagnostic.
- User-visible behavior: preserve skipped/warning/passed statuses, summaries,
  connection details, first-twelve tool-name preview and empty-line filtering.
- Non-goals: change trust, connect to servers, execute tools, call a model,
  release or resume RC1 signed-device verification.

## Context And Implementation Plan

Baseline: local main `a69adaf69`; diagnostic service 2,335 lines.
Extract `LiveLlmRemoteMcpExposureProbe` over the existing domain catalog value.
Keep catalog acquisition, settings/provider selection, elapsed time and report
publication in the service. Preserve the asynchronous service method contract.
No transport imports, generated entities or dependency changes are needed.

## Tasks And Acceptance

1. Verify the existing service path before extraction, including no completion.
2. Move only snapshot scoring, preserving server-count precedence and output.
3. Directly cover all statuses, summary counts independent of tool-name list,
   empty/whitespace summaries and bounded tool-name preview.
4. Lower service size budget, budget the module, and run focused coverage,
   analysis and dependency/size gates.
5. Inspect the diff, update both roadmap indexes and the boundary plan, record
   evidence and commit task files locally.

## Similar-Pattern Search

Use the existing domain catalog and diagnostic probe conventions. Remote MCP
catalog acquisition and tool-search execution remain separate responsibilities.

## Verification

All five tasks are complete. The quiet-wrapper baseline passed five service
contracts before extraction (`--name 'remote MCP exposure'`).

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_remote_mcp_exposure_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_initial_harness_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_subagent_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 610 focused tests passed across seven suites, including twelve isolated
  snapshot tests and the five pre-extraction service contracts.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Module: 12/12 executable lines covered (100%). Service: 625/704 (88.78%)
  in this focused run; this is not full-suite coverage.
- Service: 2,335 -> 2,311 lines. Module: 37 lines; both budgets verified.
- Normalized scoring matches the original after catalog and ID substitutions.
  Service fixtures prove publication, settings/catalog behavior, connection
  failure details, zero model requests and zero tool executions.
- Formatting, diff whitespace and local documentation links checked. No
  generated entity or dependency changed; build_runner was unnecessary.
- No full Flutter-suite, live-model, signed-device, release or push run.
  The pre-existing `macos/Podfile.lock` change remains outside this task.

## Follow-Up

F5 remains `current`; RC1 stays on hold. Next: scope narrow datetime-tool
selection scoring, retaining availability, tool definitions, request settings
and report ownership in the service. Keep tool-search execution separate.
