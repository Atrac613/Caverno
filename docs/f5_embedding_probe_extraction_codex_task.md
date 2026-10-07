# F5 Embeddings Response Scoring Extraction

## Task

- Goal: isolate pure embeddings response validation and semantic scoring.
- User-visible behavior: preserve structural rejection, the 0.05 semantic
  margin, two-check denominator, result wording and physical metrics.
- Non-goals: embedding transport, endpoint selection, null/error diagnostics,
  client lifetime, model/approval policy or live/device verification.

## Context

- Base: `d56fb06df`, the locally committed streaming extraction.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- Remaining families include embeddings, exact preservation, edit-format and
  tool/harness diagnostics. The embeddings evaluator is a bounded pure concern
  with three existing service tests; it can move without a new IO boundary.

## Implementation Notes

- Move `_evaluateEmbeddings`, its outcome, fixed input texts and semantic cutoff
  into `LiveLlmEmbeddingProbe`. Keep `EmbeddingsMath` as the cosine implementation.
- The service retains selection/provider/model skips, request timing, injected
  and production clients, failure diagnostics, client closing and publication.
- Preserve short-circuit structural validation before indexing vectors, finite
  non-zero equal-width checks, the returned model name and nullable metrics.
- No generated entities, dependencies or persisted data change.

## Acceptance Criteria

- Reject missing/extra/empty/unequal/zero/non-finite vectors without metrics.
- Preserve success/warning scoring on both sides of the semantic cutoff.
- Preserve input texts, result details, model metadata and elapsed metrics.
- Add independent tests and lower the service size ratchet.
- Rollback: restore evaluator/constants/outcome and service budget from
  `d56fb06df`, remove the module, and retain service contract assertions.

## Verification

Baseline: three existing service tests passed with `--name embedding` before
extraction. Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_embedding_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/entities/live_llm_diagnostic_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Run the `live_llm` file-size checks separately. Reports and coverage are ignored.

## Implementation Evidence

- Service: 2,965 -> 2,877 lines. Independent evaluator: 97 lines.
- Normalized evaluator body matches the committed original after collaborator
  names change. The service assertion now freezes all three input texts.
- Eighteen isolated tests cover structural failures, the cutoff and result
  contents. The focused gate passed 143 tests in five suites, clean root/package
  analysis, internal-package tests and notification relay checks.
- Module: 40/40 executable lines covered (100%). Service: 796/907 (87.76%) in
  this focused run; this is not whole-suite coverage.
- Nine affected `live_llm` size checks passed, including both changed budgets.
- Formatting, diff whitespace and changed documentation references checked.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. Streaming is locally committed as
`d56fb06df`. This embeddings slice remains uncommitted. No main integration,
push, full Flutter-suite, live-model or signed-device result is claimed.
