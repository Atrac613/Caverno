# F5 Tool-Recovery Diagnostic Probe Extraction

## Task

- Goal: extract the diagnostic tool-recovery probe and per-case executor from
  `LiveLlmDiagnosticService` behind an independently testable completion port.
- User-visible behavior: preserve every scripted case, score, detail, preview,
  request setting, and report update.
- Non-goals: production recovery or approval policy changes, tool-depth and
  multi-round extraction, live-model runs, or resuming RC1 device verification.

## Context

- Base: local main `2d2a19dfd`, after fast-forward integration of the RC1 hold
  and structured-output extraction commits.
- Branch: `feature/f5-tool-recovery-probe`.
- Related docs: [boundary plan](large_file_refactor_plan.md) and
  [roadmap](roadmap.md).
- Existing service-level recovery tests cover restraint, partial-batch retry,
  forbidden-state handling, call evidence, and the fixed suite denominator.
  Keep those tests and supplement them with isolated module tests.

## Implementation Notes

- Move only recovery orchestration and its private case outcome into
  `live_llm_tool_recovery_probe.dart`; fixtures remain unchanged.
- Bind completion requests in the service through its thinking observer, model,
  temperature 0, and 512-token cap. Keep capability skips, initial messages,
  selection, elapsed time, and report publication with the service.
- Keep the complete case tool catalog on every turn, including the final answer
  turn, so restraint remains measurable.
- Move the unchanged pinned-argument comparison into the existing pure response
  scorer, shared by recovery and depth. Preserve optional arguments, trimmed
  string comparisons, and first-mismatch ordering.
- Preserve first-tool-call-only scoring, user-role scripted observations,
  `steps.length + 2` bounds, error containment, and completed-response usage.
- Inject a clock for observation IDs and timestamps; production uses
  `DateTime.now`. No generated files or data migration are needed.

## Similar-Pattern Search

- Inspected recovery/depth executors and their shared argument matcher.
- Used the existing structured-output and vision completion-port pattern.
- Follow-up: tool-depth and multi-round families remain separate F5 slices.

## Acceptance Criteria

- Four existing cases retain their prompts, tools, scripted results and scores.
- Reject refusal bypass, calls before confirmation, retrying an accepted batch
  item, forbidden state changes, premature answers, extra calls and mismatches.
- Preserve request-error evidence, bounded previews, case-insensitive visible
  final evidence, usage and passed/warning/failed aggregation.
- Provider skips perform no completion request; service requests retain model,
  token cap, system prompt and running-to-terminal report updates.
- Lower the service size budget and budget the extracted module at final size.

## Verification

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_tool_recovery_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

The additional isolated suite is
`test/features/settings/domain/services/live_llm_tool_recovery_probe_unit_test.dart`.
Run it together with the six suites above under the quiet Flutter wrapper with
coverage; check affected `live_llm` size ratchets separately.

## Handoff Notes

Implementation is complete; verification evidence is recorded below. Full
Flutter-suite, live-model and signed-device behavior are outside this slice.
RC1 stays on hold and F5 remains `current`.

## Implementation Evidence

- Diagnostic service: 3,789 → 3,605 lines; extracted recovery module: 211 lines.
  Both final sizes are enforced by ratchets.
- The existing six service-level recovery tests are unchanged. The isolated
  module suite adds 17 tests, and the diagnostic service suite adds two request
  binding/provider selection tests. Case fixtures and the suite denominator
  are unchanged.
- Flutter analysis and all three workspace package analyses passed; notification
  relay source checks passed. The verification gate's package coverage suites
  passed for content protocol, execution runtime, and tool contracts.
- The first gate run found a new integration-test expectation using the inner
  capability skip text instead of the existing selection-layer text. Only the
  expectation changed; the production skip behavior remains unchanged.
- After that correction, all 128 tests in seven focused suites passed via
  `tool/flutter_test_quiet.sh --coverage`; four affected size checks passed via
  `--plain-name live_llm` with a separate report directory.
- New module coverage: 74/74 executable lines (100%). Service coverage:
  1,095/1,238 (88.45%). The shared argument matcher is covered; the response
  scorer's six uncovered lines belong to the pre-existing repetition detector.
- Diff whitespace and local documentation references checked. No full Flutter
  suite, live-model, or signed-device run was performed.
