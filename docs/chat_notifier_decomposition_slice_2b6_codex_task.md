# ChatNotifier Decomposition Slice 2b6: Compact Protected-Path Isolation

## Task

- Goal: make compact tool-result budgeting preserve target-file evidence from
  the owning interaction generation rather than the visible conversation.
- User-visible behavior: context-length recovery for a background turn retains
  the evidence needed for that turn's saved target files and does not protect a
  different visible task's files.
- Destination API:
  - resolve `_contextSurgeryProtectedPathsForGeneration(int generation)` once at
    a generation-aware boundary;
  - pass an immutable `Set<String> protectedPaths` into
    `_budgetToolResultsForPrompt`,
    `_hasAdditionalCompactToolResultBudget`, and
    `_buildToolResultAnswerMessages`.
- Non-goals:
  - changing compact-result limits, stub wording, deduplication order, or path
    normalization;
  - changing history compaction policy;
  - changing context-surgery observation UI;
  - extracting context surgery or final-answer recovery;
  - adding a notifier part.

## Context

- Affected production files:
  - `lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_final_answer_recovery.dart`.
- Direct deterministic test file:
  `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`.
- Existing regression files:
  - `test/features/chat/domain/services/tool_result_prompt_builder_test.dart`;
  - `test/features/chat/domain/services/context_surgery_observation_service_test.dart`;
  - `test/features/chat/presentation/providers/chat_notifier_context_surgery_part.dart`;
  - `test/features/chat/presentation/providers/chat_notifier_final_answer_recovery_part.dart`.
- Exact source methods and call sites:
  - `_contextSurgeryProtectedPaths` reads visible `currentConversation` and its
    `executionFocusTask`;
  - `_budgetToolResultsForPrompt` calls it only in compact mode;
  - `_hasAdditionalCompactToolResultBudget` calls it before deciding whether a
    context retry can reduce the payload;
  - `_buildToolResultAnswerMessages` calls the budget helper;
  - `_createToolResultCompletionWithContextRetry` already receives
    `interactionGeneration` and uses both budget helpers;
  - `_streamToolResultAnswerWithContextRetry` already receives
    `interactionGeneration` and calls `_buildToolResultAnswerMessages` in normal,
    compact, and concise-recovery paths.
- Current gap: service-level tests prove protected-path behavior for explicit
  sets, but notifier tests never switch to a conversation with a different
  saved target before compact retry.

## Implementation Notes

- Resolve the owning conversation through `_conversationForGeneration` while
  the generation is registered.
- Convert its execution-focus target files into a trimmed
  `Set<String>.unmodifiable`. Empty or missing task state produces
  `const <String>{}`.
- Pass that immutable set down through every compact-result path. Lower-level
  prompt builders must not read a conversation, provider, or `ChatState`.
- Thread `protectedPaths` through:
  - both sends inside `_createToolResultCompletionWithContextRetry`;
  - `_hasAdditionalCompactToolResultBudget`;
  - `_buildToolResultAnswerMessages`;
  - concise and streamed branches in
    `_streamToolResultAnswerWithContextRetry`.
- Normal budget mode remains behaviorally identical; it may receive an empty
  set and must not add protection accidentally.
- Keep `ToolResultPromptBuilder` as the pure destination policy. The notifier
  supplies only immutable paths and tool results.
- Typed side-effect ports:
  - LLM retry remains the existing `ChatDataSource`;
  - context-surgery observation remains notifier-owned;
  - no new callback or broad context object is permitted.
- Generated files and migrations: none.

## Deterministic Two-Thread Cases

Configure A with protected `lib/a.dart` and B with protected `lib/b.dart`.
Provide oversized duplicate/stale `read_file` results for both paths:

1. Start A's tool-result completion, switch to B before the first request
   returns a context-length error, then inspect A's compact retry.
2. In A's retry, the older A result must remain full because it is protected.
   The older B result may be replaced by the existing compact stub.
3. Invert the owners and prove B protects only `lib/b.dart`.
4. Assert `_hasAdditionalCompactToolResultBudget` reaches the same decision from
   the same owner-protected set used by the actual retry payload.
5. Exercise both non-streaming
   `_createToolResultCompletionWithContextRetry` and streamed final-answer
   recovery.
6. Assert normal mode remains unchanged and no foreign path appears in the
   owner-protected set.

Inspect actual tool-result prompt payloads and retained/stubbed result IDs.
Testing only the helper's returned set is insufficient.

## Similar-Pattern Search

- Search terms:
  - `_contextSurgeryProtectedPaths`;
  - `_budgetToolResultsForPrompt`;
  - `_hasAdditionalCompactToolResultBudget`;
  - `_buildToolResultAnswerMessages`;
  - `protectedPaths`;
  - `_hasCompactablePromptHistory`;
  - `currentConversation`.
- Inspect every compact retry and concise-recovery call site.
- `_hasCompactablePromptHistory` also reads visible messages/conversation.
  Record it as a deferred adjacent finding unless it prevents a deterministic
  protected-path test; do not silently expand this slice into history ownership.
- Record context-surgery observation projection contamination separately.

## Measurement, Manifest, and Coverage

- Expected declared notifier-part delta: `0`; the count remains `42`.
- Target same-library aggregate delta: `0`; reductions are acceptable, but the
  aggregate must remain at or below `22,900` physical lines.
- Manifest records `context_surgery` and `final_answer_recovery` remain
  `remaining`; no collaborator record or discovery marker is added.
- No size budget may increase.
- Current coverage baselines:
  - `chat_notifier_context_surgery.dart`: `98/109` (`89.91%`);
  - `chat_notifier_final_answer_recovery.dart`: `85/97` (`87.63%`);
  - `chat_notifier.dart`: `3,089/3,688` (`83.76%`).
- Coverage expectation: no changed target regresses; the checked primary target
  remains at least `89.91%`, and both streaming and non-streaming ownership
  branches are hit.

## Acceptance Criteria

1. Compact-result protected paths come only from the owning generation's
   execution-focus task.
2. A visible foreign task cannot add or remove protection for a detached turn.
3. The same immutable path set drives retry eligibility and retry payload
   budgeting.
4. Streaming, non-streaming, and concise-recovery paths preserve ownership.
5. Existing compact limits, stub payloads, result ordering, and normal mode
   remain compatible.
6. Lower-level budget and prompt helpers no longer read conversation state.
7. Adjacent history and observation findings are recorded without widening the
   slice.
8. No part, manifest, marker, schema, generated file, or budget change.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart \
  lib/features/chat/presentation/providers/chat_notifier_final_answer_recovery.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --set-exit-if-changed
tool/codex_verify.sh \
  --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --test test/features/chat/domain/services/tool_result_prompt_builder_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
tool/codex_verify.sh --coverage
awk -v target='lib/features/chat/presentation/providers/chat_notifier_context_surgery.dart' \
  -v minimum=89.91 '
    /^SF:/ { selected = index(substr($0, 4), target) > 0 }
    selected && /^LF:/ { found = substr($0, 4) + 0 }
    selected && /^LH:/ { hit = substr($0, 4) + 0 }
    END {
      rate = 100 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      exit !(found > 0 && rate + 0.001 >= minimum)
    }
  ' coverage/lcov.info
git diff --check
```

The corrected Slice 2b1 live canary is required because this slice changes
production prompt-context and recovery code. Record the actually reachable
base URL and exact warmed model.

## Stop Conditions

- Stop if protected paths cannot be resolved before the generation registration
  is cleared.
- Stop if the proposed lower-level API accepts `Conversation`, `ChatState`,
  `Ref`, or a notifier-capturing callback instead of immutable paths.
- Stop if passing the test requires changing compaction thresholds, result
  order, or stub semantics.
- Stop and record `_hasCompactablePromptHistory` or observation ownership as
  follow-ups unless one directly blocks this slice's poison case.
- Stop if the fix requires a new notifier part, production extraction, schema
  change, or aggregate budget increase.

## Handoff Notes

- Record both protected path sets, result IDs, and retained/stubbed outcomes.
- Record which request triggered context-length recovery.
- Record target-file coverage and aggregate line counts.
- Record every prompt-budget call site receiving the immutable set.
- Keep this slice in one focused Conventional Commit.

## Implementation Evidence

Implementation commit `45c796dc` resolves protected paths once from the
registered interaction owner and passes one immutable set through retry
eligibility, compact payload construction, and concise recovery. Deterministic
A/B fixtures prove that non-streaming, streaming, and concise retries retain
only the owner's older result, compact the foreign older result, and make retry
eligibility from the identical path set without changing normal-mode behavior,
result order, compact limits, or stub payloads.

The specified focused coverage command passed all 401 tests. The detached file
previously passed all 37 tests, and the final matrix plus its earlier focused
cases were rerun successfully. Analyze, the file-size ratchet, the refreshed
audit baseline, the acceptance/stop-condition audit, and `git diff --check`
passed.

Fresh LCOV reports context surgery at `100/107` (`93.46%`), final-answer
recovery at `87/98` (`88.78%`), and the notifier at `3,127/3,731` (`83.81%`),
above all declared floors. The primary file is 9,374 lines, the part count
remains 42, and the aggregate remains 22,887 lines. The audit removed one
ambient read and one turn-reachable read. Manifest status, schema, generated
files, and budgets remain unchanged.

`tool/codex_verify.sh --coverage` completed generation, analysis, and package
tests before the root suite reached `+4208 -2`. Its only failures were unrelated
existing M33 tests:

- `M33 release packaging report validates static packaging lane` found
  `report.ready == false`;
- `M33 release packaging CLI writes JSON and Markdown outputs` expected
  `Ready: true` but received `Status: blocked`, `Ready: false`, with
  `sparkle_appcast_configuration`, `sparkle_s3_public_read_config`, and
  `sparkle_public_release_verifier` failed.

Those fixtures predate `45c796dc`, reflect separate packaging drift, and are in
files untouched by this slice.

The exact-model corrected Slice 2b1 live canary passed on 2026-07-28 against
loaded `qwen3.6-27b-vision` at `http://192.168.100.241:1234/v1`. Its exact exit
maps and zero-busy-owner evidence are recorded in the Slice 2b1 handoff. This
completes Slice 2b6.
