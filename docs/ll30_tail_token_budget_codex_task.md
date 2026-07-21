# LL30 Protected-Tail Token Budget

Continues `docs/ll30_structural_tool_result_prune_codex_task.md`, which
correctly listed tail budgeting as a non-goal. This is that non-goal, promoted
after measuring where the tokens actually are.

## Task

- **Goal:** Bound the compaction-retained tail by tokens instead of by message
  count, and degrade the tool payloads that fall outside the budget rather than
  dropping them. This is LL30's remaining half.
- **User-visible behavior:** Long tool-heavy conversations retain a smaller,
  cost-bounded recent context after compaction. No change to what the user sees
  in the transcript — this affects what is sent to the model, not what is
  displayed or stored.
- **Non-goals:**
  - Do not move pruning out of the compaction boundary. Per-request pruning
    invalidates the LL6 prefix-stable KV cache on every turn; the boundary
    already invalidates it once, so work placed there is free and work placed
    per request is not.
  - Do not change `ConversationToolResultPruner`'s parsing, summarization, or
    de-duplication behavior. Reuse it.
  - Do not raise `maxSummaryBullets` / `maxBulletLength`. The summary is not
    the problem (see below).
  - Do not add anti-thrashing state or attachment eviction; those stay in
    LL30's backlog.

## Work Breakdown

1. Add a retained-tail token budget at the compaction boundary while keeping
   eight messages as the continuity floor.
2. Persist content overrides in the compaction artifact so the same degraded
   tail is reused between boundary changes.
3. Cover token-heavy, oversized, prose-only, malformed, ordering, storage, and
   legacy-artifact cases.
4. Correct the measurement to compare summary plus retained tail before and
   after the change.
5. Run focused and full verification, then record the measured result and
   pressure-threshold interaction here.

## Context

### Why this is the next slice

The shipped prune reduces the **input** to `_buildSummary`, whose output is
capped at `maxSummaryBullets` (12) × `maxBulletLength` (180) ≈ 540 tokens
regardless of input size. So the prune cannot reduce prompt tokens; its
measurement tool reports savings on an intermediate list that never reaches the
model. Full analysis and probe numbers:
**`docs/ll30_prune_reaches_the_capped_half_2026-07-21.md`**.

Probed on a 60-message tool-heavy conversation:

| Stage | Tokens |
|-------|-------:|
| Summarized slice, before prune | 8803 |
| Summarized slice, after prune | 373 |
| Summary actually produced | 111 |

Post-compaction context in that probe:

| Component | Tokens | Share |
|-----------|-------:|------:|
| Summary (hard ceiling ~540) | 111 | 9% |
| **Protected tail (`recentMessagesToKeep = 8`, unbounded size)** | **1194** | **91%** |

The split is structural, not fixture-specific: the summary has a ceiling, the
tail has only a message *count*. For any conversation large enough to compact,
the tail dominates.

### Affected files or components

- `lib/features/chat/domain/services/conversation_compaction_service.dart` —
  `buildArtifact` (line ~55), `recentMessagesToKeep` (currently 8),
  `estimatePromptTokens`, `_needsCompaction`.
- `lib/features/chat/domain/services/conversation_tool_result_pruner.dart` —
  reuse `prune`; it returns `ConversationToolResultPruneResult` with
  `messages`, `originalCharacterCount`, `prunedCharacterCount`,
  `summarizedResultCount`, `duplicateResultCount`.
- `tool/measure_compaction_structural_prune.dart` — **must be corrected**, see
  below.
- Tests: `test/features/chat/domain/services/conversation_compaction_service_test.dart`,
  `conversation_tool_result_pruner_test.dart`.

### Related docs

- `docs/ll30_prune_reaches_the_capped_half_2026-07-21.md` — the finding that
  motivates this task. Read the "Method note" before writing any measurement.
- `docs/local_llm_agent_roadmap.md` — LL30, including the warning not to copy
  Grok Build's per-request firing point.
- `docs/grok_build_comparison_2026_07_21.md` — the graduated age-banded shape
  worth borrowing (untouched → soft-trim → placeholder) and the image-eviction
  placeholder wording, which tells the model the content is gone rather than
  letting it describe it from memory.

### Known quirks

- `recentMessagesToKeep` is load-bearing beyond token cost: it is what keeps the
  immediately-preceding exchange intact so the model does not lose the thread
  mid-task. A pure token budget could retain zero messages on a single huge
  tool result. Keep a **message-count floor** as well as a token ceiling.
- `estimatePromptTokens` is a character-based estimate, not a tokenizer. It is
  fine for budgeting but do not present its output as exact.
- The compaction artifact records `estimatedPromptTokens` from the *unpruned*
  message list. If you change what that field means, check every consumer
  first — it is surfaced in the UI.

## Implementation Notes

- **Preferred approach:**
  1. Add a token budget for the retained tail (a constant beside
     `recentMessagesToKeep`, with the existing count becoming a floor).
  2. Walk the tail newest-first, accumulating estimated tokens. Messages inside
     the budget are retained verbatim.
  3. Messages beyond the budget are **degraded, not dropped**: run them through
     `ConversationToolResultPruner` so a tool result becomes its one-line
     outcome summary. A dropped message loses the fact that the step happened;
     a degraded one keeps it.
  4. Consider the graduated shape from Grok Build rather than a binary
     in/out: newest untouched, middle soft-trimmed head+tail, oldest replaced
     by a placeholder. Justify whichever you pick with the measurement, not
     with preference.

- **Constraints:**
  - Everything stays inside `buildArtifact`, at the compaction boundary.
  - The pruner is pure and must stay pure; no IO, no clock, no randomness.
  - Preserve message ordering and roles; the tail must remain a valid
    conversation prefix for the next request.

- **Generated files needed:** none expected. If you touch an entity, run
  `dart run build_runner build --delete-conflicting-outputs`.
- **Migration or data compatibility concerns:** the artifact is versioned
  (`artifactVersion = 2`). If its shape changes, bump it and check
  deserialization of stored artifacts.

## Fix the measurement tool before trusting any number

`tool/measure_compaction_structural_prune.dart` currently reports
`estimatePromptTokens` on the message list before and after pruning. That is
the stage that does not reach the model, and it is why a 99.2% saving was
reported for a change that saves nothing.

Correct it to report the **post-compaction total** and its split:

```
summary tokens        : <artifact.summary.length ~/ 4>
retained tail tokens  : <estimatePromptTokens(retained)>
post-compaction total : <sum>
```

Report before and after *your* change at that stage. A number that does not
describe what is sent to the model is worse than no number, because it gets
quoted.

## Similar-Pattern Search

- **Search terms:** `recentMessagesToKeep`, `estimatePromptTokens`,
  `maxEstimatedPromptTokens`, `assessTokenPressure`, `shouldAutoCompact`.
- **Files or modules to inspect:** `ConversationTokenPressure` and its
  consumers — if the tail becomes token-bounded, the pressure thresholds that
  decide *when* to compact may double-count or fight the new budget. Check
  whether `maxEstimatedPromptTokens` (6000) and the new tail budget are
  consistent, and say so in the handoff notes either way.
- **Follow-up tasks found:** record, do not expand scope.

## Acceptance Criteria

- **Required behavior:** for a tool-heavy conversation, post-compaction context
  (summary + retained tail) is measurably smaller than before this change, with
  the reduction reported at the corrected measurement stage.
- **Edge cases:**
  - A single message larger than the whole budget must still be retained in
    degraded form, never dropped, and never left as an empty message.
  - Conversations at or below the message-count floor must behave exactly as
    today (regression test).
  - A tail containing no tool results must be unaffected — the budget should
    not truncate ordinary prose exchanges that fit.
- **Failure paths:** malformed tool payloads already pass through the pruner
  verbatim; keep that. Degradation must never produce a message that fails to
  round-trip through storage.
- **Accessibility, localization, or platform expectations:** none; nothing
  user-facing changes.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_compaction_service_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_tool_result_pruner_test.dart
dart run tool/measure_compaction_structural_prune.dart
```

Then the full suite, since compaction is on the main chat path:

```bash
tool/codex_verify.sh
```

## Handoff Notes

- **Summary:** implemented a 1,000 estimated-token verbatim suffix inside the
  eight-message retained floor. Older messages in that floor are passed
  through the existing structural pruner and stored as artifact content
  overrides. The corrected synthetic measurement reports summary plus retained
  tail at 19,924 estimated tokens before the change and 404 after it, a 98.0%
  reduction. The fixture intentionally uses large repeated file reads, so this
  is evidence that the firing point works, not a forecast for normal sessions.
- **Tests run:** focused compaction tests (15 passed), structural-pruner tests
  (5 passed), corrected measurement, and `tool/codex_verify.sh` (static
  analysis clean; all 3,944 tests passed).
- **Coverage or low-coverage notes:** focused coverage includes a partial
  verbatim suffix, a single result larger than the whole budget, prose-only and
  malformed tails, ordering and role preservation, message storage round-trip,
  artifact round-trip, and legacy version-2 artifact deserialization.
- **Risks or follow-ups:** `maxEstimatedPromptTokens` remains 6,000 and still
  decides when to compact from the original transcript. The 1,000-token tail
  budget is applied only after that decision, while prompt pressure is then
  assessed from the actual summary plus overridden tail, so the thresholds do
  not double-count the new budget. `estimatedPromptTokens` retains its prior
  UI-facing meaning. A binary boundary was sufficient: the existing pruner
  reduced the measured tail to 146 estimated tokens while retaining every
  message, so a new soft-trim representation did not earn its complexity.
  Ordinary prose and malformed tool payloads intentionally remain verbatim and
  can exceed the best-effort tail budget. Anti-thrashing and attachment
  eviction remain separate LL30 follow-ups.
