# Computer Use Live Smoke Summary Extraction

Status: complete on `feature/computer-use-live-smoke-summary`.

## Task

- Goal: extract the existing Computer Use live-smoke summary from
  `computer_use_settings_page.dart` into an independently tested stateless
  widget backed by an immutable typed presentation view model.
- User-visible behavior: none. Envelope precedence, heading text, status-chip
  order and semantics, blocker summary, detail order, path shortening, spacing,
  and malformed-input fallbacks remain unchanged.
- Non-goals: changing smoke execution, report generation or persistence,
  helper or XPC behavior, permission gates, refresh state, platform operations,
  diagnostics export, or localization.

## Context

- Affected files or components:
  - a new `ComputerUseLiveSmokeSummary` widget and immutable presentation
    values for status rows and detail lines
  - `ComputerUseSettingsPage` diagnostics composition
  - direct view-model/widget tests, existing settings integration tests, and
    exact file-size ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 4
  - `docs/roadmap.md` F5
  - `docs/computer_use_ipc_runtime_summary_codex_task.md`
- Reference implementation or pattern: follow the IPC runtime extraction. The
  page owns the latest report envelope and refresh lifecycle; the extracted
  boundary eagerly copies presentation values and performs no service,
  Riverpod, platform, lifecycle, or action work.
- Known quirks, compatibility rules, or release gates:
  - A nested `report` map overrides envelope report fields, while envelope
    `path` takes precedence over the nested `reportPath` when non-null.
  - Live Core and Live Capture always render first; ten gate-derived rows keep
    their current conditional order.
  - System audio is positive when it has no blockers or reports
    `unsupported`, with the existing `Unsupported` success label.
  - Blocker categories retain their existing order and ` | ` separator.
  - M4 details precede capture details, followed by the report path.
  - Long M4 helper paths retain the current final-four-component shortening.

## Implementation Notes

- Preferred approach:
  1. Characterize envelope normalization, required and optional status rows,
     audio and unsafe semantics, blocker aggregation, detail ordering, path
     fallback, and malformed nested values.
  2. Add immutable summary, status-row, and detail values that eagerly copy the
     source envelope without retaining mutable maps or lists.
  3. Move only `_LiveSmokeSummary` presentation and its normalization helpers
     into the new widget file.
  4. Have the page construct the view model from `_lastLiveSmokeReport`, then
     lower exact primary and extracted-widget ratchets.
- Constraints:
  - Do not pass a service, provider ref, page state object, or callback into the
    extracted widget.
  - Do not move `_lastLiveSmokeReport`, live-smoke loading, refresh behavior,
    report generation, export, or helper and platform operations out of the
    page.
  - Do not combine verification, persistence, or XPC timing summaries with
    this slice.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_LiveSmokeSummary`, `_StatusChip`, `reportEnvelope`,
  `positiveSmokeGateSummary`, `readinessExpectations`, `m4SignoffGate`,
  `captureFailureClasses`, and `Live capture next action`.
- Files or modules inspected: Computer Use settings page, settings page widget
  tests, live-smoke fake service report, IPC runtime widget and tests, current
  roadmap, and file-size ratchets.
- Follow-up tasks found: verification, persistence, and XPC timing summaries
  remain independent later Phase 4 slices.

## Acceptance Criteria

- Required behavior:
  - the view model produces the required and optional status rows in their
    current order with identical positive-state and label decisions.
  - blocker and detail lines preserve current category and display order.
  - nested report and outer path precedence remain unchanged.
  - the view model retains no source envelope, nested map, or mutable list.
  - the widget renders only immutable presentation values and performs no
    action.
  - the settings page keeps report ownership, refresh state, diagnostics
    generation, smoke execution, and every helper or platform operation.
- Edge cases:
  - no nested report uses the envelope itself as the report body.
  - non-map nested diagnostics are ignored while empty maps retain their
    current ready, clear, blocked, or `null` presentation.
  - absent or empty blocker lists produce no blocker detail.
  - `failureClass: none` suppresses capture failure details.
  - a non-string or empty path is hidden, and short helper paths remain
    unchanged.
- Failure paths: no new failure handling is introduced; malformed or absent
  fields continue to degrade through the existing presentation rules.
- Accessibility, localization, or platform expectations: preserve Material
  status icons, colors, text, wrapping, and layout. Direct tests perform no
  native Computer Use, helper, permission, IPC, audit, file, or smoke action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_live_smoke_summary_test.dart \
  --test test/features/settings/presentation/pages/settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted live-smoke envelope normalization and presentation into
  `ComputerUseLiveSmokeSummaryViewModel` and
  `ComputerUseLiveSmokeSummary`. The settings page retains report ownership,
  refresh state, diagnostics generation, smoke execution, and every helper or
  platform action. Its exact ratchet fell from 2,189 to 1,927 lines, and the
  new widget is independently ratcheted at 302 lines.
- Tests run: the focused verifier passed 58 root tests plus 13 internal-package
  tests. The full coverage verifier passed 3,616 root tests plus 13
  internal-package tests with no analyzer findings.
- Coverage or low-coverage notes: full repository line coverage was 73.51%
  (52,001/70,738). The new live-smoke widget reached 100.00% line coverage
  (137/137), and the remaining settings page reached 95.83% (804/839).
- Risks or follow-ups: keep live report and platform ownership in the page.
  Extract the XPC timing summary next, followed by the smaller verification
  and persistence summaries as separate behavior-preserving slices.
