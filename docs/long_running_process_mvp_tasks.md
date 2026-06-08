# Long-Running Process MVP Tasks

This document tracks the remaining MVP work for Caverno's long-running local
process flow. It is focused on background commands started from chat or coding
tool loops through `local_execute_command(background: true)` or `process_start`.

## MVP Goal

The MVP is ready when Caverno can start a long-running desktop command without
blocking the LLM request, expose enough process state for the assistant to
monitor it, and refuse completion claims until every relevant background
process has exited successfully.

## Current Implementation Snapshot

- `BackgroundProcessTools` can start, list, inspect, tail, wait for, and cancel
  local background processes within the current app process.
- `McpToolService` exposes `process_start`, `process_status`, `process_tail`,
  `process_wait`, `process_list`, and `process_cancel` alongside
  `local_execute_command(background: true)`.
- `ChatNotifier` collects background `job_id` values from process tool results.
- Completion claims are blocked when a related process is still running, failed,
  or has an unverified status.
- Running background jobs require periodic progress reports based on refreshed
  status, elapsed time, stdout tails, and stderr tails instead of silent waits.
- Unit coverage includes successful completion, still-running completion blocks,
  failed process completion blocks, multiple-job completion checks, and
  unverified status completion blocks.

## MVP Scope

In scope:

- Chat and coding tool-loop use of local background process tools.
- Completion-claim safety for running, failed, and unverified process states.
- Focused deterministic tests for the guard behavior.
- A dedicated live LLM canary for the background process lifecycle.
- Repeatable release evidence for the target model and endpoint.
- Documentation that tells reviewers which warnings block MVP sign-off.

Out of scope for this MVP:

- Resuming process state after Caverno restarts.
- Discovering arbitrary OS processes that were not started by Caverno.
- Distributed or remote process monitoring.
- Routine scheduler background execution.
- User-facing desktop notifications for process completion.

## Remaining MVP Tasks

| ID | Task | Status | Acceptance evidence |
|----|------|--------|---------------------|
| LRP-MVP-1 | Keep the background process tool contract stable. | Implemented | Tool definitions include `process_start`, `process_status`, `process_tail`, `process_wait`, `process_list`, and `process_cancel`; tests cover tool availability and aliases. |
| LRP-MVP-2 | Reject premature completion while a process is running. | Implemented | Deterministic chat tests prove a completion claim is replaced with `background_process_still_running` monitor feedback. |
| LRP-MVP-3 | Reject completion when a process exits unsuccessfully. | Implemented | Deterministic chat tests prove a non-zero process exit produces `background_process_failed` feedback instead of final success. |
| LRP-MVP-4 | Reject completion when process status is unverified. | Implemented in current branch | Deterministic chat test proves `status: unknown` produces `background_process_status_unverified` feedback and keeps the conversation in monitoring mode. |
| LRP-MVP-5 | Add a dedicated chat live canary for the background process lifecycle. | Implemented | `tool/canaries/chat_background_process_live_canary_test.dart` covers start, required monitoring, progress reporting from observed stdout/status, prose-only still-running recovery, and safe completion after a zero-exit wait result. |
| LRP-MVP-6 | Add a repeatable long-run evidence wrapper. | Implemented | `tool/run_chat_background_process_live_canary.sh` can run the canary repeatedly, aggregates JSON logs, and fails if any iteration fails. |
| LRP-MVP-7 | Record cleanup-cancellation policy for long-running scenarios. | Implemented | This document defines cleanup cancellation as allowed, warning, or blocker, and requires no late disposed-container task failures. |
| LRP-MVP-8 | Promote the new canary into the Live LLM coverage map. | Implemented | `docs/live_llm_canary_coverage.md` and `README.md` now list the background process canary and repeat instructions. |
| LRP-MVP-9 | Capture model and endpoint evidence in the canary matrix. | Implemented | `docs/plan_mode_live_llm_model_canary_matrix.md` records clean `qwen3.6-27b-mtp-vision` evidence for one-run, three-run repeat, progress-report, and prose-only recovery background-process canaries. |

## Cleanup-Cancellation Policy

Apply this policy to background command flows:

- Allowed:
  - A canary ends with `cleanup-cancelled` before process completion when the
    provider is shutting down and no side-effect path depends on process result.
  - The provider container logs `harness shutdown` and does not emit a user-visible
    completion after disposal.
- Warning:
  - Cleanup happens while a foreground user-visible completion is expected, and
    the final process signal is unknown or still running.
  - Process state transitions stop after the expected canary timeout but before a
    cleanup report is persisted.
- Blocker:
  - Any callback or task runs after the provider container is disposed.
  - A long-running background task writes to chat state after the cancellation path.
  - Process monitor callbacks fail to emit a structured end state and keep retrying
    after shutdown.

Release policy: cleanup-cancellation warnings do not automatically fail a release,
but blockers fail it unless a focused regression test or live harness change can
reasonably attribute the behavior to environment constraints.

## MVP Ready Criteria

Mark the long-running process MVP ready only when all of these are true:

- Focused deterministic chat tests pass.
- The dedicated background process live canary passes on the target model and
  endpoint.
- The repeat wrapper passes at least three consecutive iterations for the
  target release model.
- The final live canary summary contains no failed, still-running, or
  unverified final process states.
- Long-running jobs report concise progress from observed process status and
  output tails before continuing to monitor.
- Cleanup cancellation, if observed, is classified with an explicit release
  policy and does not produce late provider-disposal task failures.
- Live LLM coverage docs and the model canary matrix point to the new evidence.

## Verification Commands

Current focused deterministic coverage:

```bash
fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart --name "background process"
fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart --name "process status is unverified"
```

Documentation coverage:

```bash
fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart
```

Planned live evidence:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_chat_background_process_live_canary.sh

CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_REPEAT_COUNT=3 \
tool/run_chat_background_process_live_canary.sh
```

## Next Implementation Slice

1. Promote the background-process MVP status into the release handoff once the
   same app revision also passes the broader model-switch gate.
2. Keep `tool/run_chat_background_process_live_canary.sh` in every model switch
   baseline where tool-loop execution, local command safety, or completion
   guards changed.
3. Watch future summaries for non-zero failed, still-running, or unverified
   process states before treating a model as release-ready.
