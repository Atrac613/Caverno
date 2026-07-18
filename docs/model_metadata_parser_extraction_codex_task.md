# Model Metadata Parser Extraction

## Task

- Goal: extract model ID normalization and context-window metadata parsing from
  `ModelRemoteDataSource` into a pure, provider-neutral service.
- User-visible behavior: OpenAI-compatible, LM Studio, llama.cpp, and Ollama
  catalogs retain the same model IDs and context-window token values.
- Non-goals: changing HTTP requests, provider fallback order, model lifecycle
  actions, catalog merging, endpoint detection, or error messages.

## Context

- Affected files or components:
  - `lib/features/settings/data/model_remote_datasource.dart`
  - a new `lib/features/settings/data/model_metadata_parser.dart`
  - focused settings data tests and file-size ratchets
- Related docs: `docs/large_file_refactor_plan.md` and
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- Reference implementation or pattern: the completed filesystem diff and LAN
  IP network slices move pure logic behind direct tests while retaining public
  compatibility at the original service boundary.
- Known quirks, compatibility rules, or release gates:
  - metadata keys and nested container keys have deterministic precedence;
  - direct metadata is checked before nested metadata containers;
  - positive integers, finite numbers, and digit-only strings are accepted;
  - selected LM Studio loaded-instance context wins before the first loaded
    instance and model-level fallback;
  - existing public `ModelRemoteDataSource.parse*` methods remain available;
  - the full `tool/codex_verify.sh --coverage --no-codegen` gate is required.

## Implementation Notes

- Preferred approach:
  1. characterize normalization, nested metadata precedence, numeric coercion,
     and LM Studio selected-instance behavior;
  2. move the constants and pure helpers unchanged into `ModelMetadataParser`;
  3. delegate every existing datasource call to the new service;
  4. retain HTTP, provider selection, response parsing, and lifecycle actions in
     `ModelRemoteDataSource`;
  5. add exact non-increasing line-count ratchets for both files.
- Constraints: the new service must depend only on the Dart SDK and must not
  know about HTTP clients, URLs, providers, or settings state.
- Generated files needed: none.
- Migration or data compatibility concerns: none; parsed token counts and model
  IDs remain identical for the same payloads.

## Similar-Pattern Search

- Search terms: `_normalizeModelId`, `_readContextWindowTokens`,
  `_readSelectedLmStudioLoadedContext`, `_readFirstLmStudioLoadedContext`,
  `_metadataSources`, and `_parsePositiveInt`.
- Files or modules inspected: `model_remote_datasource.dart`,
  `model_remote_datasource_test.dart`, model-list providers, and settings pages
  that display context metadata.
- Follow-up tasks found: response-catalog parsing and model lifecycle HTTP
  orchestration remain separate future candidates. Do not include them here.

## Acceptance Criteria

- Required behavior:
  - whitespace-only model IDs remain absent and valid IDs remain trimmed;
  - all supported root and nested context-window keys retain their precedence;
  - positive numeric values retain current coercion and invalid values remain
    absent;
  - LM Studio selected and fallback loaded-instance selection remains exact;
  - all existing datasource parsing and provider tests remain green.
- Edge cases: null and non-list loaded instances, malformed entries, duplicate
  containers, zero and negative values, fractional strings, non-finite numbers,
  and selected instances without usable context metadata.
- Failure paths: malformed metadata returns `null` without throwing.
- Accessibility, localization, or platform expectations: no UI, localized copy,
  network, or platform behavior changes.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/data/model_metadata_parser_test.dart \
  --test test/features/settings/data/model_remote_datasource_test.dart \
  --test test/features/settings/presentation/pages/general_settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ModelMetadataParser` now owns model ID normalization, ordered
  context-window metadata lookup, positive integer coercion, and LM Studio
  loaded-instance context selection. `ModelRemoteDataSource` retains its public
  parsing APIs as compatibility delegates and fell from 1,813 to 1,710 lines;
  the pure parser is ratcheted at 120 lines.
- Tests run: the focused gate passed 104 selected Flutter tests and 13 internal
  package tests. The full gate passed analysis, 3,885 Flutter tests, and 13
  internal package tests.
- Coverage or low-coverage notes: full line coverage remained 74.97%
  (53,349/71,156). The parser reached 97.14% (34/35), the remaining datasource
  reached 79.36% (546/688), and their combined coverage reached 80.22%
  (580/723). The pre-extraction datasource snapshot was 80.08% (575/718), and
  the selected metadata helper region started at 100.00% (37/37).
- Risks or follow-ups: keep provider response construction, catalog merging,
  HTTP transport, and lifecycle actions out of this extraction. Refresh the
  ownership and coverage ranking before choosing another datasource concern.
