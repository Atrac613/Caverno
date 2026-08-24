# RAG1 Completion Audit — 2026-08-25

## Outcome

RAG1 is complete. The measurement contract distinguishes unavailable
capabilities from zero scores, detects a known-bad retriever, captures lexical,
vector, hybrid, answer, citation, latency, resource, and token evidence, and
leaves production retrieval unchanged.

RAG2 is **No-Go** on the current evidence. Vector retrieval is strong on all 16
answerable cases but has no abstention policy and retrieves five documents for
all four no-answer cases. The measured lexical policy does not retrieve any
answerable case. RAG2 must design and evaluate a bounded retrieval/no-answer
policy before adding a production index or tool.

## Reproduction identity

- Fixture: `rag1-seed-v1`, metric policy `v1`, K = 5
- Corpus SHA-256:
  `4adb4bc8013b8893f67295305ac451aa00c54f1eaa4732fff2fd4199d119f57b`
- Answer run: clean commit `dce6de97`, run `rag1-answer-dce6de97`
- Vector run: clean commit `0321d7b0`, run `rag1-vector-0321d7b0`
- Answer model: `qwen/qwen3.8-27b`, temperature 0, strict JSON schema
- Embedding model: `text-embedding-nomic-embed-text-v1.5`
- Host identity: `macos/12/3.12.2`
- Generated reports:
  `build/integration_test_reports/rag_retrieval_eval/{answer,vector}`
  (ignored build artifacts)

## Consolidated evidence

| Arm | Answerable hits | MRR@5 | nDCG@5 | No-answer retrieved | Grounding | Citation precision | Prompt/completion tokens | Context tokens |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `NONE` | 0/16 | 0.000 | 0.000 | 0/4 | 0.200 | 0.200 | 865/474 | 0 |
| `L` | 0/16 | 0.000 | 0.000 | 0/4 | 0.200 | 0.200 | 865/474 | 0 |
| `V` | 16/16 | 0.922 | 0.922 | 4/4 | not measured | not measured | 0/0 | 8,391 |
| `H` | 16/16 | 0.922 | 0.922 | 4/4 | not measured | not measured | 0/0 | 8,391 |
| `FULL` | 14/16 | 0.381 | 0.468 | 4/4 | 0.875 | 0.775 | 12,125/746 | 10,520 |

Grounding requires both a correct candidate fact and a valid evidence citation.
The 0.200 score for `NONE/L` consists only of the four correct no-answer
abstentions; unsupported fact selections without citations score zero. `FULL`
answered from evidence but often over-cited, while its unbounded context
retrieved evidence for every no-answer case.

The vector request embedded the seven repository documents and 20 queries in
12,598 ms. `H` matched `V` because the production-shaped lexical ranking was
empty for every case. The answer pass took 51,699 ms for `NONE`, 53,928 ms for
`L`, and 86,996 ms for `FULL`. These are single-run descriptive measurements,
not latency benchmarks. Peak application RSS was 255,688,704 bytes; VRAM was
not available to the client process.

## Miss and authority review

Lexical misses: 10 `query_policy`, two `ranking`, and four Japanese
`tokenization`. `L` scored current 0/7, historical 0/5, conflict 0/4, and none
0/4. `V/H` scored current 7/7, historical 5/5, conflict 4/4, and none 0/4.
Every required category was represented by four cases.

The seed has 16 answerable cases and four no-answer cases. One answerable hit
changes Hit@K by 6.25 percentage points; one no-answer false positive changes
its rate by 25 points. Gates use these whole-case counts.

## Controls and capability outcome

- `NEG-EMPTY` missed its required non-zero Hit@5 threshold, so the evaluator
  detected the known-bad arm and the negative-control check passed.
- `V/H` were available and measured through the configured embedding endpoint.
- `AK` is `not_available` because agent-kb results do not yet satisfy the
  timestamp/confidence/source-agent provenance contract.
- `H+AK` is `not_available` because the required federated input is blocked.

## RAG2 entry condition

Start with an evaluable local-only design, not production injection. A proposed
RAG2 slice must preserve provenance, introduce an explicit no-answer threshold,
beat `NONE` on answerable cases, avoid the 4/4 false-positive behavior of
`V/H/FULL`, and remain reversible. Automatic prompt injection, a second router,
and agent-kb federation remain out of scope.
