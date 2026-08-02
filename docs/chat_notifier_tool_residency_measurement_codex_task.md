# ChatNotifier Tool Residency Measurement

## Task

- Goal: Join the validated static tool manifest to pinned private catalogue
  snapshots and normalized tool-result submissions.
- User-visible behavior: Maintainers can produce deterministic private JSON
  that distinguishes static definitions from configuration-specific dynamic
  definitions and retains zero-observation rows.
- Non-goals: Change production tool registration, payload composition,
  ChatNotifier dispatch, or derive guard action states.

## Context

- Affected files or components:
  `tool/analyze_chat_notifier_inventory.py`, its focused Python tests, and this
  task contract.
- Related docs: `docs/chat_notifier_inventory_codex_task.md` and
  `docs/chat_notifier_static_tool_manifest_codex_task.md`.
- Reference implementation or pattern: The schema-v2 corpus summary and
  schema-v1 static tool manifest validators.
- Known quirks, compatibility rules, or release gates: Request subsets are not
  full catalogues. Dynamic MCP names are sensitive and may appear only in the
  private output, never in a checked-in file.

## Implementation Notes

- Preferred approach: Reuse the exact corpus validation pass to collect pinned
  snapshot definitions and normalized tool-result counts. Join known names to
  static manifest bindings; classify snapshot-only names as dynamic rows bound
  to the single generic MCP fallback.
- Constraints: Preserve zero-observation definitions, group observations by
  represented build, include immutable input digests, and write byte-identical
  JSON for identical inputs.
- Generated files needed: None.
- Migration or data compatibility concerns: Add a dedicated schema-v1 private
  measurement output without changing the existing path-free corpus summary.

## Similar-Pattern Search

- Search terms: `catalogueDefinitionCount`,
  `observedCatalogueDefinitionCount`, `toolResultSubmissionCount`,
  `genericFallback`, and `--output`.
- Files or modules inspected: Corpus snapshot validation, normalized
  tool-result extraction, static manifest validation, and the inventory task's
  residency acceptance criteria.
- Follow-up tasks found: Generate the human-reviewed residency document and
  separately derive guard action states.

## Acceptance Criteria

- Required behavior: Every static manifest definition appears exactly once;
  every snapshot-only definition appears once per configuration; each row
  records observation counts and build provenance; binding rows cover named
  handlers, intercepts, and one generic fallback.
- Edge cases: Static definitions absent from the pinned configuration remain as
  zero-observation rows; repeated submissions increase traffic counts without
  duplicating definitions; the same dynamic name in different configurations
  remains configuration-scoped.
- Failure paths: Reject invalid manifests, unknown submitted names, source
  revision drift, incomplete command inputs, and output paths that cannot be
  written.
- Accessibility, localization, or platform expectations: Not applicable; the
  output is private repository tooling data.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --require-clean-source \
  --corpus-manifest /private/path/to/corpus.json \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --tool-manifest tool/chat_notifier_tool_catalog_inventory.json \
  --output /private/path/to/tool_residency.json
tool/codex_verify.sh
git diff --check
```

## Handoff Notes

- Summary: Implemented schema-v1 private residency output with 118 static
  definitions, configuration-scoped dynamic definitions, six binding rows,
  normalized observation counts, represented-build grouping, and full-SHA
  provenance. Live dogfood correctly separated 52 dynamic definitions from a
  169-definition pinned catalogue after discovering six generated static HTTP
  definitions that the initial manifest missed.
- Tests run: All 44 focused Python tests pass. Two clean-source runs produced
  byte-identical output. `tool/codex_verify.sh` completed analysis, package
  tests, and 6,482 passing Flutter tests with the one known unrelated
  `run_coding_stalled_diagnostic_repair_live_canary_test.dart` source-text
  expectation failure.
- Coverage or low-coverage notes: Focused tests cover deterministic output,
  zero-observation static rows, normalized result joins, dynamic configuration
  scoping, binding aggregation, CLI output, and canonical manifest revisions.
- Risks or follow-ups: This output supplies evidence for the residency report;
  it does not decide which handlers should be rewired. The live private fixture
  is intentionally narrow: it contains one normalized tool-result submission,
  so its 1 observed and 169 unobserved rows are pipeline evidence rather than a
  representative traffic conclusion.
