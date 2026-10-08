# LL30: The Prune Reaches The Capped Half (2026-07-21)

Question this answers: **the structural prune landed in `297d4f52` and its
measurement reports 99.2% token savings — do those savings reach the prompt?**

Short answer: no. The savings are real as measured, but they are measured on an
intermediate list that never reaches the model. The summary the prune feeds was
already capped before the prune existed.

## What was built

`ConversationToolResultPruner.prune` runs inside
`ConversationCompactionService.buildArtifact`, on the slice of messages about
to be summarized, before `_buildSummary`. The wiring is correct on the
constraint that mattered: it fires at a compaction boundary, not per request,
so the LL6 prefix-stable KV cache is untouched. The implementation is tested
(130 lines of unit tests) and `flutter analyze` is clean.

## The measurement measures the wrong stage

`tool/measure_compaction_structural_prune.dart` reports
`estimated prompt tokens: 29499 -> 222`. That is
`estimatePromptTokens(messages)` before and after pruning — the **input** to
the summary builder.

`_buildSummary` emits at most `maxSummaryBullets` (12) bullets of at most
`maxBulletLength` (180) characters. Its output is therefore bounded at roughly
**2160 characters, ~540 tokens, regardless of how much input it is given.**
Feeding it 29499 tokens or 222 tokens produces an output in the same bounded
range.

Probed on a 60-message tool-heavy conversation (30 turns, each with a ~900-byte
`read_file` payload):

| Stage | Tokens |
|-------|-------:|
| Whole conversation | 8803 |
| Summarized slice, before prune | 8803 |
| Summarized slice, after prune | 373 |
| **Summary actually produced** | **111** |

The 8803 → 373 reduction is what the tool reports. The summary is 446
characters either way, because the cap binds long before the input size does.

## Where the tokens actually are

Same probe, post-compaction context:

| Component | Tokens | Share |
|-----------|-------:|------:|
| Summary (capped) | 111 | 9% |
| **Protected tail — `recentMessagesToKeep = 8`, never pruned** | **1194** | **91%** |
| Post-compaction total | 1305 | |

This split is structural, not an artifact of the fixture. The summary has a
hard ceiling of ~540 tokens; the retained tail has none — it is a fixed *count*
of 8 messages whose size is whatever those messages happen to be. For any
conversation large enough to trigger compaction, and especially for the
tool-heavy turns this milestone targets, the tail dominates.

LL30's own scope named this: *"switch the protected tail from a fixed message
count to a token budget"*. That half is not implemented, and it is the half
where prompt tokens live.

## What the shipped work is still worth

Not nothing, but not what was measured. Twelve bullets built from deduplicated,
outcome-summarized input can carry twelve *distinct* facts, where twelve
bullets built from raw repeated tool output may carry the same read twelve
times. That is a **summary quality** improvement, and it is plausible — but it
is a different claim from token savings, it has not been measured, and
measuring it needs a different instrument than a token counter.

The honest status: the prune is correctly built, correctly placed, and aimed at
the capped half of compaction.

## Proposed next move

Token-budget the protected tail, which is LL30's unimplemented half:

- Replace `recentMessagesToKeep = 8` with a token budget, so the retained tail
  is bounded by cost rather than by message count.
- Apply the existing pruner to tail messages that fall outside the budget
  instead of dropping them, so old tool payloads degrade rather than vanish.
- Measure the artifact and the retained tail, not the intermediate list. The
  probe above is the shape: report post-compaction total, split into summary
  and tail.

Before building, resolve one interaction: shrinking the tail changes what the
next request's prefix contains, and LL6/LL22 have invested in prefix stability.
Compaction already invalidates the prefix at its boundary, so a tail budget
applied *at the same boundary* costs nothing extra — but a tail budget that
re-evaluates per request would thrash the cache. Keep it at the boundary.

## Method note

The probe was a throwaway Dart test, deliberately not left in `test/`. It is
reproduced here rather than kept, because it asserts nothing — it prints. The
finding it produced is structural (a bounded output cannot shrink) and does not
depend on the fixture, which is why a document is the right home for it and a
test is not.
