# F5 Tool-Depth Diagnostic Probe Extraction

## Task

- Goal: extract staircase measurement and per-rung execution from
  `live_llm_diagnostic_service.dart` into `live_llm_tool_depth_probe.dart`.
- User-visible behavior: preserve the unscored tool-depth axis, scripted
  observations, failure details, measured depth and report publication.
- Non-goals: changing depth fixtures, approval/recovery policy, multi-round
  diagnostics, suite points/version, live-model runs, or RC1 device evidence.

## Context

- Base: local main `4546ab9f3`, after fast-forward integration of the recovery
  extraction. Branch: `feature/f5-tool-depth-probe`.
- Related docs: [boundary plan](large_file_refactor_plan.md) and
  [roadmap](roadmap.md).
- Reference pattern: completion ports used by the recovery and vision probes.
- The depth probe stops at the first failed rung and returns warning, never
  failed. It contributes zero suite points. Final-answer requests omit tools,
  unlike the recovery probe, which deliberately retains its forbidden tools.

## Implementation Notes

- Move rung execution and measurement into an independent service returning
  both a probe result and typed depth metrics. Expected service reduction:
  approximately 200 lines.
- Keep selection, provider checks, initial-message construction, running and
  terminal report publication, model, temperature 0, 512-token cap and thinking
  observation with the diagnostic service.
- Preserve the start timestamp captured before running publication, so elapsed
  time still includes that callback. Keep publication exceptions outside the
  completion error boundary.
- Preserve first-call-only scoring, pinned-argument comparisons, case-sensitive
  visible final-value matching, previews, usage and observation wording.
- Inject a clock for deterministic IDs/timestamps; production uses DateTime.now.
- No generated files, dependencies or persisted-data migration are needed.

## Similar-Pattern Search

- Search: `_runToolDepthProbe`, `_runToolDepthRung`, `tool_state_staircase`,
  `firstArgumentMismatch`, and completion/publication boundaries.
- Inspected recovery probe, depth fixtures, ladder presentation and service tests.
- Follow-up: scope multi-round execution as a separate slice.

## Acceptance Criteria

- All three rungs and stage depths remain unchanged. A failed shallow rung
  prevents later rungs; successful lower rungs retain their depth.
- Preserve text-instead-of-call, wrong tool, wrong argument, step/final request
  errors and missing visible final-value outcomes.
- Keep tool catalogs on step requests and omit them from final requests.
- Preserve immutable attempted-depth metrics, usage and bounded visible preview.
- Keep skip wording/no requests, running-to-terminal reports and callback errors.
- Lower the service size budget and set a budget for the extracted module.
- Rollback: restore the service methods and private outcome from main, remove
  the module/binding, and restore the service ratchet; retain contract tests.

## Verification

Before extraction, run new service contract tests with the quiet wrapper and
`--plain-name 'tool depth'`. After extraction, use:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_tool_depth_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_tool_depth_ladder_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run affected `live_llm` size checks separately. Full Flutter-suite, live-model,
and signed-device behavior are outside this slice.

## Handoff Notes

F5 remains `current`; RC1 signed-device evidence stays on hold. Implementation
and final verification evidence are recorded below.

## Implementation Evidence

- Service: 3,605 → 3,425 lines. Extracted module: 235 lines. Ratchets enforce
  both final sizes; depth fixtures, ladder version and suite points are unchanged.
- Five service contract tests passed before extraction and again after the move.
  Their initial unsupported-provider expectation was corrected to the existing
  outer selection-layer skip text before extraction; production behavior did
  not change.
- The independent module suite adds 20 tests covering complete/partial/zero
  headroom, immutable metrics, request catalogs and observations, wrong tools
  and arguments, carried values, request errors, usage, previews and clock use.
  First-call-only and final-content-only scoring quirks remain frozen.
- The first gate attempt found two missing brace blocks in new tests. Those
  were corrected, and the final `tool/codex_verify.sh --no-codegen --coverage`
  command above completed successfully with 135 tests in seven focused suites.
  Flutter and workspace package analyses, package coverage tests and relay checks
  also passed.
- Five affected size checks passed with `--plain-name live_llm`, using report
  directory `build/test_reports/f5_depth_sizes`.
- New module coverage: 79/79 executable lines (100%). Service coverage:
  1,036/1,166 (88.85%). Reports and coverage are local ignored artifacts.
- Diff whitespace, formatting and local documentation references checked. No
  full Flutter-suite, live-model or signed-device run was performed.
