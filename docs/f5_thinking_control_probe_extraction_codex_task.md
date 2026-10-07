# F5 Thinking-Control Diagnostic Probe Extraction

## Task

- Goal: isolate thinking-mode response classification.
- User-visible behavior: preserve four classifications, status, reasoning counts,
  finish reasons, usage and metadata.
- Non-goals: request-shape policy, reasoning parser changes, capability scoring,
  production thinking settings, release gates or RC1 device verification.

## Context

- Base: `f1860234c`, the locally committed tool-result extraction.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- This family makes two requests in order, thinking on then off. These requests
  deliberately bypass the fixed-mode thinking observer.

## Implementation Notes

- Move classification and prompt/constants into `LiveLlmThinkingControlProbe`
  behind one mode-aware completion port.
- Keep datasource availability and endpoint eligibility checks in the service,
  along with model/temperature/512-token settings, message construction,
  exceptions, elapsed time and publication.
- Use the existing content reasoning parser. Do not start counting stream-only
  reasoning absent from completion content.
- Preserve controllable, always-on, never-observed and inverted classifications.
  Only controllable passes; the other three warn. This probe awards no checks.
- Preserve the public service metadata key as a forwarding constant.
- No generated entities, dependencies or persisted formats change.

## Acceptance Criteria

- Preserve request order, settings, prompt and thinking-metric isolation.
- Cover all four classifications, details/usage, parser boundaries and both
  request failures. An on-request failure must prevent the off request.
- Retain both unavailable-datasource and ineligible-endpoint skips.
- Lower the service budget and add a module budget.
- Rollback: restore classification/constants from `f1860234c`, remove the module
  and completion binding, and restore the budget; retain contract tests.

## Verification

Nine service contracts passed before extraction, including new binding,
publication, request-failure and inverted-classification contracts:

```bash
CAVERNO_TEST_REPORT_DIR=build/test_reports/f5_thinking_control_baseline \
  tool/flutter_test_quiet.sh \
  test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --name thinking_control
```

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_thinking_control_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run affected `live_llm` size checks separately. Logs and coverage remain ignored.

## Implementation Evidence

- Service: 2,503 -> 2,437 lines. Independent module: 78 lines.
- Normalized classification matches the committed implementation after explicit
  completion-port and constant substitutions.
- Twelve isolated tests cover the classification matrix, detailed counts,
  finish reasons, usage, public constants, parser boundaries and both failures.
- The focused gate passed 158 tests across six suites, clean root/package
  analysis, internal-package tests and notification relay checks.
- Module: 19/19 executable lines covered (100%). Service: 645/747 (86.35%)
  in this focused run; this is not whole-suite coverage.
- Thirteen affected size checks passed, including both changed budgets.
- Formatting, diff whitespace and changed documentation references checked.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. Tool-result is locally committed as
`f1860234c`. This thinking-control slice remains uncommitted. No main integration,
push, full Flutter-suite, live-model or signed-device result is claimed.
