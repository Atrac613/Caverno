# LLM Session Logs

Caverno writes LLM request and response exchanges as JSONL logs so Codex can
analyze model behavior, tool loops, auto-review decisions, and routine runs
after the fact.

## Location

- Default root: `$HOME/.caverno/session_logs/`
- Override root: `CAVERNO_SESSION_LOG_DIR`
- Workspace subdirectories: `chat/`, `coding/`, and `routines/`
- File name: the sanitized session identifier with a `.jsonl` extension

## Enablement

Session logs are opt-in. They are disabled by default, including release builds.

- In the app, enable them from Advanced > Debug > Save LLM session logs.
- For local diagnostics, set `CAVERNO_SESSION_LOG_ENABLED=1`.
- Set `CAVERNO_SESSION_LOG_ENABLED=0` to force logging off even when the app
  setting is enabled.

## Retention

Session logs use bounded local retention by default:

- `CAVERNO_SESSION_LOG_MAX_FILE_BYTES`: maximum active log file size before
  rotation. Defaults to `10485760` bytes. Set to `0` to disable size rotation.
- `CAVERNO_SESSION_LOG_MAX_AGE_DAYS`: maximum file age before pruning. Defaults
  to `30` days. Set to `0` to disable age pruning.
- `CAVERNO_SESSION_LOG_MAX_ROTATED_FILES`: number of rotated files to keep per
  session. Defaults to `4`. Set to `0` to discard the active file when it
  exceeds the size limit instead of keeping rotated copies.

## Entry Format

Each line is one JSON object with schema name
`caverno_llm_session_log_entry`. Entries include:

- Session context such as workspace mode, session id, title, conversation id,
  routine id, routine run id, and phase
- Operation name such as `streamChatCompletionWithTools` or
  `createChatCompletionWithToolResults`
- Request messages, model, temperature, max token budget, tools, and tool
  result payloads when available
- Response content, finish reason, tool calls, token usage, or error details

## Sensitivity

Treat session logs as sensitive local diagnostic artifacts. Redaction removes
known secret-like fields, common embedded token patterns, private key blocks,
authorization headers, sensitive query parameters, and large inline media
payloads. Prompts, tool arguments, command output, file diffs, auto-review
packets, and routine outputs can still contain private data.

Do not commit generated session log files.

## Analysis Workflow

When debugging a session with Codex:

1. Identify the relevant workspace subdirectory.
2. Open the matching `.jsonl` file for the conversation or routine run.
3. Inspect entries in timestamp order.
4. Compare the model request, tool calls, tool results, and final response.
5. Check whether auto-review or memory extraction introduced a secondary LLM
   call that affected the turn.

## Recommended Next Improvements

- Add a small log export or bundle command that collects one session with
  metadata useful for Codex analysis.
- Add a manual redaction review command for sharing a log bundle outside the
  local machine.
- Add tests for redaction coverage and log compatibility before changing the
  schema version.
