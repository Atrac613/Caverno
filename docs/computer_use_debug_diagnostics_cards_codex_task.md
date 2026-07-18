# Computer Use Debug Diagnostics Cards Extraction

Status: complete on `feature/computer-use-debug-diagnostics-card`.

## Task

- Goal: move the diagnostics controls, recent audit summary, last export path,
  and last native result presentation out of `computer_use_debug_page.dart`
  behind independently importable widgets and immutable copied inputs.
- User-visible behavior: none. Card order, copy, icons, button keys and enabled
  state, audit entry order and limit, export-path visibility, selectable text,
  and monospace result presentation remain unchanged.
- Non-goals: diagnostic serialization, export or clipboard operations, smoke
  execution, audit recording or redaction, busy-state ownership, service calls,
  native Computer Use actions, or settings-page diagnostics.

## Context

- The debug image, status-primitives, and onboarding slices reduced
  `computer_use_debug_page.dart` from 2,864 to 2,275 lines.
- `_buildDiagnosticsCard()` still reads the global audit log, binds three page
  actions, applies the page busy gate, and renders the optional export path.
- `_buildResultCard()` still renders page-owned action and result strings.
- The page must retain every side effect and translate global audit data into a
  copied presentation snapshot before passing it to the extracted boundary.

## Current Behavior Contract

- The diagnostics card title is `Diagnostics`, with the existing redacted
  smoke-test subtitle and manual-smoke privacy note.
- The three tonal buttons retain their order, icons, labels, and stable keys:
  run smoke sequence, copy diagnostics, then export diagnostics.
- All three buttons are disabled while the page is busy and otherwise invoke
  exactly their supplied callback once per tap.
- The audit summary receives the copied redacted entries and shows at most the
  newest five using the existing `ComputerUseAuditLogSummary` contract.
- The last export row is absent for a null path and otherwise appears after the
  audit summary as selectable `Last export: <path>` text.
- The result card title remains `Last Native Result`; its subtitle is the last
  action and its selectable body is the last result in `kMonoFontFamily`.
- The diagnostics card remains immediately before the result card in the page.

## Implementation Notes

1. Add an immutable diagnostics view model that defensively copies the source
   audit iterable and every entry map.
2. Add `ComputerUseDebugDiagnosticsCard` with explicit callbacks and no service,
   provider, controller, or singleton dependency.
3. Add `ComputerUseDebugResultCard` with only typed presentation strings.
4. Build the view model from page state and the redacted audit snapshot, then
   replace both private page builders with thin widget construction.
5. Add direct tests for input-copy isolation, ordering, button gating and
   callbacks, empty and populated audits, export-path visibility, result copy,
   selection, and monospace styling.
6. Remove obsolete page builders and lower exact line-count ratchets.

## Constraints

- Do not move `_diagnosticsMap()`, `_diagnosticsJson()`, `_copyDiagnostics()`,
  `_exportDiagnostics()`, `_runManualSmokeSequence()`, or `_run()`.
- Do not let the extracted widgets import Riverpod, Computer Use services,
  audit-log services, clipboard APIs, filesystem exporters, or page types.
- Do not retain mutable audit lists or maps supplied by the page.
- Do not change visible English copy, audit redaction, action order, page state,
  result formatting, card spacing, or native behavior.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildDiagnosticsCard`, `_buildResultCard`,
  `ComputerUseAuditLogSummary`, `_lastDiagnosticExportPath`, `_lastAction`,
  `_lastResult`, and `kMonoFontFamily`.
- Files inspected: the debug page, audit log and summary, existing debug widget
  boundaries and tests, page product tests, line-count ratchets, refactoring
  plan, roadmap, and active worktrees.
- Follow-up tasks found: the settings page owns a separate diagnostics surface;
  it remains out of scope until this debug-page slice is complete.

## Acceptance Criteria

- Both widgets are independently importable and directly tested without a
  provider scope, native service, platform permission, clipboard, or file IO.
- The diagnostics view model exposes an unmodifiable list of unmodifiable audit
  maps and does not observe later source mutations.
- Product-path page tests retain audit rendering, export feedback, manual-smoke
  safety copy, and last-result behavior.
- Direct tests cover enabled and busy actions, null and non-null export paths,
  empty and populated audit snapshots, and result presentation.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_diagnostics_cards_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ComputerUseDebugDiagnosticsCard` now owns the manual-smoke safety
  copy, ordered diagnostic actions, copied audit presentation, and optional
  export path. `ComputerUseDebugResultCard` owns the last native action and
  selectable monospace result. The page retains all side effects, state,
  serialization, audit access, and native operations.
- Size: `computer_use_debug_page.dart` fell from 2,275 to 2,198 lines. The new
  independently importable boundary is ratcheted at 149 lines.
- Tests run: the focused verifier passed 74 root tests plus 13 internal-package
  tests. The full repository gate passed analysis, 3,798 root tests, and 13
  internal-package tests without real Computer Use actions.
- Coverage or low-coverage notes: repository line coverage is 74.00%
  (54,008/72,988). The new boundary reached 100.00% (40/40), while the
  remaining debug page reached 92.49% (936/1,012).
- Risks or follow-ups: audit maps are copied one level because the existing
  summary only reads top-level fields. The next unowned pure action-control
  candidate is the audio card; characterize its arming and recording-state
  transitions before moving it.
