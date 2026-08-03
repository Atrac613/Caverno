# Integrate Participant Tool Executor

## Goal

Delegate participant tool definition filtering and execution from
`ChatNotifier` to the existing owner-aware `ParticipantToolRuntimeAdapter` and
`ParticipantToolExecutor` boundary.

## Scope

- Build one immutable `ParticipantToolSession` for each participant turn.
- Route approval through `TurnToolApprovalCoordinator` callback ports.
- Keep MCP execution, approval UI projection, participant activity projection,
  and owner-keyed taint storage as narrow notifier callbacks.
- Preserve participant tool definitions, approval modes and denial payloads,
  execution results, activity ordering, and taint recording.
- Remove the duplicate participant policy and approval flow from
  `chat_notifier_participant_turns.dart`.

## Non-goals

- Moving participant streaming or approval widgets.
- Moving or changing `McpToolService`.
- Changing participant stop, pause, or handoff behavior.
- Regenerating the stale turn-scope baseline in this focused slice.

## Acceptance Criteria

1. Every runtime callback validates the exact conversation, generation,
   participant, tool call, and immutable argument identity supplied by the
   adapter.
2. An expired owner is rejected before MCP execution; an uncertain effect is
   not reported as a successful participant tool result.
3. Tool results are recorded only against the exact owner-keyed taint state.
4. Direct executor and adapter tests, participant notifier tests, owner poison
   tests, collaborator boundaries, and size ratchets pass.
5. `tool/codex_verify.sh --coverage` introduces no failure beyond the recorded
   stalled-diagnostic canary-runner baseline mismatch.
6. The notifier same-library aggregate and relevant size ratchets do not grow.

## Verification

```bash
fvm dart format \
  lib/features/chat/data/datasources/participant_tool_runtime_adapter.dart \
  lib/features/chat/data/datasources/participant_tool_production_ports.dart \
  test/features/chat/data/datasources/participant_tool_production_ports_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/participant_tool_executor_test.dart \
  test/features/chat/data/datasources/participant_tool_runtime_adapter_test.dart \
  test/features/chat/data/datasources/participant_tool_production_ports_test.dart
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_test.dart \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

## Completion Evidence

- `ParticipantToolExecutor` direct coverage: 100% (97/97 lines).
- Focused executor, adapter, production-port, notifier, owner-poison,
  collaborator-boundary, and size-ratchet tests pass.
- The notifier same-library aggregate decreased from 19,324 to 19,298 lines.
- `tool/codex_verify.sh --coverage` completed 6,565 tests with only the recorded
  `stalled-diagnostic runner selects the constrained repair scenario` baseline
  mismatch failing.
