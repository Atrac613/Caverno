# CLI3 Global State Storage Scope

## Task

- Goal: Define and enforce which chat-memory and routine registries a terminal
  process may read or mutate under the application-default and explicit data
  roots.
- User-visible behavior: Default terminal runs continue sharing global memory
  and routines with the GUI. Runs using `--data-dir` or `CAVERNO_HOME` use only
  state owned by that isolated data root.
- Non-goals: Adding terminal routine commands, scheduling routines from a
  terminal process, merging concurrent chat-memory updates, changing settings
  precedence, or standalone CLI packaging.

## Context

- Affected components:
  - `lib/features/terminal/application/`
  - `lib/features/terminal/presentation/caverno_cli_process.dart`
  - `lib/features/routines/data/routine_repository.dart`
  - terminal persistence and repository tests
- Related docs: `docs/caverno_cli_terminal_contract.md`, `docs/roadmap.md`,
  `docs/cli3_shared_persistence_bootstrap_codex_task.md`, and
  `docs/cli3_terminal_project_persistence_codex_task.md`.
- Existing behavior:
  - Chat memory already follows the resolved drift database. The default CLI
    opens the GUI database, while an explicit data root owns its own
    `caverno.sqlite` and migration markers.
  - Routine persistence always resolves from application-default
    SharedPreferences. A terminal container that initializes the routine
    provider under `--data-dir` would therefore cross the isolation boundary.

## Ownership Matrix

| State | Application-default terminal | Explicit data-root terminal |
| --- | --- | --- |
| Chat memory | Shared GUI drift database | Data-root `caverno.sqlite` |
| Routine registry | Shared GUI preferences | Data-root `routines.json` |
| Routine execution | Not exposed | Not exposed |
| Memory merge ownership | Existing process-local cache behavior | Isolated to its own database |

## Implementation Notes

- Keep the existing drift bootstrap as the only chat-memory storage selector.
  Add restart and cross-root tests instead of creating another memory backend.
- Introduce a routine repository interface while preserving the existing
  SharedPreferences implementation for GUI and application-default terminal
  composition.
- Add a data-root-local JSON routine repository and select it during terminal
  bootstrap. Write through a temporary file and rename so partial JSON is never
  exposed after an interrupted save.
- Keep the JSON payload equal to the existing `List<Routine>` representation.
  Missing or malformed isolated registries load as empty, matching current
  repository fallback behavior.
- Do not expose routine mutation tools or scheduler startup in this slice.

## Concurrency Boundary

- This task proves storage ownership, not concurrent memory reconciliation.
  `CachedDriftKeyValueStore` hydrates once per process, so a correct cross-
  process merge requires both authoritative refresh under ownership and an
  atomic read-modify-write policy. Adding only a file lease would still permit
  a stale cache to overwrite another process's update.
- The next memory slice must add the refresh-and-merge boundary together and
  cover two different conversations sharing the application-default data root.
- Future terminal routine execution must acquire a per-routine execution lease
  before it is exposed; storage isolation alone is not an execution-ownership
  claim.

## Similar-Pattern Search

- Search terms: `chatMemoryRepositoryProvider`, `openCavernoCliPersistence`,
  `routineRepositoryProvider`, `SharedPreferences`, `CAVERNO_HOME`, and
  `resolvedDataDirectory`.
- Files inspected: shared drift bootstrap, cached chat-memory key/value store,
  routine repository and notifier, terminal process overrides, execution lease
  task, and existing terminal persistence tests.

## Acceptance Criteria

- Two application-default frontend openings of the same production drift store
  observe the same persisted chat-memory profile after restart.
- Two explicit data roots do not observe or overwrite each other's chat memory.
- Application-default routine persistence remains SharedPreferences-compatible
  and therefore GUI-visible.
- An explicit data root reads and writes only `routines.json` beneath that root
  and does not mutate the application-default routine registry.
- The terminal provider container receives the selected routine repository even
  though no routine command is exposed.
- Focused tests and `tool/codex_verify.sh` pass without generated-file drift or
  analyzer findings.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/terminal/application/caverno_cli_persistence_test.dart \
  --test test/features/terminal/application/caverno_cli_routine_repository_test.dart \
  --test test/features/routines/presentation/providers/routines_notifier_test.dart
```

Then run `tool/codex_verify.sh` and update `docs/roadmap.md` with the verified
storage boundary and the cross-process memory merge follow-up.

## Handoff Notes

- Summary: Terminal composition now selects the routine repository from the
  resolved data-root scope. Application-default runs retain the GUI-compatible
  SharedPreferences registry, while explicit roots use an atomically replaced
  local `routines.json` file.
- Tests run: The focused storage gate passed with no generated-file drift, no
  analyzer findings, and 22 passing tests. `tool/codex_verify.sh` passed with no
  generated-file drift, no analyzer findings, and 3,378 passing tests.
- Coverage notes: Routine tests cover default compatibility, explicit-root
  isolation, replacement without temporary-file residue, malformed registry
  fallback, and existing notifier behavior. Chat-memory tests reopen the same
  drift file across application-default processes and prove separate explicit
  roots cannot observe each other's profile.
- Concurrency note: The tests deliberately do not claim safe concurrent memory
  merging. A process can still hold a stale hydrated key/value cache while a
  different conversation writes to the same application-default database.
- Next risk: Add authoritative chat-memory refresh and atomic merge under a
  data-root-scoped lease, beginning with a deterministic stale-cache regression
  across two frontend owners and different conversations.
