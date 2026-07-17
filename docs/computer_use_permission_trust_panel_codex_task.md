# Computer Use Permission And Trust Panel Extraction

Status: complete on `feature/computer-use-permission-trust-panel`, stacked
on `feature/mcp-computer-use-tool-handler`.

## Task

- Goal: extract the existing Computer Use permission-flow and recovery-guidance
  presentation from `computer_use_settings_page.dart` into one independently
  tested stateless widget with explicit data and callback inputs.
- User-visible behavior: none. Labels, status colors, button visibility,
  callback behavior, spacing, ordering, and recovery details remain unchanged.
- Non-goals: changing permission requests, System Settings navigation, helper
  lifecycle, refresh timing, onboarding state, diagnostics, audit behavior,
  service contracts, localization, or Computer Use safety policy.

## Context

- Affected files or components:
  - a new `ComputerUsePermissionTrustPanel` under settings widgets
  - `ComputerUseSettingsPage` onboarding-card composition
  - direct panel tests, existing settings integration tests, and file-size
    ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 4
  - `docs/roadmap.md` F5
  - `docs/mcp_computer_use_tool_handler_codex_task.md`
- Reference implementation or pattern: keep the stateful
  `_ComputerUseOnboardingCardState` as the coordinator. Pass its derived grant
  booleans, loading state, recovery summary, and existing callbacks into a
  stateless presentation boundary.
- Known quirks, compatibility rules, or release gates:
  - Accessibility and Screen & System Audio Recording retain separate action
    keys and callbacks.
  - Granted rows show `Done` and do not expose their open action.
  - Missing rows expose their existing open action and all rows expose
    `Recheck` unless loading disables interaction.
  - Recovery guidance preserves missing, revoked, stale diagnostics, helper
    path mismatch, reachability, permission-owner, and next-action rows.

## Implementation Notes

- Preferred approach:
  1. Add direct widget characterization for missing and granted states,
     callback routing, loading disablement, and detailed recovery output.
  2. Introduce a single stateless panel that composes private flow and recovery
     rows in the same order and spacing as the current page.
  3. Replace only the two existing page-local summaries with the new panel.
  4. Remove the moved private widgets and lower exact line-count ratchets.
- Constraints:
  - Keep every async operation and mutable field in the page coordinator.
  - Do not pass `MacosComputerUseService`, Riverpod refs, or raw permission JSON
    into the extracted widget.
  - Do not add new permission prompts, helper actions, platform calls, or audit
    reads to direct widget tests.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_PermissionFlowSummary`, `_PermissionFlowRow`,
  `_PermissionRecoverySummary`, `_RecoveryDetailRow`,
  `MacosComputerUsePermissionRecoverySummary`, `Permission flow`, and
  `Recovery guidance`.
- Files or modules inspected: Computer Use settings page, settings page widget
  tests, Computer Use setup summary model, debug page, and current file-size
  ratchets.
- Follow-up tasks found: gate-plan, IPC runtime, verification, persistence,
  timing, and live-smoke panels remain separate later slices and must not be
  combined with this extraction.

## Acceptance Criteria

- Required behavior:
  - the panel renders permission flow before recovery guidance.
  - missing and granted rows retain exact labels, copy, button visibility, and
    status icons.
  - Accessibility, Screen Recording, and Recheck callbacks remain distinct and
    route exactly once per interaction.
  - recovery rows retain conditional visibility and exact field values.
  - the settings page passes derived values and callbacks without moving
    mutable state or service calls.
- Edge cases:
  - loading disables every open and recheck action.
  - a ready recovery summary shows the ready status while retaining permission
    owner and next-action details.
  - multiple missing or revoked permissions remain comma-separated in source
    order.
- Failure paths: no new failure handling is introduced; the page coordinator
  continues to own service failures and refresh state.
- Accessibility, localization, or platform expectations: preserve semantic
  button labels, existing English copy, Material layout behavior, and desktop
  platform boundaries. Direct tests perform no real Computer Use action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_permission_trust_panel_test.dart \
  --test test/features/settings/presentation/pages/settings_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ComputerUsePermissionTrustPanel` now owns the ordered permission
  flow and recovery guidance presentation behind derived grant flags, a
  loading flag, a typed recovery summary, and three explicit callbacks.
  `computer_use_settings_page.dart` fell from 3,270 to 2,995 lines, and the new
  318-line widget has its own exact ratchet.
- Tests run: the focused verifier passed 53 root tests plus 13
  internal-package tests. The full verifier passed 3,595 root tests plus 13
  internal-package tests.
- Coverage or low-coverage notes: final line coverage was 73.16% overall. The
  new panel reached 100.00% (126/126), while the remaining Computer Use
  settings page reached 96.30% (1,326/1,377).
- Risks or follow-ups: all permission, helper, System Settings, audit,
  diagnostics, lifecycle, and refresh side effects remain in the page
  coordinator. Direct widget tests used typed synthetic summaries and performed
  no native Computer Use action. Keep gate-plan, IPC runtime, verification,
  persistence, timing, and live-smoke presentation as separate follow-up
  slices.
