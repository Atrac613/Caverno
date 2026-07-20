# Chat Completion Response Normalizer

## Task

- Goal: Extract non-streaming assistant response normalization from
  `ChatRemoteDataSource` into a focused, directly testable data-layer service.
- User-visible behavior: Preserve reasoning tags, native and embedded tool-call
  handling, finish reasons, raw parse-failure recovery, and sanitized tool
  arguments for every OpenAI-compatible provider response.
- Non-goals: Do not change HTTP transport, request construction, reasoning
  retries, streaming accumulation, telemetry, image handling, tool-result
  prompting, or ChatNotifier tool-loop behavior.

## Context

- Affected files or components:
  - `lib/features/chat/data/datasources/chat_remote_datasource.dart`
  - `lib/features/chat/data/datasources/chat_completion_response_normalizer.dart`
  - `test/features/chat/data/datasources/chat_completion_response_normalizer_test.dart`
  - `test/features/chat/data/datasources/chat_remote_datasource_test.dart`
  - `test/quality/file_size_ratchet_test.dart`
- Related docs:
  - `docs/large_file_refactor_plan.md`
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference implementation or pattern:
  - `lib/features/chat/data/datasources/mcp_tool_result_normalizer.dart`
  - `lib/features/settings/data/model_metadata_parser.dart`
- Known compatibility rules:
  - Non-empty reasoning precedes content in one `<think>...</think>` block.
  - Native tool calls take precedence over textual tool calls.
  - Textual calls are promoted for an ordinary response only when every call
    names a tool advertised in that request.
  - A promoted textual call forces the finish reason to `tool_calls`.
  - A missing provider finish reason falls back to `stop`.
  - Recoverable raw parser output accepts completed textual tool calls without
    an advertised-tool filter because the provider response could not be
    decoded far enough to retain request metadata.
  - Malformed native arguments preserve the call with an empty argument map.

## Implementation Notes

- Preferred approach:
  - Add an immutable normalized response value and a stateless normalizer.
  - Move reasoning composition, native call conversion, advertised embedded
    call selection, and raw parser recovery behind that service.
  - Keep logging, usage extraction, last-finish-reason assignment, exception
    propagation, and request-specific control flow in `ChatRemoteDataSource`.
  - Retain datasource product-path tests and add exhaustive direct tests.
- Constraints:
  - The normalizer may depend on `openai_dart`, `ContentParser`, and domain tool
    call values, but not on HTTP clients, Flutter widgets, Riverpod, providers,
    ChatNotifier, or mutable application state.
  - Preserve the public datasource API and response values.
  - Lower the datasource line-count ratchet and add a non-increasing normalizer
    ratchet after extraction.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `_parseToolCalls`, `_parseEmbeddedToolCalls`,
  `_parseAdvertisedEmbeddedToolCalls`, `_tryRecoverRawAssistantTextFromError`,
  `reasoningContent`, `finishReason`, `ChatCompletionResult`.
- Files or modules inspected:
  - `lib/features/chat/data/datasources/chat_remote_datasource.dart`
  - `lib/features/chat/data/datasources/mcp_tool_result_normalizer.dart`
  - `test/features/chat/data/datasources/chat_remote_datasource_test.dart`
- Follow-up tasks found: Re-rank the remaining streaming transformation and
  request-building concerns after this extraction. Do not combine them here.

## Acceptance Criteria

- Required behavior:
  - Plain, reasoning-only, and reasoning-plus-content responses normalize
    without changing text or tag order.
  - Native tool calls retain IDs, names, sanitized arguments, and precedence.
  - Advertised textual tool calls promote only when all names are allowed.
  - Raw parse failures recover normalized channel markers and completed calls.
- Edge cases:
  - Null content and finish reason produce empty content and `stop`.
  - Empty or malformed native arguments produce an empty argument map.
  - Unknown or partially completed textual calls do not promote.
- Failure paths: Non-matching or empty parser errors remain unrecoverable and
  continue through the datasource exception path.
- Accessibility, localization, or platform expectations: No UI or platform
  behavior changes.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/data/datasources/chat_completion_response_normalizer_test.dart \
  --test test/features/chat/data/datasources/chat_remote_datasource_test.dart \
  --test test/quality/file_size_ratchet_test.dart
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: Extracted reasoning composition, native and embedded tool-call
  normalization, finish-reason selection, and raw parse-failure recovery into
  a 183-line stateless data-layer service. The datasource retains transport,
  request construction, telemetry, retries, streaming state, and logging.
- Tests run: The focused verifier passed analysis, 109 root tests, and 13
  internal-package tests. The full verifier passed analysis, 3,944 root tests,
  and 13 internal-package tests.
- Coverage or low-coverage notes: Full line coverage reached 75.19%
  (53,557/71,231). The normalizer reached 100.00% (60/60),
  `chat_remote_datasource.dart` reached 52.81% (263/498), and their combined
  executable coverage is 57.89% (323/558).
- Risks or follow-ups: No transport or tool-loop behavior changed. Re-rank the
  remaining request-building and streaming transformations before another
  datasource move. The next independent contract candidate is MessageInput.
