# Shared Chat Turn Harness Foundation

## Task

- Goal: Promote the reusable scripted-model behavior currently implemented by
  `_SequencedToolDataSource` into shared test support, add append-only request
  and runtime-event recording, and migrate its existing callers without
  changing production behavior.
- User-visible behavior: None. This is a test-only characterization foundation.
- Non-goals: Changing `ChatNotifier`, renaming or expanding `TurnRuntime`,
  introducing `ThreadRuntime`, deciding whether one conversation permits
  overlapping protocol turns, changing tool policy, or adding an HTTP mock
  server.

## Context

- Affected files or components:
  - new `test/support/chat_turn_harness.dart`;
  - new focused tests for the support API;
  - `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`;
  - no file under `lib/` or `packages/`.
- Related docs:
  - `docs/chat_notifier_renewal_state_of_play_codex_task.md`;
  - `docs/turn_runtime_codex_reference_findings.md`;
  - `docs/session_logs.md` for the distinction between test capture and
    sensitive production logging.
- Reference implementation or pattern:
  - `_SequencedToolDataSource` at
    `chat_notifier_detached_turn_project_test.dart:783`;
  - the real interleaving test `detached owner waits for pending content tool
    before terminal event` in the same file;
  - Codex `tmp/codex/codex-rs/core/tests/common/test_codex.rs` for real-runtime
    composition;
  - Codex `tmp/codex/codex-rs/core/tests/common/responses.rs` for declarative
    response sequences and exact request capture;
  - Codex `tmp/codex/codex-rs/core/tests/common/streaming_sse.rs` for explicit
    barriers.
- Known quirks, compatibility rules, or release gates:
  - A streamed `sendMessage` may return before its terminal callback and
    persistence release complete. Runtime terminal events, not the method
    return alone, define completion.
  - `lastFinishReason` and `lastUsage` are compatibility surfaces whose ambient
    reads must remain poisoned in owner-scoped tests.
  - `StreamWithToolsResult.stream` and `completion` have independent timing.
    The harness must preserve that distinction.
  - Existing tests may rely on the private double's fallback response. Preserve
    compatibility during the move, but expose request counts so later strict
    scenarios can assert exact script consumption.
  - Recorded prompts and tool results are test-process data. Do not write them
    to repository or session-log files.

## Implementation Notes

- Preferred approach:
  1. Move the behavior of `_SequencedToolDataSource` into a shared
     `ScriptedChatDataSource` in `test/support/chat_turn_harness.dart`.
  2. Represent initial and tool-result responses as immutable scripted steps.
     A step may expose an optional asynchronous barrier before its completion
     becomes observable.
  3. Record every outbound call in one append-only ledger. Each record names
     the data-source method and captures immutable messages, advertised tool
     definitions, input tool results, model, temperature, and max-token values
     that the method received.
  4. Provide an append-only `RuntimeEventLedger` over
     `Stream<CavernoRuntimeEvent>`. A predicate wait returns the matching event
     without consuming or deleting unmatched events.
  5. Replace all `_SequencedToolDataSource` callers in the detached-turn test
     with the shared implementation, then delete the private class. Keep local
     scenario-specific tool services and `ProviderContainer` composition local.
  6. Use the shared request and event ledgers in the existing detached-owner
     interleaving test to assert that thread B terminalizes before thread A while
     both requests remain attributable to their original conversations.
- Constraints:
  - Production source is unchanged.
  - The harness drives the real `ChatNotifier` and existing
    `CavernoExecutionRuntime`; it does not reproduce their state machines.
  - Capture values are defensive, unmodifiable copies.
  - Wait helpers use bounded timeouts and report the recorded ledger on failure.
  - The support API remains narrowly test-oriented. Do not export it from a
    production library.
  - Preserve the existing double's streaming and non-streaming method coverage;
    do not funnel semantically distinct methods through an inaccurate shortcut.
- Generated files needed: None.
- Migration or data compatibility concerns: None. This is a test-only move.

## Similar-Pattern Search

Before finishing, identify which other doubles can later adopt the support API
without migrating them in this slice.

- Search terms:
  - `implements ChatDataSource`;
  - `extends ChatRemoteDataSource`;
  - `streamedRequestMessages`;
  - `toolResultBatches`;
  - `beforeInitialResponse`;
  - `beforeToolResultResponse`.
- Files or modules inspected:
  - `test/features/chat/presentation/providers/chat_notifier_test_doubles_part.dart`;
  - `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`;
  - other chat provider tests found by the search.
- Follow-up tasks found:
  - H1: express two-thread pause/switch/complete/resume through the shared
    harness with full request, tool, UI, event, and teardown assertions.
  - H2: characterize same-conversation replacement and stale-completion
    fencing before proposing a per-thread active-turn slot.

## Acceptance Criteria

- Required behavior:
  - `test/support/chat_turn_harness.dart` supplies one shared scripted data
    source with initial-response and tool-result-response sequencing.
  - Every supported data-source method records an immutable outbound request
    before exposing its response.
  - The ledger exposes exact request counts and preserves original call order.
  - Script barriers can deterministically pause and release response completion.
  - Runtime-event waits do not remove unmatched events.
  - The detached-turn test has no `_SequencedToolDataSource` declaration or
    reference after migration.
  - The existing detached-owner interleaving test still observes thread B's
    terminal event before thread A's and now asserts through the shared ledgers.
  - No production file changes.
- Edge cases:
  - Script exhaustion produces the compatibility fallback only where explicitly
    enabled and is visible in the ledger.
  - Empty streamed content, tool-free completions, one tool result, and batched
    tool results retain their existing semantics.
  - Waiting for a later event does not hide an earlier unmatched event from a
    subsequent assertion.
- Failure paths:
  - Barrier timeout includes outstanding step and recorded request diagnostics.
  - Unexpected shared `lastFinishReason` or `lastUsage` reads still fail the
    owner-scoped test immediately.
  - Closing the event ledger cancels its stream subscription and settles or
    fails outstanding waits deterministically.
- Accessibility, localization, or platform expectations: None. The support
  API contains no user-facing text or platform integration.

## Verification

Run the support tests and the migrated detached-turn suite first:

```bash
tool/codex_verify.sh \
  --test test/support/chat_turn_harness_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
```

Then run the repository gate because the moved double is used by many scenarios
inside the detached-turn suite:

```bash
tool/codex_verify.sh
```

Confirm the production tree did not change:

```bash
git diff --name-only -- lib packages
```

## Handoff Notes

- Summary:
- Tests run:
- Request and event assertions migrated:
- Other doubles suitable for later migration:
- Risks or follow-ups:
