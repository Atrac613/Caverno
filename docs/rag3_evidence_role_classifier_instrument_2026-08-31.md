# RAG3 Evidence-Role Classifier Instrument Result

## Decision

Reject the `rag3-evidence-role-classifier-v1` candidate. The fixed development
measurement reached macro F1 `0.842`, below the `0.900` gate, and the
`topical_only` class reached F1 `0.588`, below the `0.850` per-class gate.

Do not run the compositional validation fixture, do not run promotion, and keep
the production decision at No-Go.

## Scope

- Date: 2026-08-31
- Endpoint: `http://192.168.100.241:1234/v1/chat/completions`
- Requested and reported model: `qwen3.8-27b-vision`
- Development fixture: `rag2-semantic-holdout-v1`
- Passage-role oracle: `rag2-passage-role-oracle-v1`
- Input policy: all 20 development queries crossed with all 5 documents
- Requests: 100
- Persisted query or evidence content: false
- Promotion artifacts accessed: false
- Compositional validation fixture accessed: false

The classifier received only the query, one document, its repository-relative
source path, the corpus revision, the query authority, role definitions, and the
strict output schema. Oracle labels, qrels, expected roles, and answer keys were
not included in classifier requests. Expected roles were joined only after each
response for scoring.

## Fixed contract

The response had to be an exact JSON object with schema version 1 and one role:

- `answer_support`
- `abstention_support`
- `topical_only`
- `irrelevant`

Unavailable or invalid responses fail closed to `irrelevant`. The predeclared
gate requires macro F1 at least `0.900`, every class F1 at least `0.850`, and no
unavailable or invalid responses.

## Result

| Role | Expected cases | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: |
| `answer_support` | 18 | 1.000 | 0.944 | 0.971 |
| `abstention_support` | 3 | 0.750 | 1.000 | 0.857 |
| `topical_only` | 8 | 0.556 | 0.625 | 0.588 |
| `irrelevant` | 71 | 0.957 | 0.944 | 0.950 |

- Macro F1: `0.8417903331545383`
- Unavailable responses: 0
- Invalid responses: 0
- Total request latency: 126,541 ms
- Classifier result: No-Go
- Production decision: No-Go
- Promotion decision: not run

Eight of 100 pairs were misclassified. Seven crossed the boundary between
`topical_only` and `irrelevant`; the remaining answer-support conflict pair was
classified as `abstention_support`. The residuals show that strict JSON output
and transport availability are solved, but the model does not meet the fixed
semantic role separation gate.

## Transport finding

The first diagnostic request exposed an interoperability issue before any
successful fixture payload delivery: the LAN proxy treated a chunked Dart
`HttpClient` request body as empty and returned HTTP 500. The instrument now
encodes the request once, sets `Content-Length`, and sends the UTF-8 bytes. A
local HTTP regression test requires a non-chunked request with a positive
content length. The corrected run completed all 100 requests with no transport
or schema failures.

## Reproduction

```bash
fvm dart run tool/rag3_evidence_role_classifier_instrument.dart \
  --fixture tool/fixtures/rag2_semantic_holdout/fixture.json \
  --oracle tool/fixtures/rag2_passage_role_oracle/oracle.json \
  --out-dir build/integration_test_reports/rag3_evidence_role_classifier_live_2026-08-31 \
  --base-url http://192.168.100.241:1234/v1 \
  --model qwen3.8-27b-vision \
  --api-key no-key
```

The ignored machine-readable report is at
`build/integration_test_reports/rag3_evidence_role_classifier_live_2026-08-31/rag3_evidence_role_classifier_instrument.json`.
