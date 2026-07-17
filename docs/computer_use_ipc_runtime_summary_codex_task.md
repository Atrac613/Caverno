# Computer Use IPC Runtime Summary Extraction

Status: complete on `feature/computer-use-ipc-runtime-summary`.

## Task

- Goal: extract the existing Computer Use IPC runtime summary from
  `computer_use_settings_page.dart` into an independently tested stateless
  widget backed by an immutable typed presentation view model.
- User-visible behavior: none. Heading text, chip order, conditional rows,
  values, path shortening, spacing, and malformed-input fallbacks remain
  unchanged.
- Non-goals: changing helper or XPC behavior, runtime report construction,
  permission or smoke gates, diagnostics refresh, persistence, timing policy,
  platform operations, settings actions, or localization.

## Context

- Affected files or components:
  - a new `ComputerUseIpcRuntimeSummary` widget, immutable view model, and
    immutable info-row value
  - `ComputerUseSettingsPage` diagnostics composition
  - direct view-model/widget tests, existing settings integration tests, and
    exact file-size ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 4
  - `docs/roadmap.md` F5
  - `docs/computer_use_action_gate_plan_codex_task.md`
- Reference implementation or pattern: follow the action-gate extraction. The
  stateful page assembles the runtime map, while the extracted boundary eagerly
  copies presentation values and performs no service, Riverpod, platform,
  lifecycle, or action work.
- Known quirks, compatibility rules, or release gates:
  - Preserve the exact existing chip order from Active IPC through Next XPC
    parity.
  - Required scalar fields keep Dart interpolation behavior, including `null`
    text for missing values.
  - Optional chips remain gated by the same runtime type checks.
  - List values stringify entries, remove only empty strings, preserve order,
    and deduplicate only fields that currently use `_uniqueStrings`.
  - Helper, capture, overlay, probe, and M4 paths retain the current four-tail
    component shortening behavior.
  - A non-map nested diagnostic value remains absent; an empty nested map may
    still produce its current `null`, `ready`, `clear`, or empty chip value.

## Implementation Notes

- Preferred approach:
  1. Characterize heading, core rows, fallback details, nested diagnostics,
     conditional type checks, path shortening, deduplication, and row order.
  2. Add immutable summary and info-row view models that eagerly normalize the
     runtime map without retaining mutable maps or lists.
  3. Move only `_IpcRuntimeSummary` presentation and its private normalization
     helpers into the new widget file.
  4. Have the page construct the view model from `_helperIpcRuntime()`, then
     lower exact primary and extracted-widget ratchets.
- Constraints:
  - Do not pass a service, provider ref, page state object, or callback into the
    extracted widget.
  - Do not move `_helperIpcRuntime()`, `_xpcTimingSummary()`, refresh behavior,
    or any helper and platform operation out of the page.
  - Do not combine verification, persistence, XPC timing, or live-smoke panels
    with this slice.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_IpcRuntimeSummary`, `_InfoChip`, `selectedIpcTransport`,
  `xpcProductionBlockers`, `helperPathMismatch`, `captureGate`, `overlaySmoke`,
  `existingHelperProbeOk`, and `m4SignoffGate`.
- Files or modules inspected: Computer Use settings page, settings page widget
  tests, action-gate widget and tests, helper setup/runtime report builders,
  current roadmap, and file-size ratchets.
- Follow-up tasks found: verification, persistence, XPC timing, and live-smoke
  summaries remain independent later Phase 4 slices.

## Acceptance Criteria

- Required behavior:
  - the view model produces all visible info rows in their current order.
  - every conditional type check and status decision matches the existing
    widget for ready, blocked, missing, fallback, stale, mismatch, and
    unsupported diagnostic states.
  - the view model retains no source runtime map or mutable list reference.
  - the widget renders only immutable presentation values and performs no
    action.
  - the settings page keeps runtime-map assembly, refresh state, diagnostics
    ownership, and every helper or platform operation.
- Edge cases:
  - missing required scalar values render as `null` where they do today.
  - non-map nested diagnostics are ignored while empty maps retain current
    derived chip behavior.
  - duplicate overlay values collapse in first-seen order.
  - long paths shorten to the final four non-empty components; short paths
    remain unchanged.
  - absent lists produce no optional chip, and empty next-parity lists render
    `Next XPC parity: none`.
- Failure paths: no new failure handling is introduced; malformed or absent
  fields continue to degrade through the existing presentation rules.
- Accessibility, localization, or platform expectations: preserve Material
  chip icons, text, wrapping, and layout. Direct tests perform no native
  Computer Use, helper, permission, IPC, audit, or filesystem operation.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_ipc_runtime_summary_test.dart \
  --test test/features/settings/presentation/pages/settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ComputerUseIpcRuntimeSummary` now renders the existing ordered IPC
  diagnostics from `ComputerUseIpcRuntimeSummaryViewModel`. The model eagerly
  copies all heading and chip values into an unmodifiable typed row list, while
  the page retains runtime-map assembly, refresh state, diagnostics ownership,
  and every helper, XPC, permission, and platform responsibility. The page
  ratchet fell from 2,816 to 2,189 lines; the extracted widget is ratcheted at
  582 lines.
- Tests run: the focused verification gate passed 57 root tests plus 13
  internal-package tests. The full coverage gate passed 3,609 root tests plus
  13 internal-package tests with no analyzer findings.
- Coverage or low-coverage notes: repository line coverage is 73.50%
  (52,001/70,747). The extracted widget reached 100.00% (299/299), while the
  page remains at 95.53% (941/985).
- Risks or follow-ups: `_LiveSmokeSummary` is the next highest-value pure
  presentation boundary. Extract its report-envelope normalization and
  immutable display model without moving live-smoke ownership, refresh state,
  report generation, or platform operations out of the page.
