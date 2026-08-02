# Chat Tool Catalogue Snapshot Validation: Codex Task

Status: Implemented and live-verified on 2026-08-02 against the private
169-definition snapshot captured from clean build `739957a5`.

## Task

- Goal: Validate every pinned catalogue snapshot as a complete schema-v1
  exporter artifact and join its configuration and build provenance to the
  corpus segment that references it.
- User-visible behavior: `--check-corpus-manifest` rejects malformed,
  internally inconsistent, or provenance-mismatched catalogue snapshots before
  dynamic inventory analysis can consume them.
- Non-goals: Do not measure tool invocations, derive guard action states,
  validate a static tool manifest, change snapshot capture, or change runtime
  tool selection.

## Context

- Affected files or components:
  - `tool/analyze_chat_notifier_inventory.py`
  - `test/python/analyze_chat_notifier_inventory_test.py`
  - Phase 1 inventory status documents
- Related docs:
  - `docs/chat_tool_catalogue_snapshot_codex_task.md`
  - `docs/chat_notifier_pinned_corpus_contract_codex_task.md`
  - `docs/chat_notifier_inventory_codex_task.md`
- Reference implementation or pattern: Reuse the analyser's exact-field,
  timestamp, SHA-256, and unambiguous Git revision validators. Mirror the
  canonical encoding used by the schema-v1 catalogue exporter.
- Known quirks, compatibility rules, or release gates: Snapshots and corpus
  manifests are private. A request-level `tools` array is not a complete
  catalogue and must not satisfy this contract.

## Implementation Notes

- Preferred approach:
  1. Parse each hash-verified snapshot as an exact schema-v1 artifact.
  2. Validate capture time, exporter revision, build provenance, tool count,
     function-definition shape, sorted unique names, and the canonical
     configuration fingerprint.
  3. Require the snapshot fingerprint, exporter revision, build commit, and
     dirty marker to match the referencing segment and corpus file.
  4. Extend the path-free deterministic corpus summary with validated catalogue
     definition counts, fingerprints, and exporter revisions.
- Constraints: Fail closed on unexpected fields or unsupported schema
  versions. Do not print private paths, tool names, endpoint configuration, or
  session identifiers in normal output or validation errors.
- Generated files needed: None.
- Migration or data compatibility concerns: Existing placeholder snapshot
  fixtures must become valid schema-v1 fixtures. Real snapshots from older or
  unknown exporters remain rejected rather than guessed.

## Similar-Pattern Search

- Search terms: `configurationFingerprint`, `toolDefinitions`, `toolCount`,
  `exporterRevision`, `catalogueSnapshotSha256`, `BuildInfo.toJson`.
- Files or modules inspected:
  - `tool/analyze_chat_notifier_inventory.py`
  - `lib/features/chat/domain/services/chat_tool_catalogue_snapshot.dart`
  - `test/features/chat/domain/services/chat_tool_catalogue_snapshot_test.dart`
- Follow-up tasks found: Consume validated definitions when producing dynamic
  per-tool inventory measurements.

## Acceptance Criteria

- Required behavior: A valid snapshot is accepted only when its canonical
  fingerprint and all segment/file provenance joins agree. The summary remains
  deterministic and path-free.
- Edge cases: Optional build time is validated when present; short commits are
  canonicalized; multiple segment snapshots may share an exporter revision but
  must retain distinct pins.
- Failure paths: Invalid JSON, schema drift, unknown fields, malformed or
  duplicate tool names, count mismatches, unsorted definitions, fingerprint
  drift, and exporter/build/dirty mismatches fail with `InventoryError`.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-corpus-manifest /path/to/private/corpus.json
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Corpus validation now parses every pinned snapshot, enforces the
  exact schema-v1 envelope, checks canonical tool ordering, uniqueness, count,
  and fingerprint integrity, and joins exporter and build provenance to its
  segment and file declarations. Its deterministic summary reports validated
  definition counts, fingerprints, and exporter revisions without paths or
  tool names.
- Tests run:
  - `python3 test/python/analyze_chat_notifier_inventory_test.py`: 30 passed.
  - The private clean-build snapshot passed through a one-record pinned corpus
    fixture with all 169 definitions and its original fingerprint intact.
  - `tool/codex_verify.sh`: dependency installation, generated-file check,
    project and package analysis, and package tests passed. The full Flutter
    suite reached 6,482 passing tests and failed the same unrelated stale
    assertion in
    `test/tool/run_coding_stalled_diagnostic_repair_live_canary_test.dart`,
    which still requires the removed source text `.where(_isTodoVerifierCall)`.
- Coverage or low-coverage notes: Focused tests cover exact snapshot fields,
  exporter extensions on definitions, invalid JSON without path disclosure,
  malformed definitions, ordering, uniqueness, count, canonical fingerprint,
  capture and build timestamps, and segment/file provenance mismatches.
- Risks or follow-ups: Dynamic measurement remains a separate slice. Its first
  useful corpus still requires clean matching-build session logs joined to
  snapshots captured for each represented runtime configuration.
