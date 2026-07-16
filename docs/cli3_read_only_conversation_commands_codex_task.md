# CLI3 Read-Only Conversation Commands

## Task

- Goal: Add read-only `caverno conversations list` and
  `caverno conversations show <conversation-id>` commands over the shared
  production drift repository.
- User-visible behavior: Terminal users can inspect persisted conversations
  without starting an LLM request, MCP client, tool runtime, or GUI window.
- Non-goals: Conversation resume, deletion, mutation, fuzzy identifier lookup,
  full-text search, execution leases, project ownership, or session-log queries.

## Context

- Affected files or components: CLI argument parsing, terminal process routing,
  shared CLI persistence bootstrap, read-only output formatting, and CLI docs.
- Related docs: `docs/roadmap.md`, `docs/caverno_cli_terminal_contract.md`,
  `docs/cli3_shared_persistence_bootstrap_codex_task.md`, and
  `docs/codex_task_template.md`.
- Reference implementation or pattern: CLI3 already hydrates the same cached
  drift repositories as the GUI. Existing terminal JSON output uses the
  `caverno_cli_event` schema and passes every payload through
  `CavernoCliRedactor`.
- Known quirks, compatibility rules, or release gates:
  - Default storage uses SharedPreferences migration markers. Explicit data
    directories use root-local Hive migration markers.
  - A completed migration must not require opening the legacy conversation or
    chat-memory Hive boxes.
  - An incomplete migration may write only the idempotent drift migration and
    its completion markers before serving the read request.
  - Stored messages can contain inline image data and response metadata that
    are outside this command's output contract.

## Implementation Notes

- Preferred approach:
  - Extend the invocation contract with separate read-only conversation
    actions so runtime command switches remain exhaustive and unchanged.
  - Support `list` with an optional bounded `--limit` and `show` with one exact
    conversation identifier.
  - Implement a small application-layer query service that depends only on the
    conversation repository, terminal output port, clock, and redactor.
  - Emit `conversation_list` and `conversation_detail` JSON Line events using
    `caverno_cli_event` schema version 1.
  - Resolve migration state before opening legacy boxes. Open only the boxes
    required by an incomplete migration, and return from read-only actions
    before creating a Riverpod container or terminal runtime adapter.
- Constraints:
  - Do not initialize ChatNotifier, MCP clients, tools, or LLM configuration for
    read-only commands.
  - Redact persisted text in both human and JSON output.
  - Omit image data, image paths, response metrics, and internal workflow
    payloads from message output.
  - Keep identifiers exact and complete in this first slice.
- Generated files needed: None.
- Migration or data compatibility concerns: Preserve the existing F4 migration
  keys and the root-local marker behavior introduced by the CLI3 persistence
  bootstrap.

## Similar-Pattern Search

- Search terms: `CavernoCliInvocationAction`, `openCavernoCliPersistence`,
  `conversationRepositoryProvider`, `Hive.openBox`, `caverno_cli_event`, and
  `CavernoCliRedactor`.
- Files or modules inspected: Terminal parser and process bootstrap, terminal
  presenter and redactor, conversation repository contract, cached drift
  repository, F4 migration bootstrap, CLI docs, and focused terminal tests.
- Follow-up tasks found: Conversation resume must wait for a cross-process
  execution lease. Session-log root injection and search remain separate CLI3
  slices.

## Acceptance Criteria

- Required behavior:
  - `conversations list` returns the most recently updated conversations first,
    defaults to 20 results, and accepts `--limit` from 1 through 200.
  - `conversations show <conversation-id>` returns metadata and text messages
    for one exact identifier.
  - Human output is readable and JSON output is stable, newline-delimited, and
    redacted.
  - Read-only actions do not start the execution runtime or access LLM/MCP
    configuration.
  - Completed migrations do not open legacy conversation or chat-memory boxes.
- Edge cases:
  - An empty list succeeds with an explicit empty result.
  - A missing exact identifier returns exit code 65 with
    `conversation_not_found`.
  - Missing subcommands or identifiers, extra positional arguments, invalid
    limits, and unsupported flags return exit code 64.
- Failure paths:
  - Persistence bootstrap failures remain redacted and return exit code 74.
  - An incomplete migration without the required legacy reader fails closed.
- Platform expectations: Commands run without opening a Flutter window and
  preserve the application-default and explicit `--data-dir` path contracts.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/terminal/application/caverno_cli_arguments_test.dart \
  --test test/features/terminal/application/caverno_conversation_query_test.dart \
  --test test/features/terminal/application/caverno_cli_persistence_test.dart
```

Then build the macOS debug executable and run an isolated empty-store
`conversations list --json` process smoke. The smoke must emit one
`conversation_list` event without MCP startup or an LLM request.

## Handoff Notes

- Summary: Added bounded `conversations list` and exact-ID
  `conversations show` commands with redacted human and JSON output. The
  terminal process completes both actions from the shared drift repository
  before creating the LLM runtime, and completed migrations no longer require
  legacy conversation or chat-memory Hive boxes.
- Tests run: `tool/codex_verify.sh` completed dependency resolution, clean
  generated-file verification, full Flutter analysis, and 26 focused parser,
  query, persistence, and documentation tests. A macOS debug build passed. Two
  isolated executable smokes emitted one empty `conversation_list` event; the
  second also passed while the migrated legacy conversation and chat-memory
  files were temporarily unreadable.
- Coverage or low-coverage notes: Coverage is not required for this slice.
- Risks or follow-ups: The macOS debug executable still prints Flutter engine
  diagnostics outside the JSON event stream. Resume and mutation remain
  blocked on an explicit conversation and project execution lease.
