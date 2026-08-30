# RAG2 Hosted Passage-Role Evaluation V2 Task

## Goal

Audit and replace the invalid raw no-answer retrieval promotion gate without
changing the frozen hosted lexical candidate. Evaluate passage roles after the
actual file-backed `AppDatabase` and `rag2_chunk_search` path returns evidence.

This slice may decide whether the candidate clears an offline lexical
retrieval gate. It must not select production retrieval, prompt injection,
`search_knowledge`, automatic routing, embeddings, or RAG3 wiring.

## Frozen inputs

- Candidate: `trigram_or_idf`
- Query coverage threshold: `0.15`
- Metric K: `5`
- Host: file-backed `AppDatabase`, schema version `5`
- Passage roles:
  - `answer_support`
  - `abstention_support`
  - `topical_only`
  - `irrelevant`
- Runtime passage role: `unknown`

`rag2-hosted-retrieval-eval-contract-v1` and its No-Go result remain immutable.
The v2 contract does not reinterpret that result as a pass. It records that the
v1 gate measured a different and now-withdrawn promotion question.

## Evaluation order

1. Commit this contract before adding the promotion holdout.
2. Create and content-hash a new 20-case holdout and its complete role oracle.
3. Commit the holdout before the v2 evaluator reads it.
4. Validate the instrument against the existing semantic and compositional
   passage-role fixtures. Those inspected datasets are diagnostic only.
5. Apply the unchanged candidate and v2 gate once to the untouched holdout.
6. Record the result without tuning the candidate, oracle, or gate.

## Promotion holdout shape

The holdout must contain exactly:

- 14 answer-support cases;
- 2 expected abstention-support cases;
- 4 unavailable cases;
- all four Japanese cases as answer-support cases;
- all five required RAG retrieval categories.

The corpus must include current code, current documentation, historical
rationale, conflicting facts, explicit bounded-negative evidence, and safety
text that can support abstention without containing a requested secret or
executable instruction.

## V2 promotion gate

Every condition is conjunctive:

- at least 13 of 14 answer-support cases retrieve `answer_support`;
- all 4 Japanese cases retrieve `answer_support`;
- both expected abstention cases retrieve `abstention_support`;
- zero unavailable cases return only `irrelevant` evidence;
- every returned hit validates against the committed generation provenance;
- the empty negative control remains detectable;
- the existing conversation-search row and LL5 embedding row remain intact;
- total retrieved context across 20 cases does not exceed 6,000 estimated
  tokens.

`abstention_support` and `topical_only` are not unconditional false positives.
Their counts remain visible. The oracle is evaluation-only and must not become
a runtime classifier. A report must keep retrieval relevance, passage role,
answerability, and claim verification as separate decisions.

## Report contract

The deterministic JSON and Markdown reports must record:

- contract, fixture, corpus, candidate, threshold, generation, and build
  identities;
- answer-support, Japanese-support, and expected-abstention counts;
- unavailable cases with abstention, topical-only, only-irrelevant, or no
  evidence;
- role counts, support MRR@5, nDCG@5, and context tokens;
- provenance, negative-control, host-preservation, and every promotion gate;
- `runtimeRoleClassifier: not_available`;
- independent offline candidate, production, and RAG3 decisions.

Reports may contain case IDs and repository-relative object IDs. They must not
contain source text, query text, stored lexical terms, absolute roots, API
keys, or credentials.

## Verification

```bash
fvm flutter test test/tool/rag2_hosted_passage_role_eval_test.dart
fvm dart analyze tool/rag2_hosted_passage_role_eval.dart \
  test/tool/rag2_hosted_passage_role_eval_test.dart
tool/codex_verify.sh --test \
  test/tool/rag2_hosted_passage_role_eval_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```

## Stop conditions

- Do not tune the lexical threshold from either diagnostic fixture or the new
  holdout.
- Do not add intent keywords, semantic heuristics, a runtime role classifier,
  or a model call.
- Do not weaken a failed v2 gate.
- Do not change storage, settings, prompts, tools, chat/runtime wiring, or RAG3
  in this slice.
