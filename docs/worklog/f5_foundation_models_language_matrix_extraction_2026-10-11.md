# F5 Foundation Models Language Matrix Extraction

## Task And Acceptance

Isolate the three-case language matrix, sequential completion contract and result
aggregation without changing prompts, markers, status precedence, details or
240-character previews. Keep transport, provider exception classification,
tool schema, request settings, timing and report publication in the service.
Cover all status branches, sequential order, failure continuation and request
shape; run focused analysis, tests, coverage and boundary gates; update both
roadmaps and commit locally. No release, live-model or device work.

## Selection Evidence

Baseline: local main `95e4c8816`. The diagnostic service has 2,270 lines and
38 commits since 2026-09-11; ChatNotifier has 7,344 lines/82 commits, remote
coding server 3,261/15 and remote coding page 2,671/12. Size alone does not
justify moving orchestration. The matrix has a bounded three-case aggregation
contract; video modality owns HTTP client lifecycle and tool search owns tool
execution, so those boundaries remain with their current owners. Existing
Foundation Models service tests passed before extraction (4 tests). Shared
evidence previews and existing completion-port patterns were inspected.

## Verification

Implementation and inspection are complete. The extracted aggregation matches
the original after whitespace and probe-ID substitutions. The request adapter,
exception classification and tool schema match after the intentional typed-port
mapping. Tool schema construction now occurs for the third request rather than
when the case list is built; the schema builder is pure and has no side effects.

The original four Foundation Models service tests passed before extraction.
Added isolated tests cover all status branches, exact prompts/markers, ordered
awaiting, classified-failure continuation and independent preview bounds. Five
service contracts cover accepted/missing markers, unsupported language,
provider unavailability and generic transport errors while asserting model,
temperature, token cap, tool schema and pending/running/final publication.
Initial test expectations were corrected to include the existing pending
notification; new test lint findings were resolved before the final gate.

Final gate:

```bash
tool/codex_verify.sh --no-codegen --coverage \
  --test test/features/settings/domain/services/live_llm_foundation_models_language_matrix_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_instruction_echo_probe_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart \
  --test test/quality/package_boundary_test.dart \
  --test test/quality/layer_import_ratchet_test.dart
```

- 611 focused tests passed across six suites, including seven isolated matrix
  tests and five new service contracts.
- Root/package analysis, 125 internal-package tests, notification relay source
  checks and size/package/layer gates passed.
- Extracted module: 25/25 executable lines covered (100%). Service: 603/672
  (89.73%) in this focused run; this is not full-suite coverage.
- Service: 2,270 -> 2,187 physical lines. Module: 110 lines. Both ratchets pass.
- Formatting, diff whitespace and new documentation references checked.
- No new domain-to-data dependency, reviewed-edge allowance, generated entity,
  dependency or execution port.

## Follow-Up

F5 remains `current`. Inspect catalog construction and freeze ordering, initial
selection and capability filtering before moving it. Preserve the HTTP video
client lifecycle, tool-search execution and sampler orchestration boundaries.
RC1 signed-device verification remains on hold. No full Flutter suite,
live-model, signed-device, release or push verification is part of this slice.
The pre-existing `macos/Podfile.lock` change remains outside this task.
