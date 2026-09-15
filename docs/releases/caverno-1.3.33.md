# Caverno v1.3.33

> Release date: 2026-09-15

## Summary

Apple Watch remote project and thread browsing, Anabasis plan-mode acceptance and worktree delegation improvements, macOS deployment target fix, and numerous plan-mode robustness fixes.

## Changes

### Features

- **Apple Watch remote browsing** — Added remote project and thread browsing on Apple Watch, enabling users to view coding projects and chat threads from their wrist.
- **Plan task panel: blocked/accepted status** — The plan execution panel now shows why a task is blocked and what evidence accepted it, giving users visibility into task state transitions.
- **Waiting-on-user indicator** — Shows what is waiting on the user in the panel, where the user is already looking, regardless of whether a project is open.
- **Acceptance evidence display** — Shows what an acceptance was made on, beside the chip that claims it, and tells the next turn what an acceptance was made on.
- **Parent judgement turn** — Gives the Anabasis parent a dedicated turn whose only move is to record its judgement on delegated children.
- **Worktree delegation** — The parent can now delegate to a worktree child, read it back, see it in the queue, and accept on its evidence.
- **Produced / Verified / Accepted distinction (ANA3 PR 3)** — Plan task rows now distinguish between produced, verified, and accepted states.
- **Three-way canary verdict (ANA2)** — Closed ANA2's evidence gap and made the canary's verdict three-way (pass / fail / inconclusive).
- **Anabasis canary chaining** — Chained the plan and the parent turn into one Anabasis canary for end-to-end verification.

### Fixes

- **macOS deployment target** — Raised macOS deployment target to 12.
- **Plan-mode run budget** — Counted every follow-up turn in the plan-mode run budget to prevent unbounded execution.
- **Policy refusal handling** — Stopped a policy refusal from ending the turn that could act on it, and stopped reporting a policy refusal as an approval prompt.
- **Database close on quit** — Stopped a stuck database close from silently vetoing quit.
- **Worktree branch isolation** — Enforced one branch per saved task at a time; a worktree child owes no changed files where its task named none.
- **Planner validation commands** — Stopped the planner from writing validation commands nothing will run.
- **Unknown child id** — Answered an unknown child id with the ids that exist instead of failing silently.
- **Foreground child recording** — Recorded a foreground child so its acceptance can find it.
- **Parent bookkeeping tools** — Let the Anabasis parent run its own bookkeeping tools.
- **Knowledge-cutoff rules** — Gave the knowledge-cutoff rules a date they can point at.
- **Prompt budget measurement** — Measured the prompt budget against what the endpoint charges.
- **Contradiction policy** — Gave ANA2's contradiction policy the caller it never had.
- **Assumption edge handling** — Turned an unsatisfiable assumption edge into the question it reads like.
- **Open question counting** — Counted an open question nobody has opened yet.
- **Acceptance readout** — Stopped the acceptance readout from aborting its own verdict.
- **Delegation queue** — Stopped a parent turn from claiming the task it should delegate.

### Refactors

- **Plan execution overview extraction** — Moved the plan execution overview out of the chat_page library.
- **Notification body extraction** — Gave the notification body to the class that describes it.
- **get_subagent_result payload extraction** — Extracted the get_subagent_result payloads into a dedicated module.
- **Acceptance decision extraction** — Extracted the acceptance decision from the notifier.
- **Progress writer budget** — Gave the progress writers a file with its own budget.

### Testing

- **Worktree scenario** — Gave the worktree route a scenario it can run in, and gave the worktree parent time to finish judging.
- **Acceptance question coverage** — Gave the acceptance question work that can actually be finished; asked the parent directly whether it accepts in its own turn.
- **Delegation queue measurement** — Measured the delegation queue on the way out of the follow-up turn.
- **Plan assumptions** — Confirmed the plan's assumptions, the fourth thing a ready queue needs.
- **Elicitation distinction** — Told an elicitation that was declined from one that never happened.

### Documentation

- **Apple Watch plan** — Planned remote project browsing and voice threads on Watch.
- **ANA3/ANA4 roadmap** — Reorganized roadmap index and milestone evidence; separated Anabasis project vision from ANA4; moved ANA4 into progress.
- **Worktree findings** — Recorded the six worktree findings and what is proven live; recorded the worktree dispatch where the limit was written down.
- **Acceptance evidence** — Recorded the acceptance observed live; recorded the last two acceptance blocks; added the third acceptance block.
- **Canary coverage** — Put the Anabasis canaries in the coverage table; recorded the delegation refusal the canary measured.

## Version

- `1.3.33+46`

## Notes

This release introduces Apple Watch support for remote project and thread browsing, significantly improves the Anabasis plan-mode acceptance and worktree delegation pipeline (ANA2/ANA3), and fixes numerous plan-mode robustness issues including run budget enforcement, policy refusal handling, and database close on quit.
