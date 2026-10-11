# F5 Narrow Tool Call Probe Extraction

## Task

- Goal: isolate the narrow datetime-tool diagnostic prompt and scoring.
- User-visible behavior: preserve the exact request and existing outcomes,
  including success when datetime calls coexist with other or repeated calls.
- Non-goals: execute returned calls, change scoring, tool availability, transport,
  catalog policy, releases or RC1 signed-device verification.

## Context And Plan

Baseline: local main `d374348e4`; service 2,311 lines. Follow the initial-harness
completion-port pattern using only domain reply values. Retain datetime-tool
lookup, availability, request settings, native/embedded response parsing, usage
adaptation, thinking observation, errors, elapsed time and publication in the
service. No generated entity or dependency changes.

## Tasks And Acceptance

1. Add service contracts and verify them before extraction.
2. Move prompt and scoring without changing selection precedence or evidence.
3. Cover datetime, other, absent and repeated calls, previews, usage and failures.
4. Update service/module size budgets and run focused coverage, analysis and
   package/layer/size gates.
5. Inspect the diff, refresh both roadmap indexes and boundary plan, record
   evidence and commit only task files locally.

## Similar-Pattern Search

Inspected initial-harness/subagent completion ports and sampler tool-loop
scoring. The sampler uses the same request text but retains its independent
request-class/temperature policy; it is outside this extraction.

## Verification

All five tasks are complete. Five service contracts passed before extraction
using the quiet wrapper with `--name 'narrow datetime'`. The initial test
assumption of one request was corrected to account for eight existing sampler
trials. Their temperature order and success are verified; they continue even
when the main diagnostic completion fails.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_narrow_tool_call_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_remote_mcp_exposure_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_initial_harness_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_subagent_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 626 focused tests passed across eight suites, including ten isolated probe
  tests and five service contracts for native/embedded calls, disabled/missing
  tools and completion failure.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Module: 11/11 executable lines covered (100%). Service: 625/699 (89.41%) in
  this focused run; this is not full-suite coverage.
- Service: 2,311 -> 2,294 lines. Module: 49 lines; both budgets verified.
- Normalized scoring matches the original after reply-port/ID substitutions.
  Exact prompt, single-tool request, model, token cap, temperatures, observation,
  publication and service error handling are verified.
- Formatting, diff whitespace and local documentation links checked. No new
  transport import, execution port, reviewed-edge exception or generated entity.
- No full Flutter-suite, live-model, signed-device, release or push run.
  The pre-existing `macos/Podfile.lock` change remains outside this task.

## Follow-Up

F5 remains `current`; RC1 stays on hold. Next: scope instruction-echo JSON
scoring with request/report ownership retained in the service. Keep sampler
orchestration and tool-search execution separate.
