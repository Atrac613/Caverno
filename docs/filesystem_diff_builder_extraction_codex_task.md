# Filesystem Diff Builder Extraction

## Task

- Goal: extract pure unified-diff construction and preview truncation from
  `FilesystemTools` into an independently testable service.
- User-visible behavior: filesystem write and edit previews retain exactly the
  same headers, hunks, context, truncation marker, and fallback-content text.
- Non-goals: changing filesystem access, path resolution, edit preconditions,
  write or rollback behavior, tool payloads, or the diff algorithm.

## Context

- Affected files or components:
  - `lib/features/chat/data/datasources/filesystem_tools.dart`
  - a new
    `lib/features/chat/data/datasources/filesystem_diff_builder.dart`
  - focused filesystem tests and file-size ratchets
- Related docs: `docs/large_file_refactor_plan.md` and
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- Reference implementation or pattern: the completed network route, routine
  run-history, and LAN IP network extraction slices preserve their public
  facade while moving one cohesive concern behind a direct test boundary.
- Known quirks, compatibility rules, or release gates:
  - `FilesystemTools.buildUnifiedDiff` is public and must remain available;
  - null content denotes `/dev/null` in diff headers;
  - small inputs use longest-common-subsequence ordering, while large inputs
    use common prefix and suffix anchors;
  - previews are capped at 400 lines and 12,000 characters and end with the
    existing truncation marker;
  - the full `tool/codex_verify.sh --coverage --no-codegen` gate is required.

## Implementation Notes

- Preferred approach:
  1. characterize public diff output, hunk context, large-input fallback,
     truncation, and unavailable-preview content;
  2. move the pure implementation unchanged into `FilesystemDiffBuilder`;
  3. retain `FilesystemTools.buildUnifiedDiff` as a compatibility delegate;
  4. delegate write and edit preview fallback formatting to the new service;
  5. add exact non-increasing line-count ratchets for both files.
- Constraints: keep file I/O, snapshots, and edit validation in
  `FilesystemTools`; do not add Flutter or platform dependencies to the new
  service.
- Generated files needed: none.
- Migration or data compatibility concerns: none; all returned strings remain
  byte-for-byte compatible for the same inputs.

## Similar-Pattern Search

- Search terms: `buildUnifiedDiff`, `_buildDiffOperations`,
  `_buildPreviewUnavailableMessage`, `Diff preview unavailable`, and
  `diff preview truncated`.
- Files or modules inspected: `filesystem_tools.dart`,
  `filesystem_tools_test.dart`, built-in filesystem tool handlers, and diff
  preview consumers.
- Follow-up tasks found: none in this slice. The remaining filesystem boundary
  must be re-ranked after extraction instead of widening this change into file
  scanning or mutation behavior.

## Acceptance Criteria

- Required behavior:
  - the public `FilesystemTools.buildUnifiedDiff` API remains source compatible;
  - new, deleted, unchanged, small changed, and large changed inputs preserve
    their current output;
  - write and edit preview failure text remains unchanged;
  - the extracted service is pure Dart and directly testable.
- Edge cases: null and empty contents, no changes, distant hunks, inputs above
  the LCS cell limit, and both line and character truncation.
- Failure paths: unavailable snapshot and invalid edit previews retain the
  current reason and optional proposed-content rendering.
- Accessibility, localization, or platform expectations: no UI or localized
  copy changes; output is platform-independent text.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/filesystem_diff_builder_test.dart \
  --test test/features/chat/data/datasources/filesystem_tools_test.dart \
  --test test/features/chat/data/datasources/built_in_filesystem_tool_handler_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `FilesystemDiffBuilder` now owns pure unified-diff construction,
  LCS and anchor selection, hunk rendering, unavailable-preview formatting,
  and preview truncation in a 213-line library. `FilesystemTools` retains its
  public `buildUnifiedDiff` API as a delegate and fell from 1,476 to 1,282
  physical lines. Both files have exact line-count ratchets.
- Tests run: the focused verification gate passed analysis, 13 internal-package
  tests, and 103 selected root tests. The full coverage gate passed analysis,
  13 internal-package tests, and 3,876 root tests.
- Coverage or low-coverage notes: overall line coverage reached 74.97%
  (53,344/71,151). The extracted service reached 99.06% (105/106), while the
  remaining filesystem service reached 78.98% (417/528). Combined executable
  coverage rose from the original 77.46% snapshot to 82.33% (522/634).
- Risks or follow-ups: path handling, file I/O, snapshots, and edit preconditions
  remain in `FilesystemTools`. Refresh the inventory before considering another
  filesystem slice rather than widening this extraction.
