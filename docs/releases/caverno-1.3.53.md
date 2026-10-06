# Caverno v1.3.53

> Release date: 2026-09-26

## Summary

The project farm track lands: a project dashboard with a Start work button,
a cross-project overview that proposes each project's next step, and
background work on worktree agents with a run ledger. Alongside it, shell
approval is trimmed for read-only git segments and `;` chains, and several
chat fixes keep carry metadata and background job state honest.

## Changes

### Features

- **Project dashboard with a Start work button** — A per-project dashboard
  shows the project's state and lets the user start work from it.
  (`lib/features/chat/`)
- **Roadmap snapshot service** — The dashboard reads a measured roadmap
  snapshot instead of re-parsing the roadmap file on every build.
- **Model reads project and thread state** — The model can now read project
  and thread state as part of its context.
- **Start a roadmap task from chat** — The model can start a roadmap task
  directly from a chat message.
- **Cross-project overview for the project farm** — A single overview lists
  every project in the farm and its current state.
- **Propose each project's next step** — The overview proposes the next step
  for each project.
- **Flag out-of-date proposals** — Proposals that no longer match the
  project's state are flagged as out of date.
- **Declare a project's background-work policy** — The user can declare
  whether a project allows background work.
- **Run a proposed task in the background on a worktree agent** — A proposed
  task can be run in the background on a worktree agent instead of blocking
  the chat.
- **Cancel a project's background task from the overview** — A running
  background task can be cancelled from the overview.
- **Pin a project's next task and choose its roadmap file** — The user can
  pin the next task and choose which roadmap file the project follows.
- **Advance opted-in projects during idle maintenance** — Opted-in projects
  advance during idle maintenance windows.
- **Unattended-run settings and a run ledger for FARM5** — Settings for
  unattended runs and a ledger that records each run.
- **Page the dashboard's thread list** — The dashboard's thread list is now
  paginated.
- **Show roadmap progress beside threads on the dashboard** — Roadmap
  progress is shown next to the thread list.

### Fixes

- **Make a worktree-agent cancel stop the run and stick** — Cancelling a
  worktree-agent run now actually stops it and the cancellation persists.
- **Read background job state from the outcome, not the budgeted payload** —
  Background job state is read from the outcome so it is not lost when the
  payload is budgeted down.
- **Read only future forms of check as a coding continuation** — Only future
  forms of "check" are read as a coding continuation, not past or present
  forms.
- **Keep carry metadata through prompt budgeting** — Carry metadata survives
  prompt budgeting instead of being dropped.
- **Run `;` chains and a trailing head/tail without a shell** — `;` chains
  and a trailing `head`/`tail` are now handled without spawning a shell.
- **Run read-only git segments through GitTools without a shell** — Read-only
  git segments in a chain are routed through GitTools instead of the shell,
  so they no longer require shell approval.

### Refactors

- **Bring four files back under their size ratchets** — Four files that had
  grown past their size ratchets are split back under the limit.
- **Move the measured roadmap extraction contract into lib** — The measured
  roadmap extraction contract moves from test support into `lib`.
- **Split the dashboard's roadmap and thread cards evenly** — The dashboard
  lays out its roadmap and thread cards with even spacing.

### Testing

- **Add a live probe for FARM2 workspace tool selection** — A live probe
  verifies workspace tool selection for FARM2.
- **Prove two projects' background tasks do not cross** — A test proves that
  background tasks from two different projects do not interfere with each
  other.

### Documentation

- **Add the project farm track and record the FARM0 spikes** — The project
  farm track is added to the roadmap and the FARM0 spikes are recorded.
- **File the completed FARM milestones and refresh the roadmap** — Completed
  FARM milestones are filed and the roadmap is refreshed.
- **Record background runs in the LL13 registry, not the approval audit** —
  Background runs are recorded in the LL13 registry instead of the approval
  audit trail.
- **Add the project farm lesson to FOR_ME.md** — The project farm lesson is
  recorded in FOR_ME.md.

## Version

- `1.3.53+67` (proposed)

## Notes

- The previous tag `1.3.52+66` exists on the `feature/farm0-design` branch
  and is not on `main`; this release skips to `1.3.53+67` to avoid a tag
  collision.