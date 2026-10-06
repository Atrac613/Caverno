# F5 Structured-Output Probe Extraction

Investigation: 2026-10-02, against local main `55c739761`.
Status: `done` for this slice on `feature/f5-structured-output-probe`;
F5 remains `current`. The selection evidence below records the pre-edit source.

## Selection Evidence

RC1 signed-device evidence is on hold by user decision. The
[roadmap](roadmap.md#recommended-next-slice) therefore selected this existing F5
boundary before starting another feature track.

- A fresh line-count scan of non-generated `lib/**/*.dart` places
  `chat_notifier.dart` first at 8,630 lines and
  `live_llm_diagnostic_service.dart` second at 3,963. The diagnostic service is
  exactly at its file-size budget; the owner's earlier 4,067-line summary
  predates its thinking-observer extraction.
- The structured-output family remains in the service:
  `_runStructuredOutputProbe`, `_schemaArmDetail`, `_runStructuredObjectArm`,
  and the schema/marker constants. The arm execution and result construction
  are a bounded concern with no tool execution or persisted-entity changes.
- `_responseFormatSupport` owns a metadata GET. Keep that IO in the service
  and pass its result through a port so independent probe tests need no
  endpoint. The existing vision and sampler modules demonstrate this pattern.
- Existing service tests assert schema preference, literal prompt values,
  reasoning-aware decoding, truncation wording, object fallback, and failure
  of both modes. Other tests cover bounded probe selection and provider skips.
  Inspecting these assertions establishes a starting contract, not a passing
  test result on this revision.

| Alternative | Decision for this investigation |
| --- | --- |
| RC1 signed-device evidence | `later`; resume only at the user's request. Required product-promotion evidence remains outstanding. |
| F5 tool-loop families | Follow separately. Recovery, depth, and multi-round probes carry more catalog/state/report coupling than the two structured-output arms. |
| Farm macOS surface check and historical diff review | Still open in the Farm owner. This F5 slice is independent; complete those checks before further Farm feature expansion. |
| SEC1 Farm capability classification | `start_project_task` still falls through to the capability classifier's `other`/low-risk/unknown-effect defaults. Its handler separately requires user approval. Keep a focused follow-up; do not describe this observation as a demonstrated approval bypass. |
| Strict Farm execution environment | The 2026-10-01 boundary design records missing SDK/cache provisioning and separate Git/Python authority routes. This needs its own scoped environment task and runtime evidence. |
| FARM6 | Deferred pending token-storage and egress decisions. |

The SEC1 index also still describes HTTP/browser gaps that the audit's
remediation map records as completed. Do not select a repeat fix from that
summary without checking the owning code and audit. This investigation does
not declare SEC1 complete or re-audit all tools.

## Task

- Goal: extract the structured-output probe arms into an independently
  testable module, reducing the diagnostic service without changing behavior.
- User-visible behavior: preserve diagnostic status, summaries, details,
  profile inference, and progress updates for the same responses.
- Non-goals: tool-loop extraction, new endpoint conformance rules, token-cap
  changes, revised schema-enforcement claims, live calibration, or UI changes.

## Context

- Affected files:
  - `lib/features/settings/domain/services/live_llm_diagnostic_service.dart`
  - New `lib/features/settings/domain/services/live_llm_structured_output_probe.dart`
  - `test/features/settings/domain/services/live_llm_diagnostic_service_test.dart`
  - New `test/features/settings/domain/services/live_llm_structured_output_probe_test.dart`
  - `test/quality/file_size_ratchet_test.dart`
- Related docs: [boundary plan](large_file_refactor_plan.md#next-boundary-selection-2026-10-02),
  [cross-track selection](roadmap.md#recommended-next-slice),
  [Farm constraints](project_farm_roadmap.md#open-questions), and
  [execution boundaries](project_execution_boundary_design.md#compatibility-and-remaining-work).
- Reference modules: `live_llm_vision_probes.dart`,
  `live_llm_sampler_calibration_trials.dart`,
  `live_llm_diagnostic_evidence.dart`, and
  `live_llm_diagnostic_response_scoring.dart` in the same service directory.
- Compatibility: a datasource wrapper can hide
  `StructuredOutputChatDataSource`. Preserve the existing capability type
  check against the original datasource.

## Implementation Notes

- Use a completion port taking messages, `StructuredOutputRequest`, and the
  requested token cap. The service binds model, temperature, and successful
  response observation. Bind parameter-support lookup through a separate
  port; preserve unknown support as a reason to attempt the schema arm.
- The module returns `LiveLlmDiagnosticProbeResult` and publishes it through
  an optional callback port. The service retains probe selection,
  provider/datasource skips, running-state publication, and final report
  updates. Keep schema publication inside its original failure boundary;
  object publication errors still propagate. Preserve elapsed timing across
  lookup and both arms.
- Move schema/marker constants with the arms. Preserve the public
  `LiveLlmDiagnosticService.structuredOutputSupportMetadataKey`, forwarding it
  if needed. Keep public probe definitions and IDs unchanged.
- Reuse existing evidence and visible-content helpers. Keep each successful
  response counted exactly once by the thinking observer and usage totals.
- Use an independent Dart library, not a new `part` of the large service.
  Lower the service ratchet to the measured final size and budget the new file.
- No generated entities or persisted formats need to change.

## Similar-Pattern Search

- Search terms: `StructuredOutputChatDataSource`,
  `structuredOutputSupportMetadataKey`, `_schemaArmDetail`,
  `_runStructuredObjectArm`, `_responseFormatSupport`, and
  `LiveLlmDiagnosticObservedChatCalls`.
- Inspect probe calls, thinking observation, evidence helpers, and
  `ModelCapabilityProfileBuilder` consumption. Check for duplicate helpers,
  stale imports, or a second observation of a completed response.
- Keep tool-loop extraction, SEC1 Farm classification, and strict execution
  environment work as separate follow-ups.

## Acceptance Criteria

- Preserve schema-first execution, no fallback after success, and object
  fallback after an unsupported schema, an invalid answer, or a request error.
- Preserve exact prompts, schema, temperature, model selection, and current
  caps: 2,048 for the schema arm and 512 for the object arm.
- Preserve `structured_output`, `structuredOutputSupport`, and its
  `jsonSchema`/`jsonObject`/`none` values, scoring, usage, and callbacks.
- Preserve selection, Apple Foundation Models, and incapable-datasource skip
  paths without generation. A metadata lookup failure stays `unknown` and
  does not disable generation.
- Test empty/invalid responses, `finish_reason: length`, reasoning containing
  braces, schema and object exceptions, and combined usage on fallback. Retain
  the distinction between truncation and a schema violation.
- Independent tests use fake completion and metadata ports; they must not
  call a live LLM. Service tests still prove profile inference, skips,
  thinking totals, and report publication through the delegated boundary.
- Preserve UI/localization keys. Do not add storage, approval, or migration
  behavior. Keep service and new-module size checks green.

## Verification

Focused implementation gate (coverage mode also runs package and relay checks):

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_structured_output_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_response_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_evidence_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart
tool/flutter_test_quiet.sh test/quality/file_size_ratchet_test.dart \
  --plain-name live_llm
git diff --check
```

Inspect coverage of the new boundary and explain any remaining untested paths;
do not reuse the historical service percentage as current evidence. A live
endpoint run is optional follow-up evidence, not a prerequisite for this
behavior-preserving extraction.

## Handoff Notes

- Investigation checks: current source and tests inspected, line-count/budget
  comparison, documentation references, and diff whitespace checks.
- At investigation time, Flutter tests, analysis, live-model checks, and device
  checks were not run. The implementation results below supersede that
  source-only handoff for tests and analysis.
- Rollback unit: revert the module, its service delegation, migrated tests,
  and ratchet changes together. F5 remains `current` after this one slice.

## Implementation Evidence

Completed 2026-10-02 on `feature/f5-structured-output-probe`:

- The service delegates both arms to the independent module while retaining
  its public IDs/metadata constant, datasource capability check, skip paths,
  metadata HTTP lookup, report updates, and thinking observer. It fell from
  3,963 to 3,789 lines; the new module is 210 lines.
- Moved prompt and reasoning-decoding assertions to the new boundary. Its 25
  tests also cover unsupported/unknown metadata, exact schema and object
  contracts, truncation, request failures, combined usage, elapsed time,
  bounded previews, and publication exceptions. Service integration tests
  preserve model/temperature/caps, profile inference, one observation per
  response, report states, and skipped generation.
- The initial `tool/codex_verify.sh --no-codegen --coverage` gate passed.
  After preserving publication-error scope, final Flutter analysis passed,
  and the same six suites passed again with coverage: 128 tests. Three
  `live_llm` file-size checks passed separately.
- Final coverage: module 52/52 executable lines (100%); service 1,147/1,312
  (87.42%) in the focused run. Coverage and test reports are generated local
  artifacts, not repository evidence files.
- Similar-pattern search found no stale arm helpers or duplicate schema
  constants in the service. No generated entities, storage formats, or
  dependency locks changed. Live-model and device behavior remain unverified;
  RC1 signed-device evidence remains on hold.

Next F5 slice: scope the tool-recovery family independently of depth and
multi-round probes.
