# ChatNotifier Decomposition — Tranche 1 Task Specs

Status: ready for implementation. Anchors verified against commit `4f1b756b`
(branch `claude/sad-carson-dba82d`, clean tree). Line numbers WILL drift — always
re-locate symbols by name with grep before editing.

This document turns Phase 1 of `docs/large_file_refactor_plan.md` into seven
self-contained Codex tasks plus one docs task. Hand Codex **one task section at
a time**, together with the "Shared Context" section below. Execute in order:

```
Task 1 (Slice B) → Task 2 (A1) → Task 3 (A2) → Task 4 (A3) → Task 5 (A4)
→ Task 6 (Slice C) → Task 7 (Slice D) → Task 8 (docs)
```

Each task is one conventional commit and one review pass (per AGENTS.md).

---

## Shared Context (include with every task)

### Problem

`lib/features/chat/presentation/providers/chat_notifier.dart` is a god object:
12,888 lines in the main file plus 32 same-library part files (~22,600 lines
total). One Riverpod `Notifier<ChatState>` orchestrates the chat loop, tool
calling, plan/workflow proposals, approvals, and memory. This tranche extracts
the low-risk, mostly-pure clusters into constructor-injected services
(~3,700-line reduction), leaving the notifier as an orchestration shell and
preparing a later tool-loop extraction.

### Invariants (every task)

- **Behavior-preserving only.** No feature changes, no logic "improvements",
  no reformatting of moved code beyond what the move itself requires.
- `chatNotifierProvider`, `ChatState`, and every public method on `ChatNotifier`
  stay untouched (the `*ForTest` harnesses remain on the notifier as thin
  delegates).
- All existing tests stay green **without edits** (allowed exceptions: adding
  imports, or renaming a private type that a test never references). Do not
  rewrite or duplicate existing tests; add small focused tests for each new
  service.
- New services are plain Dart classes with constructor injection. No Freezed,
  no code generation, no new providers unless a task says otherwise.
- English-only comments and identifiers. Conventional commit messages in
  English, no AI attribution.

### Extraction idiom (copy this pattern exactly)

The repo already contains the target pattern:

- Service: `lib/features/chat/domain/services/workflow_task_proposal_quality_service.dart`
  (instance class, injectable `createId` defaulting to `Uuid().v4`).
- Delegate part file: `lib/features/chat/presentation/providers/chat_notifier_task_proposal_quality.dart`
  — a `part of 'chat_notifier.dart'` file whose
  `extension ChatNotifierTaskProposalQuality on ChatNotifier` methods are
  one-line delegates into the service.

For every slice: move the logic into a domain service, keep the private
notifier-side names alive via a thin delegate extension (new part file or
existing one), so the ~200 private call sites in the main file and part files
do not change.

### Pinned behaviors (do not break; these tests are the tripwires)

| Behavior | Pinned by |
|---|---|
| Tool dedup: execution key **keeps** `reason`, failure key **strips** it | `test/features/chat/domain/services/tool_call_execution_policy_test.dart` |
| Approval cache ignores `reason` | `test/features/chat/presentation/providers/tool_approval_cache_test.dart` |
| `read_file` is repeatable (no dedup guard) | `test/features/chat/presentation/providers/chat_notifier_read_only_inspection_guard_test.dart` |
| False-completion claim correction: notice prepended, never stacked, original answer preserved, notice strings verbatim | `chat_notifier_test.dart` via `messageContentWithPrependedClaimCorrectionNoticeForTest` (main file ~L4960) |
| Auto-review denial escalates to manual approval (coding only) | `test/features/chat/presentation/providers/chat_notifier_auto_review_escalation_part.dart` |
| Prefix-stable mode sends the full fixed tool list on every request | `test/features/chat/presentation/providers/chat_notifier_prefix_stability_test.dart` |
| Workflow/task proposal parsing (59 tests via public harnesses `parseWorkflowProposalForTest`, `parseTaskProposalForTest`, `promoteOpenQuestionsForTest`, ...) | `test/features/chat/presentation/providers/chat_notifier_workflow_proposal_test.dart` |

### Verification (every task)

```bash
flutter analyze
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_workflow_proposal_test.dart
# plus the slice-specific tests listed in the task
```

After the last code slice (Task 7): `tool/codex_verify.sh --coverage`.

---

## Task 1 — Slice B: extract PlanningResearchCollector

**Commit:** `refactor(chat): extract planning research collection into PlanningResearchCollector`

### Task

- Goal: move the Plan-Mode repository research collection (directory listing,
  key-file discovery, grep queries, file notes, risk synthesis) out of
  `chat_notifier.dart` into a focused domain service.
- User-visible behavior: none (identical research context in proposals).
- Non-goals: changing which tools run, their order, prompts, or log strings.

### Context

- Source: `chat_notifier.dart` ~L1399–1842 plus the private carrier types
  `_PlanningResearchFileNote` (~L234) and `_PlanningResearchContext` (~L244)
  and `_planningResearchStopWords` (~L380).
- The carrier types are referenced at ~16 sites, including
  `chat_notifier_task_proposal_quality.dart:46`.
- Related docs: `docs/large_file_refactor_plan.md` Phase 1 slice 1/4.

### Implementation Notes

- New file: `lib/features/chat/domain/services/planning_research_collector.dart`.
- API sketch:

```dart
typedef PlanningResearchToolRunner =
    Future<McpToolResult> Function(ToolCallInfo toolCall);

class PlanningResearchFileNote { /* moved, made public */ }
class PlanningResearchContext { /* moved, made public; keeps hasContent, toPromptBlock() */ }

class PlanningResearchCollector {
  PlanningResearchCollector({required PlanningResearchToolRunner runTool});

  Future<PlanningResearchContext> collect({
    required Conversation currentConversation,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  });
}
```

- Move: `_collectPlanningResearchRootEntries`,
  `_collectPlanningResearchImportantFiles`, `_buildPlanningResearchQueries`,
  `_collectPlanningResearchNamedMatches`, `_collectPlanningResearchTextMatches`,
  `_collectPlanningResearchFileNotes`, `_runPlanningResearchTool`,
  `_compactPlanningResearchLine`, `_extractPlanningResearchPathFromMatch`,
  `_extractPlanningResearchHighlights`, `_buildPlanningResearchRisks`,
  `_planningResearchStopWords`, and both carrier classes (renamed public).
- **Stays in the notifier:** the guard at the top of
  `_buildPlanningResearchContext` (null `_mcpToolService`, non-coding
  workspace, empty project root → empty context); it then delegates to
  `PlanningResearchCollector(runTool: _dispatchToolCall).collect(...)`.
  `_projectLooksEmptyForTaskPlanning` (~L4718) also stays this slice.
- Keep verbatim: the tool-call id format `planning_research_${microseconds}`
  and all `appLog` strings.
- Call-site change: rename `_PlanningResearchContext` /
  `_PlanningResearchFileNote` to the public names at every reference
  (grep both names across `lib/` and `test/`).

### Similar-Pattern Search

- Search terms: `_PlanningResearchContext`, `planning_research_`,
  `_collectPlanningResearch`.
- Confirm no other part file constructs the carrier types directly.

### Acceptance Criteria

- `chat_notifier.dart` shrinks by roughly 470 lines.
- Existing end-to-end test "planning proposals include hidden research context
  from read-only tools" (in `chat_notifier_test.dart`, uses
  `_PlanningResearchMcpToolService`) passes unchanged.
- New focused tests in
  `test/features/chat/domain/services/planning_research_collector_test.dart`:
  query building, risk synthesis, highlight extraction, and the
  tool-result-JSON-decode-failure path (collector must degrade gracefully).

### Verification

```bash
flutter analyze
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --test test/features/chat/domain/services/planning_research_collector_test.dart
```

---

## Task 2 — Slice A1: extract proposal JSON repair and section text utilities

**Commit:** `refactor(chat): extract proposal JSON repair and section text utilities`

### Task

- Goal: move the pure text/JSON utility layer used by proposal parsing into a
  domain service file, so the workflow/task parsers (Tasks 3–4) can build on it.
- Non-goals: touching request orchestration (`_requestWorkflowProposal`,
  `_requestTaskProposal`) or the `*ForTest` harnesses' signatures.

### Context

- Source: `chat_notifier.dart`, utilities spread over ~L3458–4818.
- Purity audit (already done): everything in this cluster is pure **except**
  `_extractJsonMap`, which fires the telemetry hook
  `_recordPlanningJsonRepairRuntimeFeedback()` at exactly three sites
  (~L3472, ~L3487, ~L3495). That hook reads notifier state and must stay in
  the notifier; inject it as a callback.

### Implementation Notes

- New file: `lib/features/chat/domain/services/proposal_parsing_text_utils.dart`.
- Shape: static helpers for the pure functions, plus:

```dart
class ProposalJsonExtractor {
  const ProposalJsonExtractor({void Function()? onJsonRepair});
  Map<String, dynamic>? extractJsonMap(String rawContent);
}
```

  `onJsonRepair` must fire at the same three points with the same conditions
  (repair-telemetry sampling depends on call counts).
- Move: `_extractJsonMap`, `_tryDecodeMap`, `_tryRepairAndDecodeMap`,
  `_repairJsonCandidate`, `_extractLooseJsonScalar`,
  `_extractLooseJsonStringList`, `_collectProposalSections`,
  `_normalizeProposalContent`, `_extractProposalReasoningContent`,
  `_extractStructuredWorkflowProposalReasoning`,
  `_extractStructuredTaskProposalReasoning`, `_sanitizeReasoningProposalValue`,
  `_looksLikeStructuredReasoningListItem`, `_isWorkflowListSection`,
  `_workflowSectionDisplayLabel`, `_taskFieldDisplayLabel`, `_asCleanString`,
  `_asStringList`, `_isCompletionTruncated`, `_stripMarkdownListMarker`,
  `_appendTextValue`, `_proposalPreview`, `_extractPlainTextForProposal`,
  `_extractInlineTaskPlanCandidate`, `_sanitizeInlineReasoningTaskTitle`,
  `_matchTaskTitleLine`.
- Add a new delegate part file
  `lib/features/chat/presentation/providers/chat_notifier_proposal_parsing.dart`
  (`part of 'chat_notifier.dart'`) holding one-line private delegates for the
  moved names, following `chat_notifier_task_proposal_quality.dart`. The
  notifier constructs `ProposalJsonExtractor(onJsonRepair: _recordPlanningJsonRepairRuntimeFeedback)`.

### Acceptance Criteria

- ~600-line reduction in `chat_notifier.dart`.
- Zero edits in `chat_notifier_workflow_proposal_test.dart` (59 tests green).
- New focused test file
  `test/features/chat/domain/services/proposal_parsing_text_utils_test.dart`
  covering: JSON repair happy path, repair-hook call counts (use a counter
  callback), section collection, truncation detection.

### Verification

Shared commands plus the new test file.

---

## Task 3 — Slice A2: extract WorkflowProposalParser

**Commit:** `refactor(chat): extract workflow proposal parser`

### Task

- Goal: move workflow-proposal response parsing (structured JSON, markdown
  sections, loose JSON, narrative fallback, truncation fallback) into
  `WorkflowProposalParser`.
- Non-goals: moving request orchestration, retry/decision collection, or the
  `_WorkflowProposalCancelled` exception (all stay in the notifier).

### Context

- Source: `chat_notifier.dart`. The sealed response types live at ~L210–232:
  `_WorkflowProposalResponse`, `_WorkflowProposalDraftResponse`,
  `_WorkflowProposalDecisionResponse`. Parse entry points at ~L3212
  (`_parseWorkflowProposalResponse`) and the WithFallback variant used at
  ~L2623 and by `parseWorkflowProposalForTest` (~L4819).
- Depends on Task 2 (`ProposalJsonExtractor`, text utils).

### Implementation Notes

- New file: `lib/features/chat/domain/services/workflow_proposal_parser.dart`.
- API sketch:

```dart
sealed class WorkflowProposalParseResult {}
final class WorkflowProposalParsedDraft extends WorkflowProposalParseResult {
  final WorkflowProposalDraft proposal;
}
final class WorkflowProposalParsedDecisions extends WorkflowProposalParseResult {
  final List<WorkflowPlanningDecision> decisions;
}

class WorkflowProposalParser {
  WorkflowProposalParser({
    required WorkflowTaskProposalQualityService qualityService,
    void Function()? onJsonRepair,
  });
  WorkflowProposalParseResult? parse(String rawContent);
  WorkflowProposalParseResult? parseWithFallback(String rawContent);
  WorkflowProposalDraft? buildFallback(/* same params as _buildWorkflowProposalFallback */);
  WorkflowProposalDraft? buildTruncationFallback(/* same params */);
}
```

- Move: `_parseWorkflowProposalResponse`,
  `_parseWorkflowProposalResponseWithFallback`, `_parseWorkflowProposalMap`,
  `_parseWorkflowProposalFromSections`, `_parseWorkflowProposalFromLooseJson`,
  `_parseWorkflowProposalFromNarrative`, `_parseWorkflowDecisionResponseMap`,
  `_parseWorkflowStage`, `_inferWorkflowStageFromProposal`,
  `_inferWorkflowStageFromSectionKeys`,
  `_inferWorkflowStageFromLooseProposalContent`,
  `_extractNarrativeWorkflowGoal`, `_trimNarrativeWorkflowGoalCandidate`,
  `_sanitizeNarrativeWorkflowGoal`, `_extractNarrativeWorkflowList`,
  `_buildWorkflowProposalFallback`, `_buildWorkflowProposalTruncationFallback`,
  `_deriveWorkflowFallbackGoalFromConversation`, plus the sealed types
  (renamed to the public result types).
- The sealed-type rename is the only non-mechanical edit: update the pattern
  matches in the main file (grep `_WorkflowProposalDraftResponse` /
  `_WorkflowProposalDecisionResponse`; ~8 sites, e.g. ~L1934, ~L1958, ~L2644,
  and the `*ForTest` harnesses ~L4819–4836).

### Acceptance Criteria

- ~750-line reduction. 59 workflow-proposal tests green with zero edits.
- Small smoke test for the parser service (structured draft, decisions
  response, narrative fallback) — do not duplicate the 59 notifier tests.

---

## Task 4 — Slice A3: extract TaskProposalParser

**Commit:** `refactor(chat): extract task proposal parser`

### Task

- Goal: move task-proposal parsing into `TaskProposalParser`.
- Non-goals: `_buildTaskProposalQualityGateFallback` (~L3392) stays in the
  notifier this tranche (it composes conversation state; future candidate for
  the quality service).

### Context

- Source: `chat_notifier.dart` ~L3294–3457 and ~L4232–4370. The only impurity
  is task-id generation via `_uuid.v4` (notifier field ~L5387) inside
  `_parseTaskProposalMap` and the section/inline parsers — inject `createId`
  exactly like `WorkflowTaskProposalQualityService` does.
- Depends on Tasks 2–3.

### Implementation Notes

- New file: `lib/features/chat/domain/services/task_proposal_parser.dart`.

```dart
class TaskProposalParser {
  TaskProposalParser({
    required WorkflowTaskProposalQualityService qualityService,
    String Function()? createId,           // notifier passes _uuid.v4
    void Function()? onJsonRepair,
  });
  WorkflowTaskProposalDraft? parse(String rawContent);
  WorkflowTaskProposalDraft? parseWithFallback(String rawContent);
  WorkflowTaskProposalDraft? buildTruncationFallback(/* same params as _buildTaskProposalTruncationFallback */);
}
```

- Move: `_parseTaskProposal`, `_parseTaskProposalWithFallback`,
  `_parseTaskProposalMap`, `_parseTaskProposalFromLooseJson`,
  `_parseTaskProposalFromSections`, `_parseTaskProposalFromInlineReasoningPlan`,
  `_buildTaskProposalTruncationFallback`.
- `parseTaskProposalForTest` and `buildTaskProposalTruncationFallbackForTest`
  keep their signatures and delegate.

### Acceptance Criteria

- ~450-line reduction; zero test edits; focused parser smoke test added.

---

## Task 5 — Slice A4: extract planning decision option extraction

**Commit:** `refactor(chat): extract planning decision option extraction`

### Task

- Goal: move open-question promotion and EN/JA choice-option extraction into a
  static-helper service.
- Non-goals: none — this cluster is 100% pure (verified: no `ref`, `state`,
  `_settings`, `_uuid` references).

### Context

- Source: `chat_notifier.dart` ~L1998–2554 plus `_mergeWorkflowDecisionAnswers`
  (~L2709).

### Implementation Notes

- New file: `lib/features/chat/domain/services/proposal_option_extraction.dart`
  (class `PlanningDecisionPromotion` with static methods, or top-level
  functions — match repo style).
- Move: `_removeAnsweredOpenQuestions`, `_promoteChoiceLikeOpenQuestions`,
  `_promoteOpenQuestionsToPlanningPrompts`,
  `_buildOrderedChoiceDecisionFromOpenQuestion`,
  `_buildAlternativeChoiceDecisionFromOpenQuestion`,
  `_buildYesNoDecisionFromOpenQuestion`, `_extractEnglishOrderedOptions`,
  `_extractJapaneseOrderedOptions`, `_extractEnglishAlternativeOptions`,
  `_extractJapaneseAlternativeOptions`, `_splitEnglishChoiceList`,
  `_splitJapaneseChoiceList`, `_stripEnglishChoicePrefix`,
  `_stripJapaneseChoicePrefix`, `_stripChoiceSuffix`,
  `_cleanDecisionOptionLabel`, `_decisionOptionId`,
  `_looksLikeYesNoOpenQuestion`, `_containsJapaneseText`,
  `_normalizeWorkflowDecisionText`, `_filterUnansweredWorkflowDecisions`,
  `_mergeWorkflowDecisionAnswers`.
- **The EN/JA regexes must move byte-identical** — many of the 59 tests pin
  option splitting. `_mergeWorkflowDecisionAnswers` mutates its list argument
  in place; preserve that semantic.

### Acceptance Criteria

- ~610-line reduction; zero test edits (`promoteOpenQuestionsForTest` keeps
  delegating); focused tests for EN and JA option extraction edge cases.

---

## Task 6 — Slice C: extract FinalAnswerClaimDetector

**Commit:** `refactor(chat): extract unexecuted-action claim detection into FinalAnswerClaimDetector`

### Task

- Goal: move the pure detector / notice-builder layer that classifies final
  assistant answers against tool evidence (unexecuted tool requests, false
  success claims, unverified inspection claims) into a domain service.
- Non-goals: do **not** extend `coding_command_output_guardrail_service.dart`
  (different concern: it diagnoses command output for feedback prompts; this
  slice classifies assistant prose vs. tool evidence). Do **not** move the
  apply layer.

### Context

- Source (moves): `chat_notifier.dart` ~L11327–11945 (detectors and notice
  builders: `looksLike*Claim` / `has*Result` helpers,
  `contentWith*Notice` transforms), plus
  `_shouldSkipUnexecutedToolRequestNoticeForToolResults` (~L11025),
  `_toolResultsContainFailedCommandValidation` (~L10533),
  `_toolResultsMentionExactNonZeroExitCodeExpectation`,
  `_hasSuccessfulCommandExecutionResult` (~L11461), and the CJK marker helpers
  (`_containsAny`, `_containsAnyAtOrAfter`, `_containsAnyCodeUnitSequence`,
  `_containsCjk*`).
- Also move these cross-part pure predicates (leave one-line delegates in
  their part files): `_hasSuccessfulFinalAnswerToolEvidence`,
  `_looksLikeCompletedCodingFinalAnswer`, `_looksLikeCodingFutureAction`
  (in `chat_notifier_turn_finalization_recovery.dart` ~L174–260) and
  `_hasSuccessfulFileSideEffectResult`
  (in `chat_notifier_unexecuted_action_recovery.dart` ~L201).
- **Stays in the notifier:** every `_append*NoticeIfNeeded` /
  `_replace*SuccessClaimIfNeeded` apply method (~L10939–11326) — they own
  `ref.mounted` / `state` writes, generation caches, and record
  `_appliedTurnTransforms` (~L11123, ~L11178).

### Implementation Notes

- New file: `lib/features/chat/domain/services/final_answer_claim_detector.dart`.

```dart
class FinalAnswerClaimDetector {
  const FinalAnswerClaimDetector({
    ToolCallExecutionPolicy policy = const ToolCallExecutionPolicy(),
  });
  // Pure content classifiers over (String content) and
  // tool-result classifiers over (List<ToolResultInfo> toolResults),
  // plus notice transforms:
  //   contentWithUnexecutedCommandActionNotice,
  //   contentWithPrependedClaimCorrectionNotice,
  //   contentWithUnverifiedReadOnlyInspectionNotice, ...
}
```

- Move the notice string constants **verbatim, including doc comments**. The
  prepend semantics of `contentWithPrependedClaimCorrectionNotice` are pinned
  by tests: notice is prepended once, never stacked on re-runs, and the
  original answer stays visible.
- Do not reformat the CJK code-unit tables — resequencing them changes
  matching behavior.

### Similar-Pattern Search

- Search terms: `SuccessClaim`, `UnexecutedTool`, `claimCorrection`,
  `_containsCjk`.
- Confirm no other part file duplicates a detector before deleting the
  original bodies.

### Acceptance Criteria

- ~650-line reduction in the main file.
- Green with zero edits: `chat_notifier_test.dart` (claim-correction tests),
  `chat_notifier_read_only_inspection_guard_test.dart`,
  `tool_call_execution_policy_test.dart`.
- New focused test
  `test/features/chat/domain/services/final_answer_claim_detector_test.dart`:
  success-claim detection, unexecuted-tool detection, notice prepend
  idempotency (calling the transform on already-noticed content must not
  stack).

### Verification

```bash
flutter analyze
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_read_only_inspection_guard_test.dart \
  --test test/features/chat/domain/services/tool_call_execution_policy_test.dart \
  --test test/features/chat/domain/services/final_answer_claim_detector_test.dart
```

---

## Task 7 — Slice D: extract ActiveResponseRegistry

**Commit:** `refactor(chat): extract generation-keyed active response registry`

### Task

- Goal: move the interaction-generation counter and all generation-keyed
  active-response bookkeeping into a plain class, so later tranches can hand a
  registry object to extracted services instead of relying on same-library
  extension access.
- Non-goals: no behavior change; this slice is an enabler (~180-line
  reduction only).

### Context

- Source: `chat_notifier.dart` ~L5411–5583 (fields and ~14 accessor methods).
- Fields to own: `_interactionGeneration`, the current-response mirror fields,
  `_activeResponseConversationIdsByGeneration`,
  `_activeResponseMessagesByGeneration`,
  `_lastStreamedToolResultFinalAnswersByGeneration`,
  `_responseMetricTimersByGeneration`, `_turnFinalizationRecoveryGenerations`.
- Fields **not** owned (different concerns; cleared alongside by the notifier
  delegates): `_llmSessionLogContextsByGeneration`,
  `_askUserQuestionTurnCache`, and the paused-participant-turn fields reset in
  `_clearAllActiveResponses`.
- Raw (non-accessor) field touches exist in the main file and in
  `chat_notifier_turn_finalization_recovery.dart` (4 sites) and
  `chat_notifier_participant_turns.dart` — grep every owned field name across
  `chat_notifier*.dart` and route those sites through registry methods.

### Implementation Notes

- New file:
  `lib/features/chat/presentation/providers/active_response_registry.dart`
  (presentation layer — it holds `Message` lists, not domain policy).
- API sketch:

```dart
class ActiveResponseRegistry {
  int get interactionGeneration;
  int beginInteractionGeneration();
  void register({required int generation, required String? conversationId,
      required List<Message> messages});
  void cacheMessages(int generation, List<Message> messages);
  String? conversationIdForGeneration(int generation);
  List<Message>? messagesForGeneration(int generation);
  int? generationForConversation(String? conversationId);
  bool get hasActiveResponse;
  bool isDetachedForGeneration(int generation,
      {required String? currentConversationId});
  void setLastStreamedFinalAnswer(int generation, String content);
  String? lastStreamedFinalAnswer(int generation);
  void removeLastStreamedFinalAnswer(int generation);
  void startResponseMetricsTimer(int generation);
  Stopwatch? takeResponseMetricsTimer(int generation);
  void discardResponseMetricsTimer(int generation);
  bool markTurnFinalizationRecovery(int generation);
  bool hasTurnFinalizationRecovery(int generation);
  void clearGeneration(int generation);
  void clearAll();
}
```

- Keep all ~14 existing accessor methods on the notifier as one-line delegates
  so the ~41 part-file call sites stay untouched.
- `_isCurrentInteractionGeneration` keeps its `ref.mounted` check in the
  notifier wrapper; detached checks needing `conversationId` stay wrapped too.
- `_takeResponseMetricsForGeneration` keeps metric assembly (usage,
  finishReason) in the notifier; only the `Stopwatch` comes from the registry.
- **Critical:** the dual bookkeeping between the mirror fields and the
  by-generation maps (`generation == interactionGeneration` special-casing in
  register/cacheMessages/clearGeneration) must be replicated exactly —
  detached-response and queued-message behavior rides on it.

### Acceptance Criteria

- All provider tests green with zero edits, including
  `chat_notifier_prefix_stability_test.dart`.
- New unit test
  `test/features/chat/presentation/providers/active_response_registry_test.dart`
  covering register/cache/clear semantics, detachment, and the
  current-generation mirror behavior.

### Verification

```bash
flutter analyze
flutter test test/features/chat/presentation/providers/
tool/codex_verify.sh --coverage
```

---

## Task 8 — update the refactor plan doc

**Commit:** `docs: update large file refactor plan with tranche 1 status`

- Refresh the line-count inventory in `docs/large_file_refactor_plan.md`
  (`wc -l` on the listed files).
- Mark Phase 1 progress: which slices landed (B, A1–A4, C, D), the new service
  files, and the measured line reduction.
- Record the later-tranche roadmap:
  1. **Tranche 2 — tool loop:** extract `_executeToolCalls` guard-result
     builders and dispatch into a `ToolLoopRunner` (parameterized over the
     approval gate, content-tool handling, and `ActiveResponseRegistry`);
     afterwards converge `lib/features/routines/data/routine_execution_service.dart`
     onto it.
  2. **Tranche 3 — content tool calls + continuation** (~L9764–10428,
     ~L12323–12540).
  3. **Tranche 4 — sendMessage pipeline** (queueing, generation begin,
     compaction trigger).
  4. **Tranche 5 — turn finalization** (`_finishStreaming` + recovery part
     files, consuming `FinalAnswerClaimDetector`).
  5. **Phase 2 — ChatPage decomposition** (scroll controller → right sidebar →
     plan/workflow builders as callback-based widgets), per the existing plan.

---

## What explicitly stays in ChatNotifier after this tranche

Init/lifecycle wiring, persistence callbacks, model preparation, proposal
request orchestration (`_requestWorkflowProposal`, `_requestTaskProposal`,
decision collection, `_buildWorkflowProposalMessages`,
`_buildTaskProposalMessages`, `_buildTaskProposalQualityGateFallback`), all
`*ForTest` harnesses, `sendMessage`/queueing, `_sendWithTools` /
`_sendWithoutTools`, `_executeToolCalls` (the tool loop), content-tool
handling, the notice apply layer, `_finishStreaming`, and error/cancel
handling.
