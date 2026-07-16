# CLI3 Chat-Memory Atomic Merge

## Task

- Goal: Prevent GUI and terminal processes that share a Caverno data root from
  losing chat-memory updates when their drift-backed repositories were
  hydrated at different times.
- User-visible behavior: Memory extracted from different conversations remains
  available after either frontend exits, even when both frontends update the
  same global memory sections concurrently.
- Non-goals: Serializing complete chat turns, refreshing prompt memory before
  every read, exposing terminal routine execution, changing the chat-memory
  schema, or packaging the standalone CLI.

## Context

- Affected components:
  - `lib/features/chat/data/repositories/key_value_store.dart`
  - `lib/features/chat/data/repositories/chat_memory_repository.dart`
  - `lib/features/chat/domain/services/session_memory_service.dart`
  - `lib/features/chat/application/runtime/caverno_execution_lease.dart`
  - GUI and terminal persistence composition
- Related docs: `docs/caverno_cli_terminal_contract.md`, `docs/roadmap.md`, and
  `docs/cli3_global_state_storage_scope_codex_task.md`.
- Existing behavior: Each `CachedDriftKeyValueStore` hydrates once. A later
  read-modify-write operation can therefore merge against a stale process-local
  cache and overwrite another process's committed memory.

## Mutation Contract

1. Acquire one data-root-scoped `chatMemory` execution lease for the shortest
   complete logical mutation.
2. Refresh every chat-memory key from the authoritative drift store after the
   lease is acquired and before any read-modify-write calculation.
3. Keep a composite `SessionMemoryService` operation under that same lease so
   its summary, memory, review, suppression, and profile changes share one
   refreshed snapshot.
4. Permit nested repository mutations without reacquiring the lease, while
   still serializing unrelated asynchronous mutations in the same process.
5. Release the lease after success or failure. Retry a live conflict for a
   bounded interval, then surface a stable chat-memory mutation timeout.
6. Keep explicit data roots independent because their lease directories and
   drift databases are rooted beneath different directories.

The lease protects only mutation consistency. Synchronous read APIs continue
to use their hydrated cache until the next mutation refresh; prompt-read
freshness is a separate follow-up if live cross-frontend visibility requires
it.

## Old-To-New Integration Map

| Existing path | New responsibility |
| --- | --- |
| `CachedDriftKeyValueStore` startup hydration | Add targeted authoritative cache refresh. |
| `ChatMemoryRepository` process-local read-modify-write | Run each mutation inside a refresh-and-merge boundary. |
| `SessionMemoryService` multi-section updates | Hold one reentrant boundary for each logical operation. |
| Conversation/workspace execution lease resources | Add a global chat-memory mutation resource. |
| GUI drift bootstrap | Inject a coordinator rooted at the GUI data root. |
| Terminal drift bootstrap | Resolve its runtime data root first and inject the same coordinator contract. |

This extends the existing execution-lease mechanism instead of introducing an
independent state machine. Conversation and workspace leases still own runtime
turn execution; the chat-memory lease owns only post-turn memory persistence.

## Similar-Pattern Search

- Search terms: `ChatMemoryRepository`, `CachedDriftKeyValueStore`,
  `updateFromConversation`, `saveProfile`, `clearAll`,
  `CavernoExecutionLeaseResource`, `CavernoPersistenceBootstrap`, and
  `openCavernoCliPersistence`.
- Files inspected: every chat-memory mutation entrypoint, session-memory
  composite operations, drift and Hive key-value adapters, GUI and terminal
  persistence bootstrap, runtime lease integration, settings memory actions,
  and memory recall tools.
- Finding: Production mutations route through `SessionMemoryService`; memory
  recall tools are read-only. Repository-level boundaries remain necessary for
  direct settings actions and defensive correctness in future callers.

## Acceptance Criteria

- Two independently hydrated repositories sharing one drift database can add
  distinct memory entries without losing either entry.
- Different conversation summaries written by different frontend owners are
  both present after reopening the database.
- A composite session-memory update refreshes once and keeps all of its writes
  inside one lease.
- Concurrent mutations in one process serialize rather than treating nesting
  from an unrelated asynchronous operation as reentrancy.
- The coordinator releases its lease after both success and failure and emits
  a stable timeout when another owner does not release it.
- Different explicit data roots remain independent.
- Focused tests and `tool/codex_verify.sh` pass without generated-file drift or
  analyzer findings.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/application/persistence/caverno_chat_memory_mutation_coordinator_test.dart \
  --test test/features/chat/application/runtime/caverno_execution_lease_test.dart \
  --test test/features/chat/data/repositories/chat_memory_repository_test.dart \
  --test test/features/chat/domain/services/session_memory_service_test.dart \
  --test test/features/terminal/application/caverno_cli_persistence_test.dart
```

Then run `tool/codex_verify.sh` and update `docs/roadmap.md` with the verified
merge boundary and any remaining CLI3 ownership risk.

## Handoff Notes

- Summary: Drift-backed chat memory now refreshes all six authoritative
  sections after acquiring a short data-root-scoped lease. Repository mutations
  use a zone-reentrant boundary, and composite session-memory operations keep
  their related summary, memory, review, suppression, and profile writes under
  one boundary. GUI and terminal persistence inject coordinators rooted at the
  same resolved data directory.
- Tests run: The focused gate passed with no generated-file drift, no analyzer
  findings, and 38 passing tests. `tool/codex_verify.sh` passed with no
  generated-file drift, no analyzer findings, and 3,383 passing tests.
- Coverage notes: Regression coverage starts two independently hydrated drift
  repositories before either writes, then verifies that memory entries and
  conversation summaries from both frontend owners survive a database reopen.
  Additional tests cover one-refresh nesting, composite service ownership,
  conflict waiting, stable timeout reporting, and lease release after success
  or failure. Existing explicit-root isolation and external-process lease tests
  remain green.
- Next risk: Measure mixed conversation, workspace, and chat-memory contention
  across separate GUI-like and terminal-like processes. Record wait latency,
  timeout frequency, and throughput before deciding whether the direct file
  lease remains sufficient or CLI3 needs a local coordination daemon. Keep
  routine execution unavailable until its separate per-routine lease contract
  is defined.
