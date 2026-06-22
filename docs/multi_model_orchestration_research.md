# Multi-Model Orchestration Research

Paper-grounded survey for the **persistent multi-PC mesh** setup: several
machines (PC1, PC2, …), each holding **one model resident in memory with no
load/unload**, collaborating on a single task. Written to inform LL24/LL25 and a
possible new "coordinator" milestone. See `docs/local_llm_agent_roadmap.md`.

Context: this is the heterogeneous-pool generalization of Sakana Fugu
(`sakana.ai/fugu`), but for a local LAN mesh instead of a hosted API.

---

## 1. The setup and the one constraint that decides everything

Two physical facts about "N PCs, each model resident, no swap" drive the whole
design space:

1. **Concurrency is real, not time-shared.** Because each model lives on its own
   machine, asking 3 models is genuinely parallel: wall-clock latency is
   `max(workers) + aggregation`, **not** `sum(workers)`. Weight-swap cost is
   zero. This *inverts* the earlier single-GPU recommendation (cascade was
   preferred only because swapping weights on one box was expensive — see
   `caverno-prefix-stable-tool-loop`). With a mesh, **parallel "ask several,
   combine" paradigms become cheap.**

2. **Communication is at message granularity, over the LAN.** Endpoints exchange
   whole responses via HTTP (OpenAI-compatible `/v1/chat/completions`), not
   per-token logits over a shared bus. This single fact partitions the entire
   research literature:

   | Granularity | Examples | Works over LAN mesh? |
   |---|---|---|
   | **Token / logit fusion** | DeePEn, distributed speculative decoding | ❌ needs per-step logit/tensor exchange and tight sync |
   | **Model-parallel (one model split)** | Petals | ⚠️ different goal (run one model too big for one PC); high inter-stage chatter |
   | **Message / text orchestration** | Routing, MoA, debate, role frameworks | ✅ coarse-grained, network-tolerant — **your lane** |

   **Takeaway: design at the message level.** Token-level ensembles (however
   elegant) are off the table for a LAN of separate machines.

---

## 2. Taxonomy of collaboration paradigms (paper-grounded)

Grouped by *how* the models collaborate, each tagged with fit for the mesh and
the Caverno milestone it maps to.

### Group A — Routing / cascading (one model answers; decide which)
Pick the cheapest model that can handle the query; escalate only if needed.
- **RouteLLM** — learned router (matrix factorization / BERT / LLM classifier)
  from preference data; 85% cost cut on MT-Bench at GPT-4 quality. arXiv:2406.18665.
- **Hybrid LLM** (Ding et al., ICLR 2024) — router on predicted query difficulty;
  40% fewer large-model calls, no quality drop. arXiv:2404.14618.
- **FrugalGPT** (Chen et al., 2023) — LLM *cascade*: try light → escalate; match
  GPT-4 at up to 98% cost reduction. arXiv:2305.05176.
- Recent unifications: "A Unified Approach to Routing and Cascading" (2410.10347),
  "Dynamic Model Routing and Cascading: A Survey" (2603.04445).
- **Caverno fit:** this is exactly **LL24 (mode routing) / LL25 (cascade)**. Mesh
  makes it free to keep the strong model resident on PC2 instead of swapping.

### Group B — Ensemble by aggregation (N answer; fuse or rank)
- **LLM-Blender** (Jiang et al., ACL 2023) — `PairRanker` ranks candidate outputs
  pairwise, `GenFuser` synthesizes the top-k into one better answer.
  arXiv:2306.02561. ★ The fuser model can be any resident endpoint.
- **Self-consistency / voting / "More Agents Is All You Need"** — sample many,
  majority/verifier vote. Cross-*model* voting is the heterogeneous version.
- **DeePEn** (Huang et al., NeurIPS 2024 spotlight) — fuse *probability
  distributions* across heterogeneous vocabularies via relative representation.
  arXiv:2404.12715. ⚠️ **logit-level → ruled out over LAN** (listed for completeness).
- **Caverno fit:** **LL7 Best-of-N gated by verification is already a
  selection-ensemble.** Adding a `GenFuser`-style aggregator turns "pick best"
  into "synthesize best."

### Group C — Interaction / debate (N answer; critique iteratively; converge)
- **Multiagent Debate** (Du et al., ICML 2024) — instances propose, then debate
  over rounds; *seeing other agents' reasoning* (not just their answer) is what
  helps; reduces hallucination, lifts math/strategic reasoning. arXiv:2305.14325.
- **ReConcile** (Chen et al., 2023) — round-table consensus among *diverse* LLMs
  with confidence-weighted voting. arXiv:2309.13007. ★ explicitly heterogeneous.
- **Caverno fit:** good for high-stakes reasoning turns; costs `rounds × latency`.
  A "plan-mode debate" between PC1/PC2 before committing a plan is plausible.

### Group D — Layered aggregation: Mixture-of-Agents ★
- **Mixture-of-Agents (MoA)** (Wang et al., ICLR 2025) — layers of LLM "proposers"
  each see the previous layer's outputs as context; a final "aggregator" synthesizes.
  65.1% on AlpacaEval 2.0 with **open models only**, beating GPT-4 Omni.
  arXiv:2406.04692; ref impl `github.com/togethercomputer/moa`.
- **Why it is the best architectural fit:** MoA is *defined* as N independent
  models answering in parallel then one aggregating — a perfect match for "PC1..PCn
  propose concurrently, one endpoint aggregates." Pure message passing; one extra
  round-trip per layer. Heterogeneity is a feature, not a bug.
- **Reference implementation — OpenRouter Fusion (2026)** (`openrouter.ai/fusion`):
  a hosted, productized MoA with a *refined 3-stage pipeline*:
  **(1) Panel** — up to 8 models answer in parallel, each with web search/fetch
  (`analysis_models`, 1–8, default 3); **(2) Judge** — a judge model *compares
  rather than merges*, emitting structured JSON (consensus / contradictions /
  partial coverage / unique insights / blind spots); **(3) Synthesis** — the final
  model writes the answer from that JSON. Invoke via the `openrouter/fusion` alias
  or an `openrouter:fusion` server tool; params `model` (judge+synthesis),
  `preset` (`general-high`/`general-budget`), `max_tool_calls` (default 8);
  recursion-bounded via `x-openrouter-fusion-depth`. The explicit *judge* stage
  (separating analysis from synthesis) is the notable delta over vanilla MoA and is
  more debuggable — the JSON is verifier-friendly. DRACO deep-research benchmark:
  Fable5+GPT-5.5 synthesized by Opus 4.8 = **69.0%** vs solo Fable 5 65.3%; and
  **Opus-paired-with-itself = 65.5% (+6.7 over its 58.8% solo)** — evidence the
  *synthesis step itself* helps even without model diversity (it partially softens
  the homogeneity risk below, though the diverse panel still adds ~3.5pts on top).
  Cost ≈ **4–5× a single call**, latency proportional; the vendor explicitly says
  **skip Fusion for coding and real-time tasks** — direct external corroboration of
  the LL27 risk note that for code, verification beats synthesis. DRACO is a
  *deep-research* benchmark (web search + citations), not interactive coding.

### Group E — Role-specialized agent orchestration (Planner / Coder / Reviewer)
- **AutoGen** (Wu et al., COLM 2024) — conversable agents, group/nested chat, tools
  + humans. arXiv:2308.08155.
- **MetaGPT** (Hong et al., ICLR 2024) — SOP-encoded assembly line (PM → architect
  → engineer → QA). arXiv:2308.00352.
- **ChatDev** (Qian et al., 2023) — virtual software company; agents collaborate
  across SDLC phases; beats single-agent baselines. arXiv:2307.07924.
- **CAMEL** (Li et al., NeurIPS 2023) — role-playing via inception prompting.
  arXiv:2303.17760.
- **Caverno fit:** maps cleanly onto coding work — assign **role → endpoint**
  (strong reasoner on PC1 plans, coder model on PC2 edits, a local small model
  verifies). Caverno's **LL13 (parallel agents in worktrees over the mesh)** is
  already the substrate for this.

### Group F — Learned / evolved conductor ★ (closest to your mental model)
- **Sakana Trinity** (`sakana.ai/trinity`, ICLR 2026) — a small **~0.6B**
  coordinator assigns roles (**Thinker / Worker / Verifier**) to a pool of larger
  models; the *evolved* coordinator beat every constituent (incl. GPT-5,
  Gemini-2.5-Pro, Claude-4-Sonnet).
- **Conductor** (ICLR 2026) — RL-trained to *discover* natural-language
  coordination strategies between LLMs (how agents should talk, what focused
  prompts make a diverse pool beat any single worker).
- Together they ship as **Fugu** (`sakana.ai/fugu`): one OpenAI-compatible
  endpoint that selects, delegates, verifies, and synthesizes.
- **Caverno fit:** "small local coordinator + large resident workers on PC1/PC2"
  *is* the Trinity topology. The learned/evolved part is the hard frontier; a
  **hand-written conductor with the same Thinker/Worker/Verifier role split** is
  the pragmatic 80%, and Caverno's **LL1 per-role model mapping** already encodes
  "role → model/endpoint."

### Group G — Distributed serving (orthogonal — note, don't conflate)
- **Petals** (Borzunov et al., 2023) — shard *one* big model's layers across many
  consumer GPUs over the internet; ~1 step/s for BLOOM-176B. arXiv:2209.01188.
- This solves "run a model too big for any single PC," **not** "make several
  models collaborate." Relevant only if you later want one >local-VRAM model
  across PC1+PC2; high inter-stage network sensitivity. Keep it separate from the
  orchestration question.

### Surveys / recent
- **"Merge, Ensemble, and Cooperate: A Survey on Collaborative Strategies"**
  (2407.06089) — the canonical taxonomy reference.
- **MoE²: Collaborative Inference for Edge LLMs** (2501.09410), **AdaFuse**
  (2601.06022), **xRouter** (RL cost-aware orchestration, 2510.08439) — recent,
  worth tracking.

---

## 3. How the mesh changes the trade-off (vs the earlier single-GPU advice)

| Dimension | Single GPU (earlier advice) | Persistent N-PC mesh (this setup) |
|---|---|---|
| Adding a 2nd model | weight swap, VRAM pressure | free — it is resident on PC2 |
| Parallel "ask 3, combine" | pay 3× sequentially | pay ~1× wall-clock (parallel) |
| Preferred paradigm | **cascade** (avoid loading heavy model) | **parallel aggregate / MoA / debate / conductor** |
| New bottleneck | VRAM / swap | slowest worker latency + aggregation round + LAN |
| KV cache | one shared cache, lost on swap | each endpoint keeps its own cache (a plus); but aggregator prompt grows with proposer outputs |

So the mesh **unlocks** the Group B/C/D/F paradigms that were uneconomical on one
box. The cost moves from compute to **latency and aggregation quality.**

---

## 4. What Caverno already has (the substrate is mostly built)

| Need | Already shipped |
|---|---|
| Register PC1/PC2 as endpoints + health fallback | **LL8** LAN mesh (`MeshEndpointRouter`, `NamedEndpoint`) |
| Run different sub-tasks on different machines | **LL13** parallel agents in worktrees, distributed over the mesh |
| Concurrent candidate execution | **LL20** parallel slot substrate (`--parallel N`, pinned `id_slot`) |
| Selection-ensemble (generate N, keep verified) | **LL7** Best-of-N gated by verification |
| Role → model/endpoint mapping | **LL1** per-role routing (memory/subagent/goal/approval) |
| Per-model harness + capability auto-adapt | **LL3** profiles + **LL23** harness configs (model-keyed) |

**The missing piece is a coordinator / aggregator layer** that makes the resident
models collaborate on **one** conversation turn (MoA aggregator, debate rounds, or
a Trinity-style conductor). Everything underneath it exists.

---

## 5. Candidate architectures for Caverno, cheapest first

- **A0 — Parallel Best-of-N + verifier pick (ships on existing parts).**
  LL7 over LL8/LL20: PC1 and PC2 each generate a candidate concurrently, the
  verifier keeps the one that passes. Already an ensemble (Group B, selection).
  *Build cost: wiring only.*

- **A1 — MoA-lite (2-layer Mixture-of-Agents).** PC1 + PC2 propose in parallel;
  one aggregator endpoint synthesizes a final answer (LLM-Blender `GenFuser`
  style). One extra round-trip. *Group D. Highest quality-per-complexity.*

- **A2 — Role conductor (Trinity-style).** A small local coordinator (0.6–4B)
  assigns **Thinker (strong, PC1) / Worker (coder, PC2) / Verifier (local)** per
  turn, reusing the LL1 role→endpoint map and LL8 routing. *Group E/F. Closest to
  your mental model and to Fugu; start hand-written, learn it later.*

- **A3 — Debate for high-stakes turns.** 2–3 resident models debate over N rounds
  for plan-mode / hard reasoning, then converge. *Group C. Costs `rounds ×
  latency`; gate it behind plan mode or a difficulty signal (LL25).*

**Recommendation:** A0 is effectively free and worth wiring now. **A2 (role
conductor)** is the right research target — it matches the user's "small router +
big resident workers" intuition and Caverno's LL1/LL8/LL13 already cover ~70% of
it. A1 (MoA-lite) is the strongest single quality lever if A2's per-turn
conductor latency proves too high.

**Roadmap positioning (2026-06-22):** A0 is filed as **LL26 (`later`, sequenced
after LL24)** — high-confidence and cheap, but not the immediate next. The eval
gate is real: LL12 already scores wall-clock duration alongside pass rate, so
"beats single-strong including latency" is measurable; the only residual eval work
is letting an orchestration recipe run as one replay candidate. The collaboration
paradigms (A1/A2/A3) are filed
as **LL27 (`later`)**, with the **A2 role conductor kept explicitly as the guiding
thesis / future challenge** rather than a committed build, gated by the LL12/LL19
eval harness ("beats single-strong-model including latency"). See
`docs/local_llm_agent_roadmap.md`.

---

## 6. Open questions to prototype and measure

Use the **LL12 / LL19 personal eval harness** to answer these on *your* tasks and
*your* model pool — do not trust paper benchmarks blindly:

1. **Does parallel-aggregate actually beat the single strong model** on your tasks,
   once you count the slowest worker + aggregation latency? (the core go/no-go)
2. **Aggregator choice:** strongest model as aggregator vs a dedicated fuser. MoA
   found a good aggregator matters more than proposer count.
3. **Does heterogeneity help?** MoA and DeePEn show a weak model can *lift* a
   strong one via fusion; confirm it holds for your PC1/PC2 pair.
4. **Latency budget per mode:** general turns may not justify orchestration;
   reserve A1/A2/A3 for plan/coding (ties back to LL24/LL25 gating).
5. **Failure semantics:** a downed PC already demotes to primary (LL8). Confirm an
   aggregator/conductor degrades gracefully to a single-model answer.

---

## 7. Reading list (grouped)

**Routing / cascade (A):** RouteLLM 2406.18665 · Hybrid LLM 2404.14618 (ICLR'24) ·
FrugalGPT 2305.05176 · Unified routing+cascading 2410.10347.
**Ensemble / fusion (B):** LLM-Blender 2306.02561 (ACL'23) · DeePEn 2404.12715
(NeurIPS'24, logit-level) · AdaFuse 2601.06022.
**Debate (C):** Multiagent Debate 2305.14325 (ICML'24) · ReConcile 2309.13007.
**Layered aggregation (D):** Mixture-of-Agents 2406.04692 (ICLR'25).
**Role frameworks (E):** AutoGen 2308.08155 · MetaGPT 2308.00352 (ICLR'24) ·
ChatDev 2307.07924 · CAMEL 2303.17760 (NeurIPS'23).
**Learned conductor (F):** Sakana Trinity + Conductor (ICLR 2026, `sakana.ai/trinity`,
`sakana.ai/fugu`).
**Distributed serving (G, orthogonal):** Petals 2209.01188.
**Surveys:** Merge/Ensemble/Cooperate 2407.06089 · Dynamic routing+cascading 2603.04445.
