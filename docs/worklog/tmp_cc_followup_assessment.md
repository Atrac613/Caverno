# tmp/cc Follow-up Assessment

Date: 2026-05-25

## Scope

This pass reviewed reusable implementation patterns from `tmp/cc` after the
dynamic tool search and stalled tool-loop recovery work had already landed.
The goal was to identify small, high-leverage ideas that fit Caverno's current
tool loop without importing broad architecture.

## Inspected tmp/cc Areas

- `services/tools/StreamingToolExecutor.ts`
- `services/tools/toolOrchestration.ts`
- `services/toolUseSummary/toolUseSummaryGenerator.ts`
- `cli/structuredIO.ts`
- `cli/remoteIO.ts`
- `tools/FileWriteTool/FileWriteTool.ts`
- `tools/FileEditTool/FileEditTool.ts`
- `hooks/useTurnDiffs.ts`
- `hooks/useDiffData.ts`
- `utils/gitDiff.ts`
- `services/vcr.ts`
- `services/compact/*`
- `services/extractMemories/*`
- `services/SessionMemory/*`

## Findings

Caverno already has several concepts that map to the broader `tmp/cc`
direction: conversation compaction artifacts, session memory artifacts, trusted
MCP onboarding, dynamic tool discovery, and concurrency-aware scheduling for
read-only tool batches.

The remaining high-value gap is observability. `tmp/cc` tracks tool execution
as a lifecycle with queued, executing, completed, yielded, and cancellation
states. Caverno had batch telemetry and result persistence, but not per-tool
lifecycle diagnostics with enough structure to explain live LLM stalls.

## Adopted In This Slice

Added per-tool lifecycle diagnostics around Caverno's scheduler:

- `queued`, `started`, and `completed` lifecycle events from
  `ToolExecutionScheduler`
- `success`, `tool_failure`, and `exception` result status labels
- duration reporting for completed tool executions
- ChatNotifier JSON logs with `toolCallId`, `toolName`, `lifecycleState`,
  `loopIndex`, `schedulerClass`, `resultStatus`, `skipReason`, and `durationMs`
- duplicate tool-call skip diagnostics before the scheduler drops a call

These logs are emitted through the existing `[Tool]` log channel so plan-mode
failure artifact capture can include them without changing the artifact schema.

## Deferred Candidates

- Structured plan-mode harness events for live scenarios.
- Structured file diff summaries for saved-task and coding artifacts.
- Optional VCR-style replay for live LLM/tool-loop failures.
- Resolve-once approval primitives for dialog and permission races.
- Lightweight tool-use summary labels for long batches.

## Verification

Focused coverage was added in
`test/features/chat/domain/services/tool_execution_scheduler_test.dart`.
