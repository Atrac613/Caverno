# F5 Multi-Round Diagnostic Probe Extraction

## Task

- Goal: move multi-round measurement from `live_llm_diagnostic_service.dart`
  to `live_llm_multi_round_probe.dart` behind completion and tool-execution ports.
- User-visible behavior: preserve search discovery, sequential datetime use,
  final JSON scoring, physical metrics, usage and report publication.
- Non-goals: changing production tool loops, tool approvals, transport formats,
  suite points, release gates or RC1 device verification.

## Context

- Base: local main `2ee77ddb2`, after integrating the tool-depth extraction.
- Branch: `feature/f5-multi-round-probe`.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- Existing service regressions cover wrong/missing calls, batched searches and
  final marker loss. Unlike scripted depth/recovery, this probe executes local
  search and datetime tools; name checks must precede execution.

## Implementation Notes

- Extract only `_measureMultiRoundToolLoop` and its outcome, about 240 lines.
- Keep catalog lookup, selected-probe/provider skips, initial messages, request
  settings, thinking observation, exception-to-report handling and publication
  in the service. Bind tool execution to the existing MCP service.
- Execute every allowed first-turn search in order, union discovered names,
  allow only datetime calls on the second turn, and execute only its first call.
  Final requests have an empty tool catalog; extra final calls warn without
  execution. Preserve fallback IDs, counters, previews and check denominators.
- Unexpected completion/execution/decoding exceptions still reach the service
  catch boundary and produce a failed result without partial metrics.
- No generated files, dependency or persisted-data changes are needed.

## Similar-Pattern Search

- Search: `_measureMultiRoundToolLoop`, `_singleTool`, `toolCallsFrom`,
  `discoveredToolNamesFromResults`, and multi-round service fixtures.
- Compared recovery/depth/vision completion ports and publication boundaries.
- Further decomposition requires a fresh inventory after this family is moved.

## Acceptance Criteria

- Preserve requests, execution order, tool-name checks and batched discovery.
- Preserve absent-tool skips, wrong/missing calls, execution failure results,
  missing discovery, copied marker/date/timezone and extra-final-call scoring.
- Preserve all physical counters, completed-response usage and observed names.
- Retain publication exception propagation and service error handling.
- Lower the service ratchet and budget the module at final size.
- Rollback: restore measurement and private outcome from main, remove the
  module/binding and restore the service budget; retain contract tests.

## Verification

Run service tests matching `multi-round` before extraction, then:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_multi_round_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Check affected `live_llm` size ratchets separately. Use fake completion/execution
ports for isolated tests; service tests use local search/datetime without remote
servers. Live models, the full Flutter suite and devices remain unverified.

## Handoff Notes

F5 remains `current` and RC1 stays on hold. Final implementation evidence is
recorded below.

## Implementation Evidence

- Service: 3,425 → 3,203 lines. New module: 284 lines. Both sizes are ratcheted.
- Eleven service multi-round tests passed before extraction, including six new
  request-binding, skip, request-error and publication-error contracts.
- The isolated suite adds 31 tests for absent ports/tools, safe name checks,
  batched discovery, execution order, repeated datetime calls, execution errors,
  fallback IDs, final field/extra-call scoring, physical counters, usage,
  textual bridge calls, previews and unexpected exception propagation.
- The coverage gate above completed successfully: Flutter and all workspace
  package analyses, 147 tests in six focused suites, package coverage suites and
  notification relay checks passed.
- Six affected size checks passed with `--plain-name live_llm` using
  `build/test_reports/f5_multi_round_sizes`.
- New module: 107/107 executable lines covered (100%). Diagnostic service:
  947/1,065 (88.92%). Reports/coverage remain local ignored artifacts.
- Formatting, diff whitespace and local documentation references checked. No
  generated entities, dependency locks or production tool policies changed.
- No full Flutter-suite, live-model or signed-device verification was performed.
  The next F5 step is a fresh boundary inventory/coverage ranking.
