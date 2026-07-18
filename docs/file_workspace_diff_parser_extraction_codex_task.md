# File Workspace Diff Parser Extraction

## Task

- Goal: extract unified-diff row classification and line-number tracking from
  `FileWorkspaceViewerSheet` into a pure presentation parser.
- User-visible behavior: the file workspace preview retains the same row text,
  header classification, old and new line numbers, colors, and ordering.
- Non-goals: changing diff generation, truncation, file loading, path
  containment, viewer layout, colors, copy, or revert behavior.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/widgets/file_workspace_viewer_sheet.dart`
  - a new
    `lib/features/chat/presentation/widgets/file_workspace_diff_parser.dart`
  - focused parser and viewer tests plus file-size ratchets
- Related docs: `docs/large_file_refactor_plan.md` and
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- Reference pattern: completed pure boundary slices retain UI and orchestration
  in the original file while moving deterministic logic behind direct tests.
- Known compatibility rules:
  - valid hunk headers reset both old and new line counters;
  - file headers are classified before addition and removal prefixes;
  - additions advance only the new counter and removals only the old counter;
  - context rows advance both initialized counters;
  - malformed hunk text, blank rows, and no-newline markers retain their
    current context-row treatment;
  - row text and input order remain byte-for-byte unchanged after Dart string
    splitting;
  - the full `tool/codex_verify.sh --coverage --no-codegen` gate is required.

## Implementation Notes

- Preferred approach:
  1. characterize headers, multiple hunks, additions, removals, context, blank
     rows, malformed hunk text, and trailing newline behavior;
  2. introduce immutable `FileWorkspaceDiffRow` values and a pure
     `FileWorkspaceDiffParser`;
  3. make the existing preview widget consume the parser result without moving
     Flutter styling or layout;
  4. remove the private parser types from the viewer;
  5. add exact non-increasing line-count ratchets for both files.
- Constraints: the parser must depend only on the Dart SDK and must not know
  about Flutter widgets, themes, files, paths, or `TurnDiff` entities.
- Generated files needed: none.
- Migration or data compatibility concerns: none; the parsed rows are transient
  presentation state.

## Similar-Pattern Search

- Search terms: `_DiffRow`, `_DiffRowKind`, `_hunkPattern`, `unifiedPatch`, and
  `_DiffCodeLine`.
- Files or modules inspected: `file_workspace_viewer_sheet.dart`,
  `turn_diff_sheet_test.dart`, `filesystem_diff_builder.dart`, and its direct
  tests.
- Follow-up tasks found: file loading and root containment remain separate
  candidates. Do not include them in this extraction.

## Acceptance Criteria

- Required behavior:
  - every existing header, context, addition, and removal row remains in the
    same order with the same text;
  - old and new line numbers remain exact across single and multiple hunks;
  - the viewer still renders generated patches and clean-state presentation;
  - the parser has no Flutter or IO dependency;
  - both source files have non-increasing line-count ratchets.
- Edge cases: zero-length ranges, omitted range counts, malformed hunk headers,
  content before the first hunk, empty patches, and trailing newlines.
- Failure paths: arbitrary patch text returns rows without throwing.
- Accessibility, localization, or platform expectations: no semantic labels,
  localized copy, keyboard behavior, or platform behavior changes.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/widgets/file_workspace_diff_parser_test.dart \
  --test test/features/chat/presentation/widgets/turn_diff_sheet_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `FileWorkspaceDiffParser` now owns deterministic header, context,
  addition, and removal classification plus old and new line-number tracking.
  `file_workspace_viewer_sheet.dart` retains rendering and fell from 1,634 to
  1,559 lines; the pure parser is ratcheted at 97 lines.
- Tests run: the focused gate passed 79 selected Flutter tests and 13 internal
  package tests. The full gate passed analysis, 3,892 Flutter tests, and 13
  internal package tests.
- Coverage or low-coverage notes: full line coverage remained 74.97%
  (53,351/71,159). The parser reached 96.97% (32/33), the remaining viewer
  reached 82.90% (514/620), and their combined coverage reached 83.61%
  (546/653). The pre-extraction viewer snapshot was 83.69% (544/650), and the
  selected private parser region started at 100.00% coverage (30/30).
- Risks or follow-ups: keep rendering, file IO, path handling, and diff
  generation out of this extraction. Re-rank the remaining viewer concerns
  before selecting another boundary.
