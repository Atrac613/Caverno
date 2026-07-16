# Caverno CLI Terminal Contract

Status: CLI3 completed contract. The terminal frontend, read-only conversation
queries, stable-ID conversation resume, production persistence, and
cross-process ownership exist in the macOS application executable, but a
packaged standalone CLI is not yet released.

## Commands

The supported command family is:

```text
caverno chat [input options]
caverno coding --project <path> [input options]
caverno plan --project <path> [input options]
caverno conversations list [--limit <count>] [--json]
caverno conversations show <conversation-id> [--json]
caverno conversations resume <conversation-id> [input options]
```

The runtime commands accept exactly one input source:

- `--prompt <text>` for a literal prompt.
- `--prompt-file <path>` for UTF-8 file input.
- stdin when neither prompt flag is present and stdin is not a TTY.
- An interactive TTY prompt when no other input source is present.

Conflicting explicit input sources are a usage error. Empty non-interactive
input is an input error and must not start an LLM request.

The read-only conversation commands accept `--data-dir` and `--json`; `list`
also accepts a limit from 1 through 200 and defaults to 20. `show` requires one
complete, exact conversation identifier. These commands use the shared drift
repository but do not initialize the LLM runtime, MCP clients, tools, or
approval flow. They do not resume, modify, or delete a conversation.

`conversations resume` requires one complete, exact conversation identifier and
one normal runtime input source. It infers Chat, Coding, or Plan Mode from the
saved conversation and restores the saved coding project and worktree before
initializing the chat runtime. It accepts normal endpoint and output options,
but does not accept `--project` or `--limit`. Missing conversations, projects,
project directories, or worktrees fail before `run_started`; resume never
silently substitutes a source project for a missing saved worktree.

## Configuration Precedence

Configuration resolves in this order, from highest to lowest priority:

1. Command flags.
2. `CAVERNO_*` environment variables.
3. Existing Caverno user settings when their schema is compatible.
4. Application defaults.

The effective endpoint, model, workspace, approval mode, output mode, and data
directory must be observable in startup diagnostics. API keys and other
secrets must remain redacted.

Application-default runs share the GUI persistence and session-log roots. An
explicit `--data-dir` or `CAVERNO_HOME` isolates drift storage, migration state,
coding projects, routines, execution leases, and `session_logs/` beneath that
root. `CAVERNO_SESSION_LOG_DIR` overrides only the session-log location and has
priority over the selected data root.

## Output

Human mode streams assistant text to stdout. Progress and diagnostics go to
stderr so redirected output remains usable.

`--json` emits JSON Lines on stdout. Every event includes:

- `schema`: `caverno_cli_event`.
- `schemaVersion`: `1`.
- `sequence`: a monotonically increasing integer for the process.
- `timestamp`: an RFC 3339 UTC timestamp.
- `type`: a stable event type.
- `conversationId` and `turnId` when available.
- `payload`: the event-specific object.

Runtime event types are `run_started`, `assistant_delta`, `tool_lifecycle`,
`approval_required`, `question_required`, `usage`, `run_completed`, and
`run_failed`. Read-only queries emit one `conversation_list` or
`conversation_detail` event. Conversation detail exposes text messages and
basic metadata while omitting attachment data, local image paths, response
metrics, and internal workflow payloads. Automation must consume these events
rather than parse formatted terminal prose.

## Exit Codes

| Code | Meaning |
| ---: | --- |
| `0` | The requested turn completed successfully. |
| `2` | Execution reached a verified blocked or failed task state. |
| `64` | Command or flag usage is invalid. |
| `65` | Input or local configuration is invalid. |
| `69` | The configured LLM or required service is unavailable. |
| `74` | Persistence or session-log output failed. |
| `75` | Execution ownership is held by another process; retry later. |
| `77` | A required approval was denied or unavailable. |
| `130` | The user cancelled execution with SIGINT. |

The JSON `run_failed` event includes a stable machine-readable `code` before
the process exits non-zero.

## Approval And Questions

Interactive TTY mode presents typed approval and question events. The terminal
presenter must show the capability, risk, target, command or mutation summary,
and whether the decision can be remembered.

Non-TTY mode fails closed when an action requires approval. It emits
`approval_required`, then `run_failed` with exit code `77`; the absence of a GUI
never grants approval. CLI0 does not expose an option that silently converts a
pending approval into consent.

Computer Use is unavailable from the headless CLI. It remains reserved until a
dedicated host, fresh arming flow, and observable approval boundary exist.

## Cancellation And Ownership

SIGINT stops new LLM and tool work, cancels owned child processes through the
existing process lifecycle, flushes session logs, persists resumable state when
safe, and exits `130`. A second SIGINT may force immediate termination.

Before publishing `run_started`, the shared runtime acquires ownership of the
conversation and, for Coding and Plan Mode, the canonical effective workspace.
It then refreshes the conversation from the authoritative drift repository so
the turn cannot mutate a stale frontend cache. A conflict emits only a terminal
`run_failed` event with code `execution_lease_conflict` and exit code `75`.

Ownership remains held until pending conversation persistence drains after a
completed, failed, or cancelled turn. Runtime shutdown also waits for pending
preparation and ownership release. `conversations resume` uses this same leased
refresh boundary. Read-only `conversations list` and `conversations show` do not
acquire an execution lease because they cannot mutate persisted conversation
state.

Chat-memory refresh-and-merge mutations acquire a short global lease under the
same data root. The CLI3 contention gate runs GUI-like and terminal-like owners
in separate operating-system processes against the same conversation,
canonical workspace, and chat-memory resources. Its schema-versioned report
must recommend `investigate_local_daemon` if an operation times out, an owner
diagnostic is invalid, or the configured p95 threshold is exceeded. Three
representative CLI3 runs instead recorded `direct_file_locking_sufficient`.

## CLI0 Verification Boundary

The CLI0 headless lane must reuse the same TODO fixture, exact short prompt,
saved workflow expectations, independent post-validator, session-log schema,
and report vocabulary as the macOS application lane. It records duration,
tool-loop count, recovery count, approval decisions, and session-log paths.

The macOS lane remains the gate for app bootstrap, localization, proposal UI,
approval rendering, and screenshots. The headless lane remains the frequent
weak-model and repeatability gate. Neither result substitutes for the other.
