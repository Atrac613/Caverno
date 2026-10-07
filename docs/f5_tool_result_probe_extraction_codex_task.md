# F5 Tool-Result Diagnostic Probe Extraction

## Task

- Goal: isolate datetime tool-result integration measurement.
- User-visible behavior: preserve prompts, permitted execution, final-answer
  scoring, previews, usage and diagnostic status.
- Non-goals: production tool loops, capability weights, transport, release
  gates or RC1 device verification.

## Context

- Base: `1bd7f4cfe`, the locally committed edit-format extraction.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- This bounded family makes one completion, executes the first datetime call,
  and makes one final-answer completion with an empty tool catalog.

## Implementation Notes

- Move measurement into `LiveLlmToolResultProbe` behind completion, follow-up,
  execution and message ports.
- Keep catalog availability, selected-probe policy, model/temperature/512-token
  settings, thinking observation, exceptions, elapsed time and publication in
  the service.
- Execute only the first `get_current_datetime` call. Do not execute initial
  unsolicited tools or any follow-up calls; warn on follow-up tool requests.
- Preserve call IDs and the empty-ID fallback, arguments and raw tool results.
- Preserve marker substring/JSON acceptance and optional missing date/timezone
  fields. Invalid field types still propagate to generic service error handling.
- Final results retain only follow-up usage; early failures retain initial
  usage. This extraction does not change accounting semantics.
- No generated entities, dependencies or persisted formats change.

## Acceptance Criteria

- Preserve prompt bytes, request bindings and report lifecycle.
- Cover tool selection, execution errors, envelope identity, missing fields,
  final-answer mismatches, unexpected calls, empty answers and request errors.
- Lower the service budget and add a module budget.
- Rollback: restore the measurement and marker from `1bd7f4cfe`, remove the
  module/binding and restore the service budget; retain contract tests.

## Verification

Seven service contracts passed before extraction, including four new request,
publication, unavailable-catalog and per-request error contracts:

```bash
CAVERNO_TEST_REPORT_DIR=build/test_reports/f5_tool_result_baseline \
  tool/flutter_test_quiet.sh \
  test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --name 'tool-result'
```

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_tool_result_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run affected `live_llm` size checks separately. Logs and coverage remain ignored.

## Implementation Evidence

- Service: 2,583 -> 2,503 lines. Independent module: 142 lines.
- Normalized measurement matches the committed original after explicit
  completion/message/execution port substitutions.
- Twenty-one independent tests cover request envelopes, allowed execution,
  usage paths, optional/invalid fields, scoring and propagated failures.
- The focused gate passed 163 tests across six suites, clean root/package
  analysis, internal-package tests and notification relay checks.
- Module: 55/55 executable lines covered (100%). Service: 661/763 (86.63%)
  in this focused run; this is not whole-suite coverage.
- Twelve affected size checks passed. Formatting, diff whitespace and changed
  documentation references checked.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. Edit-format is locally committed as
`1bd7f4cfe`. This tool-result slice remains uncommitted. No main integration,
push, full Flutter-suite, live-model or signed-device result is claimed.
