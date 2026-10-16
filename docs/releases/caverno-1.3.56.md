# Caverno v1.3.56

> Release date: 2026-10-16

## Summary

A roadmap and headless execution release: Caverno gains `caverno farm`, a
headless runner that executes roadmap tasks end to end with automatic review,
verification repair, and commit handling. The tool loop keeps its final answer
by default, session logs label every kind of request, and a large batch of
fixes hardens verification evidence, prompt budgeting, and coding-task
recovery.

## Changes

### Features

- **Add `caverno farm` to run a roadmap task headless** — Roadmap tasks can
  now run unattended: the farm hosts the Remote Coding server, breaks the
  task into subtasks, reviews the result, repairs verification failures, and
  commits the reviewed task with its roadmap item checked off.
- **Resume a stopped roadmap task from where it stopped** — A stopped task
  resumes from its saved thread and git state instead of starting over.
- **Review started roadmap tasks automatically** — Started tasks are reviewed
  without manual prompting, and upcoming tasks are shown in priority order
  with next-task suggestions.
- **Keep the tool loop's final answer by default** — The loop's own final
  answer is kept instead of being dropped, with an opt-in setting to change
  the behavior.
- **Label every request kind in session logs** — Routine, approval review,
  memory, planning, farm, and worktree agent requests are labeled in session
  logs, and each request records which system prompt sections it carried.
- **Fingerprint request envelopes and report prompt-cache breaks** — Request
  envelopes are fingerprinted so prompt-cache breaks are reported.
- **Scale the tool-result budget with the route's context window** — The
  tool-result budget is sized by the routed model's learned context window.
- **Show per-conversation work time in the companion sidebar** — The
  companion sidebar shows the work time spent per conversation.
- **Workspace containment for foreground Bash commands** — Foreground Bash
  commands run contained to the coding workspace.
- **Isolate CLI preferences under `--data-dir`** — CLI preferences are
  isolated per `--data-dir`.
- **Let a terminal prompt yield to an answer from another device** — A
  terminal prompt can be answered from another device.

### Fixes

- **Keep productive tool loops from ending mid-work** — Productive loops at
  the tool limit get an extended budget, and reasoning-only stops are
  recovered after tool progress.
- **Ground coding task completion in execution evidence** — Completion
  claims are judged on visible execution evidence; captured writes,
  verification results, and task-file patches settle status instead of
  stopping the loop.
- **Harden verification evidence and local command gating** — Verification
  evidence is reconciled across pytest verbosity, tail wrappers, and
  environment lookups; masked command chains settle once any verification
  passes.
- **Bound worktree verification repair** — Verification repair is bounded,
  and unattended maintenance is rechecked and cancelled on foreground
  return.
- **Keep the newest single-file diff whole in the prompt budget** — The
  prompt budget fills smallest first, keeps the newest diff whole, and drops
  reads another read of the same file covers.
- **Keep CLI exit codes and JSON output accurate** — CLI exit codes and JSON
  output stay accurate, including for zero-exit artifact errors.
- **Keep Approve on screen for a long command on the phone** — The approval
  prompt stays visible for long commands on the phone and shows the exact
  command.
- **Recover incomplete farm reviews with current inspections** — Farm
  reviews are recovered with fresh inspections, require file evidence, and
  review the task's net change instead of stacked turn patches.
- **Isolate Farm commit phases and bound idle recovery** — Farm commit
  phases are isolated, require native preparation, and verify roadmap edits
  before completion.
- **Treat past conversation transcripts as untrusted evidence** — Past
  transcripts are treated as untrusted evidence, and symlinks are resolved
  before a worktree agent mutates a path.
- **Classify LLM request failures by type instead of error text** — Request
  failures are classified by type, and storage failures stay diagnosable
  outside the auth error path.
- **Recover complete memory JSON with a missing root brace** — Memory JSON
  with a missing root brace is recovered.
- **Preserve heredoc transcripts in content parsing** — Heredoc transcripts
  survive content parsing, and the content-tool fallback stays on an empty
  continuation.
- **Let contained commands run git through the Xcode shim** — Contained
  commands can run git through the Xcode shim, and seatbelt reports are told
  apart from no outside writes.
- **Disarm the browser pane when its WebView never mounts** — The browser
  pane is disarmed when its WebView never mounts, and personal eval replays
  stay off the browser and desktop.

### Tooling

- **Restore shared checks for dependency pull requests** — Shared checks run
  again on dependency pull requests, and CI release rehearsals and shallow
  RAG2 checkouts are unblocked.
- **Add bounded repair for project verification failures** — Project
  verification failures get bounded repair.

### Documentation

- **Record the first live `caverno farm` runs** — The first live farm runs
  are recorded.

## Version

- `1.3.56+70` (proposed)
