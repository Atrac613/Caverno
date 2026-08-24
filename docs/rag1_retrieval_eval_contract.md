# RAG1 Retrieval Evaluation Contract

Status: foundation implemented; production retrievers are not wired by this
slice.

## Purpose

RAG1 freezes the measurement contract before RAG2 adds a project index or RAG3
adds vector fusion. The evaluator consumes checked or captured ranking results,
so metric correctness, missing-capability behavior, and negative controls can be
reviewed without changing production retrieval.

## Versioned inputs

The fixture uses `caverno_rag_retrieval_fixture` schema version 1 and contains:

- a content-hashed mini repository;
- exactly 20 query cases;
- object and chunk qrels with integer relevance grades;
- answer facts and stable citation IDs;
- an explicit authority value: `current`, `historical`, `conflict`, or `none`;
- the five required categories: current source facts, historical decisions,
  cross-source conflicts, Japanese queries, and unanswerable/adversarial cases.

The run uses `caverno_rag_retrieval_run` schema version 1. Every run declares
the `L`, `V`, `H`, `AK`, `H+AK`, `NONE`, and `FULL` arms. An unavailable arm
uses `status: not_available` plus a reason and is never converted to a zero
score. Reproducibility metadata records the build commit and dirty state,
embedding fingerprint, hardware, and cold/warm state.

Available arms provide one result per case, elapsed time, prompt/context token
counts, and peak RSS/VRAM fields. Japanese lexical misses must be attributed to
`tokenization` or `ranking`. Answer grounding and citation counts are optional
until an answer-producing arm is measured.

## Metrics and controls

The version 1 metric policy reports object and chunk Recall@K, Hit@K, MRR@K,
nDCG@K, grounded-answer rate, citation precision, latency, prompt/context
tokens, RSS/VRAM metadata, and the false-positive rate on unanswerable cases.

At least one known-bad arm is mandatory. The checked tests use an empty ranking
with a non-zero minimum Hit@K. A report fails if that arm starts meeting its
expectation, because the instrument can no longer distinguish the known-bad
retriever. Thresholds for the 20-case seed must be expressed as whole-case
differences rather than sub-case percentages.

## Command

```bash
fvm dart run tool/rag_retrieval_eval.dart \
  --fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --run /path/to/rag_retrieval_run.json \
  --out-dir build/integration_test_reports/rag_retrieval_eval
```

The command writes deterministic `rag_retrieval_eval.json` and
`rag_retrieval_eval.md` reports. Generated reports remain build artifacts and
must not be committed.

## Deliberate non-goals

- No production database migration or index.
- No embedding request or vector store.
- No `search_knowledge` tool.
- No agent-kb process invocation.
- No automatic prompt injection or router behavior.

RAG2 remains `later` until real lexical rankings populate this contract and the
resulting report makes lexical misses and authority handling reviewable.
