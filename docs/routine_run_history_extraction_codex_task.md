# Routine Run History Extraction

## Task

- Goal: extract routine run-history presentation from `RoutineDetailView` into
  an independently testable widget boundary.
- User-visible behavior: none. History ordering, empty state, status chips,
  metadata, previews, transcript/error actions, sheet contents, and responsive
  sizing must remain compatible.
- Non-goals: notifier mutations, routine execution, scheduling, plan editing,
  routine duplication/deletion, localization changes, or entity changes.

## Context

- Affected files or components:
  - `lib/features/routines/presentation/pages/routine_detail_view.dart`
  - a new widget under `lib/features/routines/presentation/widgets/`
  - focused routine presentation tests
  - file-size ratchets and the large-file refactor plan
- Related docs:
  - `docs/large_file_refactor_plan.md`
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference implementation or pattern: recent settings and Computer Use slices
  move display-only sections behind immutable inputs while leaving provider and
  native action ownership in the page.
- Known quirks, compatibility rules, or release gates:
  - run records are displayed in the order stored on `Routine.runs`;
  - transcript actions are hidden only when both output and tool calls are
    empty;
  - error actions are hidden only when the trimmed error is empty;
  - assistant transcript content uses `ParsedContentView`, while user and tool
    content remains selectable plain text;
  - this branch is stacked on `feature/network-route-tools-extraction` until
    the preceding slice is integrated into `main`.

## Implementation Notes

- Preferred approach:
  - add product-path characterization through `RoutineDetailView` first;
  - introduce `RoutineRunHistorySection` with a single immutable `Routine`
    input;
  - keep transcript and error sheet launch behavior inside the extracted
    display boundary so the page does not retain presentation callbacks;
  - move record cards, transcript blocks, and their private display helpers
    with the section.
- Constraints:
  - preserve exact localization keys, date formats, duration formats, button
    visibility, chip colors, and sheet geometry;
  - preserve run ordering and all trimming behavior;
  - keep Riverpod and `RoutinesNotifier` out of the new widget;
  - avoid Dart `part` files so the extracted widget is an independent library.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: run history, transcript sheet, text viewer, run record card,
  status chip, metadata line, and routine detail tests.
- Files or modules inspected: `routine_detail_view.dart`, all routine tests,
  the routine entity, the notifier, recent extracted presentation widgets,
  and the file-size inventory.
- Follow-up tasks found: the plan card/editor and notifier-backed action methods
  remain separate candidates after the run-history boundary is verified.

## Acceptance Criteria

- Required behavior:
  - the detail page still renders no-runs and populated-history states;
  - successful and failed run cards retain status, trigger, tools, plan,
    delivery, preview, reviewed-failure, and delivery-message presentation;
  - transcript and error buttons preserve visibility and open the same content;
  - the new widget imports no Riverpod provider or notifier.
- Edge cases:
  - empty previews and errors;
  - sub-second, second, and minute duration formatting;
  - tool calls with arguments, results, both, or neither;
  - output-only and tool-only transcripts;
  - delivered timestamps and acknowledged failures.
- Failure paths: failed routine and failed delivery records retain their exact
  visual and textual status.
- Accessibility, localization, or platform expectations: keep selectable
  transcript/error content, existing localization keys, responsive transcript
  width, and scrollable bottom sheets.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/routines/presentation/pages/routine_detail_view_test.dart \
  --test test/features/routines/presentation/widgets/routine_run_history_section_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `RoutineRunHistorySection` now owns the empty and populated history
  states, run cards, duration and delivery presentation, and transcript and
  error sheets behind one immutable `Routine` input. `RoutineDetailView` fell
  from 1,407 to 948 physical lines, and both boundaries have exact line-count
  ratchets.
- Tests run: the focused verification gate passed analysis, 13 internal-package
  tests, and 68 selected root tests. The full coverage gate passed analysis,
  13 internal-package tests, and 3,857 root tests.
- Coverage or low-coverage notes: overall line coverage reached 74.91%
  (53,293/71,147). The extracted widget reached 96.17% (251/261), while the
  remaining detail page reached 37.72% (175/464), up from the original 34.90%
  snapshot.
- Risks or follow-ups: plan-card and notifier-backed action orchestration remain
  in the page. Pause this boundary now that it is below 1,000 lines and refresh
  the inventory before choosing another extraction.
