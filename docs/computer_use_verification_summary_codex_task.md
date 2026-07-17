# Computer Use Verification Summary Extraction

Status: complete on `feature/computer-use-verification-summary`.

## Task

- Goal: extract the existing Computer Use onboarding verification summary from
  `computer_use_settings_page.dart` into an independently tested stateless
  widget backed by an immutable typed presentation view model.
- User-visible behavior: none. Visibility, heading fallback and interpolation,
  step-list presence, step filtering and order, label and status fallbacks,
  status-chip semantics, icons, wrapping, and spacing remain unchanged.
- Non-goals: changing onboarding verification, helper-status lookup
  precedence, refresh state, helper lifecycle, diagnostics export, permission
  recovery, persistence presentation, or platform operations.

## Context

- Affected files or components:
  - a new `ComputerUseVerificationSummary` widget and immutable presentation
    values for its heading, step-list presence, and ordered status rows
  - `ComputerUseSettingsPage` diagnostics composition
  - direct view-model/widget tests, existing settings integration tests, and
    exact file-size ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 4
  - `docs/roadmap.md` F5
  - `docs/computer_use_persistence_summary_codex_task.md`
- Reference implementation or pattern: follow the persistence and XPC timing
  extractions. The page owns verification lookup precedence, visibility,
  refresh, helper lifecycle, and platform state; the extracted boundary eagerly
  copies presentation values and performs no service, Riverpod, lifecycle, or
  action work.
- Known quirks, compatibility rules, or release gates:
  - the page renders this summary only when `_onboardingVerification()` returns
    a map; this visibility and three-source lookup decision remains in the
    page.
  - any non-null `summary` value wins and is string-interpolated without a type
    or empty-string check.
  - without a summary, a string `generatedAt`, including an empty string, is
    used; otherwise the heading falls back to `Unknown`.
  - step presentation appears only when `steps` is a list. An empty list or a
    list containing no maps still retains the existing six-pixel step-section
    spacing and empty wrap.
  - only map entries in the step list produce chips, in list order.
  - a step label uses the first non-null value from `label`, `id`, and `Step`,
    with direct string interpolation.
  - only `ok: true` renders Done. Other values use the first non-null value from
    `status` and `Failed`, with direct string interpolation.

## Implementation Notes

- Preferred approach:
  1. Characterize heading precedence, malformed and empty scalar values,
     step-list presence, map filtering and order, label and status fallbacks,
     exact-true success, and source mutation isolation.
  2. Add immutable summary and status-row values that eagerly copy the source
     map, nested list, and step maps without retaining mutable inputs.
  3. Move only `_VerificationSummary` presentation and normalization into the
     new widget file.
  4. Have the page construct the view model from its existing verification map,
     then lower exact primary and extracted-widget ratchets.
- Constraints:
  - Do not pass a service, provider ref, page state object, callback, or source
    map into the extracted widget.
  - Do not move `_onboardingVerification`, lookup precedence, visibility,
    refresh behavior, diagnostics assembly, helper lifecycle, permission
    recovery, or platform operations out of the page.
  - Do not combine shared status-chip cleanup or another diagnostics section
    with this slice.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_VerificationSummary`, `_StatusChip`,
  `_onboardingVerification`, `onboardingVerification`, `generatedAt`, `steps`,
  `Last Verify`, and `Done`.
- Files or modules inspected: Computer Use settings page, settings and debug
  page tests, onboarding diagnostics fixtures, persistence and XPC timing
  widgets and tests, current roadmap, and file-size ratchets.
- Follow-up tasks found: after this final small settings diagnostics summary,
  refresh the large-file inventory before choosing a debug-page or ChatPage
  tranche.

## Acceptance Criteria

- Required behavior:
  - the view model produces the heading, step-list presence, and ordered status
    rows with identical fallback decisions and copy.
  - non-map steps are skipped without changing the order of map steps.
  - the view model retains no source map, nested list, step map, or mutable row
    list.
  - the widget renders only immutable presentation values and performs no
    action.
  - the settings page keeps verification lookup and visibility, refresh state,
    helper lifecycle, diagnostics generation, permission recovery, and every
    platform operation.
- Edge cases:
  - a non-null non-string or empty summary retains direct interpolation.
  - a missing summary uses any string generated time, including empty; a
    non-string or missing generated time uses `Unknown`.
  - absent or non-list steps omit the step section, while an empty list retains
    the empty step section.
  - absent, non-map, and malformed step values preserve existing filtering and
    fallbacks.
  - source-map, nested-list, or step-map mutation after construction cannot
    change rendered values.
- Failure paths: no new failure handling is introduced; malformed or absent
  fields continue to degrade through the existing presentation rules.
- Accessibility, localization, or platform expectations: preserve Material
  status icons, theme colors, text, wrapping, and layout. Direct tests perform
  no native Computer Use, helper, permission, IPC, file, or smoke action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_verification_summary_test.dart \
  --test test/features/settings/presentation/pages/settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted verification normalization and presentation into
  `ComputerUseVerificationSummaryViewModel` and
  `ComputerUseVerificationSummary`. The settings page retains verification
  lookup precedence and visibility, refresh state, diagnostics generation,
  permission recovery, helper lifecycle, and every platform action. Its exact
  ratchet fell from 1,759 to 1,725 lines, and the new widget is independently
  ratcheted at 107 lines.
- Tests run: the focused verifier passed 62 root tests plus 13
  internal-package tests. The full coverage verifier passed 3,638 root tests
  plus 13 internal-package tests with no analyzer findings.
- Coverage or low-coverage notes: full repository line coverage was 73.53%
  (52,050/70,786). The new verification-summary widget reached 100.00% line
  coverage (38/38), and the remaining settings page reached 95.22% (697/732).
- Risks or follow-ups: keep verification and platform ownership in the page.
  Refresh the large-file inventory before selecting the next tranche, with
  ChatPage plan-review and approval actions as the current preferred candidate.
