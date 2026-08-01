# ChatNotifier Decomposition Slice 2b2: Approval Isolation

## Task

- Goal: prove and enforce that production-release approval belongs to one
  conversation and one interaction generation.
- User-visible behavior: approval in one thread or an earlier turn can no longer
  authorize a production release in another thread or later turn.
- Destination API: make
  `_buildProductionReleaseApprovalGuardResult` consume an immutable
  generation-owned approval-evidence value instead of reading visible
  `state.messages`.
- Non-goals:
  - changing which commands count as production releases;
  - changing approval wording or weakening the existing explicit-approval rule;
  - refactoring unrelated tool approvals;
  - extracting command guardrails or adding a notifier part.

## Context

- Affected production files:
  - `lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier.dart` only for
    generation-owned evidence capture and cleanup.
- Direct deterministic test file:
  `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`.
- Existing regression files to preserve:
  - `test/features/chat/presentation/providers/chat_notifier_git_guardrails_part.dart`;
  - `test/features/chat/presentation/providers/chat_notifier_ask_user_question_part.dart`.
- Exact source methods and call sites:
  - `_buildProductionReleaseApprovalGuardResult` already receives
    `interactionGeneration`;
  - `_hasExplicitProductionReleaseApproval` first calls
    `_latestUserExplicitlyApprovedProductionRelease`;
  - `_latestUserExplicitlyApprovedProductionRelease` and
    `_previousAssistantAskedForProductionReleaseApproval` scan visible
    `state.messages`;
  - `_askUserQuestionTurnCache.anyResult` is already keyed by interaction
    generation;
  - `_executeToolCallBatch` in `chat_notifier_tool_loop_batch.dart` calls the
    production-release guard with the owning generation;
  - `_clearActiveResponseForGeneration` already owns generation cleanup.
- Current gap: a detached turn can evaluate another visible thread's most recent
  user and assistant messages. Direct-message approval also has no durable
  boundary preventing reuse by a later generation.

## Implementation Notes

- Capture direct user approval at turn start, before another thread can become
  visible. The immutable evidence must contain only:
  - `interactionGeneration`;
  - owning `conversationId`;
  - whether the submitted user message explicitly approves production release;
  - whether that submitted affirmative answer immediately follows an owning
    assistant production-release question.
- A private immutable record is sufficient. Do not pass `ChatState`,
  `Conversation`, `Ref`, or a broad callback into the guard.
- Key stored evidence by `interactionGeneration` and remove it from
  `_clearActiveResponseForGeneration` and `_clearAllActiveResponses`.
- Hidden or automatic continuations that submit no new user message start with
  no direct-message approval. They may be authorized only by an
  `ask_user_question` result recorded for that same generation.
- Build the final approval evidence at the tool-loop call site from the
  generation-owned direct snapshot and the existing generation-owned question
  cache. Pass that value into
  `_buildProductionReleaseApprovalGuardResult`.
- Keep `_looksLikeExplicitProductionReleaseApproval`,
  `_looksLikeAffirmativeReleaseApprovalAnswer`, and
  `_looksLikeProductionReleaseApprovalPrompt` behavior unchanged.
- Typed side-effect ports:
  - no new port is required;
  - generation cleanup remains owned by the notifier lifecycle;
  - tool execution continues through the existing batch dispatcher only after
    the pure approval decision succeeds.
- Generated files and migrations: none.

## Deterministic Two-Thread Cases

Add poisoned conversations with distinct user and assistant approval text:

1. Start thread A without production approval and hold its first model response.
   Make thread B visible with an explicit production-release approval in its own
   transcript. Release A's response with a production-release tool call. A must
   receive `production_release_explicit_approval_required`, and the release tool
   must not execute.
2. Invert the poison: A's submitted message explicitly approves release while B
   is visible with a denial or neutral message. A's release tool call must be
   allowed. This proves the implementation did not merely disable direct
   approval.
3. Complete generation N after an explicit direct approval. Start generation
   N+1 on the same conversation through a hidden or neutral continuation with
   no new approval. A production-release tool call in N+1 must be blocked.
4. Complete an `ask_user_question` approval in generation N, then attempt the
   release in generation N+1. The earlier cached answer must not authorize it.
5. Preserve existing same-generation direct-reply and
   `ask_user_question`-approval cases.

Assert tool execution count and the structured guard code, not only displayed
assistant prose.

## Similar-Pattern Search

- Search terms:
  - `_latestUserExplicitlyApprovedProductionRelease`;
  - `_previousAssistantAskedForProductionReleaseApproval`;
  - `_hasExplicitProductionReleaseApproval`;
  - `_askUserQuestionTurnCache`;
  - `production_release_explicit_approval_required`;
  - `state.messages`.
- Inspect every call to `_buildProductionReleaseApprovalGuardResult` and every
  cleanup path for interaction-generation caches.
- Record other approval policies that scan visible messages as deferred
  findings; do not repair them in this slice.

## Measurement, Manifest, and Coverage

- Expected declared notifier-part delta: `0`; the count remains `42`.
- Target same-library aggregate delta: `0`; reductions are acceptable, but the
  aggregate must remain at or below `22,900` physical lines.
- Manifest record `command_guardrails` remains `remaining`; no collaborator
  record or discovery marker is added.
- No size budget may increase.
- Current target-file coverage baseline:
  `chat_notifier_command_guardrails.dart` is `342/369` lines (`92.68%`).
- Coverage expectation: the full gate must remain at or above `92.68%` for that
  target, and every new cross-thread and cross-generation branch must be hit.

## Acceptance Criteria

1. Production-release approval cannot cross conversation IDs.
2. Direct-message and question-answer approval cannot cross interaction
   generations.
3. Same-generation explicit approval still authorizes the same command set.
4. Same-generation denial, neutral input, or missing evidence still blocks.
5. The guard no longer reads visible `state.messages` to decide approval.
6. Generation-owned evidence is cleared on normal completion, failure,
   cancellation, and clear-all paths.
7. Structured guard payloads and existing approval wording remain compatible.
8. No part, manifest, marker, generated file, or size-budget change.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --set-exit-if-changed
tool/codex_verify.sh \
  --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
tool/codex_verify.sh --coverage
awk -v target='lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart' \
  -v minimum=92.68 '
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

The ordered work-plan table does not require the live canary for a test-only
Slice 2b2. If the poison tests require a production approval or guardrail fix,
run the corrected Slice 2b1 canary and record its exact model and base URL.

## Stop Conditions

- Stop if no deterministic failing cross-thread or cross-generation test can be
  produced before changing production code.
- Stop if the fix requires a global "latest approved" flag or any value not
  keyed by generation and conversation.
- Stop if preserving direct affirmative replies requires scanning ambient
  visible history after the turn starts.
- Stop and record a follow-up if another approval domain is contaminated; do
  not widen this slice beyond production-release approval.
- Stop if the fix requires a provider schema change, a new notifier part, an
  aggregate budget increase, or a production extraction.

## Handoff Notes

- Record both poisoned conversation IDs and interaction generations.
- Record blocked and executed tool counts for every case.
- Record the target-file hit/line count and aggregate line count.
- Record any deferred approval scans found by the similar-pattern search.
- Keep this slice in one focused Conventional Commit.

## Implementation Evidence

Implementation commit `61f96ab3` captures immutable approval evidence by
interaction generation and owning conversation. The deterministic fixtures use
poisoned thread A and thread B transcripts and prove:

- a thread B approval cannot authorize thread A generation 1: the structured
  guard code is `production_release_explicit_approval_required` and the release
  execution count is zero;
- a thread B denial cannot revoke thread A generation 1 direct approval: the
  release execution count is one;
- thread A generation 1 direct approval cannot authorize hidden generation 2:
  generation 2 is blocked and performs zero release executions;
- thread A generation 1 `ask_user_question` approval cannot authorize hidden
  generation 2: generation 2 is blocked and performs zero release executions.

The two direct verification files pass all 332 tests. Fresh coverage from the
committed implementation is `346/369` lines (`93.77%`) for
`chat_notifier_command_guardrails.dart`, above the `92.68%` floor. The declared
part count remains 42, the same-library aggregate remains at its 22,900-line
budget, and the manifest remains unchanged.

The similar-pattern search found a separate visible-state read in
`_buildAutoReviewRequest`, where the general high-risk auto-review request
builds a conversation tail from `state.messages`. That approval domain is
deferred to its own slice and was not changed here.

The exact-model corrected Slice 2b1 live canary passed on 2026-07-28 against
loaded `qwen3.6-27b-vision` at `http://192.168.100.241:1234/v1`. Its exact exit
maps and zero-busy-owner evidence are recorded in the Slice 2b1 handoff. This
completes Slice 2b2.
