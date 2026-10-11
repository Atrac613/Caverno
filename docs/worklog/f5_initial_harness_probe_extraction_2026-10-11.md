# F5 Initial Harness Selection Probe Extraction

## Task

- Goal: isolate initial tool-selection scoring as the next bounded F5 slice.
- User-visible behavior: preserve the exact request and existing outcomes,
  including datetime selection taking precedence over tool-search calls.
- Non-goals: execute returned tools, change the catalog or scoring policy,
  alter tool-search execution, release or resume RC1 device verification.

## Context And Implementation Plan

Baseline: local main `6374a895c`, following subagent recognition extraction.
The service has 2,355 lines. Move the initial-harness prompt and scoring to
`LiveLlmInitialHarnessProbe` behind a domain-only completion port. Retain
availability, tool selection, transport reply parsing, diagnostic usage
adaptation, request settings, thinking observation, exception handling,
elapsed time and publication in the service. No generated entities change.

## Tasks And Acceptance

1. Preserve scoring and prompt bytes while extracting the bounded concern.
2. Cover datetime/search/other/no calls, mixed and repeated calls, catalog
   details, evidence bounds and port failures directly.
3. Verify service request settings, selected tools, publication, observation,
   disabled catalog, embedded call parsing and error handling.
4. Lower the service size budget, budget the module, and run focused coverage,
   static analysis and package/layer boundary checks.
5. Inspect the result, refresh both roadmap indexes and the boundary plan,
   record verified evidence and commit task files locally.

## Similar-Pattern Search

Use the subagent domain reply adapter and existing diagnostic evidence helpers.
Keep tool-search execution as a separate responsibility.

## Verification

All five tasks are complete. Baseline: four service contracts passed before
extraction using the quiet wrapper with `--name 'initial harness'`.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_initial_harness_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_subagent_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_goal_update_fidelity_probe_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 614 focused tests passed across seven suites, including 15 isolated probe
  tests and the four pre-extraction service contracts.
- Root/package static analysis, 125 internal-package tests, notification relay
  source checks, size budgets and package/layer import checks passed.
- Module: 13/13 executable lines covered (100%). Service: 623/714 (87.25%)
  in this focused run; this is not whole-suite coverage.
- Service: 2,355 -> 2,335 lines. Module: 59 lines.
- Normalized scoring matches the original after explicit reply/catalog port
  substitutions. Request prompt/settings/catalog, native and embedded calls,
  observation, publication, disabled tools and request failure are verified.
- Formatting, diff whitespace and local documentation links checked. No new
  reviewed-edge exception, generated entity, dependency or execution port.
- No full Flutter-suite, live-model, signed-device, release or push run.
  The pre-existing `macos/Podfile.lock` change remains outside this task.

## Follow-Up

F5 remains `current`; RC1 stays on hold. Next: scope snapshot-only remote-MCP
exposure scoring, retaining connection/catalog loading in the service and
keeping tool-search execution separate.
