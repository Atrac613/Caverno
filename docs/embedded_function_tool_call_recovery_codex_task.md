# Embedded Function Tool-Call Recovery

## Task

- Goal: Execute complete embedded tool calls that use
  `<function=name>` and `<parameter=name>` markup in tool-aware,
  non-streaming completions.
- User-visible behavior: A valid structured tool request emitted after a tool
  result continues through the normal approval and dispatch path instead of
  being treated as final prose.
- Non-goals: Executing tool calls from the final-answer stream, relaxing tool
  approval, changing tool-loop failure policy, or raising iteration budgets.

## Context

- Affected components: `ContentParser`, `ChatRemoteDataSource`, and tool-loop
  regression tests.
- Related docs: `docs/final_answer_tool_request_recovery_codex_task.md` and
  `docs/tool_loop_pending_batch_exit_codex_task.md`.
- Reference pattern: Existing JSON and named-XML embedded tool-call parsing,
  plus raw-response recovery in `ChatRemoteDataSource`.
- Known failure: Live session
  `59907240-ebc9-4fad-93dc-c92c6fb576e3` returned a complete
  `<tool_call><function=delete_file>...` request from
  `createChatCompletionWithToolResults`. The response had `finishReason=stop`
  and no native tool calls, so the requested deletion remained unexecuted and
  required another Goal Auto-Continue turn.

## Implementation Notes

- Parse the compatibility dialect only inside an explicit completed
  `<tool_call>` or `<tool_use>` block.
- Require valid tool and parameter identifiers, a complete function wrapper,
  at least one parameter, and no ambiguous duplicate parameter names.
- When a successful non-streaming response was sent a non-empty tool list and
  contains no native tool calls, promote complete embedded calls to
  `ChatCompletionResult.toolCalls` and report `finishReason=tool_calls` only
  when every embedded call names a tool in that list.
- Native tool calls take precedence over embedded markup to avoid double
  execution.
- Do not change streaming completion handling. Final-answer streaming remains
  non-tool-aware and must not execute embedded calls directly.

## Similar-Pattern Search

- Search terms: `<function=`, `<parameter=`, `_parseEmbeddedToolCalls`,
  `createChatCompletionWithToolResults`, and `scanForTools: false`.
- Files or modules inspected: content parsing, OpenAI-compatible remote data
  source, chat tool loop, routine tool runner, Apple Foundation Models bridge,
  final-answer recovery, and existing parser/notifier tests.
- Follow-up task found: Classify structured verifier failures separately from
  transport or approval failures before considering broader LL29 recovery.

## Acceptance Criteria

- The exact live-log `delete_file` markup parses into one call with `path` and
  `reason` arguments.
- Malformed wrappers, duplicate parameter names, and missing parameters do not
  produce executable calls.
- A successful non-streaming response with advertised tools promotes embedded
  calls only when native tool calls are absent and every tool name was
  advertised.
- Successful responses without advertised tools do not promote embedded calls;
  existing raw parse-failure recovery remains unchanged.
- Existing final-answer streaming does not execute embedded calls directly.
- Promoted calls use the existing approval, dispatch, audit, and deduplication
  paths.

## Verification

```bash
tool/codex_verify.sh --test test/core/utils/content_parser_test.dart
tool/codex_verify.sh --test test/features/chat/data/datasources/chat_remote_datasource_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh
```

After local verification, rerun the exact short TODO Live LLM canary and
confirm that the embedded deletion no longer requires a separate continuation
when the same response shape recurs.

## Handoff Notes

- Preserve the final-answer no-direct-execution boundary.
- Keep verifier failure classification as a separate atomic change.
