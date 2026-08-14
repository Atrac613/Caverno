---
title: "Recent LLM Inference Research for Caverno and Cost-Efficient Local LLMs"
document_id: "caverno-local-llm-research-2026-08-14"
date: "2026-08-14"
language: "en"
audience:
  - "Caverno maintainers"
  - "Codex"
status: "reviewed research brief / implementation input"
source_document: "User-provided caverno_recent_llm_research_brief_2026-08-14.md"
repository: "https://github.com/Atrac613/Caverno"
repository_revision_reviewed: "ed2c2dab"
source_window: "Primarily 2026-05-01 through 2026-08-14, with selected work back to 2026-02"
---

# Recent LLM Inference Research for Caverno

## 0. Scope and authority

This document is research and implementation input. It is not an instruction to
modify the repository, create milestones, enable runtime flags, or change a
deployment. Current repository instructions, roadmap state, security gates, and
verified runtime behavior take precedence.

Before implementation:

1. Re-read the current `README.md`, `docs/roadmap.md`,
   `docs/local_llm_agent_roadmap.md`, `docs/security_audit_2026-08-14.md`, and
   `AGENTS.md`.
2. Re-detect hardware, runtime version, model artifact, server flags, endpoint
   behavior, and available slots. Do not rely on the hardware snapshot in this
   document.
3. Treat every paper performance number as an author-reported result until it is
   independently reproduced on the target Caverno deployment.
4. Do not multiply speedup factors from different papers.
5. Prefer documented capability detection over inferred provider support.
6. Keep desired policy separate from provider-resolved configuration and from
   what was actually served.
7. Keep CUDA, Triton, KV-compression, and offload implementations in external
   runtimes. Caverno should detect, select, observe, and evaluate them.

## 1. Executive decision

The central thesis is accepted: Caverno can become a control plane for
heterogeneous local inference by combining endpoint selection, model capability,
runtime configuration, cache behavior, live state, personal evaluation, and
observed cost.

The original execution order is revised for three reasons:

- LL20, LL22, LL24, and LL39 already provide much of the proposed transport,
  cache, routing, and benchmark foundation.
- KV precision, multi-GPU split, parallel slots, and speculative decoding are
  primarily deployment-time settings in current llama.cpp, not arbitrary
  request-time fields.
- The current Caverno security exit criteria override feature-track promotion,
  and COMPAT1 is the next compatibility foundation.

The near-term target is therefore not an automatic optimizer. It is an additive
observation contract, reproducible deployment-profile benchmark, and shadow
decision policy that preserves current behavior.

### 1.1 Research priority versus product priority

Use `R0` through `R3` for research priority so it is not confused with Caverno's
product and security P0 gates.

| Research priority | Area | Decision |
|---|---|---|
| R0 | Unified inference observation | Extend existing logs, LL20 timings, and LL39 metrics; do not create a parallel telemetry stack. |
| R0 | Deployment fingerprints and endpoint conformance | Build on COMPAT1 and record model, runtime, flags, hardware, and evidence. |
| R0 | Reproducible one-factor benchmark | Compare immutable server presets under cold and warm conditions. |
| R1 | LL25 shadow inference policy | Record deterministic decisions without changing production routing. |
| R1 | N-gram speculative evaluation | Start disabled and promote only a measured, compatible preset. |
| R1 | Prefix/cache-aware selection | Extend LL6, LL20, and LL22 evidence into route inputs. |
| R2 | Bounded streaming experiment | Integrate with API1/OBS1 only after a concrete queue or cancellation failure is demonstrated. |
| R2 | Persistent KV adapter | Keep provider-specific and experimental; require privacy and compatibility controls. |
| R3 | KV compression, tensor offload, FP4 kernels, PIM, and 3D DRAM | Monitor external runtimes and research; do not add application-level kernel implementations. |

## 2. Repository-aligned baseline

This brief extends the current Caverno architecture rather than replacing its
roadmap.

| Existing area | Current state | Reuse in this research track |
|---|---|---|
| LL3 / LL21 | Model capability profiles, probe history, and model-drift detection are complete. | Keep model capability separate from endpoint and deployment capability. |
| LL6 / LL22 | Prefix-stable requests and idle prefix warm-up are complete. | Add production-path cache observations and route inputs. |
| LL8 / LL9 | LAN endpoint routing and Local Stack lifecycle guidance are complete. | Resolve candidate deployments and immutable runtime presets. |
| LL12 / LL19 | Personal eval CLI plus in-app recording and replay are complete. | Supply task-level quality gates. |
| LL20 | `id_slot`, `cache_prompt`, llama.cpp `timings`, slot discovery, and bounded parallel execution are complete. | Reuse the extension-preserving transport and timing parser. |
| LL24 | Primary model and endpoint routing with health fallback and reason logging is complete. | Preserve it as the authoritative turn route. |
| LL25 | Automatic difficulty routing and cascade escalation remain later work. | Add the inference policy as an extension, not a second router. |
| LL33 | Turn-to-session-log provenance remains current work. | Complete correlation before broad event or observation expansion. |
| LL39 | Live capability benchmark, physical metrics, and saturation detection are complete. | Extend the artifact with deployment-mode comparisons. |
| API1 / OBS1 | Agent event normalization and trace timeline remain later work. | Own any future cross-feature streaming and trace model. |
| COMPAT1 | Endpoint protocol and provider-behavior conformance is next. | Supply endpoint capability evidence and downgrade behavior. |

### 2.1 Current integration gaps

The missing pieces are mostly integration contracts:

1. LL24 selects endpoint and model and owns the ordered health-fallback route,
   but it does not select a measured deployment preset or cache policy. LL25 may
   choose a profile for the LL24-resolved route or request a predeclared LL24
   fallback attempt; it must not become an independent endpoint/model router.
2. Request usage, session logs, LL20 timings, LL39 physical metrics, and personal
   eval results are stored in different shapes.
3. Provider extensions are preserved on the LL20 llama.cpp path but are not
   uniformly available through every typed OpenAI-compatible path.
4. Local Stack detects and recommends `ngram-simple`, but Caverno does not yet
   measure acceptance or select speculation by validated task class.
5. Prefix reuse exists, but expected and observed cache reuse are not first-class
   routing evidence across production request paths.
6. Persistent KV lifecycle, compatibility validation, quota, purge, and restore
   fallback are not implemented.
7. Typed execution events exist, but there is no cross-feature bounded queue,
   overflow policy, or shared backpressure contract.

## 3. Evidence policy

### 3.1 Evidence levels

| Level | Meaning | Suitable use |
|---|---|---|
| E0 | Primary bibliographic record exists; ID, title, and date are confirmed. | Discovery and citation only. |
| E1 | An author-reported result appears in a preprint or paper. | Design hypothesis; do not extrapolate performance. |
| E2 | Author-provided executable artifact, scripts, or data exist. | Inspect and run; the claim is still author-reported. |
| E3 | Independent reproduction confirms the relevant result with recorded hardware, runtime, workload, and revision. | Strong engineering candidate. |
| E4 | Caverno-local repeated measurement passes latency, memory, energy, reliability, privacy, and quality gates on target hardware. | Production or automatic-routing decision. |

A DOI does not imply peer review or independent reproduction. Automatic
selection requires E4 evidence for the exact deployment profile.

### 3.2 Verified research shortlist

The identifiers, titles, dates, and headline values below were rechecked against
the current primary records. The numbers remain E1 author reports.

| Research | Author-reported result | Caverno use | Scope limit |
|---|---|---|---|
| [ModeSwitch-LLM](https://arxiv.org/abs/2605.23057) | 2.10x mean latency speedup and 51.7% lower energy/token versus FP16. | Motivates cheap rule-based selection among measured modes. | Single A100, Llama 3.1 8B, vLLM, synthetic workload. |
| [AiFlow](https://arxiv.org/abs/2608.00558) | 70.9–94.7% lower application time-to-first-processed-token and bounded queues. | Input to API1/OBS1 streaming design. | Does not improve provider-side model TTFT; avoid a global rewrite without local failure evidence. |
| [Cache-Aware Prompt Compression](https://arxiv.org/abs/2607.15516) | Query-independent compression plus caching outperformed compared strategies in the reported API workloads. | Reinforces byte-stable prefixes and cache-aware compaction boundaries. | Anthropic-specific economics; local evaluation must use prefill and cache measurements. |
| [SAECache](https://arxiv.org/abs/2605.18825) | Up to 756x reuse variation by token type and 1.4–2.7x TTFT improvement. | Motivates semantic labels in cache experiments. | Requires serving-cache-manager support and multi-session workload evidence. |
| [RouteBalance](https://arxiv.org/abs/2606.17949) | Joint quality/load routing improved the reported high-load frontier. | Motivates queue and measured-rate inputs for the LAN mesh. | Evaluated on a 13-instance, 28-GPU deployment. |
| [Dual-Pool Token-Budget Routing](https://arxiv.org/abs/2604.08075) | 31–42% fewer GPU-hours in the reported fleet experiments. | Motivates separate short- and long-context deployment profiles. | Fleet-scale A100/vLLM evidence; likely small benefit for one user and one slot. |
| [Agent Memory Below the Prompt](https://arxiv.org/abs/2603.04428) | Up to 136x TTFT reduction and four times as many agent contexts with persistent Q4 KV. | Informs a future provider-specific snapshot adapter. | Custom runtime behavior; not a current llama.cpp feature contract. |
| [CompressKV](https://arxiv.org/abs/2606.24467) | More than 97% of FullKV LongBench QA performance with 3% KV; 90% NIAH with 0.7% KV. | Hypothesis for long-context runtime research. | The arXiv record notes substantial text overlap with earlier work; do not use as sole evidence. |
| [PolyKV](https://arxiv.org/abs/2606.15157) | Layer-specific retention and budget allocation improved the reported fixed-budget baselines. | Input to future runtime preset design. | Requires runtime changes and model-specific evaluation. |
| [DFlare](https://arxiv.org/abs/2606.02091) | 3.91–5.52x reported wall-clock speedup on supported targets. | Track when exact target/draft/runtime support exists. | Requires trained, target-specific draft artifacts. |
| [Windowed-MTP](https://arxiv.org/abs/2607.21535) | About 99% draft-KV reduction and 28–44% lower per-step cost at 1M context. | Long-term runtime selection research. | B200, SGLang, native MTP, and million-token context. |
| [ATSInfer](https://arxiv.org/abs/2607.10183) | Up to 1.94x prefill and 3.29x decode improvement. | External consumer CPU/GPU offload research. | Useful mainly when the model exceeds VRAM. |
| [SharQ](https://arxiv.org/abs/2606.26587) | 2.2–2.4x latency reduction versus FP16 on RTX 5090. | FP4 and activation-sparsity learning track. | Different from GGUF Q4 weight quantization and dependent on specialized kernels. |

The withdrawal correction remains valid:
[arXiv:2604.09613](https://arxiv.org/abs/2604.09613) is withdrawn as a
duplicate of arXiv:2604.08075.

## 4. Artifact corrections and limitations

### 4.1 Revalidated Zenodo records

The earlier lookup did not resolve these records, but current Zenodo metadata
confirms that both exist:

- [zenodo.21875513](https://zenodo.org/records/21875513) is version 1.0.1 of
  *Quantization Regime and Governed Routing: A 2x2 Study...*. The record says it
  is superseded by [version 1.0.2, zenodo.21903706](https://zenodo.org/records/21903706).
  Cite version 1.0.2 for current work.
- [zenodo.21766588](https://zenodo.org/records/21766588) is version v4 of
  *TCO Break-Even Model for Mobile LLM Inference — Reproducibility Workbook and
  Data*. It is an author-provided dataset and spreadsheet package; current
  metadata does not identify a related paper.

These records must not be described as nonexistent or unverified. Their
existence is confirmed, but their claims still require independent validation.

### 4.2 Artifact evidence caveats

- [ModeSwitch-LLM software](https://zenodo.org/records/20371757) is suitable for
  studying features, baselines, decision logs, and benchmark structure. Re-run
  the relevant experiments before borrowing thresholds.
- [Agent Memory v1.0.1](https://zenodo.org/records/18793753) is useful for
  snapshot format, agent isolation, and restore benchmarking. Direct adoption
  requires license, runtime, privacy, and compatibility review.
- [Windowed-MTP reproduction](https://zenodo.org/records/21522902) is a B200 and
  SGLang package. Use it as runtime design material, not a consumer llama.cpp
  implementation.
- [FSM-Bench-20](https://zenodo.org/records/20516296) contains 20 natural-language
  specifications, prompts, Ollama scripts, and metrics, but its archived gold
  JSON files are placeholders. Treat it as a protocol and dataset scaffold, not
  a completed benchmark with approved gold outputs.
- [TurboQuant Pro v1.4.2](https://zenodo.org/records/21186512) is a separate
  toolkit rather than the canonical TurboQuant paper artifact. Treat its KV and
  fused-CUDA paths as experimental software evidence.
- [SMOOTH](https://zenodo.org/records/20020344) is useful as a long-term artifact
  evaluation and hardware-simulation reference.
- [ATLAS-MICRO-2026](https://zenodo.org/records/21439810) has thin metadata and
  no related identifier. Treat it as educational material rather than strong
  reproduction evidence.

## 5. Inference control-plane architecture

### 5.1 Configuration boundaries

Current llama.cpp exposes split mode, K/V cache types, parallel slots, and
speculative strategy primarily as server launch configuration. Caverno should
select among immutable, measured deployment profiles rather than pretend that
every option can be changed on each request.

```text
Desired policy
  ├─ quality, latency, and energy constraints
  ├─ cache/speculation permissions
  └─ constraints for LL24-owned fallback
             │
             ▼
LL24 authoritative turn route
  └─ endpoint + model + ordered health fallback
             │
             ▼
LL3 model capability + COMPAT1 endpoint conformance
             │
             ▼
LL25 inference policy
  └─ select one compatible profile for the LL24-resolved route
             │
             ▼
Provider adapter and immutable turn snapshot
             │
             ▼
Attempt observations → task outcome → personal eval gate
```

### 5.2 Domain model

| Object | Lifetime | Responsibility |
|---|---|---|
| `InferenceDesiredPolicy` | User/session policy | Express provider-neutral quality, latency, energy, cache, speculation, and fallback preferences. |
| `InferenceDeploymentProfile` | Measured deployment | Fingerprint one endpoint/model/runtime/hardware/server-preset combination and its evidence. |
| `InferenceLiveState` | Short-lived sample | Capture health, queue, slots, memory, and optional power readings with timestamp and TTL. |
| `TurnInferenceDecision` | One immutable turn | Record the LL24-resolved route and select its deployment preset with deterministic reasons; never own endpoint/model routing. |
| `RequestAttemptObservation` | One network attempt | Record requested, resolved, applied, and actually served state plus measurements. |
| `TaskOutcome` | Whole turn or task | Aggregate quality, verification, tools, latency, tokens, and energy across attempts. |

#### `InferenceDeploymentProfile` fingerprint

Include, when available:

- provider and endpoint identity
- model identifier and model/GGUF checksum
- runtime name, version, and commit
- complete server launch configuration
- context, split, K/V cache, parallelism, and speculation settings
- hardware, backend, driver, and device topology
- benchmark suite version, run identifiers, and gate verdict

A declared capability is not an enabled capability until a compatible tested
preset exists. Profile changes invalidate prior automatic-routing evidence.

#### `TurnInferenceDecision`

The decision is immutable for the turn and contains:

- `turnId`, `decisionVersion`, and desired-policy version
- LL24 route-decision reference and resolved endpoint/model identifiers
- selected deployment profile and preset identifiers
- deterministic profile reason codes and the predeclared LL24 fallback-chain reference
- `shadow` or `applied` status
- creation time and capability evidence references

An endpoint or model change is valid only as an explicit attempt from the
predeclared LL24 fallback chain and receives a separate
`RequestAttemptObservation`. LL25 does not independently switch the route. Do
not start a new model attempt after visible output has been emitted.

#### `RequestAttemptObservation`

Record at minimum:

- `attemptId`, `turnId`, phase, role, and attempt index
- desired, resolved, applied, and actually served mode
- actual endpoint/model and deployment fingerprint
- TTFT, prefill, decode, total latency, and token counts
- cache and speculation measurements when reported
- optional peak VRAM/RAM and energy, with source and confidence
- completion, cancellation, fallback, and failure class
- redaction status and missing-measurement reasons

Do not duplicate prompt text, private source code, tool arguments, secrets, or
raw credentials into this observation.

#### `TaskOutcome`

Task success, verification, JSON validity, edit application, test results, and
tool-call success are task-level aggregates, not properties of one completion.
Join them to the attempt identifiers and benchmark manifest version.

## 6. Benchmark plan for the reported dual-GPU environment

The previously reported hardware is two RTX 5060 Ti 16 GB GPUs, 64 GB system
RAM, and an Intel Core i5-12400F. Re-detect all hardware and runtime details
before each promoted benchmark.

### 6.1 Deployment-profile matrix

Each row is a separate immutable server preset. Verify current flag names with
the deployed `llama-server --help`, `/props`, `/slots`, and actual responses.

| ID | Split | K/V cache | Speculation | Comparison purpose |
|---|---|---|---|---|
| B0 | layer | f16 | none | Production-shaped baseline. |
| B1 | layer | q8_0 | none | Isolate KV precision. |
| B2 | layer | q4_0 | none | Isolate aggressive KV quantization. |
| B3 | layer | f16 | ngram-simple | Isolate history-local draftless speculation. |
| B4 | layer | f16 | ngram-mod | Isolate modified n-gram speculation and confirm its state-sharing behavior. |
| B5 | tensor | f16 | none | Isolate experimental tensor split where supported. |
| B6 | layer | q8_0 | ngram-simple | Measure an interaction only after B1 and B3 pass independently. |
| B7 | layer | compatible | matching EAGLE-3, DFlash, or DSpark | Evaluate only when the exact target, draft artifact, and runtime declare support. |

Do not combine tensor split with quantized KV when the deployed runtime rejects
that combination. `ngram-mod` state-sharing behavior is revision-dependent;
confirm it against the pinned runtime source and live behavior. If state is
shared across slots, measure cross-session isolation, warm-state dependence,
and repeatability before considering it for automatic routing.

### 6.2 Workloads

Start with a narrow production-shaped core:

- ordinary chat
- structured JSON and native tool calls
- repeated-source code rewrite
- small code edit with mechanical verification

Add long-context RAG, long reasoning, multi-agent handoff, interruption/resume,
and 10–20 step tool loops only after the core harness is stable.

### 6.3 Measurement contract

Record:

- latency: TTFT, prompt processing, decode rate, total turn time
- cache: reused tokens, evaluated prompt tokens, cached share, avoided prefill
- speculation: drafted, accepted, rejected, acceptance rate, and overhead
- resources: per-GPU peak VRAM, system RAM, KV bytes, and draft bytes
- energy: source, sample interval, GPU/wall energy, J/token, and J/successful task
- quality: personal eval, tool-call result, JSON validity, edit application, and verification
- reliability: OOM, disconnect, retry, fallback, stall, and cancellation latency
- routing: desired policy, selected profile, reason, evidence, and actual fallback

Quality and reliability are hard gates. Among passing profiles, report the
latency/energy Pareto frontier instead of collapsing all metrics into one score.
Keep energy in kWh and monetary TCO in a separate currency-denominated model.

### 6.4 Experimental discipline

1. Freeze the model artifact and checksum, runtime commit, driver, server flags,
   prompt fixtures, tool catalog, sampler, seed, and verification command.
2. Measure cold and warm states separately.
3. Change one factor at a time before measuring interactions.
4. Alternate or randomize baseline and candidate order to reduce thermal and
   time-order bias.
5. Record concurrency, slot state, clocks, temperature, and power limits when
   available.
6. Repeat enough times to make median, p95, and uncertainty meaningful; report
   the sample count and missing measurements.
7. Reject a profile when quality or reliability regresses, regardless of tok/s.
8. Require repeated E4 evidence before enabling automatic selection.

## 7. Revised implementation work breakdown

### Prerequisite: repository gates

Complete the applicable security P0 exit criteria, finish the required LL33
provenance work, and implement COMPAT1 endpoint conformance before promoting a
new execution-affecting inference policy.

### Slice A: Additive observation contract

Add local-only schemas for deployment profile, live state, turn decision,
request attempt, and task outcome. Reuse current session logs, usage accounting,
LL20 timings, and LL39 artifacts.

Acceptance criteria:

- requested, resolved, applied, and actual state remain distinguishable
- every fallback attempt correlates to its originating turn
- unknown measurements remain unknown rather than becoming zero
- no new prompt, private source, tool-argument, or secret duplication
- existing log readers remain compatible

### Slice B: Deployment capability and profile resolver

Probe documented runtime surfaces and preserve capability evidence, expiry, and
failure reasons. Fingerprint endpoint, model, runtime, server configuration,
hardware, and driver. Unsupported or stale profiles fall back to current
behavior.

### Slice C: Extend the LL39 benchmark

Add manifest-driven deployment profiles, cold/warm separation, raw attempt
observations, and one-factor comparisons. Keep LL39 conformance scores, physical
metrics, and LL12/LL19 personal eval outcomes distinct but joinable.

### Slice D: LL25 shadow policy

Compute a deterministic `TurnInferenceDecision` without changing the current
route or server mode.

Acceptance criteria:

- router-off behavior is unchanged
- the decision copies the LL24-resolved endpoint/model and selects only a
  compatible deployment profile
- identical inputs and profiles produce identical decisions
- every decision has reason codes
- unsupported options are never sent
- endpoint/model fallback follows only the predeclared LL24 chain
- no new model attempt starts after visible output
- shadow and actual routes can be compared

### Slice E: Single-mode activation

Activate exactly one candidate for exactly one compatible deployment profile
after it passes repeated quality, reliability, and latency gates. Keep
n-gram speculation and prefix/cache routing as separate activation slices.
Automatic disablement requires repeated negative evidence and hysteresis; one
slow request must not rewrite a profile.

### Slice F: Bounded streaming experiment

Do not introduce a global streaming graph first. If evidence demonstrates queue
growth or cancellation leaks, add one bounded boundary around one tool-loop
path. Content deltas may be coalesced, but tool-call, terminal, error, and
cancellation events must not be silently dropped. Preserve current terminal and
cancellation semantics and align the work with API1 and OBS1.

### Deferred work

Defer until a compatible external runtime and E3/E4 evidence exist:

- persistent KV snapshots in the core chat data source
- semantic KV eviction or compression
- tensor-granular CPU/GPU offload
- custom CUDA or Triton kernels
- learned routing
- a global streaming-pipeline replacement
- durable application settings for experimental runtime flags

Persistent KV and compression should remain provider-specific experimental
adapters until compatibility, privacy, corruption recovery, and task-quality
behavior are demonstrated.

## 8. Promotion rule

A deployment profile may become eligible for automatic selection only when:

```text
capability evidence is current
AND privacy and security gates pass
AND task quality does not regress
AND reliability does not regress
AND repeated target-hardware measurements improve latency or cost
```

The first production policy should be explainable, reversible, and narrow:

- `Auto` shows the selected profile and reason.
- The decision is locked for the turn.
- The user can return to the normal profile immediately.
- An explicit user model or profile choice is never overridden.

## 9. Recommended execution order

1. Close the applicable security release gates.
2. Complete LL33 correlation required by the observation contract.
3. Implement COMPAT1 endpoint conformance and downgrade evidence.
4. Add the local-only additive observation schema.
5. Extend LL39 with immutable deployment-profile benchmarks.
6. Measure B0 versus B3 first on production-shaped workloads.
7. Add the LL25 shadow policy and compare shadow versus actual decisions.
8. Promote one known-green deployment profile behind an opt-in setting.
9. Evaluate prefix/cache-aware selection as a separate slice.
10. Define API1/OBS1 semantics before broader streaming backpressure work.
11. Prototype persistent KV only after measurement, compatibility, and privacy foundations exist.
12. Monitor KV compression, ATSInfer-style offload, FP4, PIM, and 3D DRAM in external runtimes.

## 10. Success criterion

Caverno should eventually answer this question with reproducible evidence:

> Which already-tested endpoint, model, and deployment profile should execute
> this task while preserving the required quality and reliability and minimizing
> latency, memory pressure, energy, or monetary cost?

The distinctive product value is not a universal inference optimizer. It is a
local-first, evidence-backed control plane that composes heterogeneous models,
multiple machines, idle time, cache reuse, personal evaluation, and reversible
runtime choices.

## Appendix A. Primary sources

### arXiv

- ModeSwitch-LLM: https://arxiv.org/abs/2605.23057
- ATSInfer: https://arxiv.org/abs/2607.10183
- AiFlow: https://arxiv.org/abs/2608.00558
- Cache-Aware Prompt Compression: https://arxiv.org/abs/2607.15516
- SAECache: https://arxiv.org/abs/2605.18825
- Agent Memory Below the Prompt: https://arxiv.org/abs/2603.04428
- CompressKV: https://arxiv.org/abs/2606.24467
- PolyKV: https://arxiv.org/abs/2606.15157
- Windowed-MTP: https://arxiv.org/abs/2607.21535
- DFlare: https://arxiv.org/abs/2606.02091
- RouteBalance: https://arxiv.org/abs/2606.17949
- Dual-Pool Token-Budget Routing: https://arxiv.org/abs/2604.08075
- SharQ: https://arxiv.org/abs/2606.26587

### Zenodo

- ModeSwitch-LLM software: https://zenodo.org/records/20371757
- Agent Memory v1.0.1: https://zenodo.org/records/18793753
- Windowed-MTP reproduction: https://zenodo.org/records/21522902
- FSM-Bench-20: https://zenodo.org/records/20516296
- TurboQuant Pro v1.4.2: https://zenodo.org/records/21186512
- SMOOTH ISCA 2026 AE: https://zenodo.org/records/20020344
- ATLAS-MICRO-2026: https://zenodo.org/records/21439810
- Gemma 4 quantization study v1.0.2: https://zenodo.org/records/21903706
- Mobile LLM TCO workbook v4: https://zenodo.org/records/21766588

### Implementation references

- Caverno: https://github.com/Atrac613/Caverno
- llama.cpp speculative decoding: https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md
- llama.cpp multi-GPU: https://github.com/ggml-org/llama.cpp/blob/master/docs/multi-gpu.md

## Appendix B. Change summary from the source brief

- Rebased the implementation plan on current LL20, LL22, LL24, LL25, LL33,
  LL39, API1, OBS1, and COMPAT1 status.
- Separated research priority from Caverno product/security priority.
- Replaced per-request runtime-flag selection with immutable measured deployment
  profiles.
- Split desired policy, deployment profile, live state, turn decision, request
  attempt, and task outcome.
- Changed the benchmark matrix to isolate one factor before interactions.
- Made shadow routing the first LL25 integration step.
- Deferred global streaming replacement and persistent KV product integration.
- Corrected the two previously unresolved Zenodo records.
- Marked FSM-Bench-20 gold outputs as placeholders and refined artifact evidence
  levels.
