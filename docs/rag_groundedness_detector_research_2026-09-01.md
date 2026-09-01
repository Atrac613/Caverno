# Groundedness Detector Research

## Decision

Keep production RAG3 closed. The next retrieval-related milestone is a bounded
runtime-feasibility study for a dedicated **post-answer groundedness detector**,
not another query-to-passage filter and not production retrieval wiring.

The intended decision boundary is:

```text
generated claim + cited evidence -> supported | contradicted | unsupported
```

This differs materially from the rejected RAG3 v2/v3 boundary, which classified
whether a retrieved passage could support an answer before an answer existed.
It also differs from factual-truth checking: a claim that happens to be true but
is absent from the supplied evidence is still `unsupported`.

The strongest research candidate is the Qwen3.5-2B detector reported by
[Beyond Document Grounding](https://arxiv.org/abs/2607.00895), because its
benchmark includes source code, developer-tool output, Markdown, tables, and
repository metadata. Generic document-grounding baselines remain necessary,
especially [MiniCheck](https://arxiv.org/abs/2404.10774) and
[FactCG](https://arxiv.org/abs/2501.17144). None is eligible for a Caverno
runner until exact artifacts, licenses, input limits, and a locally deployable
runtime are verified.

## Scope And Method

This investigation reconciles:

- the frozen Caverno RAG3 quality and 1,200 ms added-p95 gates;
- the rejected deterministic and semantic query-to-passage candidate families;
- read-only snapshots of Hermes Agent and Codex;
- primary arXiv papers and Zenodo records available on 2026-09-01.

No production code, model download, endpoint measurement, fixture access, or
promotion run was authorized by this research slice.

## Local Repository Findings

### Hermes Agent

Snapshot: commit `18a76be124d7c16ed98b629a358b23fef76a7f46`.
An unrelated existing modification under `contributors/emails/` was ignored.

Hermes provides two useful patterns but no reusable claim-support classifier:

- `skills/research/grounded-citations/SKILL.md` uses a mechanically maintained
  URL-to-citation ledger, requires inline attribution, can attach verbatim
  evidence, and verifies that cited evidence exists before accepting a draft.
- `agent/context_references.py` expands bounded, typed references such as files,
  folders, Git state, and URLs while tracking warnings and injected-token cost.

The transferable lesson is to make evidence identity and provenance explicit
before classification. Citation presence is not semantic support, so the ledger
is useful input discipline rather than the detector itself.

### Codex

Snapshot: commit `82099786163f3c05facf09078136679e18b64279`.

Codex Guardian V2 provides a strong low-latency classifier transport pattern in
`codex-rs/ext/guardian-v2/src/async_scorer/`:

- `sampler.rs` prewarms authenticated Responses WebSocket connections;
- the first non-empty output delta is the complete classification;
- later output is drained only for connection reuse and token accounting;
- output bytes and accepted labels are strictly bounded;
- `extension.rs` accepts only exact `high` or `low` output and records a
  fail-closed score on sampling or validation failure;
- classification duration, outcome, risk, and token usage are recorded.

This is an implementation reference for a future causal-model classifier. It
does not make Guardian's security-risk model a groundedness detector, and the
WebSocket pattern does not directly apply to encoder or token-classification
models that need a separate inference runtime.

## arXiv Candidate Review

| Candidate | Reported evidence | Caverno fit | Decision |
| --- | --- | --- | --- |
| [Beyond Document Grounding](https://arxiv.org/abs/2607.00895) | The fine-tuned Qwen3.5-2B detector reports unified span-F1 0.689 and code-agent source span-F1 0.60. The same benchmark reports 0.17 for LettuceDetect-large and at most 0.22 for the strongest evaluated zero-shot LLM judge on code-agent source. | Best domain match for code, tool output, Markdown, tables, and repository metadata. | Primary artifact and runtime candidate. |
| [MiniCheck](https://arxiv.org/abs/2404.10774) | A 770M document-claim checker reports GPT-4-level aggregate grounding performance at roughly 400 times lower cost. | Direct binary claim-support baseline with a smaller deployment footprint. Sentence decontextualization may add work for coreference and ellipsis. | Primary generic baseline. |
| [FactCG](https://arxiv.org/abs/2501.17144) | Graph-derived multi-hop training data improves document-level fact checking; the paper reports that FactCG outperforms GPT-4o on LLM-AggreFact with a much smaller model. | Useful when one claim depends on several of the five evidence items. | Multi-evidence baseline after runtime feasibility. |
| [LettuceDetect](https://arxiv.org/abs/2502.17125) | ModernBERT token classification reports RAGTruth example-F1 79.22% and 30-60 examples per second on one GPU. | Attractive natural-language latency control, but the code-agent result above demonstrates severe domain shift. | Natural-language control only. |
| [CCHD](https://arxiv.org/abs/2606.08158) | Constrained paraphrase consistency is applied during training with no additional inference-time stage; the paper reports gains over FactCG, MiniCheck, and AlignScore. | Promising generic checker, but exact released artifacts and local serving support were not established. | Track; do not select yet. |
| [RefChecker](https://arxiv.org/abs/2405.14486) | Decomposes answers into subject-predicate-object claim triplets, then labels each against references as entailment, contradiction, or neutral. | Good offline audit and fixture-authoring approach, but its extraction stage adds a separate LLM step. | Offline reference only. |
| [RAGTruth](https://arxiv.org/abs/2401.00396) | Nearly 18,000 naturally generated RAG responses with case-level and word-level annotations. | Useful natural-language seed data, subject to the label warning below. | Dataset control, not a Caverno promotion fixture. |

### Architecturally Incompatible Candidates

- [RAGLens](https://arxiv.org/abs/2512.08892) depends on the generator's hidden
  activations. Caverno's OpenAI-compatible boundary does not expose them.
- [RAGognizer](https://arxiv.org/abs/2604.15945) adds a detection head and jointly
  fine-tunes the generator. It is not a client-side or independent endpoint.
- [GSAR](https://arxiv.org/abs/2604.23366) is useful as a recovery-policy
  taxonomy, but its multi-agent judge design is not a 1,200 ms inline detector.

## Zenodo Evidence And Warnings

Zenodo provides durable records and artifacts; a Zenodo DOI does not by itself
establish peer review. Zenodo-only results remain exploratory until their code,
data, and measurements are reproduced.

| Record | Relevant result | Use |
| --- | --- | --- |
| [Two Kinds of Hallucination, One Positive Class](https://zenodo.org/records/21693377) | Reports that 13.5% of RAGTruth positive spans by count are unsupported but factually true. | Freeze the distinction between evidence support and external factual truth. For Caverno, these remain `unsupported`. |
| [Grounding on absence](https://zenodo.org/records/21868238) | The deterministic checker reports response-level precision 100% and recall 8.7% on its 408-response subset; its span gate reports precision 83.8% and recall 3.6%. | Confirms that deterministic checks are precision-first tripwires, not a general detector. |
| [SentHalu](https://zenodo.org/records/20555080) | Describes an NLI-initialized DeBERTa-v3-small detector trained on RAGTruth and HaluEval and explicitly identifies false-positive control as an open problem. | Exploratory low-cost baseline only; artifact and peer-review status must be verified. |
| [Temporal Multi-Signal Fusion](https://zenodo.org/records/21196830) | Combines text statistics, NLI, and surprisal into a token-level model and reports AUC 0.840 on RAGTruth. | Research control; multiple inference signals are unlikely to satisfy the current latency budget without a colocated runtime. |
| [FEVEROUS](https://zenodo.org/records/4911508) | Provides 87,026 verified claims with sentence/table-cell evidence and support, refute, or not-enough-information labels. | Structured-evidence fixture-design reference; too large and domain-shifted to use directly as the Caverno fixture. |

## Frozen Label Contract For Future Evaluation

Future development evidence must use three evidence-relative labels:

- `supported`: the cited evidence entails the material claim;
- `contradicted`: the cited evidence entails an incompatible claim;
- `unsupported`: the supplied evidence is insufficient, including a claim that
  may be true outside the supplied evidence.

Record external truth separately when an oracle exists:

- `factuallyTrueButNotEvidenced` must not change `unsupported` to `supported`;
- citation presence alone must not change a semantic verdict;
- missing, invalid, superseded, or authority-mismatched citations fail closed;
- claims and evidence retain source identity, revision, authority, and spans.

## Roadmap Recommendation

Add a separate `RAG3R` research milestone while leaving RAG3 `blocked`.

### RAG3R-A: Artifact And Runtime Feasibility

Before adding a Caverno Dart runner or reading a development fixture:

1. Resolve exact model and code artifacts, immutable revisions, licenses,
   supported input lengths, and output semantics for Beyond Document
   Grounding, MiniCheck, and FactCG.
2. Determine whether each candidate can run on the existing LAN hardware and
   whether it needs a new Transformers, ONNX, or other inference service.
3. Measure one synthetic, non-fixture claim with five evidence items, recording
   cold and warm latency, memory/VRAM, input tokens or bytes, output size, and
   unavailable/invalid behavior.
4. Stop if no candidate has a credible route to the frozen 1,200 ms added-p95
   ceiling. Do not hide model loading or transport cost outside the measurement.

### RAG3R-B: Non-Promotion Instrument

Only after RAG3R-A identifies a runnable candidate:

1. Freeze a new post-answer contract, model revision, input boundary, output
   schema, fail-closed behavior, privacy boundary, and gates before measurement.
2. Build a new 20-case smoke fixture: four cases each for source code, tool
   JSON/log output, Markdown/prose, table/structured data, and mixed multi-hop
   evidence. Use five evidence items per case.
3. Compare the primary candidate, MiniCheck, FactCG, and LettuceDetect where
   their released runtimes permit a fair measurement.
4. Record per-class and span/claim metrics, false refusal, unavailable and
   invalid responses, warm/cold p50 and p95, token/byte usage, and VRAM.
5. Treat the 20 cases as non-promotion smoke evidence. A separately frozen,
   untouched promotion fixture remains mandatory after the candidate,
   evaluator, and gates are committed.

The existing inline gates remain zero false positives, zero false negatives,
zero unavailable responses, zero invalid responses, and p95 at or below
1,200 ms. RAG3 production persistence, tools, prompts, retrieval routing, and
promotion remain blocked until the full resume contract passes.

## Source List

### arXiv

- Beyond Document Grounding: https://arxiv.org/abs/2607.00895
- MiniCheck: https://arxiv.org/abs/2404.10774
- FactCG: https://arxiv.org/abs/2501.17144
- LettuceDetect: https://arxiv.org/abs/2502.17125
- CCHD: https://arxiv.org/abs/2606.08158
- RefChecker: https://arxiv.org/abs/2405.14486
- RAGTruth: https://arxiv.org/abs/2401.00396
- GSAR: https://arxiv.org/abs/2604.23366
- RAGLens: https://arxiv.org/abs/2512.08892
- RAGognizer: https://arxiv.org/abs/2604.15945

### Zenodo

- RAGTruth label audit: https://zenodo.org/records/21693377
- Grounding on absence: https://zenodo.org/records/21868238
- SentHalu: https://zenodo.org/records/20555080
- Temporal Multi-Signal Fusion: https://zenodo.org/records/21196830
- FEVEROUS: https://zenodo.org/records/4911508
