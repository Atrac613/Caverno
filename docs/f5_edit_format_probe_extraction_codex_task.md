# F5 Edit-Format Diagnostic Probe Extraction

## Task

- Goal: isolate whole-file, SEARCH/REPLACE and unified-diff measurement.
- User-visible behavior: preserve request order, normalization, exact mismatch
  diagnostics, three-check scoring and the selected edit-format preference.
- Non-goals: production edit parsing, prompts/capability weights, transport,
  new normalization rules, release gates or RC1 device verification.

## Context

- Base: `1624ef4fe`, the locally committed exact-preservation extraction.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- This remaining family is bounded by three observed completion requests.
  Shared response-scoring helpers already own fences, mismatch details and
  unified-diff file-header normalization.

## Implementation Notes

- Move measurement, fixture constants, cases/outcomes and preference selection
  into `LiveLlmEditFormatProbe`, behind completion/message ports.
- Keep selection, request settings (including the existing 2,048-token cap),
  thinking observation and generic error/elapsed/publication handling in service.
- Preserve the public `editFormatPreferenceMetadataKey` as a forwarding constant.
- Run whole-file, SEARCH/REPLACE, unified diff in order, then prefer unified
  diff over SEARCH/REPLACE over whole-file. No success means `unknown`.
- Strip visible reasoning and a single code fence before exact comparison.
  Forgive only optional a/b file-header prefixes for unified diffs; retain body
  and hunk-count checks. Name truncation only when a mismatch exists.
- No generated entities, dependencies or persisted formats change.

## Acceptance Criteria

- Preserve prompt bytes, request bindings, usage, previews and result metadata.
- Cover all eight supported-format combinations, fences/reasoning, header
  normalization, hunk drift, mismatch/truncation details and each request error.
- Lower the service budget and add an independent module budget.
- Rollback: restore measurement, helpers, cases/outcomes and constants from
  `1624ef4fe`, remove module/binding and restore the budget; retain contracts.

## Verification

Eleven service contracts passed before extraction, including five new binding,
skip and per-request error contracts:

```bash
CAVERNO_TEST_REPORT_DIR=build/test_reports/f5_edit_baseline \
  tool/flutter_test_quiet.sh \
  test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --name 'edit format|unified diff'
```

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_edit_format_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run affected `live_llm` size checks separately. Logs and coverage remain ignored.

## Implementation Evidence

- Service: 2,746 -> 2,583 lines. Independent module: 195 lines.
- Normalized measurement and preference-selection bodies match the committed
  original after the completion/message bindings move to the service.
- Nineteen isolated tests cover format combinations, preference order, prompts,
  normalization, truncation/mismatch details, previews and request exceptions.
- The focused gate passed 157 tests across six suites, clean root/package
  analysis, internal-package tests and notification relay checks.
- Module: 54/54 executable lines covered (100%). Service: 698/809 (86.28%) in
  this focused run; this is not whole-suite coverage.
- Eleven affected `live_llm` size checks passed, including both changed budgets.
- Formatting, diff whitespace and changed documentation references checked.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. Literal preservation is locally committed
as `1624ef4fe`. This edit-format slice remains uncommitted. No main integration,
push, full Flutter-suite, live-model or signed-device result is claimed.
