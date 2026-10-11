# F5 Instruction Echo Probe Extraction

## Task

- Goal: isolate instruction-echo prompt and JSON contract scoring.
- User-visible behavior: preserve exact prompt, JSON parsing, marker-based
  warning/failure distinctions, evidence preview and usage.
- Non-goals: change JSON acceptance, transport, selection/provider policy,
  sampler orchestration, release or resume RC1 device verification.

## Context And Plan

Baseline: local main `ec5bdafed`; diagnostic service 2,294 lines. Use a
completion port with domain content/diagnostic usage values. Retain request
settings, thinking observation, exception handling, elapsed time, report
publication and sampler orchestration in the service. Reuse the existing
JSON parsing and evidence helpers. No generated entities or dependencies.

## Tasks And Acceptance

1. Verify service request/report contracts before extraction.
2. Move prompt and scoring without changing parsing or marker precedence.
3. Cover exact/extra/wrong JSON fields, malformed/plain/absent marker replies,
   fenced and reasoning-wrapped JSON, previews, usage and port failures.
4. Lower service size budget, budget the module and run focused coverage,
   static analysis and size/package/layer gates.
5. Inspect the diff, update both roadmap indexes and boundary plan, record
   evidence and commit only task files locally.

## Similar-Pattern Search

Inspected initial-harness/narrow-tool completion ports, shared JSON/evidence
helpers and routine/coding/plan sampler trials. Parsing remains shared, while
request-class/temperature policy remains with sampler orchestration.

## Verification

All five tasks are complete. Three service contracts passed before extraction
with the quiet wrapper (`--name 'instruction echo preserves'`), covering plain
and reasoning-wrapped replies and request failure. Each run retains the 24
routine/coding/plan sampler trials, including after a failed main completion.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_instruction_echo_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_narrow_tool_call_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_remote_mcp_exposure_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_initial_harness_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_subagent_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 652 focused tests passed across nine suites, including 22 isolated probe
  tests and the three pre-extraction service contracts.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Module: 13/13 executable lines covered (100%). Service: 621/692 (89.74%) in
  this focused run; this is not full-suite coverage.
- Service: 2,294 -> 2,270 lines. Module: 54 lines; both budgets verified.
- Normalized JSON scoring matches the original after reply-port and constant
  substitutions. Extra fields, wrapped JSON, raw marker presence (including
  inside reasoning), previews and usage retain their existing semantics.
- Service tests verify exact prompt, no tools, model/token cap/temperature,
  progress publication, reasoning observation, request failure and all 24
  sampler trials with their original temperature order.
- Formatting, diff whitespace and local documentation links checked. No new
  transport import, execution port, reviewed-edge exception or generated entity.
- No full Flutter-suite, live-model, signed-device, release or push run.
  The pre-existing `macos/Podfile.lock` change remains outside this task.

## Follow-Up

F5 remains `current`; RC1 stays on hold. Refresh remaining file sizes, churn,
focused coverage and diagnostic boundaries before choosing another extraction.
Compare provider-language matrix, video-modality and catalog seams. Keep
request/report and sampler orchestration and tool-search execution with their
existing owners unless a bounded contract and evidence justify a move.
