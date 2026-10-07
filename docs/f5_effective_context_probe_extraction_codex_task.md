# F5 Effective-Context Diagnostic Probe Extraction

## Task

- Goal: isolate effective-context ladder measurement behind completion,
  message-building and advertised-context ports.
- User-visible behavior: preserve opt-in, ladder limits, boundary-marker
  scoring, first-failure stopping, usage, previews, metrics and publication.
- Non-goals: changing prompts, model capability scoring, transport, approvals,
  production context handling or RC1 signed-device verification.

## Context

- Base: `3517ce46e`, with the multi-round extraction already integrated.
- Current inventory (2026-10-08): non-generated primary Dart files include
  ChatNotifier (7,935 lines / 60 commits since 2026-09-08), Remote Coding server
  (3,261 / 17), diagnostic service (3,203 / 26), Remote Coding page
  (2,671 / 14) and workflow coordinator (2,375 / 0).
- The diagnostic service has a size budget and an existing context-trial
  injection point. Its bounded 216-line context family is selected over a
  broader ChatNotifier extraction. RC1 device evidence remains on hold.
- Related docs: [boundary plan](large_file_refactor_plan.md),
  [roadmap](roadmap.md). Reference: depth and multi-round completion ports.

## Implementation Notes

- Move measurement, prompt construction, targets, failure classification and
  result construction into `live_llm_effective_context_probe.dart`.
- Keep selected-probe/provider/opt-in checks, request settings, thinking
  observation, metadata HTTP handling and running/terminal publication in the
  service. Preserve the public `RunEffectiveContextTrial` typedef and override.
- Read advertised context after trials, as before. Per-trial errors become
  evidence; publication and unexpected metadata-port errors propagate.
- Keep 2,048-token initial targets, doubling to the exact requested maximum,
  the 1,048,576-token cap, 32 response tokens, visible-content exact recall and
  positive prompt-usage requirements.
- No generated entities, dependencies or persisted data change.

## Similar-Pattern Search

- Inspected depth/multi-round modules, thinking-observed chat calls,
  effective-context metrics and service tests.
- Streaming and embeddings remain separate future boundaries. No other probe
  is moved in this slice.

## Acceptance Criteria

- Preserve prompt bytes, request bindings and report contents.
- Preserve first-failure stop, usage from completed responses, immutable trials,
  response/error preview limits, and failed/warning/passed outcomes.
- Cover small and non-power-of-two maxima, clamping, unsupported/unselected
  skips, missing usage, reasoning/whitespace normalization and publication
  exception propagation with disposable fake ports.
- Lower the service size ratchet and add a module ratchet.
- Rollback: restore the original measurement/helpers and service budget,
  remove the new module/binding, and retain service contract tests.

## Verification

Baseline:

```bash
tool/flutter_test_quiet.sh --coverage \
  test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --plain-name context
```

Focused gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_effective_context_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run `file_size_ratchet_test.dart --plain-name live_llm` separately. SDK cache
initialization required filesystem escalation; the equivalent pinned-SDK
commands were then run. Coverage artifacts and reporter logs remain ignored.

## Implementation Evidence

- Service: 3,203 -> 3,055 lines. Independent module: 206 lines.
- Seven existing context tests passed before extraction. That context-only run
  covered 228/1,040 executable service lines; this is not whole-service coverage.
- The isolated module suite adds 18 tests. Five service contracts cover
  request settings, thinking observation, skips, clamping and publication errors.
- The focused coverage gate passed 139 tests in six suites, clean root/package
  analysis, internal-package tests and notification relay checks.
- Module: 90/90 executable lines covered (100%). Service: 871/983 (88.61%) in
  this focused run; it is not a full-suite coverage measurement.
- Seven affected `live_llm` file-size checks passed, including both new budgets.
- Normalized ladder/prompt/failure-classification helpers match the original.
  Formatting, diff whitespace and local documentation references checked.
- No full Flutter-suite, live-model or signed-device run is part of this slice.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. Integration and commits are separate
from this worktree implementation.
