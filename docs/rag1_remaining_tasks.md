# RAG1 Remaining Task Plan

Goal: finish the RAG1 evaluation milestone without adding a production index,
embedding path, `search_knowledge` tool, or automatic retrieval behavior.

## Task A: Deterministic Retrieval-Arm Capture

Status: `done`

- Add an offline runner over the versioned mini repository.
- Capture the existing `unicode61`/AND-query lexical shape as arm `L`.
- Capture `NONE` and small-corpus `FULL` controls.
- Emit explicit `not_available` records for `V`, `H`, `AK`, and `H+AK` when
  their dependencies are absent.
- Record build state, corpus hash, cold/warm state, hardware, elapsed time,
  estimated token method, peak RSS, and nullable VRAM.
- Attribute each Japanese lexical miss to tokenization or ranking.

Verification:

```bash
tool/codex_verify.sh --test test/tool/rag_retrieval_baseline_test.dart
```

Evidence:

- `tool/rag_retrieval_baseline.dart`
- `test/tool/rag_retrieval_baseline_test.dart`
- `tool/fixtures/rag_retrieval_eval/repository/docs/japanese_facts.json`
- Focused evaluator and baseline tests pass with cold/warm capture coverage.

## Task B: Checked Baseline Evidence

Status: `done`

- Run cold and warm captures from a clean commit.
- Produce deterministic run JSON plus evaluator JSON/Markdown reports.
- Check that the empty-ranking negative control fails its own gate and makes the
  overall instrument pass.
- Review every lexical miss, every cross-source conflict, and every
  unanswerable false positive.
- Record gates as whole-case counts: 16 answerable cases and four no-answer
  cases, rather than treating every seed case as a retrieval qrel.

Evidence:

- `docs/rag1_retrieval_baseline_2026-08-24.md`
- Clean cold/warm captures from commit `875067d9` produced identical rankings.
- `L` matched `NONE` at 0/16 answerable hits; `FULL` reached 14/16 but retrieved
  content for 4/4 no-answer cases and consumed 10,520 estimated context tokens.
- The empty negative control remained detectable.

## Task C: Answer And Citation Measurement

Status: `done`

- Add answer-producing `NONE`, `L`, and `FULL` measurements using the same
  answer keys and citation IDs.
- Record model, endpoint, sampler, usage tokens, and availability rather than
  converting a missing endpoint to zero.
- Score grounded claims and citation precision deterministically where the
  answer key permits; keep ambiguous cases review-required.
- Compare answer quality and token cost in the same report as retrieval.

Evidence: `docs/rag1_completion_audit_2026-08-25.md`. A clean live run on
commit `dce6de97` measured `NONE`, `L`, and `FULL` with strict JSON-schema
selection and citation-required grounding.

## Task D: Optional Capability Arms

Status: `done`

- Populate `V` when a configured embedding endpoint is available.
- Populate `H` only after both lexical and vector rankings exist; do not ship a
  production fusion path in RAG1.
- Populate `AK` and `H+AK` only through the reviewed agent-kb boundary and only
  when required provenance is available.
- Preserve `not_available` for every arm whose capability or provenance gate is
  unmet.

Evidence: a clean run on commit `0321d7b0` measured `V/H`; `AK/H+AK` remained
explicitly unavailable because their provenance/federation gates are unmet.

## Task E: RAG1 Completion Audit

Status: `done`

- Publish one reviewable report containing metric policy version, lexical miss
  attribution, authority handling, answer/citation quality, latency, resources,
  and token costs.
- Prove the known-bad arm remains detectable.
- Decide whether the evidence promotes RAG2 or records a No-Go.
- Update both roadmaps with exact evidence and mark RAG1 `done` only if every
  acceptance criterion is proven.

Evidence: `docs/rag1_completion_audit_2026-08-25.md`. RAG1 is complete and the
RAG2 promotion decision is No-Go until retrieval gains an evaluated no-answer
policy.
