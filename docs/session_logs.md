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

Session logs are enabled by default, including release builds, so feedback and
diagnostic flows can include the current session trace when the user submits
feedback.

- In the app, disable them from Advanced > Debug > Save LLM session logs.
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
  result payloads when available. A first-party structured tool result can also
  carry optional `request.toolResults[].outcome` facts such as exit status,
  file change/identity, or diagnostic counts. The outcome is additive and can
  be absent for older entries and tools without a trustworthy typed fact.
- `request.label` (schema v3), naming the producer that issued the call —
  `turn opening request`, `tool-result follow-up`, `coding verification
  feedback`, `narrated transcript feedback`, `blocked production release
  retry`, and so on. Several producers share one operation name, so without
  the label a request cannot be attributed to a code path. This is what makes
  a tool catalogue that changes shape mid-loop diagnosable: compare the tool
  list of two adjacent requests and read which producer built the odd one out.
  The field is absent when no producer set a label.
- Response content, finish reason, tool calls, token usage, or error details
- Turn-level markers such as `turn_exit`, `goal_auto_continue`,
  `primary_model_route`, `goal_completion_shadow`, `execution_shadow`, and
  `tool_outcome_shadow`,
  which make non-request decisions visible in the same JSONL timeline as model
  calls.
  `turn_exit.guardDecisions` records metadata-
  only guard outcomes. Its `completedToolResultFinalAnswerRecovery` field is
  one of `not_evaluated`, `skip_recovery`, or `allow_recovery`; older v2 entries
  can omit the object. `goal_auto_continue` records bounded continue, stop, and
  active-goal skip decisions; its evidence includes the first safe boundary
  veto when one prevented dispatch. `execution_shadow` stores only redacted
  hashes, enum names, counts, and booleans; it excludes contract text, task
  identifiers, and diagnostic text. `tool_outcome_shadow` records the tool
  name, typed-versus-legacy exit-code agreement, both optional exit codes, and
  correlation keys. It deliberately excludes the rendered tool payload.
  `goal_completion_shadow` records one explicit-tool-versus-lexical comparison
  for every turn that started with an active goal. Its `agreement` is `agree`
  or `disagree`; disagreement records also carry a stable `label`. Optional
  tool outcome, lexical completion verdict, and owner-scoped turn id fields
  support diagnosis without mutating goal state. Tool acknowledgement,
  structured task state, and explicit user confirmation own terminal status;
  lexical completion is retained only for this comparison. Older
  disagreement-only markers can omit `agreement`.
  `primary_model_route` records the immutable LL24 route selected at the turn
  boundary: turn id, resolved assistant mode, endpoint id, model, route reason,
  and whether the assignment was demoted to the primary endpoint. It contains
  no prompt or response content and obeys the same settings and environment
  logging gates as request entries.

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
   For corpus-level anomaly ranking and LL34/LL35 agreement counts, use
   `python3 tool/triage_session_logs.py --since-days 2 --top 40 --full`.
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
