# CLI3 Shared Persistence Bootstrap

## Task

- Goal: Eliminate the GUI/CLI conversation-storage split by moving the F4
  drift migration and repository bootstrap into a reusable application
  service, then make the terminal runtime use that production drift store.
- User-visible behavior: A default terminal invocation reads and writes the
  same conversation and chat-memory store as the GUI. An explicit CLI data
  directory uses an isolated SQLite database and migrates its own legacy Hive
  data at most once.
- Non-goals: Conversation `list`, `show`, or resume commands; execution leases;
  concurrent mutation support; routine persistence; packaging; or changing the
  current session-log directory contract.

## Context

- Affected files or components: GUI startup, terminal process bootstrap, F4
  migration services, drift database opening, provider overrides, and owned
  storage cleanup.
- Related docs: `docs/roadmap.md`, `docs/caverno_cli_terminal_contract.md`,
  `docs/cli2_interactive_terminal_mvp_codex_task.md`, and
  `docs/codex_task_template.md`.
- Reference implementation or pattern: `main.dart` currently initializes
  drift, migrates Hive data once, hydrates cached repositories, and overrides
  the production providers. The terminal process currently opens only Hive.
- Known quirks, compatibility rules, or release gates:
  - The GUI intentionally falls back to Hive if drift bootstrap fails.
  - Once the F4 migration marker is set, stale Hive data must never overwrite
    newer drift data.
  - A CLI process must fail with persistence exit code 74 instead of silently
    writing to stale Hive after a drift bootstrap failure.
  - Explicit data directories need migration markers scoped to that directory;
    the application-default directory must keep using the existing
    SharedPreferences markers.

## Implementation Notes

- Preferred approach:
  - Extract the drift migration, cache hydration, and owned database cleanup
    into a reusable application-layer bootstrap service.
  - Inject the database opener, migration state, legacy readers, and marker
    callbacks so the service does not depend on a specific frontend.
  - Preserve the GUI's current catch-and-fallback behavior in `main.dart`.
  - Make the terminal process require a successful drift bootstrap and install
    the same conversation, chat-memory, and database provider overrides as the
    GUI.
  - Allow `openAppDatabase` to target an explicit SQLite file while preserving
    the current application-support default.
- Constraints:
  - Do not add a second migration implementation.
  - Close the database when bootstrap fails or when the CLI process exits.
  - Keep API keys and persisted content out of diagnostics.
  - Do not weaken the CLI2 approval, cancellation, or Computer Use boundaries.
- Generated files needed: None unless the drift schema changes. This slice must
  avoid a schema change.
- Migration or data compatibility concerns: Default storage must keep the
  existing F4 marker keys. Explicit data directories must store their markers
  inside the same isolated Hive root so deleting and recreating the root cannot
  inherit stale global migration state.

## Similar-Pattern Search

- Search terms: `_initDriftStorage`, `openAppDatabase`,
  `conversationRepositoryProvider`, `chatMemoryRepositoryProvider`,
  `appDatabaseProvider`, `CAVERNO_HOME`, and `--data-dir`.
- Files or modules inspected: `lib/main.dart`, terminal process/bootstrap
  files, F4 repositories and migration services, session-log root resolution,
  and CLI parser/application tests.
- Follow-up tasks found: CLI3 read-only conversation queries should avoid
  opening unrelated Hive boxes after migration. Session-log root injection and
  cross-process execution leases remain separate CLI3 slices.

## Acceptance Criteria

- Required behavior:
  - GUI startup still uses drift when available and Hive fallback when drift
    initialization fails.
  - A default CLI invocation installs the same drift-backed conversation,
    chat-memory, and database providers as the GUI.
  - An explicit `--data-dir` stores `caverno.sqlite` and migration markers under
    that directory.
  - The CLI closes the drift database and every Hive box it owns.
- Edge cases:
  - Completed migrations never invoke legacy readers.
  - Failed migrations do not mark completion and close the opened database.
  - Recreating an explicit data directory does not inherit a marker from a
    previous directory instance.
- Failure paths:
  - CLI drift-open or migration failures return exit code 74 with a redacted
    `bootstrap_failed` diagnostic.
  - GUI drift-open or migration failures preserve the existing logged Hive
    fallback.
- Platform expectations: The default database path remains the platform app
  support directory. No window or platform interaction is added to CLI startup.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/application/persistence/caverno_persistence_bootstrap_test.dart \
  --test test/features/terminal/application/caverno_cli_arguments_test.dart
```

Then rerun the focused terminal runtime/provider tests and a temporary
`--data-dir` process smoke before the CLI0 Live LLM comparison is repeated in a
later read-only-command slice.

## Handoff Notes

- Summary: GUI and terminal frontends now share one F4 drift bootstrap. The GUI
  preserves its logged Hive fallback, while the CLI requires drift and scopes
  explicit data-directory databases and migration markers to the same root.
  Terminal shutdown no longer initializes an unused chat runtime after an
  early validation failure.
- Tests run: Flutter analysis; three shared-bootstrap tests; three terminal
  persistence tests with real temporary SQLite and Hive stores; five terminal
  runtime-adapter tests; macOS debug build; and an isolated no-network process
  smoke that returned exit code 65 for an invalid URL after creating the
  expected persistence files.
- Coverage or low-coverage notes: Coverage was not collected for this slice.
- Risks or follow-ups: Read-only `list` and `show`, avoiding unrelated Hive
  boxes for read-only queries, session-log root injection, resume, and
  execution leases remain follow-up CLI3 slices.
