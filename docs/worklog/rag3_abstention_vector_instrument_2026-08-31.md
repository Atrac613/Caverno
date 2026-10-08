# RAG3 Abstention Vector Instrument

## Decision

Exact cross-arm chunk consensus is **rejected as a RAG3 abstention candidate**.
No predeclared depth in `{1, 3, 5}` satisfied the development eligibility rule
that requires zero unavailable cases with only irrelevant selected evidence.
The instrument selected no candidate, did not read the promotion fixture, and
does not authorize production retrieval work.

## Frozen Instrument Contract

- Contract: `rag3-abstention-vector-instrument-v1`
- Policy family: exact chunk-ID intersection between lexical and vector arms
- Depths: `1`, `3`, and `5`
- Development datasets: `rag1-seed-v1` and
  `rag2-semantic-holdout-v1`
- Validation dataset: `rag2-compositional-holdout-v1`
- Embedding model: `qwen3-embedding-0.6b`
- Candidate eligibility: zero development unavailable cases containing only
  irrelevant selected evidence
- Candidate ordering: maximize answer support, maximize abstention support,
  minimize answerable abstention, then prefer the shallower depth
- Selected depth: none
- Promotion fixture accessed: false
- Promotion decision: `not_run`
- Production decision: `no_go`

The prediction policy reads only submission state, vector availability, and
the two ranked chunk-ID lists. Qrels and passage roles are used only after the
prediction to score the instrument result. Tests prove that changing oracle
roles does not change a prediction.

## Development Selection Result

| Depth | Answer support | Abstention support | Unavailable irrelevant-only | Answerable abstained | Eligible |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 23/30 | 1/2 | 1 | 7/30 | no |
| 3 | 29/30 | 2/2 | 1 | 0/30 | no |
| 5 | 30/30 | 2/2 | 2 | 0/30 | no |

Depth 3 was the strongest quality tradeoff, but
`none-instruction-injection` still produced exact top-ranked agreement on
`docs/security_boundary.md#1`. Both retrieval arms agreeing on the same chunk
therefore does not establish that the chunk is evidence for the requested
fact. Depth 5 also admitted irrelevant evidence for `none-secret-value`.

## Per-Dataset Measurements

### RAG1 seed development

| Depth | Answer support | Japanese support | Unavailable irrelevant-only | Unavailable abstained |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 12/16 | 4/4 | 1 | 3/4 |
| 3 | 15/16 | 4/4 | 1 | 3/4 |
| 5 | 16/16 | 4/4 | 2 | 2/4 |

### RAG2 semantic development

| Depth | Answer support | Japanese support | Abstention support | Unavailable irrelevant-only | Unavailable abstained |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 11/14 | 3/4 | 1/2 | 0 | 2/4 |
| 3 | 14/14 | 4/4 | 2/2 | 0 | 1/4 |
| 5 | 14/14 | 4/4 | 2/2 | 0 | 1/4 |

### RAG2 compositional validation

No depth was promoted from development, so these figures are diagnostic only.

| Depth | Answer support | Japanese support | Abstention support | Unavailable irrelevant-only | Unavailable abstained |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 9/13 | 1/2 | 2/3 | 0 | 3/4 |
| 3 | 13/13 | 2/2 | 3/3 | 0 | 1/4 |
| 5 | 13/13 | 2/2 | 3/3 | 0 | 1/4 |

The validation split shows that depth 3 can preserve support on these
inspected fixtures, but it cannot override the failed development eligibility
condition.

## Evidence Identity

- Aggregate report SHA-256:
  `30d8cc3aa6e8da01e24572367a52916671cc64a15ee1a041cc9fd678ed05c67f`
- RAG1 run SHA-256:
  `0a1018e8d9a9e410d06a85c3eafff88d78cb43967057b06ad7db7bf5380cf61f`
- RAG2 semantic run SHA-256:
  `f81f7482c1a95dc29058a4e6e963968c1be061fea4e99538a452eb5a9c9eb38d`
- RAG2 compositional run SHA-256:
  `43fd058f6da79c88fea508efca0d4ee29e3a5d731eb11b3dbfae1d6464a4b2e6`
- Generated artifacts:
  `build/integration_test_reports/rag3_abstention_vector/`

The report records build commit `b95c5791` with `buildDirty: true` because the
new runner had not yet been committed when the authorized network run began.
The unchanged runner and its input-boundary tests were committed immediately
after the run as `12ab2691`. The network measurement was not repeated.

## Consequences

- Do not tune the three depths against these results.
- Do not add lexical score thresholds or intent keywords; earlier independent
  audits already rejected those policy families.
- Do not reinterpret exact cross-arm agreement as an answerability signal.
- Keep vector persistence, `search_knowledge`, prompt injection, and runtime
  routing blocked.
- Any next abstention family needs a new predeclared contract and must evaluate
  whether evidence supports the query, rather than only whether two retrievers
  returned the same chunk.

## Verification

- `dart analyze tool/rag3_abstention_vector_instrument.dart tool/rag3_instrument_eval.dart test/tool/rag3_abstention_vector_instrument_test.dart`
- `fvm flutter test test/tool/rag3_abstention_vector_instrument_test.dart test/tool/rag3_abstention_policy_instrument_test.dart test/tool/rag3_instrument_eval_test.dart`
- `tool/codex_verify.sh`
- `git diff --check`
