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

Session logs are on by default in debug builds, and on in release builds for
any install that predates the setting — `SettingsRepository` migrates those to
enabled once, so feedback and diagnostic flows can include the current session
trace when the user submits feedback. A *fresh* release install starts disabled
(SEC4.6k-C); the user opts in.

- In the app, toggle them at Advanced > Logging > Save LLM session logs. The
  same page lists the approval audit trail and the app log file, each with a
  "Delete saved files" action. The app log file is not debug-only: it writes in
  release builds too when enabled. The audit trail has no switch — it is always
  on, and only the delete action clears it.
- Turning a switch off only stops new writes. Nothing prunes on a timer, and
  both the audit trail and the app log file prune only while writing, so use
  the delete action to clear what is already on disk.
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
  result payloads when available. Schema v5 also records `tool_choice`, the
  top-level `enable_thinking` value, and `chat_template_kwargs` so strict tool
  requests can be compared with the exact post-policy wire controls without
  recording credentials. A first-party structured tool result can also
  carry optional `request.toolResults[].outcome` facts such as exit status,
  file change/identity, or diagnostic counts. The outcome is additive and can
  be absent for older entries and tools without a trustworthy typed fact.
  A result re-sent from an earlier loop across file writes also carries
  `request.toolResults[].changesSinceCapture`, the `<tool> <path>` writes it
  predates; the model sees the same list stated beside the result.
- `request.label` (schema v3), naming the producer that issued the call —
  `turn opening request`, `tool-result follow-up`, `coding verification
  feedback`, `narrated transcript feedback`, `blocked production release
  retry`, and so on. Several producers share one operation name, so without
  the label a request cannot be attributed to a code path. This is what makes
  a tool catalogue that changes shape mid-loop diagnosable: compare the tool
  list of two adjacent requests and read which producer built the odd one out.
  The field is absent when no producer set a label.
- `request.usageRole` (schema v4), naming which part of the app the request was
  booked to — `chat`, `memoryExtraction`, `planning`, `subagent`,
  `anabasisParent`, `routine`, and so on. Always written, including as
  `unknown`: an entry point that claimed no role is a gap worth seeing, and a
  missing field would read as "not recorded yet" instead. Before this field the
  only way to tell which role a request ran under was to grep the logged system
  prompt for text unique to it, which is how the Anabasis parent was found
  running under the wrong role while every test passed.
  Captured by the caller at issue time, never by the writer: the record is
  written once the response lands, and a streaming body is listened to outside
  the caller's zone, so the writer's view of the ambient role is not the
  caller's.
- Response content, finish reason, tool calls, token usage, or error details
- Turn-level markers such as `turn_exit`, `goal_auto_continue`,
  `primary_model_route`, `goal_completion_shadow`, `execution_shadow`,
  `tool_outcome_shadow`, and `shell_write_observation`,
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
  `shell_write_observation` exists only when
  `CAVERNO_SHELL_WRITE_OBSERVATION=1` (macOS, SEC4.4i-a). It lists the paths
  outside the project that one `local_execute_command` shell command wrote,
  read back from seatbelt reports after the tool result, so it lands later in
  the file than the call it names (`toolCallId`, `tag`). The kernel can drop
  reports, so the list is a lower bound. It stores paths only, never the
  command or its output.
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

Coding prose warnings (`coding_action_promise_without_tool` and
`coding_task_incomplete`) inspect visible text after removing thinking and tool
artifacts. They are advisory diagnostics: their language-dependent patterns do
not authorize project-task continuation or change the summary result.
A summary result of `complete` in an older log means a final response exists;
it does not certify implementation or verification success.

Project Farm implementation turns carry explicit turn metadata. Before their
final response is saved, the harness requests `update_goal` when typed
status is missing or reports remaining work. This request offers only
`update_goal`; subsequent work follows the normal tool and approval gates.
The status elicitation also sets a function `tool_choice` for `update_goal`;
its acknowledgement follow-up does not force another status call.
Exactly one valid `update_goal` call is accepted. Missing status, other tools,
or invalid arguments receive one protocol correction and one retry. Rejected
calls are never dispatched; a second violation records missing status.
An accepted completion requires captured file changes and a successful terminal
execution after the latest change, with no unresolved contradictory evidence.
A progress report can resume the tool loop; a blocker, approval, user question,
budget cap, or already accepted completion prevents this recovery. Dedicated
review turns and ordinary chat do not opt into this protocol through prose.
Another status request requires new mutation hashes or successful verification
evidence, with at most three recovery boundaries per turn and two requests
per boundary. Repeated reads and equivalent verifier results do not renew
this budget.

The `coding_task_status_*` turn transforms record the reconciled acknowledgement.
The exit record is written after goal reconciliation so it includes that status.
Only `coding_task_status_completionRecorded` settles the implementation status.
Other recorded statuses produce `coding_task_status_unresolved` and an
`incomplete` summary. A later terminal turn supersedes an earlier unresolved
status. Language-dependent diagnostics remain visible as history.

Command output feedback records its source `tool_call_id`. Completion evidence
and final-answer prompts supersede an earlier pytest invocation only when a
later invocation in the same absolute working directory verifies the same
pytest arguments with a terminal typed zero exit and positive passing runner
counts, without failed tests or output issues. Python executable selection and
a trailing output-only `tail -N` pipeline may differ. Other targets, options,
directories, unknown shell syntax, and unknown outcomes do not settle the old
diagnostic. Original tool results remain in the log and execution ledger.
One literal `cd <directory> &&` prefix is resolved before comparison; quoted
literal paths and arguments are supported without shell expansion. Successful
pytest replay candidates retain the actual runner and effective directory,
omitting only the recognized directory and output wrappers. Failed pytest
invocations do not replace a captured working verifier.
If the model returns to an earlier failed runner, the harness may reuse a later
passing result for the same directory and pytest arguments. It requires no
observed mutation or unknown command between failure and success or after
success, no changed read hash, no later failure, and no pending mutation.
The result identifies the captured runner, source call, and requested command
and explicitly marks execution reuse; it does not claim a new execution.

Optional environment inspection composed solely of literal `cd`, `ls`, `pwd`,
`which`, and Python version queries may end in `|| true` without producing a
task failure. It never counts as verification. Unknown commands, mutations,
masked checks, and actual runtime failure output retain their diagnostics.

A zero exit code from a pipeline is not successful verification when its output
reports a Python missing module or failed pytest tests. These output diagnostics
identify execution failures rather than infer the user's or model's intent.

The summary reports `all_calls_discarded` when the latest recorded turn ended
after repeated tool calls were skipped, even if a final answer exists. This
is a tool-loop stop, not proof that the requested task is complete. Check the
mutation and verification results. An `unwritten_file_claim` warning records
the corresponding turn-exit guard; raw model claims alone are not file-change
evidence.

## Recommended Next Improvements

- Add a small log export or bundle command that collects one session with
  metadata useful for Codex analysis.
- Add a manual redaction review command for sharing a log bundle outside the
  local machine.
- Add tests for redaction coverage and log compatibility before changing the
  schema version.
