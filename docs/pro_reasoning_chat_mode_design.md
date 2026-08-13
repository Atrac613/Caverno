# Pro Reasoning Mode For Chat Workspace (LL40)

Status: **implemented and live-canary verified** (2026-08-13)
Roadmap item: LL40 in `docs/local_llm_agent_roadmap.md`
Related: LL7 (Best-of-N), LL20 (parallel slot substrate), LL26 (A0 mesh
selection), LL27 (collaborative orchestration),
`docs/multi_model_orchestration_research.md`

---

## 1. The problem

Chat mode answers in a single pass. Every turn gets the same compute budget
whether the question is "what time is it" or "compare these three architectures
and tell me which one survives our constraints". There is no way for the user to
say *this one is worth five minutes*.

The goal is a ChatGPT-Pro-style option for the chat workspace: an opt-in mode
that investigates with tools, explores several independent lines of reasoning in
parallel, and synthesizes one well-grounded answer — taking minutes instead of
seconds, visibly, and cancellably.

## 2. What shapes the design

### 2.1 The parallel substrate is built and now has a production consumer

LL20 shipped `ParallelSlotExecutor`, `LlamaCppSlotDiscovery`, and
`LlamaCppSlotTransport` in `lib/features/chat/data/datasources/`, plus providers
in `parallel_slot_substrate_provider.dart`. Its own doc comment says it is "the
substrate LL7 (Best-of-N) and LL13 (parallel worktrees) build on".

LL40 now consumes that substrate through `ProReasoningCandidateExplorer`. It is
the first production path to use the slot discovery, raw transport, and executor
together. Candidate work is parallelized across responding hosts, while each
host is deliberately constrained to one in-flight candidate so multiple slots
on one GPU are never mistaken for independent GPUs.

`ParallelSlotExecutor.run()` still supplies the sequential fallback for a
single-slot or non-slot endpoint. LL40 additionally sets `maxConcurrency: 1`
for every host queue to enforce the host-placement rule in §2.5.

### 2.2 This is LL26 (A0) pointed at chat instead of code

`docs/local_llm_agent_roadmap.md` files LL26 "Parallel Best-of-N Selection
Across The Mesh (A0)" as `later`, describing it as "high-confidence and cheap …
ships almost entirely on existing parts". Its optional extension — "a single
*synthesis* pass over the top candidates" — is stage 5 below.
`docs/multi_model_orchestration_research.md` §5 recommends A0 as the one
architecture worth wiring now.

The important divergence: **LL26 is about code, and code has ground truth.** Its
acceptance criterion "selection is verifier-grounded (compile / test / LSP), not
a subjective vote" cannot be met for prose. LL40 therefore does *not* claim to
be verifier-grounded; see §4.4.

### 2.3 The existing reasoning knob is a no-op on the real server

`reasoningEffort` is plumbed end to end — `ReasoningEffortPreference` in
`app_settings.dart:29`, a composer popup in `message_input.dart:2194`, and
`reasoningEffortForRequest` in `chat_completion_request_fallback.dart:17` feeding
all five request shapes.

The LAN llama.cpp host runs with `--reasoning off` and **ignores
`reasoning_effort`**. The override that works there is
`chat_template_kwargs: {"enable_thinking": true}`. `openai_dart`'s typed
`ChatCompletionCreateRequest` cannot carry it; the implemented LL40 path now
sends it through the raw HTTP `LlamaCppSlotTransport.buildRequestBody` surface.

A "Pro" mode built only on `reasoningEffort` would therefore be visibly inert on
the primary development endpoint. This assumption was load-bearing, so it was
measured before implementation — see §2.4.

### 2.4 Measured baseline (2026-08-12)

Probed against the configured endpoint `http://192.168.100.241:1234/v1`,
llama.cpp build `b10358-030ebb558`, model `qwen3.6-27b-128k`. Same prompt, three
request shapes:

| Variant | Reasoning returned | Completion tokens | Answer |
|---|---|---|---|
| baseline | none | 6 | `$0.05` |
| `reasoning_effort: "high"` | **none** | 6 | `$0.05` (byte-identical, 0.4 s cache hit) |
| `chat_template_kwargs: {"enable_thinking": true}` | **1383 chars** in `reasoning_content` | 512 (capped) | **empty** |

**§2.3 is confirmed.** `reasoning_effort` is inert on this server;
`chat_template_kwargs.enable_thinking` is the working override, and it returns
reasoning in `reasoning_content` — which
`chat_completion_response_normalizer.dart:150` already wraps into `<think>`, so
rendering integrates with no UI work.

Four further findings changed the plan:

1. **Thinking mode needs a generous token budget.** At `max_tokens: 512` the
   model spent the entire budget reasoning and returned **empty content**. Stage
   3 must give candidates room (measured good at 3000) and must treat
   "reasoning present, content empty, `finish_reason: length`" as an exhausted
   candidate. The explorer retries that candidate once with a 6000-token
   ceiling, then drops it if the retry still has no answer content.
2. **The server is in router mode** (`model_path: none`, four models served via
   `--models-dir`). `GET /slots` returns **HTTP 400 "model name is missing from
   the request"**; `GET /slots?model=<name>` returns 200. LL40 closes this LL20
   gap by passing the model to `LlamaCppSlotDiscovery`, which now emits the
   query parameter. It does not change the execution path chosen in §2.5 — this
   host has one slot either way — but it is the difference between "one slot, known"
   and "slots unknown, assume the worst", which the budget policy and the
   progress UI both read, and it is what makes a future `--parallel N` host work
   without a code change.
3. **The server exposes one slot** (`--parallel 1`), so candidates run
   sequentially. See §2.5 — this was evaluated and *kept* rather than worked
   around.
4. **Throughput**: ~30 tok/s; one thinking candidate on a *simple* question took
   **37 s** (1116 completion tokens: 2010 chars reasoning + 833 chars answer,
   `finish_reason: stop`). A real research question carrying evidence context
   will be materially longer. `id_slot` is accepted but **not echoed** in the
   response; `SlotChatResult.fromResponseJson` already falls back to the
   requested slot, so no change is needed there. The `timings` block the LL20
   transport parses is present (`cache_n`, `prompt_n`,
   `predicted_per_second`, …).

### 2.5 Decision: fan out across hosts, never across slots on one GPU

The obvious reflex on finding one slot is to raise `--parallel`. That was
evaluated against the real router configuration and **rejected**.

Router contents, measured 2026-08-12:

| Registered name | n_ctx | parallel | GGUF |
|---|---|---|---|
| `qwen3.6-27b-128k` | 131072 | 1 | `Qwen3.6-27B-Q4_K_M.gguf` |
| `qwen3.6-27b-vision` | 65536 | 1 | *same GGUF* |
| `qwen3.6-35b-a3b-vision` | 32768 / slot | **2** | `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf` |

**Option A — raise `qwen3.6-27b-128k` to `--parallel 2`.** llama.cpp splits the
total KV cache across slots, so this halves every request to ~64 K. Stage 3
candidates are tool-free and evidence-bounded (~5–27 K), so they would fit
comfortably. The cost lands elsewhere: stage 5 goes through `sendHiddenPrompt`
and therefore carries the **full tool catalog** plus history, evidence, K
candidate answers and the critique — realistically 40–55 K, uncomfortably close
to a 64 K ceiling — and every ordinary chat turn permanently loses half its
headroom, firing `ContextTokenPressureLevel` compaction far earlier.

The return does not justify that. Two slots share one GPU, so continuous
batching yields roughly 1.4–1.7× aggregate throughput, not 2×; against N=3 that
is 3 waves → 2 waves at reduced per-slot speed, and stage 3 is only ~50–60% of a
Pro run. End to end: **~10–18% faster, for halving the context of every turn.**

**Option B — route stage 3 to `qwen3.6-35b-a3b-vision`** (already `parallel=2`,
and a different architecture, which would give genuine candidate diversity).
Rejected: the two models **cannot be VRAM-resident simultaneously** on this host,
so each candidate would drag a 27B/35B load-unload cycle that dwarfs any parallel
saving.

**Option C (chosen) — fan candidates out across LL8 mesh *hosts*, and fall back
to sequential on one host.** Every objection to Option A is an artifact of
sharing one GPU, and none of them survives moving to separate machines:

| | `--parallel 2`, one GPU | 2 hosts (LL8 mesh) |
|---|---|---|
| Compute | shared; batches to ~1.4-1.7x | independent; true ~2x |
| Context | halved to ~64 K **for every turn** | each host keeps its full context |
| Evidence prefill | paid twice, **serially on one GPU** | paid twice, **concurrently** — free in wall clock |
| Model diversity | none (same weights) | real, if hosts run different models |

So the rule is: **fan out across hosts, never across slots on one GPU.** This is
`docs/multi_model_orchestration_research.md`'s core claim — over a mesh, latency
is `max(workers) + aggregation`, not `sum` — and it makes LL40 the chat-side
delivery of LL26/A0 rather than a compromise around it.

When only one host is healthy the run degrades to sequential candidates on that
host, and there it gains a compensating advantage:

> **Every candidate shares the same evidence prefix.** On one slot with
> `cache_prompt: true`, candidates 2..N reuse the cached KV for that prefix and
> skip re-prefilling it. Each llama.cpp slot owns a separate KV cache, so with 2
> slots on one GPU a 20 K evidence block gets prefilled twice instead of once —
> the parallel gain partly pays for itself in refilled cache. Across hosts the
> duplicate prefill is concurrent, so it costs nothing in wall clock.

This holds **only if the per-candidate angle is placed last**, after the shared
evidence, so the prefix stays byte-stable across candidates. That is a hard
design requirement on the stage-3 prompt builder (§4.3), and it is the same
prefix-stability principle as LL6/LL22.

**Endpoint registrations go stale, so trust a fresh preflight, not config.** Measured
2026-08-12: of three registered LAN endpoints, `192.168.100.241` answered,
while `.91` and `.78` timed out — their host had moved to `192.168.100.5`, which
answers at the network level but had nothing listening on the LLM port. A run
therefore performs its own live preflight over the active endpoint and every
enabled additional endpoint. For each target it probes
`GET /slots?model=<name>` and then sends a one-token completion; only targets
whose completion succeeds enter the round-robin candidate pool. This is new
run-local evidence, not a read of the existing LL8 health inventory. The
progress card shows the labels of the targets that survived preflight, so a
single-host degradation is visible rather than just mysteriously slow.

Consequence: `proReasoningModel` / `proReasoningEndpointId` ship defaulting to
empty, and candidate placement is decided per run from that live preflight
(§5). The selected Pro endpoint anchors the candidate pool and receives the Pro
model override; other mesh hosts retain their own configured models.

### 2.6 Hosts are heterogeneous — probe capability, never assume it

Measured 2026-08-12 across both live LAN hosts. They agree on almost nothing:

| | `192.168.100.241` | `192.168.100.5` |
|---|---|---|
| Server | llama.cpp router mode (`b10358`) | **LM Studio** |
| Models | `qwen3.6-27b-128k` / `-vision` / `-35b-a3b-vision` | `qwen/qwen3-coder-next`, `prism-ml/bonsai-27b`, `google/gemma-4-31b-qat` |
| `GET /slots` | supported, **requires `?model=`** | **not implemented** — returns HTTP **200** with `{"error": "Unexpected endpoint…"}` |
| `chat_template_kwargs.enable_thinking` | **works** (1383 chars reasoning, on `qwen3.6-27b-128k`) | **no effect** on `qwen/qwen3-coder-next` — output byte-identical to baseline |
| `reasoning_effort` | inert | inert |
| Context | 131072 / 65536 | **31423** (loaded model) |
| Cold start | — | **111 s** measured to load a model |

**Scope of the `.5` result.** Only `qwen/qwen3-coder-next` was tested there — it
was the loaded model, and testing another would have cost a ~111 s load plus
eviction of the user's resident model. Both override variants returned in 0.5 s
with output byte-identical to baseline, which means the *rendered prompt* was
unchanged, so `chat_template_kwargs` did not reach the template. That is
consistent with two different causes which this measurement cannot separate:
LM Studio not passing the field through at all, or the coder model having no
thinking branch in its template. **Do not generalize this to "LM Studio cannot
do thinking"** — treat it as "capability unknown per model, resolved by probe"
(rule 1 below), which is the behavior the design needs either way.

Five rules follow, none of which the original design assumed:

1. **Thinking is a per-host, per-model capability.** A candidate from `.241`
   reasons; the same request to `.5` does not. Stage 3 must resolve the override
   per endpoint rather than sending one global request shape, and stage 4 must be
   told which candidates had reasoning enabled — otherwise it will read "shallower
   answer" as "worse model" when it is really "thinking was unavailable there".
2. **Context is per-host, and the smallest one binds.** The evidence block must be
   sized to the minimum context among *participating* hosts (31 K here, not
   128 K), or trimmed per host. Sending a 60 K evidence block to `.5` fails the
   candidate.
3. **Prefer already-loaded models.** A cold candidate costs ~111 s before it
   produces a token — comparable to the whole candidate budget. LM Studio exposes
   `state: loaded` via `GET /api/v0/models`; llama.cpp router exposes its own
   catalog. Host selection should rank loaded models first and treat a cold model
   as a last resort, since loading also evicts whatever was resident.
4. **A 200 response is not a supported endpoint.** LM Studio answers `GET /slots`
   with HTTP 200 and an error object. `SlotInventory.fromJson` already survives
   this (it requires a `List`), but the discovery fix in §2.4 must not "improve"
   this into trusting the status code.
5. **Heterogeneity is the point, not a defect.** Different servers running
   different model families is exactly the diversity
   `docs/multi_model_orchestration_research.md` says a selection ensemble needs;
   the risk it warns about is a *homogeneous* pool. The cost is that the
   coordinator must carry a per-endpoint capability record instead of one global
   request shape.

**Current implementation boundary.** The local implementation performs the
availability and slot preflight in §2.5, then probes `enable_thinking` against
the selected model. Candidate records distinguish whether thinking was
requested from whether reasoning was observed. For LM Studio, the preflight
consults `/api/v0/models` and omits a configured model that is not loaded rather
than triggering a cold load. It does not yet discover context size or choose
among multiple loaded models. Those placement refinements remain follow-up work
informed by the completed live multi-host canary.

## 3. Trigger and scope

- A **`Pro` toggle** in the chat composer, beside the existing reasoning-effort
  popup. Sticky (persisted in `AppSettings`) so the state is always visible.
- **`/pro <question>`** runs a single Pro turn *without* flipping the sticky
  toggle, for one-off deep questions.
- `AssistantMode` is deliberately **not** extended. The toggle is orthogonal to
  general/coding/plan, which avoids rippling a new enum case through the 24
  files that reference `AssistantMode` (six of them exhaustive switches).

## 4. Architecture: five stages

A new `ProReasoningRunCoordinator` owns the run. Stages 1–4 are internal and
non-streaming; stage 5 is the visible streamed answer.

| # | Stage | Calls | Purpose |
|---|---|---|---|
| 1 | Frame | 1 | Decompose into sub-questions; define what a good answer must cover |
| 2 | Investigate | ≤N tool iterations | Read-only tool loop gathering evidence |
| 3 | Explore | N across hosts | N independent candidates, round-robin across responding hosts and sequential within each host |
| 4 | Critique | 1 | Rank candidates; surface contradictions between them |
| 5 | Synthesize | 1 (streamed) | Final answer over evidence + top candidates |

### 4.1 Frame

One low-temperature structured call produces sub-questions, an investigation
list, and success criteria. `ProReasoningPromptBuilder.parseFrame` accepts direct,
fenced, or embedded JSON and falls back to a deterministic frame when parsing
fails. The implemented path makes one bounded call; it does not reuse the
workflow proposal retry ladder.

### 4.2 Investigate

A bounded read-only tool loop. `ProReasoningInvestigator` admits local
inspection tools plus explicitly named web search and URL-read tools. External
MCP definitions remain denied by default, with a narrow exception for
`web_search`, `web_url_read`, `web_fetch`, `fetch_url`, `search_web`, and
`searxng_web_search`. This gives Pro the same configured external search path
used by normal chat without exposing mutation, shell, SSH, BLE, or arbitrary
external MCP capabilities. Two consecutive failed web-verification rounds stop
the investigation and mark the external claims unverified.

Output renders as a prompt block in the style of
`PlanningResearchContext.toPromptBlock()`
(`planning_research_collector.dart`) — the existing, closest analogue of a
bounded read-only investigation pass.

Skipped entirely when stage 1 reports the question needs no external facts, so
pure-reasoning questions do not pay for a research round-trip.

### 4.3 Explore — the candidate core

Preflight the active route and enabled additional endpoints with
`LlamaCppSlotDiscovery`, using the target model, followed by a one-token
completion. The explorer runs one warm candidate to measure duration, reduces N
when the remaining deadline cannot fit the rest, then distributes the remaining
candidates round-robin across targets that passed preflight. Each target uses
`ParallelSlotExecutor.run(maxConcurrency: 1)`, so candidates stay sequential
inside a host even when it advertises multiple slots.

Candidates must be genuinely independent, not near-duplicates: each gets the
same evidence but a **different assigned angle** drawn from stage 1's
sub-questions, plus a different temperature and seed. `SlotCandidateOutcome`
already records per-candidate failure without aborting the batch, so one dead
candidate costs one candidate.

**Prompt layout is load-bearing, not cosmetic.** The shared parts — system
prompt, question, evidence block — must come **first and byte-identical across
candidates**, with the per-candidate angle appended **last**. Candidates run
sequentially on one slot (§2.5), so a stable prefix plus `cache_prompt: true`
lets candidates 2..N skip re-prefilling the evidence entirely. Interleaving the
angle earlier silently costs a full prefill per candidate and would not fail any
test — so this belongs in a comment at the builder, and the round-trip test
should assert the prefix is identical across candidate bodies.

**This stage carries the `enable_thinking` fix.**
`LlamaCppSlotTransport.buildRequestBody` supports three optional parameters —
`chatTemplateKwargs`, `reasoningEffort`, `seed` — each emitted only when
non-null, so non-llama.cpp endpoints see a byte-identical body to today. The
combined shape (`enable_thinking` + `seed` + `cache_prompt` + `id_slot` +
`max_tokens: 3000`) was verified working against the real endpoint; see §2.4.

**It also carries an LL20 fix.** `LlamaCppSlotDiscovery` sends the model name
(`GET /slots?model=<name>`), because a router-mode server answers the bare
`GET /slots` with HTTP 400 and the substrate otherwise reports `unsupported`.

Candidates start with a generous `max_tokens` (3000 measured good). A candidate
that comes back with reasoning but empty content and `finish_reason: length`
spent its whole budget thinking and is **not** usable. Retry it once with 6000
tokens while preserving the prompt, seed, and slot so prompt caching remains
effective. If the retry is also exhausted, drop the candidate rather than
feeding an empty answer to stage 4. Session logs record the logical candidate's
attempt count and final token ceiling so recovery can be distinguished from an
ordinary candidate call.

### 4.4 Critique — a judge, not a verifier

One call ranking candidates against stage 1's criteria and stage 2's evidence.

Name it honestly. LL7's Best-of-N is verifier-grounded because code compiles or
does not; a chat answer has no such oracle. This stage is a **rubric judge**,
and the design does not pretend otherwise. Its highest-value output is not the
ranking but the **contradictions between candidates** — where two independent
reasoning runs disagree on a fact is precisely the signal a multi-candidate
setup buys for prose, and it is the part worth surfacing to the user.

Mesh fan-out sharpens this. When candidates come from **different hosts running
different models** (§2.5), a disagreement is genuine model disagreement rather
than sampling noise from one model at temperature — a much stronger signal that
the claim is uncertain. The critique prompt should therefore be told which
model produced each candidate, and the run report should record it, so the
instrumentation can later answer whether cross-model disagreement predicts
error better than same-model disagreement.

### 4.5 Synthesize

Dispatched through the public `ChatNotifier.sendHiddenPrompt` boundary with
`HiddenPromptLaunchOptions`: the visible question, owning conversation, Pro
data source, model, and `ModelUsageRole.proReasoning` are captured explicitly.

The synthesis prompt (evidence + top-K candidates + critique) stays hidden; the
original question and streamed answer are visible and persisted in the captured
conversation. Going through the ordinary send path preserves streaming,
`<think>` rendering via `ContentParser`, session logging, and the normal turn
lifecycle. Synthesis deliberately sends no tools because investigated web or
file evidence is untrusted input and must not gain mutation authority.

This is also an explicit routing boundary: stage 5 uses the selected
`proReasoningEndpointId` / `proReasoningModel`, records Pro usage attribution,
and falls back through the primary chat data source when the selected endpoint
fails. The captured conversation owner prevents a navigation change during
stages 1-4 from moving the visible answer into another conversation.

## 5. Budget, degradation, cancellation

Three depth presets:

Decode dominates: at the measured ~30 tok/s a candidate generating 3–6 K tokens
of reasoning plus answer costs **~2–3.5 minutes**, and the shared-prefix cache
saves prefill, not decode. The wall clock therefore depends on how many targets
survive preflight, so the preset fixes N and the *deadline* absorbs the
difference:

| Preset | Candidates | Deadline | Investigate iterations |
|---|---|---|---|
| Standard | 2 | 6 min | 4 |
| Deep (default) | 3 | 10 min | 6 |
| Max | 4 | 20 min | 10 |

With H responding hosts, stage 3 costs roughly `ceil(N / H) × candidate_time`, so
Deep is ~3 min on three hosts and ~10 min on one. The deadlines above are sized
for the **single-host worst case**, which means a healthy mesh simply finishes
early rather than a degraded mesh blowing the budget.

Two sizing rules:

- **Placement is decided per run from a live preflight**, not from configuration
  or a previously collected health inventory (§2.5). Assign candidates
  round-robin across responding targets and keep each host queue at one in-flight
  candidate, regardless of how many slots it reports.
- **N shrinks from observation, not prediction.** After candidate 1 returns, its
  measured duration says whether the rest fit; drop N rather than letting the
  deadline truncate mid-candidate.

Rules:

- The deadline is checked at **every stage boundary**. On expiry, skip directly
  to stage 5 with whatever exists.
- **The run must never fail the turn.** Worst case it degrades to a plain
  single-pass answer. A deep-think mode that can error out is worse than no deep
  think mode.
- A single responding host runs candidates sequentially; after the warm
  candidate, the budget policy reduces N to what can still fit.
- The Pro run owns a cancellation generation and signal. A cancel during stages
  1–4 skips remaining internal work and dispatches synthesis with whatever was
  collected, including the zero-candidate fallback. A cancel during stage 5
  stops the active chat stream through `ChatNotifier.cancelStreaming()`.

This follows `docs/execution_contract_design.md`'s surviving lesson: depth comes
from structured stages under a budget, **not** from raising the tool-loop cap.

## 6. Model routing

The implementation adds a `proReasoningModel` / `proReasoningEndpointId` role
pair, mirroring
`planningModel` / `planningEndpointId` exactly (`app_settings.dart:694-711`,
resolver `_resolveRoleModel` at `:1027`). Empty means "use the main model", so
the feature is behavior-preserving by default.

It also adds `ModelUsageRole.proReasoning`
(`lib/features/chat/domain/entities/model_usage_role.dart:14`) and a row in
`model_routing_settings_page.dart:144`.

Stages 1, 2, 4, and 5 use the selected Pro endpoint and
`effectiveProReasoningModel` through `SecondaryCompletionRouter`, with endpoint
health tracking and primary fallback. Stage 3 directly preflights a pool built
from the selected target. `ProReasoningCandidateRouting.mesh` keeps the selected
target first and adds enabled peers with their own configured models;
`selectedOnly` restricts every candidate to the selected target. The default is
`mesh` so existing multi-host latency and diversity behavior remains intact.
Explicitly selecting a Pro Reasoning endpoint switches candidate routing to
`selectedOnly` as the safe default; users can opt back into mesh fan-out after
the endpoint selection. Legacy settings with a Pro endpoint pin and no stored
candidate policy migrate to the same selected-only behavior.

## 7. Constraint: the file-size ratchet

`test/quality/file_size_ratchet_test.dart` enforces non-increasing ceilings.
Measured after the implementation extraction on 2026-08-13:

- `chat_notifier.dart`: **8982 / 8984.**
- Its library aggregate: **19818 / 19840.**

Budgets "may only shrink"; the test's own doc comment forbids raising one to
make it pass. Two consequences:

1. **Effectively all new code lives outside the `chat_notifier` library**, in
   `domain/services/` and `presentation/coordinators/`. This is the correct
   architecture regardless; `WorkflowTaskRunCoordinator` (2375 lines) is the
   precedent for a large coordinator living outside the notifier.
2. **Any line added to `chat_notifier.dart` must be paid for by an extraction in
   the same change**, with both budgets lowered. Concrete candidates: the thin
   wrappers `_buildWorkflowProposalRequest` (`:1814`) and
   `_buildTaskProposalRequest` (`:1839`), which only delegate to
   `ConversationPlanningPromptService`, and the `*ForTest` shims at `:2072-2109`.

The hidden-prompt launch options live in `hidden_prompt_launch_options.dart`.
The virtual `ChatNotifier.sendHiddenPrompt` entry point remains in the main
library so existing test doubles can override it; small participant-turn
cleanup moved to the existing part file to pay for the target-conversation,
route, completion-receipt, and visible-question boundary while keeping both
ratchets green.

## 8. Verification

1. ~~**Confirm the reasoning assumption first, before building anything.**~~
   **Done 2026-08-12 — confirmed, see §2.4.** `reasoning_effort` is inert;
   `chat_template_kwargs.enable_thinking` works and returns `reasoning_content`.
   The check also surfaced the router-mode `/slots` gap, the one-slot reality,
   and the empty-content-on-small-max_tokens failure mode, all folded into the
   design above. Re-run `tool/` probes if the endpoint or model changes.
2. **Implemented pure-service tests** under
   `test/features/chat/domain/services/pro_reasoning_*` cover presets, tolerant
   frame parsing and fallback, stable candidate prefixes, tool filtering and
   dispatch, deadline and cancel synthesis, zero candidates, and candidate-host
   scheduling with injected probes and local HTTP clients.
3. **Focused static verification** covers the LL40 settings, domain services,
   coordinator, widgets, hidden-prompt persistence, translation parity, and the
   repository-wide file-size ratchets.
4. **Live multi-host and single-host canaries passed 2026-08-13.** The
   consent-gated runner is `tool/run_pro_reasoning_live_canary.sh`. A Standard
   run over the loaded LM Studio model and the loaded LAN llama.cpp model
   completed in 248.674 s with two candidates on two endpoint labels, all five
   progress stages, one visible user message, one visible assistant response,
   one conversation ID, Pro usage attribution, and no stage errors. The
   single-host repeat completed in 82.505 s with both candidates serialized on
   the one surviving endpoint. The runner now also includes a
   `selected_endpoint` scenario passed 2026-08-13 against x.ai. The 95.615 s
   run selected the secondary endpoint with `selectedOnly` routing, produced two
   candidates exclusively on `grok-4.5`, completed all five stages, and recorded
   no stage errors.
5. **Live cancel canary passed 2026-08-13.** Stop was requested after the warm
   candidate while candidate 2 was in flight. The run attempted two candidates,
   retained one, skipped critique, and completed partial synthesis in 53.205 s
   with `cancelRequested: true` and no stage error.
6. **Logging gate canary passed 2026-08-13.** With
   `CAVERNO_SESSION_LOG_ENABLED=0`, the same five-stage visible turn completed in
   64.868 s while writing zero `pro_reasoning_*` operations. Enabled runs wrote
   frame, investigate, candidate, critique, synthesis, and summary entries under
   the visible conversation ID.

Live artifacts:

- `build/integration_test_reports/pro_reasoning_live_canary_1786589936/`
  (multi-host).
- `build/integration_test_reports/pro_reasoning_live_canary_1786620048/`
  (selected x.ai endpoint only).
- `build/integration_test_reports/pro_reasoning_live_canary_1786590203/`
  (single-host and cancellation).
- `build/integration_test_reports/pro_reasoning_live_canary_1786590412/`
  (logging disabled).

The first harness attempt under
`pro_reasoning_live_canary_1786589893/` is not model evidence: Flutter's test
HTTP override returned synthetic 400 responses before any endpoint request.
The canary now restores the pre-test `HttpOverrides` value, matching existing
live-canary practice.

## 9. Instrumentation

The implementation emits `LlmSessionLogStore` entries with `operation` values
`pro_reasoning_frame`, `_investigate`, `_candidate`, `_critique`, `_synthesis`,
and `_summary`. The summary carries depth, stage timings, surviving and attempted
candidate counts, endpoint labels, models, slot IDs, deadline/cancel flags,
winning candidate index, synthesis dispatch state, and stage errors.
`tool/triage_session_logs.py` explicitly recognizes the Pro operations.

This also produces the first real dataset for the LL26/LL27 question the
research doc parks as unanswerable without measurement: *does parallel
exploration actually beat a single pass on the user's own questions, once the
slowest worker and the synthesis pass are counted?*

## 10. Non-goals

- **No `AssistantMode` change** and no LL24 primary-model router.
- **Not wired into** coding mode, routines, or subagents.
- **No claim of verifier grounding.** See §4.4.

## 11. Open questions for measurement

Answer these with real runs, not argument:

1. **The central one.** Does N=3 beat N=1 on the user's actual questions,
   counting wall clock? Sequential execution (§2.5) makes this sharper than it
   would be on a parallel mesh: three candidates cost roughly three times one
   candidate, so the quality gain has to be large to justify itself. The honest
   alternative is N=1 with a much larger token budget and the critique stage
   turned on itself (draft → critique → revise). If the instrumentation says N=1
   plus self-critique matches N=3, **ship that instead** — it is simpler and
   three times cheaper. Stage 3 is the part of this design most likely to be
   wrong.
2. Is the critique stage earning its round-trip, or would ranking by candidate
   self-consistency be as good and free?
3. Does the investigate stage help on non-research questions, or should stage 1
   skip it more aggressively than currently planned?
4. Is sticky-toggle the right default, or does it cause accidental expensive
   turns on trivial follow-ups?
