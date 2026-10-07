# F5 Streaming Diagnostic Probe Extraction

## Task

- Goal: move streaming response measurement into an independent module.
- User-visible behavior: preserve sequence scoring, TTFT, decode rate, buffering
  warnings, terminal metadata, token usage, previews and report publication.
- Non-goals: transport changes, capability-score changes, release/device gates,
  endpoint requests or production chat-stream behavior.

## Context

- Base: `e1cd3753e`, the locally committed effective-context extraction.
- Related docs: [boundary plan](large_file_refactor_plan.md), [roadmap](roadmap.md).
- The existing service owns a roughly 90-line streaming measurement plus
  request constants and a private outcome. The stream has request-local
  terminal metadata, and the service observes the complete raw content.

## Implementation Notes

- `LiveLlmStreamingProbe` receives a streaming request port, a thinking
  observation port and an injectable stopwatch factory for deterministic tests.
- The service keeps selected-probe skips, system/user message construction,
  model/temperature/token settings, error-to-report conversion, overall elapsed
  time and running/terminal report publication.
- Preserve the 1..40 prompt verbatim and the 40-check denominator. Ignore empty
  chunks, capture TTFT at first content and total elapsed at stream completion,
  then await terminal metadata before thinking observation and scoring.
- Keep raw thinking observation and bounded preview distinct from visible
  sequence scoring. A full sequence with `finishReason: length` still warns.
- Keep single-chunk and late-burst decode-rate suppression in the existing
  streaming metrics entity; no timing threshold or formula changes.
- No generated entities, dependencies or persisted formats change.

## Similar-Pattern Search

- Inspected the context/depth/multi-round completion ports, stream capture,
  terminal metadata, thinking observer and streaming metrics entity.
- A normalized body comparison against the committed service confirms that
  measurement/scoring logic changed only collaborator names and the clock port.

## Acceptance Criteria

- Preserve request bindings, scoring, usage, raw thinking and notification order.
- Cover empty/keep-alive chunks, partial/out-of-order content, truncation,
  missing metadata, buffering, bounded preview and delayed terminal metadata.
- Request, stream, terminal and thinking exceptions reach the existing service
  boundary; report publication exceptions still propagate.
- Lower the service size budget and add a module budget.
- Rollback: restore the measurement/constants/outcome and service size budget
  from `e1cd3753e`, remove the module/binding, and retain service contracts.

## Verification

Seven new service contracts passed before extraction:

```bash
CAVERNO_TEST_REPORT_DIR=build/test_reports/f5_stream_baseline \
  tool/flutter_test_quiet.sh \
  test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --plain-name streaming
```

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_streaming_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_effective_context_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/entities/live_llm_diagnostic_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
```

Check `file_size_ratchet_test.dart --plain-name live_llm` separately. Reporter
logs and coverage remain ignored local artifacts.

## Implementation Evidence

- Service: 3,055 -> 2,965 lines. Independent module: 117 lines.
- Seven service contracts passed against the original streaming measurement.
- Nineteen isolated streaming tests cover deterministic timing, buffering,
  scoring, metadata ordering, previews and propagated errors.
- The focused coverage gate passed 176 tests across eight suites, clean
  root/package analysis, internal-package tests and notification relay checks.
- Module: 40/40 executable lines covered (100%). Service: 836/947 (88.28%) in
  this focused run; this is not full-suite coverage.
- Eight affected `live_llm` file-size checks passed, including the new module.
- Normalized measurement comparison, formatting and documentation references
  checked; no generated or dependency files changed.

## Handoff Notes

F5 remains `current`; RC1 stays on hold. The context slice is locally committed;
this streaming slice remains uncommitted until separately requested. No main
integration, push, full Flutter-suite, live-model or device run is claimed.
