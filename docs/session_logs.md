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
2. Start with the bounded summary command:
   `dart run tool/caverno_session_log_summary.dart --log path/to/session.jsonl`
3. Open the matching `.jsonl` file only when the summary flags an error, a
   loop-limit prompt, missing final answer, malformed lines,
   `coding_action_promise_without_tool`, or ambiguous tool call sequence.
4. Inspect entries in timestamp order.
5. Compare the model request, tool calls, tool results, and final response.
6. Check whether auto-review or memory extraction introduced a secondary LLM
   call that affected the turn.

Entries store Caverno's normalized response shape directly. Inspect
`response.content`, `response.finishReason`, `response.toolCalls`, and
`response.usage` instead of assuming an OpenAI `choices[]` wrapper. Start with a
compact per-line metadata summary before reading large message payloads so a
debugging turn does not spend most of its tool budget on repeated ad hoc
parsing.

`response.content` is the **raw model output**, not the message the user saw.
After a response is received, `ChatNotifier` runs post-response guards that can
rewrite or annotate the final assistant message before it is displayed — e.g.
completion/success claims contradicted by a failed or missing tool result are
replaced with an "unverified / not executed" notice
(`_replaceFailedCommandSuccessClaimIfNeeded`, `_buildUnexecutedCommandActionToolResult`,
`_appendUnexecutedToolRequestNoticeForContentIfNeeded`). So a log line such as
"committed successfully" after a failed `git commit` may already have been
neutralized on screen. Before concluding the model misled the user, reproduce
the turn with a `sendMessage` test and assert on `state.messages.last.content`
rather than trusting the logged `response.content`.

For streaming operations wrapped by `SessionLoggingChatDataSource`, `stream_end`
means Caverno finished reading the stream and wrote the accumulated text to the
log. It is not an interruption signal by itself. Treat it as suspicious only
when paired with an explicit `error`, an empty or visibly incomplete final
answer, or a tool-loop limit prompt without a usable final answer.

For coding turns, `coding_action_promise_without_tool` means the final response
looked like a promise to inspect, edit, run, port, or otherwise continue work
while no tool call was emitted. Treat it as the continuation-stall signature:
the turn should be recovered before the response is saved or used for memory
extraction.

## Recommended Next Improvements

- Add a small log export or bundle command that collects one session with
  metadata useful for Codex analysis.
- Add a manual redaction review command for sharing a log bundle outside the
  local machine.
- Add tests for redaction coverage and log compatibility before changing the
  schema version.
