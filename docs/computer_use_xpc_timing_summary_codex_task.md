# Computer Use XPC Timing Summary Extraction

Status: complete on `feature/computer-use-xpc-timing-summary`.

## Task

- Goal: extract the existing Computer Use XPC timing summary from
  `computer_use_settings_page.dart` into an independently tested stateless
  widget backed by an immutable typed presentation view model.
- User-visible behavior: none. Visibility, heading copy, information-chip
  order, scalar type checks, fallback text, icons, wrapping, and spacing remain
  unchanged.
- Non-goals: changing XPC timing measurement or classification, helper
  lifecycle, report generation, refresh state, permission gates, live-smoke
  behavior, diagnostics export, or platform operations.

## Context

- Affected files or components:
  - a new `ComputerUseXpcTimingSummary` widget and immutable presentation
    values for its heading and information rows
  - `ComputerUseSettingsPage` diagnostics composition
  - direct view-model/widget tests, existing settings integration tests, and
    exact file-size ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 4
  - `docs/roadmap.md` F5
  - `docs/computer_use_live_smoke_summary_codex_task.md`
- Reference implementation or pattern: follow the live-smoke and IPC runtime
  extractions. The page owns timing-report construction, visibility, refresh,
  and platform state; the extracted boundary eagerly copies presentation
  values and performs no service, Riverpod, lifecycle, or action work.
- Known quirks, compatibility rules, or release gates:
  - the page hides the summary when classification is
    `missing_preferred_attempt`; this visibility decision remains in the page.
  - classification and status use `unknown` for absent, non-string, or empty
    values.
  - Timing status and Timing gate always render first.
  - numeric timing rows accept only `int` values, boolean rows accept only
    `bool` values, and optional text rows require non-empty strings.
  - the remaining fifteen optional rows retain their current conditional order.
  - a false preferred-fallback result renders `not used`, while a true result
    renders `succeeded`.

## Implementation Notes

- Preferred approach:
  1. Characterize required rows, every optional scalar row, row order, boolean
     labels, missing and malformed values, and source-map mutation isolation.
  2. Add immutable summary and information-row values that eagerly copy the
     source map without retaining it.
  3. Move only `_XpcTimingSummary` presentation and its string normalization
     helper into the new widget file.
  4. Have the page construct the view model from its existing derived timing
     summary, then lower exact primary and extracted-widget ratchets.
- Constraints:
  - Do not pass a service, provider ref, page state object, callback, or source
    map into the extracted widget.
  - Do not move `_xpcTimingSummary`, timing-report generation, the
    `missing_preferred_attempt` visibility condition, refresh behavior, helper
    lifecycle, XPC actions, or platform operations out of the page.
  - Do not combine verification or persistence summaries with this slice.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_XpcTimingSummary`, `_InfoChip`, `xpcTimingSummary`,
  `currentPreferredFallbackTimeoutMs`, `warmupResponseReceivedBeforeTimeout`,
  `preferredFallbackSucceeded`, `recommendedActionId`, and
  `engineeringNextAction`.
- Files or modules inspected: Computer Use settings page, settings page widget
  tests, XPC timing report builder and tests, live-smoke and IPC runtime widgets
  and tests, current roadmap, and file-size ratchets.
- Follow-up tasks found: verification and persistence summaries remain two
  independent later Phase 4 slices.

## Acceptance Criteria

- Required behavior:
  - the view model produces the heading and required information rows with
    identical fallback decisions.
  - all optional information rows retain their current conditions, labels,
    values, and order.
  - the view model retains no source map or mutable list.
  - the widget renders only immutable presentation values and performs no
    action.
  - the settings page keeps timing-report construction, visibility, refresh,
    helper and XPC lifecycle, diagnostics, and every platform operation.
- Edge cases:
  - absent, non-string, or empty classification and status values use
    `unknown`.
  - non-int timing values, non-bool state values, and empty optional strings
    produce no optional row.
  - false boolean values still render their negative text rather than hiding
    the row.
  - a source map mutation after view-model construction cannot change rendered
    values.
- Failure paths: no new failure handling is introduced; malformed or absent
  fields continue to degrade through the existing presentation rules.
- Accessibility, localization, or platform expectations: preserve Material
  information icons, theme color, text, wrapping, and layout. Direct tests
  perform no native Computer Use, helper, permission, IPC, file, or smoke
  action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_xpc_timing_summary_test.dart \
  --test test/features/settings/presentation/pages/settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted XPC timing normalization and presentation into
  `ComputerUseXpcTimingSummaryViewModel` and
  `ComputerUseXpcTimingSummary`. The settings page retains timing-report
  construction, visibility, refresh state, diagnostics generation, helper and
  XPC lifecycle, and every platform action. Its exact ratchet fell from 1,927
  to 1,811 lines, and the new widget is independently ratcheted at 176 lines.
- Tests run: the focused verifier passed 59 root tests plus 13 internal-package
  tests. The full coverage verifier passed 3,623 root tests plus 13
  internal-package tests with no analyzer findings.
- Coverage or low-coverage notes: full repository line coverage was 73.52%
  (52,012/70,749). The new XPC timing widget reached 100.00% line coverage
  (75/75), and the remaining settings page reached 95.48% (740/775).
- Risks or follow-ups: keep timing-report and platform ownership in the page.
  Extract the persistence summary next, followed by the smaller verification
  summary as a separate behavior-preserving slice.
