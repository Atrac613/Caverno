# CLI3 Runtime Lease Integration

## Task

- Goal: Make the shared execution runtime acquire cross-process ownership and
  refresh its target conversation before any GUI or terminal turn can mutate
  state.
- User-visible behavior: A competing frontend fails immediately with a stable
  temporary-conflict diagnostic, while a successful owner sees the latest
  persisted conversation and retains ownership until pending writes finish.
- Non-goals: Conversation resume syntax, a lock queue or daemon, Windows/Linux
  native CLI routing, global chat-memory merge locking, or routine execution
  leases.

## Context

- Affected files or components: Runtime composition and lifecycle, conversation
  repositories and notifier, GUI and terminal provider overrides, CLI startup,
  and focused runtime/persistence tests.
- Related docs: `docs/cli3_execution_lease_foundation_codex_task.md`,
  `docs/caverno_cli_terminal_contract.md`, and `docs/roadmap.md`.
- Reference implementation or pattern: `CavernoExecutionLeaseService` already
  provides data-root-scoped, non-blocking OS locks with in-process conflict
  protection.
- Known quirks, compatibility rules, or release gates:
  - The cached Drift conversation repository hydrates once and can otherwise
    serve stale data after another process writes to SQLite.
  - Cancellation can finish its visible runtime event before its conversation
    persistence tail completes.
  - A coding conversation can use a worktree that differs from its persisted
    project root; ownership must use the effective worktree path.
  - Migrated terminal runs still open legacy conversation, chat-memory, and
    skill Hive boxes even though Drift is authoritative.

## Existing To New Integration Map

| Existing owner | Current behavior | Integrated behavior |
| --- | --- | --- |
| `CavernoExecutionRuntime.startTurn` | Publishes `run_started` synchronously | Acquires ownership, refreshes the conversation, then publishes `run_started` |
| `CavernoRuntimeTurnHandle` | Owns only terminal event state | Also owns a lease handle until terminal persistence drains |
| `ConversationsNotifier` | Uses its hydrated repository cache | Replaces the target from an authoritative repository refresh |
| GUI runtime provider | Has no data-root identity | Receives the application-support data root used by SQLite |
| Terminal runtime provider | Has no data-root identity | Receives `--data-dir`, `CAVERNO_HOME`, or the default application-support root |
| Terminal Hive bootstrap | Opens legacy boxes for every mutating run | Opens legacy boxes only when migration still needs them |
| Terminal skill provider | Opens a process-shared Hive box | Omits unsupported Hive skill persistence from CLI runtime tools |
| Goal auto-continue and Plan Mode | Start after the runtime handle exists | Continue inside the already-owned shared runtime turn |
| Routine tool policy | Classifies tools within the chat loop | Remains unchanged and subordinate to runtime ownership |

This is an extension of the shared runtime. It must not introduce a terminal-
only execution state machine.

## Implementation Notes

- Preferred approach:
  - Add runtime ownership and conversation-refresh ports.
  - Make turn startup asynchronous and reserve its turn ID while preparation is
    in flight.
  - Emit a terminal `run_failed` without `run_started` when ownership or refresh
    fails, then surface the same typed start failure to the caller.
  - Defer lease release until the repository port drains pending conversation
    persistence, including cancellation tails.
  - Resolve the same data root for the GUI database and terminal database.
- Constraints:
  - Use exit code 75 and code `execution_lease_conflict` for retryable ownership
    contention.
  - Never include raw lock filenames, API keys, conversation content, or full
    workspace paths in the conflict event.
  - Release partial ownership and all successfully acquired leases on every
    preparation, terminal, and runtime-close path.
- Generated files needed: None.
- Migration or data compatibility concerns: No schema change is allowed. Drift
  remains authoritative after migration; legacy Hive readers are available
  only while migration is incomplete.

## Similar-Pattern Search

- Search terms: `startTurn`, `run_started`, `flushPendingPersistence`,
  `normalizedWorktreePath`, `conversationBoxProvider`, `skillBoxProvider`, and
  `openAppDatabase`.
- Files or modules inspected: Shared runtime ports and handle lifecycle,
  ChatNotifier start/terminal call sites, cached Drift repositories, GUI
  bootstrap, terminal process startup, and terminal event presentation.
- Follow-up tasks found: Conversation resume, chat-memory merge serialization,
  routine ownership, and Windows/Linux native CLI routing remain separate
  slices.

## Acceptance Criteria

- Required behavior:
  - No `run_started` event is published before all required leases are acquired
    and the target conversation is refreshed from authoritative storage.
  - Coding and Plan turns lease the current conversation and the effective
    canonical worktree when each identity is available.
  - A competing process receives `execution_lease_conflict` with exit code 75.
  - Complete, fail, cancel, preparation failure, and runtime close release all
    ownership.
  - Terminal startup does not open migrated legacy conversation/chat-memory
    boxes or the Hive skill box.
- Edge cases:
  - Concurrent starts with the same turn ID are rejected while preparation is
    pending.
  - A conversation deleted between selection and refresh fails before
    mutation.
  - Runtime close waits for pending persistence drains and ownership releases.
- Failure paths: Refresh and I/O preparation failures produce a stable terminal
  event, clean up partial state, and never leave the CLI waiting for completion.
- Platform expectations: The runtime integration is platform neutral. macOS is
  the live packaged CLI target for this slice; Windows/Linux startup routing is
  unchanged.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/application/runtime/caverno_execution_runtime_test.dart \
  --test test/features/chat/data/repositories/cached_drift_conversation_repository_test.dart \
  --test test/features/chat/presentation/providers/conversations_notifier_test.dart \
  --test test/features/terminal/application/caverno_cli_application_test.dart
```

Then run the full verification entrypoint and a packaged macOS GUI-plus-CLI
contention smoke after the focused suite passes.

## Handoff Notes

- Summary: The shared execution runtime now acquires conversation and effective
  workspace leases before `run_started`, refreshes authoritative conversation
  state, and releases ownership only after terminal persistence drains. GUI and
  terminal frontends share the resolved production data root, while explicit
  CLI data roots remain isolated. The migrated CLI runtime no longer depends on
  open legacy conversation, chat-memory, or skill Hive boxes.
- Tests run: `tool/codex_verify.sh` passed with generated-file verification,
  zero analyzer findings, and 3,355 passing tests. Focused runtime, repository,
  provider, terminal lifecycle, cancellation, override-contract, and file-size
  ratchet tests also passed. `fvm flutter build macos --debug` passed.
- Packaged smoke evidence: isolated and unreadable-legacy-file runs reached
  runtime execution without Hive or provider errors. Against
  `http://192.168.100.241:1234/v1` with `qwen3.6-35b-a3b-vision`, a second Coding
  CLI process targeting the first process's data root and workspace emitted no
  `run_started`, returned `execution_lease_conflict`, and exited `75`.
- Coverage or low-coverage notes: Targeted coverage exercises acquisition
  ordering, stale conversation replacement and deletion, partial rollback,
  same-process and separate-process contention, persistence-drained release,
  cancellation, preparation failure, and runtime shutdown. No coverage report
  was generated for this slice.
- Risks or follow-ups: Add stable-ID conversation resume on the same leased
  refresh boundary. Global chat-memory merge policy, routine ownership, and
  native Windows and Linux terminal routing remain separate milestones.
