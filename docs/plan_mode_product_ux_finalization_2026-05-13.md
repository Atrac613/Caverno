# Plan Mode Product UX Finalization - 2026-05-13

PM15 closes the remaining product UX review warning from the release candidate
rerun. The review focused on whether a user can understand Plan Mode status
from the product UI without reading harness logs.

## Review Method

- Reviewed the timeline plan card for saved plan, draft approval, generation,
  edit, cancel, and approved-plan continuity states.
- Reviewed task-row UI for pending, running, blocked, failed validation,
  retry, replan, and completed states.
- Reviewed compact footer and review sheet coverage so the chat timeline and
  approval surfaces stay consistent.
- Checked existing release candidate evidence from PM14 for completed live
  smoke, Ping CLI canary, README canary, and saved-validation convergence.

## Findings

| Surface | Result |
|---------|--------|
| Saved plan approval | Improved. Invalid drafts now explain the approval blocker directly in the timeline card. |
| Task progress | Pass. Task rows expose status, validation, target files, and next-step copy. |
| Blocked states | Pass. Blocked tasks show blocker details and recovery actions. |
| Recovery and retries | Pass. Failed validation exposes retry and replan actions instead of requiring log inspection. |
| Completion continuity | Pass. Completed tasks show terminal next-step copy and the approved plan can remain collapsed or expanded without stale status. |

## Change Applied

Invalid draft plan documents previously removed the approve action without
explaining why. The timeline plan card now renders the existing approval
blocker copy with the validation error, for example:

`Cannot approve this plan yet: plan document must include a Tasks section`

This keeps the product behavior separate from harness logs and makes the next
available action clear: edit the plan or wait for generation to finish.

## Verification

- `fvm flutter test test/features/chat/presentation/widgets/plan/timeline_plan_card_test.dart test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart test/features/chat/presentation/widgets/plan/compact_plan_footer_card_test.dart test/features/chat/presentation/widgets/plan/plan_review_sheet_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

## Decision

PM15 is complete. The Plan Mode release candidate UX warning is closed from a
product UI perspective, with PM16 carrying the remaining settings and
compatibility guidance work.
