# RAG3 Instrument Evaluation

Date: 2026-08-31

## Decision

The RAG3 instrument adapter is validated on inspected RAG1 and RAG2 data. The
promotion fixture was not opened, the promotion decision remains `not_run`, and
production remains No-Go.

This run validates the committed evaluator, hosted lexical adapter, degradation
contract, context selection, negative controls, deterministic replay, and
privacy-safe output. It does not validate vector quality because no captured
embedding corpus with a complete fingerprint exists for these instrument
fixtures. The vector arm is therefore `not_available` with the explicit reason
`instrument_vector_not_captured`, and hybrid evaluation degrades to lexical.

## Reproduction

The evidence was produced from clean commit
`dcaf4751077767f517e983c8981932a8f1a5f88b` with `buildDirty=false`:

```bash
fvm dart run tool/rag3_instrument_eval.dart \
  --rag1-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --rag2-fixture tool/fixtures/rag2_semantic_holdout/fixture.json \
  --rag2-fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --passage-role-oracle tool/fixtures/rag2_passage_role_oracle/oracle.json \
  --out-dir build/integration_test_reports/rag3_instrument
```

The adapter runs the frozen RAG2 `trigram_or_idf` candidate through the actual
AppDatabase-hosted storage and FTS path. It converts each inspected whole-file
chunk and the RAG2 passage-role oracle into the RAG3 fixture contract, then
passes the hosted rankings through the committed RAG3 run producer and pure
evaluator. An unranked synthetic budget-probe object exists only to exercise the
budget-bypass negative control; it cannot affect candidate rankings or quality
metrics.

## Results

| Dataset | Instrument | Candidate gate | Recall@10 | Hit@5 | MRR@10 | Answer support | Japanese support | Abstention support |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `rag1-seed-v1` | pass | No-Go | 0.9688 | 1.0000 | 0.8958 | 16/16 | 4/4 | 0/0 |
| `rag2-semantic-holdout-v1` | pass | Go | 1.0000 | 1.0000 | 1.0000 | 14/14 | 4/4 | 2/2 |
| `rag2-compositional-holdout-v1` | pass | No-Go | 1.0000 | 1.0000 | 1.0000 | 13/13 | 2/2 | 3/3 |

All three datasets passed:

- AppDatabase host preservation and provenance validation;
- deterministic replay;
- zero context-budget and provenance violations;
- empty-fusion and budget-bypass negative-control detection;
- explicit vector degradation with no zero-scored available vector arm;
- exact lexical/hybrid metric parity while the vector arm is unavailable.

The RAG1 and compositional candidate gates are No-Go because their historical
case distributions do not match the frozen RAG3 promotion denominators. The
semantic candidate gate is Go, but it remains instrument-only: it has no
captured vector rankings, no promotion identity, and no declared no-search
cases. None of these results can tune or promote the frozen candidate.

The generated aggregate reports omit queries, source content, raw endpoint
URLs, and vectors. Tests also reject any instrument input path that names the
RAG3 promotion fixture before reading the file.

## Verification

- `fvm flutter test test/tool/rag3_instrument_eval_test.dart test/tool/rag3_offline_hybrid_eval_test.dart`: 9 tests passed.
- `fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart -r compact`: 334 tests passed.
- `tool/codex_verify.sh`: dependency, generation, project analysis, package
  analysis/tests, and notification relay checks passed. Its full Flutter suite
  reported one transient `chat_notifier_test.dart` failure; the complete file
  passed immediately when rerun in isolation.
- `fvm flutter test -r compact`: 8,684 tests passed on the full-suite rerun.
- `git diff --check`: passed.

## Next Slice

Run the committed evaluator and frozen candidate once against the untouched
promotion holdout, pin the aggregate result, and accept either Go or No-Go
without tuning the fixture or candidate. Persistence, `search_knowledge`, and
runtime prompt wiring remain out of scope until the promotion result is Go.
