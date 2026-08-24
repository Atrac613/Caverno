# RAG1 Retrieval Baseline — 2026-08-24

## Decision

RAG2 is **No-Go** on this baseline. The production-shaped lexical arm does not
beat `NONE`, while `FULL` retrieves most answerable cases at an unacceptable
context cost and retrieves content for every no-answer case. This result is
evidence for designing RAG2's index and query policy; it does not authorize a
production query rewrite in RAG1.

## Reproduction identity

- Build commit: `875067d9a6e688181086de4893591ac095193a45`
- Build dirty: `false`
- Fixture: `rag1-seed-v1`, metric policy `v1`, K = 5
- Corpus SHA-256:
  `4adb4bc8013b8893f67295305ac451aa00c54f1eaa4732fff2fd4199d119f57b`
- Hardware: `macos/12/3.12.2`
- Lexical tokenizer: `unicode61`
- Lexical query policy: `quoted_whitespace_terms_and_v1`
- Token estimate: `unicode_code_points_div_4_v1`
- Embedding fingerprint: `not_available`

Generated JSON and Markdown reports remain ignored build artifacts under
`build/integration_test_reports/rag_retrieval_eval/{cold,warm}`.

## Retrieval results

| Arm | Answerable hits | Recall@5 | Hit@5 | MRR@5 | nDCG@5 | No-answer retrieved | Context tokens |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `L` | 0/16 | 0.000 | 0.000 | 0.000 | 0.000 | 0/4 | 0 |
| `NONE` | 0/16 | 0.000 | 0.000 | 0.000 | 0.000 | 0/4 | 0 |
| `FULL` | 14/16 | 0.813 | 0.875 | 0.381 | 0.468 | 4/4 | 10,520 |
| `NEG-EMPTY` | 0/16 | 0.000 | 0.000 | 0.000 | 0.000 | 0/4 | 0 |

The deliberately broken `NEG-EMPTY` arm missed its non-zero Hit@5 threshold,
so the report detected the known-bad retriever and the negative-control check
passed. `FULL` missed `current-default-model` and `current-tool-loop-limit`
because its deterministic first-five document window excluded
`lib/runtime_defaults.dart`.

## Lexical diagnostics

All 16 answerable cases missed in both cold and warm runs:

| Miss reason | Cases | Interpretation |
| --- | ---: | --- |
| `query_policy` | 10 | A relaxed OR diagnostic found the relevant object; the measured all-terms query did not. |
| `ranking` | 2 | The relaxed query returned candidates but did not place the relevant object in the first five. |
| `tokenization` | 4 | Japanese queries could not reach the Japanese fact object with `unicode61`, even under the relaxed diagnostic. |

Every category scored 0/4. Authority breakdown was current 0/7,
historical 0/5, conflict 0/4, and none 0/4. No-answer cases are excluded from
miss attribution and measured only through false-positive behavior.

## Cold and warm resources

| State | `L` total latency | Peak RSS | Prompt tokens | Peak VRAM |
| --- | ---: | ---: | ---: | ---: |
| cold | 23 ms | 250,658,816 bytes | 230 | `not_available` |
| warm | 20 ms | 273,203,200 bytes | 230 | `not_available` |

The elapsed-time delta is descriptive only; one local run per state is not a
latency benchmark. Retrieval rankings and diagnostics were identical.

## Capability outcome

- `V`: `not_available`; no embedding capture is configured and no embedding
  fingerprint exists for this run.
- `H`: `not_available`; vector rankings do not exist.
- `AK`: `not_available`; the required agent-kb provenance gate is not met.
- `H+AK`: `not_available`; federated inputs are unavailable.

These arms are unavailable, not zero-scoring. RAG2 promotion requires a new
lexical-only design to beat both `NONE` and the bounded `FULL` control before
vector or federated work can hide the lexical failure.
