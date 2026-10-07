# F5 Exact-Preservation Diagnostic Probe Extraction

## Task

- Goal: isolate the direct-literal, tool-result and URL preservation measurement.
- User-visible behavior: preserve prompts, request order, exact visible-value
  comparisons, raw reasoning previews, usage, labels and three-check scoring.
- Non-goals: request/transport policy, real tool execution, edit-format scoring,
  capability weights, releases or RC1 device verification.

## Context

- Base: `83137f2c4`, the locally committed embeddings scoring extraction.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- The literal-preservation family is smaller than edit-format measurement and
  already has an observed completion path. It uses a synthetic tool-result
  message rather than executing a production tool.

## Implementation Notes

- Move measurement, constants, outcome and detail rendering into
  `LiveLlmExactPreservationProbe` with completion/message/clock ports.
- Service retains selected-probe gating, model/temperature/token settings,
  thinking observation and `_runProbe` error/elapsed/publication handling.
- Keep two independent clock reads for synthetic tool-result ID and timestamp.
  Keep its user-role message, call ID, arguments, raw JSON and description.
- Execute all three requests before scoring. Request exceptions propagate to
  the existing service boundary; no partial usage is published after failure.
- No generated entities, dependencies or persisted formats change.

## Acceptance Criteria

- Preserve the money/unit, product-label and URL prompt bytes and order.
- Cover all eight pass/fail combinations, each request failure, visible versus
  raw reasoning, bounded previews and synthetic tool-result metadata.
- Preserve three checks and completed-response usage; exact matching remains
  independent of finish reason.
- Lower the service budget and add an independent module budget.
- Rollback: restore measurement/helpers/constants/outcome from `83137f2c4`,
  remove the module/binding and restore the service budget; retain contracts.

## Verification

Six service preservation tests passed before extraction, including five new
request/settings/thinking/publication, skip and per-arm failure contracts.

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_exact_preservation_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run affected `live_llm` size checks separately. Logs and coverage remain ignored.

## Implementation Evidence

- Service: 2,877 -> 2,746 lines. Independent module: 157 lines.
- Normalized measurement body matches the committed original after request
  bindings move to the service and clock calls become injectable.
- Fifteen isolated tests cover scoring combinations, request/envelope/clock
  contracts, reasoning/previews and per-request exception propagation.
- The focused gate passed 148 tests across six suites, clean root/package
  analysis, internal-package tests and notification relay checks.
- Module: 49/49 executable lines covered (100%). Service: 749/860 (87.09%) in
  this focused run; this is not whole-suite coverage.
- Ten affected `live_llm` size checks passed, including both changed budgets.
- Formatting, diff whitespace and changed documentation references checked.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. Embeddings scoring is locally committed
as `83137f2c4`. This preservation slice remains uncommitted. No main integration,
push, full Flutter-suite, live-model or signed-device result is claimed.
