# Caverno CLI Terminal Contract

Status: CLI0 design baseline. The public executable described here is not yet
released. CLI0 may use a test-runner entrypoint to measure no-window behavior,
but that entrypoint is not the product CLI.

## Commands

The supported command family will be:

```text
caverno chat [input options]
caverno coding --project <path> [input options]
caverno plan --project <path> [input options]
```

Exactly one input source is accepted:

- `--prompt <text>` for a literal prompt.
- `--prompt-file <path>` for UTF-8 file input.
- stdin when neither prompt flag is present and stdin is not a TTY.
- An interactive TTY prompt when no other input source is present.

Conflicting explicit input sources are a usage error. Empty non-interactive
input is an input error and must not start an LLM request.

## Configuration Precedence

Configuration resolves in this order, from highest to lowest priority:

1. Command flags.
2. `CAVERNO_*` environment variables.
3. Existing Caverno user settings when their schema is compatible.
4. Application defaults.

The effective endpoint, model, workspace, approval mode, output mode, and data
directory must be observable in startup diagnostics. API keys and other
secrets must remain redacted.

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

The initial event types are `run_started`, `assistant_delta`, `tool_lifecycle`,
`approval_required`, `question_required`, `usage`, `run_completed`, and
`run_failed`. Automation must consume these events rather than parse formatted
terminal prose.

## Exit Codes

| Code | Meaning |
| ---: | --- |
| `0` | The requested turn completed successfully. |
| `2` | Execution reached a verified blocked or failed task state. |
| `64` | Command or flag usage is invalid. |
| `65` | Input or local configuration is invalid. |
| `69` | The configured LLM or required service is unavailable. |
| `74` | Persistence or session-log output failed. |
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

Before the GUI and CLI can write the same conversation or coding project, the
runtime must acquire explicit ownership. A lock conflict fails with an
actionable message; it must not permit concurrent mutation by default.

## CLI0 Verification Boundary

The CLI0 headless lane must reuse the same TODO fixture, exact short prompt,
saved workflow expectations, independent post-validator, session-log schema,
and report vocabulary as the macOS application lane. It records duration,
tool-loop count, recovery count, approval decisions, and session-log paths.

The macOS lane remains the gate for app bootstrap, localization, proposal UI,
approval rendering, and screenshots. The headless lane remains the frequent
weak-model and repeatability gate. Neither result substitutes for the other.
