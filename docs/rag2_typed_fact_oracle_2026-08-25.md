# RAG2 Typed Evidence-Fact Oracle — 2026-08-25

## Decision

The source-bounded typed-fact matcher passes the frozen compositional holdout
with macro-F1 `1.000`. Supported, contradicted, and absent F1 are each `1.000`.
This is an oracle upper bound, not production evidence: fact extraction is
`not_evaluated`, and RAG2 remains `no_go`.

The result demonstrates that an explicit subject, relation, typed value, scope,
polarity, and modality representation can resolve the compositional failures
that reduced the frozen relation-aware verifier v2 to macro-F1 `0.328`. It does
not demonstrate that those facts can be recovered from arbitrary code or prose.

## Frozen inputs and contract

The evaluation keeps the 12 compositional claims, labels, citation envelopes,
and corpus unchanged. It adds:

- 12 versioned typed claim atoms with no expected labels;
- 14 oracle-annotated evidence facts;
- exact source spans and corpus-hash provenance for every evidence fact;
- a deterministic matcher that can inspect only cited source objects;
- fail-closed validation for missing coverage, invalid source spans, incompatible
  value types, corpus drift, and malformed provenance.

The `caverno_rag2_typed_claim_atoms` and
`caverno_rag2_typed_evidence_facts` schemas are both version `1`. Facts carry
`subject`, `relation`, `valueType`, `value`, `scope`, `polarity`, `modality`,
`source`, and `provenance`. Only asserted facts are eligible for support or
contradiction. Conditional, modal, and normative facts do not prove an asserted
claim, and a missing eligible fact resolves to absent.

## Results

| Evaluator | Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Frozen relation-aware verifier v2 | 0.328 | 0.400 | 0.250 | 0.333 | fail |
| Typed evidence-fact oracle matcher | 1.000 | 1.000 | 1.000 | 1.000 | pass |

All 12 claims match their frozen labels. The matcher correctly separates API
and proxy ports, explicit and implicit URI ports, default and fallback values,
scoped feature states, asserted and qualified modality, and topical absence.

## Reproduction

```bash
fvm dart run tool/rag2_typed_fact_oracle_eval.dart \
  --claims tool/fixtures/rag2_compositional_holdout/claims.json \
  --claim-atoms tool/fixtures/rag2_compositional_holdout/claim_atoms.json \
  --envelopes tool/fixtures/rag2_compositional_holdout/envelopes.json \
  --facts tool/fixtures/rag2_compositional_holdout/oracle_facts.json \
  --fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_typed_fact_oracle
```

## Next entry condition

Freeze the typed schemas, claim atoms, oracle facts, matcher, and all 60 claims.
The next offline slice must measure fact extraction separately from matching.
Produce candidate-independent facts from cited source spans and report exact
fact precision and recall by source family, plus downstream three-class claim
macro-F1. Start with deterministic Dart assignments and URI components. Prose
feature states must fail closed as unavailable until a bounded extractor earns
its own evidence.

Do not add candidate-specific aliases, a matcher v2, production model calls,
embeddings, storage migration, routing, prompt injection, or agent-kb
federation. Production work remains blocked until extraction and end-to-end
claim gates both pass on untouched evidence.

## Extraction follow-up

The first candidate-independent deterministic extractor recovers all four Dart
assignment facts and all five Markdown URI facts, but deliberately recovers
none of five prose-state facts. Overall exact precision is `1.000`, recall is
`0.643`, and F1 is `0.783`. The unchanged matcher still reaches macro-F1
`0.915`, but extraction and production remain `no_go`. These are
development-fixture results; freeze extraction v1 and apply it unchanged to a
new untouched extraction holdout. Evidence:
`docs/rag2_typed_fact_extraction_2026-08-25.md`.
