# Computer Use Persistence Summary Extraction

Status: complete on `feature/computer-use-persistence-summary`.

## Task

- Goal: extract the existing Computer Use helper persistence summary from
  `computer_use_settings_page.dart` into an independently tested stateless
  widget backed by an immutable typed presentation view model.
- User-visible behavior: none. Timestamp fallback, active-work filtering and
  order, saved-verification states, status-chip order and semantics, detail
  copy, icons, wrapping, and spacing remain unchanged.
- Non-goals: changing helper persistence, saved-state lookup precedence,
  onboarding verification, refresh state, helper lifecycle, diagnostics
  export, or platform operations.

## Context

- Affected files or components:
  - a new `ComputerUsePersistenceSummary` widget and immutable presentation
    values for its heading, two status rows, and active-work detail
  - `ComputerUseSettingsPage` diagnostics composition
  - direct view-model/widget tests, existing settings integration tests, and
    exact file-size ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 4
  - `docs/roadmap.md` F5
  - `docs/computer_use_xpc_timing_summary_codex_task.md`
- Reference implementation or pattern: follow the XPC timing and live-smoke
  extractions. The page owns persistence lookup, visibility, refresh, helper
  lifecycle, and platform state; the extracted boundary eagerly copies
  presentation values and performs no service, Riverpod, lifecycle, or action
  work.
- Known quirks, compatibility rules, or release gates:
  - the page renders this summary only when `_helperStatusPersistence()`
    returns a map; this visibility and lookup decision remains in the page.
  - a non-string timestamp renders `Unknown`, while any string, including an
    empty string, retains the existing direct interpolation behavior.
  - active work accepts only a map and includes only entries whose value is
    exactly `true`; labels stringify keys and retain map insertion order.
  - Saved Work and Saved Verify always render in that order.
  - any verification map, including an empty map, counts as saved; only
    `ok: true` renders Passed.

## Implementation Notes

- Preferred approach:
  1. Characterize timestamp handling, active-work filtering and ordering,
     verification presence and success, malformed nested values, and source
     mutation isolation.
  2. Add immutable summary and status-row values that eagerly copy the source
     map without retaining it or nested maps.
  3. Move only `_PersistenceSummary` presentation and normalization into the
     new widget file.
  4. Have the page construct the view model from its existing persistence map,
     then lower exact primary and extracted-widget ratchets.
- Constraints:
  - Do not pass a service, provider ref, page state object, callback, or source
    map into the extracted widget.
  - Do not move `_helperStatusPersistence`, lookup precedence, visibility,
    refresh behavior, diagnostics assembly, helper lifecycle, or platform
    operations out of the page.
  - Do not combine the verification summary with this slice.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_PersistenceSummary`, `_StatusChip`,
  `helperStatusPersistence`, `activeWork`, `onboardingVerification`,
  `Saved Work`, `Saved Verify`, and `Saved active work`.
- Files or modules inspected: Computer Use settings page, settings and debug
  page tests, helper persistence fixtures, XPC timing and live-smoke widgets
  and tests, current roadmap, and file-size ratchets.
- Follow-up tasks found: the verification summary remains the final small
  diagnostics-summary extraction in this Phase 4 sequence.

## Acceptance Criteria

- Required behavior:
  - the view model produces the heading, two status rows, and active-work detail
    with identical decisions and copy.
  - active-work labels retain source insertion order and exact key
    stringification.
  - the view model retains no source map, nested map, or mutable list.
  - the widget renders only immutable presentation values and performs no
    action.
  - the settings page keeps persistence lookup and visibility, refresh state,
    helper lifecycle, diagnostics generation, and every platform operation.
- Edge cases:
  - a non-map active-work value behaves as no active work.
  - non-true active-work values are ignored.
  - an absent or non-map verification renders Not saved; an empty or failed
    verification map renders Needs attention.
  - a non-string timestamp renders Unknown, while an empty string remains
    empty after the existing label prefix.
  - source-map or nested-map mutation after construction cannot change the
    rendered values.
- Failure paths: no new failure handling is introduced; malformed or absent
  fields continue to degrade through the existing presentation rules.
- Accessibility, localization, or platform expectations: preserve Material
  status icons, theme colors, text, wrapping, and layout. Direct tests perform
  no native Computer Use, helper, permission, IPC, file, or smoke action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_persistence_summary_test.dart \
  --test test/features/settings/presentation/pages/settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted persistence normalization and presentation into
  `ComputerUsePersistenceSummaryViewModel` and
  `ComputerUsePersistenceSummary`. The settings page retains persistence
  lookup precedence and visibility, refresh state, diagnostics generation,
  helper lifecycle, and every platform action. Its exact ratchet fell from
  1,811 to 1,759 lines, and the new widget is independently ratcheted at 124
  lines.
- Tests run: the focused verifier passed 60 root tests plus 13
  internal-package tests. The full coverage verifier passed 3,630 root tests
  plus 13 internal-package tests with no analyzer findings.
- Coverage or low-coverage notes: full repository line coverage was 73.52%
  (52,031/70,767). The new persistence-summary widget reached 100.00% line
  coverage (42/42), and the remaining settings page reached 95.34% (716/751).
- Risks or follow-ups: keep persistence and platform ownership in the page.
  Extract the smaller verification summary next as a separate
  behavior-preserving slice.
