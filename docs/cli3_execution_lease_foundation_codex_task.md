# CLI3 Execution Lease Foundation

## Task

- Goal: Establish a data-root-scoped cross-process ownership primitive for
  conversations and coding workspaces before CLI3 adds resume or mutation.
- User-visible behavior: Competing Caverno frontends can identify an existing
  owner and fail closed instead of mutating the same resource concurrently.
- Non-goals: Conversation resume, terminal mutation commands, runtime turn
  integration, cached conversation refresh, skill persistence migration, a
  local daemon, or a blocking lock queue.

## Context

- Affected files or components: Shared chat runtime services, terminal process
  startup, macOS single-instance startup, and focused process tests.
- Related docs: `docs/roadmap.md`, `docs/caverno_cli_terminal_contract.md`,
  `docs/cli3_read_only_conversation_commands_codex_task.md`.
- Reference implementation or pattern: CLI3 persistence already resolves an
  explicit `--data-dir` to the same root as its SQLite database. The default
  root is the application-support directory that contains `caverno.sqlite`.
- Known quirks, compatibility rules, or release gates:
  - macOS currently activates an existing application process before Dart
    handles CLI arguments.
  - POSIX file locks are process-scoped, so the service also needs an in-process
    ownership registry.
  - `CachedDriftConversationRepository` hydrates once. Runtime integration must
    refresh the target conversation after acquiring its lease and before any
    mutation.
  - Runtime CLI startup still opens legacy Hive boxes and the Hive-backed skill
    box. GUI and CLI coexistence is not safe until a later integration slice
    removes or isolates those dependencies.

## Ownership Contract

- Use a direct operating-system exclusive file lock. Do not introduce a lease
  row with TTL recovery or a daemon until contention measurements require one.
- Store lock files under `<data-root>/execution_leases`.
- Hash the normalized resource identity into the filename so resource names and
  workspace paths are not exposed through directory listings.
- Treat a conversation ID and an effective canonical coding workspace path as
  distinct resource kinds.
- Acquire multiple resources in stable sorted order and release all partial
  acquisitions when any resource conflicts.
- Use non-blocking acquisition. Return an actionable conflict containing safe
  owner metadata; never silently serialize or steal an active lock.
- Keep the file descriptor open for the full ownership lifetime. Release is
  idempotent, and process death relies on the operating system to release the
  lock rather than a timestamp or PID liveness heuristic.
- Owner metadata contains a schema version, an opaque owner ID, PID, frontend,
  acquisition timestamp, resource kind, and a sanitized display target.

## Existing To New Integration Map

| Existing owner | Foundation change | Later runtime integration |
| --- | --- | --- |
| `CavernoExecutionRuntime.startTurn` | No behavior change | Acquire before `run_started`; attach the lease handle to the turn handle |
| `CavernoRuntimeTurnHandle` terminalization | No behavior change | Release on complete, fail, cancel, and runtime close |
| CLI explicit data directory | Resolve the same root for lease tests | Inject the root into the terminal runtime composition |
| GUI application-support database | Resolve the database parent | Inject the same root into the GUI runtime composition |
| `CachedDriftConversationRepository` | Document stale-cache risk | Refresh the leased conversation before mutation |
| macOS `AppDelegate` single-instance guard | Allow CLI-shaped launches to reach Dart | Preserve activation behavior for GUI launches |
| Hive-backed terminal startup | Document coexistence blocker | Skip migrated legacy boxes and isolate or migrate skills |

This map extends the shared runtime instead of adding a separate CLI execution
state machine. Goal auto-continue, Plan Mode, and routine tool policy continue
to operate inside the turn after ownership has been acquired.

## Implementation Notes

- Preferred approach: A pure Dart `CavernoExecutionLeaseService` backed by
  `RandomAccessFile.lock(FileLock.exclusive)` and SHA-256 lock filenames.
- Constraints: The service must be usable by GUI and terminal compositions,
  avoid Flutter UI dependencies, and never persist raw conversation IDs or
  workspace paths in filenames.
- Generated files needed: None.
- Migration or data compatibility concerns: Existing lock files are harmless
  without a held OS lock. Metadata is diagnostic only and must not determine
  lock ownership.

## Similar-Pattern Search

- Search terms: `FileLock`, `RandomAccessFile`, `activateExistingInstance`,
  `conversationBoxProvider`, `skillBoxProvider`, `useTransientProject`, and
  `worktreeRoot`.
- Files or modules inspected: Runtime composition, terminal persistence and
  process startup, cached Drift repositories, coding project persistence, and
  macOS/Windows/Linux runners.
- Follow-up tasks found: Runtime acquisition and cache refresh; legacy Hive and
  skill coexistence; Windows and Linux CLI startup routing; conversation resume;
  post-response chat-memory persistence draining.

## Acceptance Criteria

- Required behavior:
  - The first owner acquires one or more resources and receives an idempotent
    handle.
  - A different process cannot acquire an overlapping resource.
  - Different resources and different data roots can be owned concurrently.
  - A failed multi-resource acquisition releases its partial ownership.
- Edge cases:
  - Duplicate resource requests are normalized.
  - Same-process duplicate acquisition conflicts.
  - Abrupt owner exit releases the operating-system lock.
  - Metadata parsing failure still reports a safe generic conflict.
- Failure paths: Directory creation, file opening, metadata writing, and lock
  failures either return a typed conflict or release every acquired descriptor.
- Platform expectations: The pure Dart service is desktop-platform neutral.
  This slice changes only the macOS startup guard because it is the first live
  CLI packaging target; Windows and Linux routing remain explicit follow-ups.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/application/runtime/caverno_execution_lease_test.dart \
  --test test/tool/desktop_single_instance_test.dart
```

The lease test must launch a separate Dart process for contention and crash
recovery instead of using isolates from the test process.

## Handoff Notes

- Summary: Implemented a reusable data-root-scoped execution lease service,
  hashed lock filenames, safe owner diagnostics, same-process protection,
  partial-acquisition rollback, and a macOS CLI startup bypass that preserves
  ordinary GUI single-instance activation.
- Tests run:
  - `tool/codex_verify.sh` passed code generation checks, project analysis, and
    all 3,342 tests.
  - Focused lease and desktop single-instance tests passed together.
  - `swiftc -parse macos/Runner/AppDelegate.swift` passed.
  - `flutter build macos --debug` passed, and the generated executable returned
    `Caverno 1.3.13` for `--version`.
- Coverage or low-coverage notes: The focused suite uses separate Dart
  processes for conflict, invalid metadata, rollback, data-root isolation, and
  abrupt-exit recovery. Native startup routing has static contract coverage and
  a compiled CLI smoke; a simultaneous live GUI plus CLI smoke remains part of
  runtime integration.
- Risks or follow-ups: Do not permit CLI resume or mutation until runtime
  integration refreshes stale Drift caches and removes unsafe Hive coexistence.
  Windows and Linux still need CLI-aware native single-instance routing before
  those packaged frontends can support cross-process execution.
