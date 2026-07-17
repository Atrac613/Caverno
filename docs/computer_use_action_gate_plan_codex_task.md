# Computer Use Action Gate Plan Extraction

Status: complete on `feature/computer-use-action-gate-plan`.

## Task

- Goal: extract the existing Computer Use action gate plan from
  `computer_use_settings_page.dart` into an independently tested stateless
  widget backed by an immutable presentation view model.
- User-visible behavior: none. Row order, statuses, details, success styling,
  spacing, and fallback guidance remain unchanged.
- Non-goals: changing permission state, live-smoke ownership, helper or IPC
  behavior, runtime report construction, refresh timing, diagnostics, action
  policy, platform operations, or localization.

## Context

- Affected files or components:
  - a new `ComputerUseActionGatePlan` settings widget and view model
  - `ComputerUseSettingsPage` onboarding-card composition
  - direct view-model/widget tests, existing settings integration tests, and
    exact file-size ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 4
  - `docs/roadmap.md` F5
  - `docs/computer_use_permission_trust_panel_codex_task.md`
- Reference implementation or pattern: follow
  `ComputerUsePermissionTrustPanel`: the stateful settings page remains the
  coordinator, while a stateless widget receives presentation-only input and
  performs no service, Riverpod, platform, or lifecycle work.
- Known quirks, compatibility rules, or release gates:
  - Preserve the eight rows from Helper boundary through Unsafe arms.
  - Helper status remains `ready`, `needs launch`, or `needs IPC` based on the
    same three booleans.
  - Missing gate status remains `not run`; missing or blank `nextAction`
    retains the existing review fallback.
  - Capture uses its gate detail whenever a gate exists. Input, system audio,
    overlay, and unsafe-arm details use gate output only after a live smoke
    report exists.
  - System audio treats both `ready` and `unsupported` as positive; unsafe arms
    treats only `armed` as positive.

## Implementation Notes

- Preferred approach:
  1. Characterize the current page output for helper states, live-smoke
     fallback copy, and gate-derived details.
  2. Add immutable plan/row view models that normalize the existing derived
     booleans and gate maps without retaining mutable maps.
  3. Move only `_ComputerUseGatePlan` and `_GatePlanRow` presentation into the
     new widget file.
  4. Have the page construct the view model from its current derived values,
     then lower exact primary and extracted-widget ratchets.
- Constraints:
  - Do not pass a service, provider ref, page state object, or callback into the
    extracted widget.
  - Copy status and next-action strings into immutable row values so later map
    mutation cannot change rendered output.
  - Do not combine IPC runtime, verification, persistence, timing, or
    live-smoke diagnostic panels with this slice.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_ComputerUseGatePlan`, `_GatePlanRow`, `captureGate`,
  `inputGate`, `audioGate`, `overlaySmoke`, `unsafeActionGate`,
  `hasLiveSmokeReport`, and `Computer Use action plan`.
- Files or modules inspected: Computer Use settings page, settings page widget
  tests, permission/trust panel and tests, debug page, setup models, and current
  file-size ratchets.
- Follow-up tasks found: IPC runtime, verification, persistence, timing, and
  live-smoke panels remain independent later slices.

## Acceptance Criteria

- Required behavior:
  - the view model produces all eight rows in their current order.
  - every status, detail, and positive-state decision matches the existing
    widget for ready, blocked, missing, unsupported, armed, and not-run states.
  - the widget renders only immutable presentation rows and performs no action.
  - the settings page keeps runtime-map assembly, permission state,
    live-smoke ownership, and every helper or platform operation.
- Edge cases:
  - helper missing or stopped resolves to `needs launch`; running but
    unreachable resolves to `needs IPC`.
  - a non-string status resolves to `not run`.
  - blank and absent next actions resolve to the existing review fallback.
  - live-smoke absence preserves the four existing instructional details.
- Failure paths: no new failure handling is introduced; malformed or absent
  gate fields continue to degrade to current fallback presentation.
- Accessibility, localization, or platform expectations: preserve row labels,
  status text, Material icons, and layout. Direct tests perform no native
  Computer Use, helper, permission, IPC, or audit operation.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_action_gate_plan_test.dart \
  --test test/features/settings/presentation/pages/settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ComputerUseActionGatePlan` now renders the existing eight-row plan
  from `ComputerUseActionGatePlanViewModel`. The model eagerly copies status,
  next-action, and positive-state decisions into an unmodifiable row list, and
  the page retains every runtime map, lifecycle, permission, helper, IPC, and
  platform responsibility. The page ratchet fell from 2,995 to 2,816 lines;
  the extracted widget is ratcheted at 203 lines.
- Tests run: the focused verification gate passed 55 root tests plus 13
  internal-package tests. The full coverage gate passed 3,602 root tests plus
  13 internal-package tests with no analyzer findings.
- Coverage or low-coverage notes: repository line coverage is 73.50%
  (52,018/70,771). The extracted widget reached 100.00% (66/66), while the
  page remains at 96.10% (1,257/1,308).
- Risks or follow-ups: the remaining `_IpcRuntimeSummary` is the next coherent
  presentation boundary. Characterize its malformed-map fallbacks and extract
  a typed immutable view model without moving runtime-map assembly, refresh
  state, diagnostics ownership, or platform operations out of the page.
