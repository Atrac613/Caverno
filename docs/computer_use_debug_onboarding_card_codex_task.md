# Computer Use Debug Onboarding Card Extraction

Status: complete on `feature/computer-use-debug-onboarding-card`.

## Task

- Goal: move the onboarding checklist card out of
  `computer_use_debug_page.dart` behind a typed immutable view model and an
  independently importable widget.
- User-visible behavior: none. Progress, step order, next-step guidance, XPC
  ready or blocker notes, icons, copy, spacing, and card presentation remain
  unchanged.
- Non-goals: checklist state calculation, permission and helper state,
  screenshot state, smoke execution, diagnostic serialization, XPC protocol
  ownership, service calls, or any real Computer Use action.

## Context

- The status-primitives slice reduced the debug page from 2,721 to 2,322 lines
  and made the onboarding row components independently testable.
- `_buildOnboardingChecklistCard()` still normalizes ten mutable checklist maps,
  calculates progress and the first incomplete step, reads XPC runtime values,
  and composes the card in the page.
- The page must continue to own the source maps because the same checklist is
  serialized into diagnostics. The extracted view model receives typed copied
  steps, blocker strings, and the next-action string only.

## Current Behavior Contract

- Steps retain input order. A step is complete only when its source value is
  exactly true.
- Completed count is the number of complete typed steps; total is the copied
  step count.
- The subtitle is `All onboarding checks are complete.` when no incomplete step
  exists. Otherwise it is `Next: <first incomplete label>`.
- Progress delegates the completed and total counts to the existing onboarding
  progress primitive, including zero-total behavior.
- Every step delegates its label and completion state to the existing step-row
  primitive.
- An empty blocker list shows one verified note titled `XPC Production Ready`
  with the caller-supplied next action.
- A non-empty blocker list shows `XPC Production Blocker` with blockers joined
  by comma and space, followed by `XPC Next Action` with the caller-supplied
  next action.
- The card keeps 16-pixel padding, 12-pixel gaps around progress and notes, and
  an eight-pixel gap between blocker and next-action notes.

## Implementation Notes

1. Add immutable `ComputerUseDebugOnboardingStep` and
   `ComputerUseDebugOnboardingViewModel` types that defensively copy input
   iterables.
2. Add `ComputerUseDebugOnboardingCard`, composed only from the existing debug
   status primitives and typed view-model fields.
3. Convert checklist maps and `MacosComputerUseIpc.current` fields into the
   typed view model inside the page.
4. Add direct widget tests for incomplete, complete, empty, and blocked states,
   source-copy isolation, ordering, progress, icons, and exact copy.
5. Remove the obsolete page builder and lower exact line-count ratchets.

## Constraints

- Do not pass maps, `WidgetRef`, providers, page state, controllers, services,
  or native result objects into the extracted boundary.
- Do not move `_onboardingSmokeChecklist()` because diagnostics still consume
  its map representation.
- Do not make the widget read `MacosComputerUseIpc.current`; protocol values are
  translated by the page.
- Do not change checklist labels, diagnostic payloads, progress semantics,
  visible copy, icon choices, card layout, or XPC ready/blocker precedence.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildOnboardingChecklistCard`,
  `_onboardingSmokeChecklist`, `xpcProductionBlockers`,
  `xpcProductionNextAction`, `ComputerUseDebugOnboardingProgressRow`, and
  `ComputerUseDebugOnboardingNote`.
- Files inspected: the debug page, status-primitives boundary, page product
  tests, macOS Computer Use setup contract, diagnostics assembly, line-count
  ratchets, active worktrees, refactoring plan, and ROADMAP.
- Adjacent work deliberately excluded: permissions card, screenshot cards,
  smoke actions, diagnostics data, and network tool implementation.

## Acceptance Criteria

- The extracted widget and view model are independently importable and directly
  tested without a provider scope or native Computer Use service.
- The view model retains no mutable input list and exposes an unmodifiable step
  and blocker snapshot.
- Product-path tests retain the existing 2-of-10 onboarding state and XPC ready
  copy without changing service-call assertions.
- Direct tests cover ready, blocked, complete, incomplete, and zero-step paths.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_onboarding_card_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ComputerUseDebugOnboardingCard` now owns checklist progress, ordered
  step presentation, next-step guidance, and XPC ready or blocker notes behind
  copied typed steps and blockers. The debug page retains checklist-state
  calculation, diagnostic maps, protocol translation, and every native action.
- Size: `computer_use_debug_page.dart` fell from 2,322 to 2,275 lines. The new
  independently importable onboarding boundary is ratcheted at 94 lines.
- Tests run: the focused verifier passed 69 root tests plus 13 internal-package
  tests. The full repository gate passed 3,771 root tests plus 13 package tests
  with analyzer checks clean and no real Computer Use actions.
- Coverage: repository line coverage is 74.13% (52,576/70,925). The extracted
  boundary reached 100.00% (32/32), while the remaining debug page is at 92.65%
  (958/1,034).
- Risks or follow-ups: the refreshed inventory leaves `network_tools.dart` as
  the next explicitly tracked non-overlapping large-file candidate. Its 39.31%
  coverage and platform side effects require characterization and injectable
  boundaries before moving behavior.
