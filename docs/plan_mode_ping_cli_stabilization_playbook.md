# Plan Mode Ping CLI Stabilization Playbook

This document captures the working notes, recurring failure patterns, and
repair workflow that led to a stable `live_ping_cli_completion` canary run.

## Current Status

- Latest stabilization commit: `b811f0c`
- Latest validated result: `3/3` short live canary pass
- Primary runner:
  `tool/run_plan_mode_ping_cli_live_canary.sh "I want to build a Python CLI script that can ping a specific host"`

The goal of this playbook is not to preserve every intermediate experiment.
It preserves the parts that were repeatedly useful when moving failures from
`planningTimeout` and `workflowBlocked` to a stable green canary.

## The Core Rule

Treat the persisted saved-task state as the source of truth.

Most flaky failures came from one of these:

- stale assistant wording overriding the real saved-task state
- future-task tool calls appearing before the current task was terminally locked
- weak or duplicate task proposals creating avoidable execution drift
- harness progress staying behind the real execution state

When choosing between transient stream text and persisted workflow/task state,
prefer the persisted state and then recover forward.

## Terminology

### Canary

A canary is a small, early warning run before trusting a broader change. In
this project, the ping CLI canary runs the real macOS integration scenario with
a live OpenAI-compatible LLM endpoint, real tool calling, and a temporary local
project. It is intentionally smaller than exhaustive testing, but closer to
real behavior than unit tests.

Use it to answer:

- Does the full workflow still complete with live model variability?
- Did the latest patch remove the target failure class?
- Did the fix introduce a new dominant failure class?

### Harness

The harness is the test machinery that drives the live scenario. It launches
the app, submits the prompt, handles proposal approval, watches workflow
heartbeats, records logs and screenshots, and classifies failures.

If the app did the right thing but the harness did not observe it, fix or
improve harness recovery. If the harness accurately observed an app failure,
fix the app logic or prompt/guardrail layer.

### 1x, 3x, and Full Pass

- `1x` is the discovery loop. Use it after a small patch to see whether the
  target failure branch moved.
- `3x` is the short stability gate. Use it after the `1x` branch is green.
- A full pass should include focused unit tests, static analysis, and a clean
  `3x` live canary. Increase the repeat count only when the remaining risk is
  model variability rather than a deterministic bug.

## Hotspots

These files carried most of the stabilization work:

- `lib/features/chat/presentation/providers/chat_notifier.dart`
  Task proposal parsing, salvage, retry gates, duplicate-task rejection,
  validator normalization.
- `lib/features/chat/presentation/pages/chat_page.dart`
  Saved-task execution flow, recovery routing, completion locking,
  same-turn handoff handling.
- `lib/features/chat/domain/services/conversation_plan_execution_guardrails.dart`
  Classification of drift, missing targets, validation outcomes, completion
  promotion, and bounded recovery entry conditions.
- `lib/features/chat/domain/services/conversation_plan_execution_coordinator.dart`
  Hidden recovery prompts and task-specific nudges.
- `lib/features/chat/domain/services/conversation_execution_progress_inference.dart`
  Extraction of completion evidence from assistant/tool stream content.
- `integration_test/plan_mode_scenario_test.dart`
  Live harness orchestration, approval flow, heartbeat timing, and
  completion detection.
- `integration_test/test_support/plan_mode_*`
  Progress recovery, warning policy, diagnostics, and synthetic timeout
  summaries.

## Failure Families That Mattered

### 1. Planning false negatives

Typical symptoms:

- `planningTimeout`
- run log contained `Workflow proposal ready` or `Task proposal ready`
- heartbeat stayed at `promptSubmitted`

What helped:

- trust ready markers from logs and persisted drafts over stale generating flags
- make approval progress explicit with markers and bounded waits
- salvage truncated or reasoning-only proposal responses before retrying

### 2. Task proposal quality drift

Typical symptoms:

- single generic scaffold task
- duplicate implementation or verification tasks
- non-portable validators such as `ls -F`
- unbounded ping commands or `pytest` validators in empty Python workspaces
- implementation plans nudging the model toward third-party runtime packages

What helped:

- reject weak or duplicate proposals before saving them
- normalize portable validator forms early
- prefer standard library and `subprocess` for simple Python CLI plans
- reject third-party runtime dependency hints unless dependency manifests are
  explicit saved targets

### 3. Execution handoff drift

Typical symptoms:

- current task was effectively complete, but the next tool call targeted a
  future task
- stale task remained `inProgress` and later stalled or blocked

What helped:

- lock same-turn completion before processing future-task tool calls
- prefer successful validation plus workspace evidence over stale stream text
- prevent completed tasks from downgrading back to `blocked` or `inProgress`

### 4. Verification task stalls

Typical symptoms:

- implementation task completed
- verification task never actually ran the saved validator or ran it once and
  drifted into explanation-only output

What helped:

- treat verification tasks as bounded
- when the validator succeeds, promote the task to terminal completion
- reject duplicate verification tasks with the same target and validator

## Command Cookbook

### Focused verification

Run focused tests before rerunning the live canary:

```bash
flutter test test/features/chat/presentation/providers/chat_notifier_workflow_proposal_test.dart
flutter test test/features/chat/domain/services/conversation_plan_execution_guardrails_test.dart
flutter test test/features/chat/domain/services/conversation_plan_execution_coordinator_test.dart
flutter analyze
```

### Live canary

Use a single run to confirm the latest patch, then a three-run pass-rate check.

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_REPEAT_COUNT=1 \
tool/run_plan_mode_ping_cli_live_canary.sh "I want to build a Python CLI script that can ping a specific host"

CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_REPEAT_COUNT=3 \
tool/run_plan_mode_ping_cli_live_canary.sh "I want to build a Python CLI script that can ping a specific host"
```

### Artifact locations

The most useful artifacts are written under:

- `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/`

Read these first:

- `canary_summary.md`
- `run_0X_suite_report.json`
- `run_0X_heartbeat.json`
- `run_0X_run.log`

## Recommended Debug Loop

1. Run a fresh `1x` canary.
2. Identify the dominant failure class from `canary_summary.md`.
3. Read the matching `run_0X_suite_report.json` and `run_0X_run.log`.
4. Build or update a replay fixture for that exact branch.
5. Add a focused test before changing production logic.
6. Patch the smallest layer that can prevent the failure:
   proposal gate, guardrail, coordinator, handoff logic, or harness.
7. Re-run focused tests.
8. Re-run `1x`.
9. Only then re-run `3x`.

This loop was more effective than trying to patch multiple speculative causes
at once.

## Replay-First Guidance

When adding a replay fixture:

- keep the fixture as close as possible to the real run log
- preserve the exact task titles, validator commands, and target files
- prefer a narrow fixture per failure family instead of one giant trace
- make the test assert the behavior change you actually need

Useful fixture targets included:

- duplicate verification tasks
- truncated workflow or task proposals
- missing target validation failures
- stale same-turn task handoffs
- recovered parse warnings that should not fail the canary

## Practical Heuristics

- Prefer bounded validators. For ping tasks, include an explicit count such as
  `-c 1`.
- Prefer portable validators. Avoid platform-sensitive flags unless the tool
  layer normalizes them.
- Prefer implementation plans that do not require package installation for the
  first slice.
- If a task succeeds by validation and workspace evidence, lock it complete
  before any future-task continuation.
- If the harness log proves progress that the heartbeat missed, recover the
  progress in diagnostics rather than assuming a hard failure.

## Retrospective Notes

These are the higher-level observations that were worth preserving after the
green canary was reached.

### What was more important than expected

- Task proposal quality mattered as much as execution recovery.
  A large share of downstream failures started from weak saved tasks rather
  than from a broken recovery path.
- Harness diagnostics were product work, not just test work.
  Better heartbeats, log-aware summaries, and warning policy changes removed a
  lot of false debugging branches.
- Terminal completion locking had to be treated as a first-class concern.
  Many failures were not "the task did not work" but "the task worked and was
  later overwritten by stale stream state."

### What was less useful than expected

- Broad speculative fixes before building a replay fixture.
  They often moved the failure without proving the root cause.
- Reading only the final error string.
  The decisive signal usually came from the combination of:
  `canary_summary.md`, `run_0X_suite_report.json`, `run_0X_heartbeat.json`,
  and `run_0X_run.log`.
- Treating all timeouts as equivalent.
  Splitting `planningTimeout`, `executionOverrun`, `verificationStall`,
  `executionStateLost`, and startup failures reduced wasted work.

## If Repeating This Work

If the same kind of stabilization effort starts again in another scenario,
this is the order that should be used from the beginning.

1. Make the failure readable before fixing it.
2. Add or improve replay coverage for the exact failure branch.
3. Strengthen task proposal gates before adding complex execution recovery.
4. Lock terminal completion before tuning future-task continuation.
5. Use `1x` live canaries to confirm the latest patch.
6. Use `3x` only after the `1x` branch is stable.

That order would likely save a meaningful amount of iteration time.

## What I Would Do Earlier Next Time

- Add duplicate-task rejection earlier.
  Duplicate implementation and verification tasks created several misleading
  late-stage failures that looked like execution bugs.
- Normalize validator portability earlier.
  Commands such as `ls -F` should have been rejected or normalized before the
  first live run.
- Encode the "prefer standard library first" Python rule earlier.
  This would have prevented the `ping3` drift branch sooner.
- Add approval-path markers earlier.
  They were essential whenever the log proved planning was ready but the
  heartbeat did not move.
- Add explicit workflow-completion recovery earlier.
  Late final-answer and memory-extraction phases can look like execution
  overruns when they are actually successful completions.

## What I Would Avoid Next Time

- Avoid bundling unrelated recovery changes into one patch.
  Single-cause patches made it much easier to tell whether the fix actually
  worked.
- Avoid using `3x` as the first feedback loop after a speculative change.
  It is better as a stability check than as a discovery tool.
- Avoid trusting assistant reasoning text over persisted task data.
  The model frequently described the wrong task even when the saved workflow
  state was still correct.
- Avoid adding recovery prompts that are broader than the saved task boundary.
  Broad prompts made the model drift into future tasks or dependency changes.

## Codex-Specific Lessons

These notes are specific to how an agent like Codex should approach similar
stabilization work.

- The best contribution was not "write more code faster"; it was preserving a
  reliable source of truth and narrowing the search space.
- Frequent short progress updates helped maintain a clear chain of reasoning
  across many batches.
- Worktrees were valuable because they allowed aggressive iteration without
  destabilizing the main branch.
- Commit granularity mattered. Small focused commits made it easier to map a
  canary improvement back to the exact class of change that caused it.

## Merge Checklist

Before merging this branch back:

1. `flutter analyze`
2. Focused tests for the touched proposal/guardrail/progress files
3. `1x` live canary pass
4. `3x` live canary pass-rate check
5. Review the latest `canary_summary.md` for any non-app-logic noise

## What To Watch Next

If regressions return after merge, check these in order:

1. proposal quality drift in `chat_notifier.dart`
2. completion locking in `chat_page.dart`
3. validation classification in `conversation_plan_execution_guardrails.dart`
4. harness recovery in `integration_test/test_support/plan_mode_*`

That order matched the most common root causes during this stabilization run.
