# Local LLM Agent Roadmap

This document plans the next major Caverno arc: making Caverno the strongest
coding agent specialized for local LLMs, while paying down the structural debt
that would otherwise block that work.

It introduces implementation tracks following the conventions in `docs/roadmap.md`:

- `F<number>` — Foundation track: refactoring, dependency currency, storage.
- `LL<number>` — Local LLM Agent track: features that attack local-LLM-specific
  constraints (small context, heterogeneous model capability, slow inference)
  and weaponize the one local asset: zero marginal token cost.

It also records a future platform vision layer. These milestones are deliberately
`later` until an implementation slice promotes one of them into active focus:

- `API<number>` — Protocol and agent-event compatibility across Chat
  Completions, Responses-style APIs, and local-provider extensions.
- `SEC<number>` — Local agent data perimeter, permissioning, and prompt
  injection resistance.
- `MLIB<number>` — Local model library, provenance, licensing, and capability
  badges.
- `OBS<number>` — Agent trace observability and exportable support evidence.
- `COMPAT<number>` — OpenAI-compatible endpoint conformance and provider
  compatibility diagnostics.
- `HOOK<number>` — External config hooks and lifecycle integration points for
  local automation, agent-kb, and future Claude-like hook flexibility.
- `EDGE<number>` — Embedded on-device runtime adapters and offline fallback.
- `EVAL-MOBILE<number>` — Flutter/mobile coding eval packs and visual
  regression harnesses.
- `MM<number>` — Multimodal evidence workflows for screenshots, voice, and
  screen recordings.
- `MCP-GOV<number>` — MCP tool contract governance, trust registry, and
  model-specific tool-prompt optimization.
- `SKILL<number>` — In-chat skill authoring and lifecycle: create, edit, and
  mine reusable skills from the conversation instead of only the settings UI.
- `TOOL<number>` — User-created Tools workspace: local-first mini applications
  built from a Caverno-owned, capability-gated manifest runtime rather than
  arbitrary generated code.
- `ROUTINE<number>` — In-chat scheduled-routine authoring and lifecycle: create
  and manage recurring agent runs from the conversation instead of only the
  routine editor UI.
- `THREAT<number>` — Endpoint threat posture: agent-as-malware-vector
  hardening, read-only host compromise triage, and idle-time local
  threat-intelligence pre-learning.

## Design Thesis

Caverno already has the rare building blocks: Plan Mode, subagents, skills,
custom slash commands, conversation compaction with token-pressure detection,
completion-claim verification (`coding_verification_feedback_service`), past
conversation search, and Remote Coding. The next leap does not come from
imitating cloud agents further. It comes from features cloud-billed agents are
structurally unmotivated to build:

1. **Capability heterogeneity is the core local problem.** Every local model
   differs in tool-call fidelity, JSON discipline, edit-format success, and
   usable context. Today the app compensates reactively (JSON repair, embedded
   `<tool_call>` tag parsing). Promote this to proactive diagnosis: probe once,
   store a profile, tune agent behavior per model.
2. **Small context windows make exploration expensive.** A compressed repo map
   plus fully local semantic search (OpenAI-compatible `/v1/embeddings`)
   compensates for the model's limited ability to explore via tool calls.
3. **Prefill latency is the local UX killer.** llama.cpp / LM Studio reuse the
   KV cache only while the prompt prefix is byte-stable. The current request
   construction (tool list changing between the first and subsequent requests,
   tool results re-sent as user-role messages) invalidates the cache every
   turn. A prefix-stable mode converts design discipline directly into speed.
4. **Tokens are free locally.** Best-of-N patch generation gated by the
   existing verification loop, and overnight unattended retry-until-green runs
   via Routines, turn zero marginal cost into output quality.
5. **The LAN is yours.** Local users often own several machines that can serve
   models with no rate limits. Caverno already ships a LAN scanner and remote
   coding pairing; discovering and routing across multiple inference endpoints
   turns a home lab into an agent farm.
6. **Local models are stale and change weekly.** Their training data ages and
   users swap GGUFs constantly. Grounding answers in the project's actually
   installed dependency versions, and replaying the user's own recorded tasks
   as a personal eval suite, beat both problems offline.
7. **Idle local hardware is a scheduled compute budget.** A desktop that sits
   idle overnight with a warm GPU is a recurring, zero-token compute budget no
   cloud-billed agent can assume. The measurement and self-improvement pieces
   above (LL3, LL12, LL16, LL17) only pay off if something schedules them while
   the machine is free; an idle/overnight orchestrator turns that budget into
   continuous model re-measurement, eval-gated self-improvement, Best-of-N
   quality, and pre-warmed caches.
8. **The OpenAI-compatible surface is a moving target.** Caverno should not bind
   its internal agent model to one provider generation. Chat Completions,
   Responses-style APIs, and provider extensions should all normalize into a
   durable event stream before UI, tools, eval, and traces consume them.
9. **Local-first agents need an explicit data perimeter.** MCP, Remote Coding,
   file operations, memory writes, and retrieved documents must carry provenance
   and permission context. Untrusted content can inform the model, but it should
   not silently become an instruction with tool authority.
10. **Local models are supply-chain artifacts.** A model name is not enough:
    users swap GGUFs, quantizations, adapters, merges, and revisions. Caverno
    should remember provenance, checksums, license assumptions, verified
    capabilities, and eval history alongside the model profile.
11. **Agent work must be observable.** Parallel candidates, overnight adoption,
    worktree tasks, and model-specific harness edits become trustworthy only
    when a user can inspect what happened, why it happened, and which evidence
    justified the final state.
12. **Flutter can be an edge runtime, not only a shell around localhost.** Small
    on-device models should eventually handle low-risk micro-tasks such as
    routing, memory extraction, privacy screening, and offline fallback while
    large local endpoints keep the heavy reasoning role.
13. **Multimodal inputs are evidence, not decoration.** Screenshots, voice,
    accessibility output, and screen recordings should become first-class
    evidence objects that can be cited, diffed, redacted, and routed through the
    same trace and permission model as text and tool results.
14. **The agent's own tool surface is an endpoint-security boundary.** A local
    agent that runs shell, fetches URLs, and writes files is the same delivery
    path attackers now target directly: a `curl`-to-shell or
    download-then-execute that an auto-approving agent runs is indistinguishable
    from a user doing it (the AMOS Stealer macOS variant arrived exactly this
    way). Caverno should both harden that path — never silently auto-approve
    network-fetch-then-execute or persistence writes — and turn its free local
    token budget toward the inverse problem: distilling public vulnerability and
    malware intelligence into a local knowledge base that informs read-only host
    triage. Vulnerability intel (what is patchable) and threat/IoC intel (what
    infection looks like) are different axes, and neither is the model's stale
    training data.
15. **User-created Tools should be manifests, not code blobs.** Caverno can
    become a local-first personal app workbench without letting an LLM write and
    execute arbitrary Flutter, JavaScript, SQL, shell, native plugin, or network
    code. A closed Tool manifest keeps generated screens, data, actions,
    capabilities, permissions, and resource limits reviewable while the runtime
    enforces Caverno's storage, approval, data-egress, and data-perimeter rules.

## Milestone Index

| Track | Milestone | Status | Size | Depends on | Goal |
|-------|-----------|--------|------|------------|------|
| Foundation | F1 | done | S | — | CI-enforced line-count ratchet for oversized files. |
| Foundation | F2 | done | M | F1 | Extract the tool-call loop from `ChatNotifier` behind a handler registry. |
| Foundation | F3 | done | M | — | Major dependency upgrades, `openai_dart` 6.x first. |
| Foundation | F4 | done | L | — | Migrate conversations/chat memory from Hive to drift (SQLite) with FTS history search. |
| Foundation | F5 | later | ongoing | F2 | Continue large-file decomposition per `docs/large_file_refactor_plan.md` phases 2-4. |
| Foundation | F6 | done | S | F1 | Built-in tool initial-load classification guard: a CI-enforced exhaustiveness test (plus optional category/flag-driven selection) so new built-in tools cannot be silently omitted from the dynamic tool-search initial set. |
| Local LLM | LL1 | done | S | — | Per-role model routing (memory extraction, subagents, goal suggestions, approval auto-review on a small fast model). |
| Local LLM | LL2 | done | S-M | — | Whole-turn checkpoints via shadow git, building on `rollback_last_file_change`. |
| Local LLM | LL3 | done | M | F3 (openai_dart) | Model capability profiles with automatic probing on model registration. |
| Local LLM | LL4 | done | M | LL3 | Repo map v1: ranked, compressed symbol outline injected into the system prompt. |
| Local LLM | LL5 | done | M | F4, LL4 | Local semantic history search via `/v1/embeddings`, stored in the drift database. Semantic *code* search is a deferred follow-up. |
| Local LLM | LL6 | done | M-L | F2, F3, LL3 | KV-cache-friendly prefix-stable request mode. |
| Local LLM | LL7 | done | M | F2, LL3 | Best-of-N patch generation gated by verification, plus overnight retry-until-green Routines. |
| Local LLM | LL8 | done | M | LL1 | LAN inference mesh: discover/register OpenAI-compatible endpoints and route secondary calls per role with health fallback. Main-conversation fan-out is a deferred follow-up; task-based primary-model routing is tracked as LL24/LL25. |
| Local LLM | LL9 | done | M | — | Local stack manager: model load/unload control and hardware-aware model guidance. |
| Local LLM | LL10 | done | M | — | Installed-dependency grounding: resolve APIs from the project's locked dependency sources, offline. |
| Local LLM | LL11 | done | M-L | — | LSP bridge: post-edit diagnostics feedback and symbol data for the repo map. |
| Local LLM | LL12 | done | M | LL3 | Personal eval harness: replay recorded real tasks to score new models. |
| Local LLM | LL13 | done | L | F2, LL2 | Parallel agents in isolated git worktrees, optionally distributed over the LL8 mesh. |
| Local LLM | LL14 | done | M | LL6 | Context surgery: stale tool-result eviction, file-read dedup, model-switch handoff brief. |
| Local LLM | LL15 | done | S-M | LL3 | Weak-model edit harness: grammar-constrained edit blocks and profile-stored few-shot exemplars. |
| Local LLM | LL16 | done | S-M | LL3 | Sampler auto-calibration: probed per-role temperature/sampler presets with runtime feedback. |
| Local LLM | LL17 | done | L | LL3, LL19, LL23 | Self-improving harness loop: cluster failure traces by verifier-grounded signature, propose minimal harness-config edits, adopt only on held-in/held-out non-regression. |
| Local LLM | LL18 | done | L | LL3, LL12, LL16, LL19 | Idle/overnight maintenance orchestrator: detect idle + AC power + night window, then chain probe → calibrate → eval → mine → eval-gated adopt and emit a morning report. |
| Local LLM | LL19 | done | M | LL12 | In-app personal eval recorder and replay executor: record sessions to eval cases and drive a candidate model through them end-to-end. |
| Local LLM | LL20 | done | M | F3, LL6 | Parallel slot execution substrate: preserve provider extension fields, pin `id_slot`, and run `--parallel N` candidates concurrently. Unblocks LL7/LL13. |
| Local LLM | LL21 | done | M | LL3, LL18 | Continuous idle re-probing and profile history: full (non-bounded) probe on idle, time-series profile versions, model-drift / quant-swap detection. |
| Local LLM | LL22 | done | M | LL4, LL6, LL18 | Idle warm-up and precompute: precompute repo map / embeddings and warm the KV cache so the first morning turn is instant. |
| Local LLM | LL23 | done | M | LL3, LL6 | Declared per-model harness config: instruction surfaces (bootstrap/verify/recovery) and runtime control policy (loop caps, recovery middleware) as a mutable schema LL17 edits. Focused coding-goal repeat canary is green; broad main-gate PM5 still blocks on saved-validation command preservation and active-task target-scope drift. |
| Local LLM | LL24 | next | S-M | LL1, LL8, LL23 | Task-based primary-model routing: select the main conversation model by assistant mode (for example plan/coding → quality-preferred assignment, general → fast/default assignment) through a single re-invokable route decision, reusing the LL1/LL8 endpoint resolver and the model-keyed LL3/LL23 profiles. |
| Local LLM | LL25 | later | M | LL24, LL7 | Auto difficulty routing: decide the primary model automatically — preferred shape is cascade escalation (answer with the fast/default model, escalate to the quality-preferred model on verification failure or tool-loop stall) over a per-turn classifier, with each route + escalation decision logged for tuning. |
| Local LLM | LL26 | later | S-M | LL7, LL8, LL20 | Parallel Best-of-N candidate selection across the mesh (A0): generate candidates concurrently on resident endpoints (PC1/PC2) via LL20 slots over the LL8 mesh, then keep the verifier-passed candidate (LL7). A latency-neutral selection ensemble; concretizes the Best-of-N half of LL8's deferred fan-out. High-confidence and cheap, but sequenced after LL24. |
| Local LLM | LL27 | later | L | LL26, LL12, LL19, LL1 | Collaborative multi-model orchestration over the mesh: layered aggregation (Mixture-of-Agents), role conductor, and debate so resident models cooperate on one turn. Guiding thesis: a Trinity-style role conductor (small coordinator → Thinker/Worker/Verifier on resident workers). Future research challenge, gated by the LL12/LL19 eval harness on "beats the best currently validated single-model path including latency". |
| Local LLM | LL28 | done | M | LL1, LL8, LL3 | User-facing multi-participant group discussion: invite a second resident model (PC2) into the same thread as named participants with per-participant roles (facilitator / senior engineer / …), round-robin turn-taking when no facilitator is present, facilitator-managed handoff routing when one is present, and selectable single-round / multi-round depth, reusing the LL8 mesh endpoint resolver (health fallback) and the existing `ToolApprovalMode` (manual / auto / full) for read-only per-participant tools. The manually-driven, *visible* sibling of LL27 — user-judged, no eval gate; an auto-moderator turn policy is the bridge toward LL27. |
| Local LLM | LL29 | next | S-M | F2, LL23 | Tool-loop failure recovery (degrade, don't abort): replace the whole-turn halt on a twice-failing tool call with escalating in-loop recovery — inject an action-oriented, tool-specific hint into the failing tool result and keep iterating (warn), make the hard turn-halt an opt-in circuit breaker, and distinguish exact-arg repeats, same-tool repeats, and read-only no-progress. Hardens the existing `toolFailureCounts` path in `ChatNotifier`. Inspired by the Hermes/Nous agent `tool_guardrails.py`. |
| Local LLM | LL30 | next | M | LL14, LL6 | Compaction structural pre-pass: before summarization, run a no-LLM tool-result prune — dedupe identical tool outputs, replace old ones with informative one-line summaries that keep *what happened* (`[run_command] \`flutter test\` → exit 0, 47 lines`), truncate oversized tool-call arguments inside parsed JSON so the payload stays valid, and strip stale image payloads; switch the protected tail from a fixed message count to a token budget and add an anti-thrashing back-off. Extends LL14 with the Hermes `context_compressor._prune_old_tool_results` / `_summarize_tool_result` pattern. |
| Local LLM | LL31 | next | S-M | F2, LL23 | Turn-exit reason and completion explainer: tag every tool-loop exit with a structured reason (`text_response` / `max_iterations` / `guardrail_halt` / `empty` / `partial`), replace an empty or truncated final response with a single user-visible explanation derived from that reason, and log a WARNING when a turn ends on a pending tool result (the "just stops" case). Inspired by the Hermes `turn_finalizer.py`. |
| API | API1 | later | M | F3, LL20, LL23 | Responses-compatible Agent Event Core: normalize Chat Completions, Responses-style APIs, and local-provider extensions into one internal event stream. |
| API | API2 | later | M | API1, COMPAT1 | Chat/Responses/local-provider adapter matrix with provider-specific downgrade paths and deterministic fixtures. |
| Security | SEC1 | current | M | F2, LL2, LL18 | Local Agent Data Perimeter: classify data sources and tool capabilities before agent execution. |
| Security | SEC2 | current | M | SEC1, LL23 | Taint-aware tool execution: surface when untrusted evidence influences a privileged tool call. |
| Security | SEC3 | later | S-M | SEC1, MCP-GOV2 | MCP permission diff and audit view for server/tool changes. |
| Model Library | MLIB1 | later | M | LL3, LL9 | Local Model Pack Manifest: provenance, checksum, quantization, license, and verified capability metadata per local model artifact. |
| Model Library | MLIB2 | later | M | MLIB1 | Model provenance and license registry with revision history and local-only export boundaries. |
| Model Library | MLIB3 | later | S-M | MLIB1, LL12, LL19 | Verified capability/eval badges backed by probes and personal eval runs. |
| Observability | OBS1 | later | M | LL7, LL18, LL20 | Agent Trace Timeline: inspect model calls, tools, checkpoints, evals, slot assignment, and verifier evidence as one run trace. |
| Observability | OBS2 | later | S-M | OBS1, SEC1 | Redacted trace export for support reports without secrets or private project content by default. |
| Observability | OBS3 | later | M | OBS1 | Local OpenTelemetry-compatible span model for agent work, async links, and maintenance runs. |
| Compatibility | COMPAT1 | next | M | LL3, LL20 | OpenAI-compatible endpoint conformance suite for chat, streaming, tools, Responses-style APIs, embeddings, vision, lifecycle metadata, and provider extensions. |
| Compatibility | COMPAT2 | later | S | COMPAT1 | Provider compatibility badge surfaced in settings and diagnostics. |
| Compatibility | COMPAT3 | later | M | COMPAT1, API2 | Streaming/tool-call fuzz tests for local endpoints and weak-model recovery paths. |
| Hooks | HOOK1 | current | S-M | F2, LL2 | Caverno-owned external config plus basic lifecycle hook bridge for agent-kb and local automation. |
| Hooks | HOOK2 | later | M | HOOK1, OBS1 | Claude-like lifecycle hook flexibility: tool-event hooks, matchers, normalized payloads, and hook-result handling. |
| Hooks | HOOK3 | later | M-L | HOOK2, SEC1, OBS1 | Advanced hook runtime with trust review, richer handler types, async/batch hooks, and reactive lifecycle events. |
| Edge | EDGE1 | later | L | F3, LL1 | Embedded local runtime adapter for on-device micro-model execution. |
| Edge | EDGE2 | later | M | EDGE1, SEC1 | On-device micro-model tasks: routing, memory extraction, privacy screening, title/summary helpers, and prompt compression. |
| Edge | EDGE3 | later | S-M | EDGE1, API1 | Offline fallback mode for selected low-risk app features when no endpoint is reachable. |
| Mobile Eval | EVAL-MOBILE1 | later | M | LL11, LL19 | Flutter/mobile coding eval pack for widget fixes, build failures, permissions, localization, and platform-channel bugs. |
| Mobile Eval | EVAL-MOBILE2 | later | M | EVAL-MOBILE1, MM3 | Golden test and screenshot regression harness for visual/mobile UI changes. |
| Mobile Eval | EVAL-MOBILE3 | later | M | EVAL-MOBILE1 | Platform build failure corpus for Android Gradle, iOS signing, entitlements, and release build regressions. |
| Multimodal | MM1 | later | M | API1, OBS1, SEC1 | Multimodal Evidence Panel: manage screenshots, audio, OCR, and screen-recording-derived facts as citeable evidence objects. |
| Multimodal | MM2 | later | M | MM1, EVAL-MOBILE1 | Screenshot-to-issue workflow that turns UI evidence into reproduction steps and a coding task. |
| Multimodal | MM3 | later | M | MM1, EVAL-MOBILE2 | Visual regression explanation for before/after screenshots and golden diffs. |
| Multimodal | MM4 | later | S-M | MM1, EDGE2 | Voice-to-agent-task pipeline with transcript cleanup, intent extraction, and approval-aware task creation. |
| MCP Governance | MCP-GOV1 | later | M | SEC1, LL3 | MCP tool contract linter for schema clarity, dangerous capability detection, and weak-model tool-selection quality. |
| MCP Governance | MCP-GOV2 | later | M | MCP-GOV1, SEC1 | Tool trust registry with server trust levels, capability classes, and approval policy defaults. |
| MCP Governance | MCP-GOV3 | later | S-M | MCP-GOV1, LL3 | Model-specific tool prompt optimizer for compressing and specializing tool descriptions per model profile. |
| Skills | SKILL1 | done | S-M | F2 | In-chat skill authoring: a `save_skill` built-in tool persists a new or updated skill from the conversation behind a non-cacheable user approval. |
| Skills | SKILL2 | done | M | SKILL1 | Chat-driven skill lifecycle: a `/skill` command plus update-by-name and diff preview before save. |
| Skills | SKILL3 | later | M | SKILL1, LL18, OBS1 | Idle-time skill mining: distill recurring verified workflows from traces into proposed skills, user-reviewed before adoption. |
| Tools | TOOL0 | next | S | F4 | Product vocabulary and navigation: add the Tools workspace entry point without changing existing LLM tool-calling behavior. |
| Tools | TOOL1 | later | M | TOOL0 | Manifest schema, capability registry, policy engine, and validator for closed, versioned user-created Tools. |
| Tools | TOOL2 | later | M | TOOL1, F4 | Local repository, record store, indexes, assets, execution logs, and storage-safety rules. |
| Tools | TOOL3 | later | M | TOOL1, TOOL2 | Declarative runtime and read-only Flutter component renderer for saved Tool manifests. |
| Tools | TOOL4 | later | M | TOOL3, SEC1, SEC2 | Action runner with confirmation gates, provenance tracking, manual fallback, and scoped writes. |
| Tools | TOOL5 | later | S-M | TOOL3, TOOL4 | Receipt ledger MVP template using the same manifest runtime, storage, and permission gates as generated Tools. |
| Tools | TOOL6 | later | M | TOOL5, LL3, COMPAT1 | Natural-language Tool builder that emits reviewable manifest drafts from approved templates and vocabularies. |
| Tools | TOOL7 | later | S | TOOL0-TOOL6 | MVP release gate and store/privacy readiness for workspace switching, validation, persistence, rendering, confirmation, data-egress copy, and receipt-ledger behavior. |
| Routines | ROUTINE1 | next | M | F2, SKILL1 | In-chat scheduled-routine authoring: a `create_routine` built-in tool that schedules a recurring routine from the conversation behind a non-cacheable user approval. |
| Routines | ROUTINE2 | later | M | ROUTINE1 | Chat-driven routine lifecycle: list/update/enable/disable/delete from chat plus a near-duplicate-by-name guard. |
| Threat Posture | THREAT1 | later | M | F2, SEC1, SEC2 | Agent-as-malware-vector hardening: non-cacheable approval plus explicit resolved-command and destination-domain review for network-fetch-then-execute and persistence-write shapes in `local_shell`. |
| Threat Posture | THREAT2 | later | M | F2, SEC1 | Read-only host compromise triage: a fixed-command `host_security_snapshot` IoC collector, a routine allowlist entry, and an AMOS-style TTP triage prompt/mode. |
| Threat Posture | THREAT3 | later | L | THREAT2, LL10, LL18, LL5, SEC1 | Local threat-intelligence pre-learning: idle-orchestrated ingestion of CISA KEV / scoped NVD CVE feeds and malware advisories, map-reduced into a provenance-tracked local KB that feeds THREAT2 triage and installed-software vulnerability matching. |

Size legend: S = days, M = one to a few weeks of slices, L = multi-week.

## Phase Plan

Phases are orderings, not date commitments. Each milestone still follows the
operating loop in `docs/roadmap.md` (one atomic slice, focused tests, format,
analyze, smoke, conventional commit).

### Phase 0 — Stop the bleeding, win quickly (F1, LL1)

F1 freezes the growth of the god files so that every later phase gets cheaper
instead of more expensive. LL1 is the highest user-visible win per line of
code: secondary LLM calls (memory extraction, title generation, compaction
summaries, subagents) stop occupying the big model.

### Phase 1 — Unlock the architecture (F2, LL2)

F2 is the keystone refactor: the tool loop becomes a domain service with a
handler registry (the `chat_notifier_*_handlers.dart` part files are already
handler-shaped). LL6 and LL7 are blocked on it, and `RoutineToolRunner` /
`SubagentExecutionService` get to share the loop instead of duplicating it.
LL2 lands the safety net early so later, riskier agent behavior changes are
cheap to undo for users.

### Phase 2 — Platform currency and diagnosis (F3, LL3, LL9)

F3 starts with `openai_dart` 4.x → 6.x because the API client underpins LL3
(probing structured-output support) and LL6 (request shaping). Remaining major
upgrades (`serious_python` 2, `flutter_local_notifications` 22, `record` 7,
`network_info_plus` 8) follow as isolated slices. LL3 reuses
`live_llm_diagnostic_service` and the canary infrastructure to probe each
registered model: native tool calls vs embedded tags, `json_schema` / grammar
enforcement, edit-format success rates, usable context length. The stored
profile becomes the tuning input for LL4, LL6, LL7, and LL15. LL9 extends the
existing read-only LM Studio / llama.cpp catalog integration
(`model_remote_datasource.dart`) into management, sharing the
model-registration touchpoint with LL3 probing.

### Phase 3 — Capability and speed leap (LL4, LL6, LL14, LL15, LL16)

LL4 ships the repo map without waiting for embeddings: symbol outlines via
ctags / LSP `documentSymbol` / Dart analyzer, ranked and compressed to a
budgeted token size per the model profile. LL6 ships the prefix-stable mode:
stable tool list across loop iterations, append-only history, volatile context
moved to the message tail, with prefill latency measured before/after on a
30B-class local model. LL14 is designed together with LL6 because eviction and
prefix stability pull in opposite directions: stale-result eviction must land
only at compaction boundaries where the cache is already paid. LL15 follows
LL3 directly, turning probe findings into grammar-constrained edit blocks and
per-model few-shot exemplars. LL16 rides the same probe runs: temperature and
sampler candidates are scored alongside edit formats, and its layer-1
request-class temperature split can ship even earlier since it needs no
profile. Once LL15 grammar enforcement lands, temperature stops being a
correctness knob for tool calls and is tuned purely for exploration quality.

### Phase 4 — Storage, retrieval, and grounding (F4, then LL5, LL10, LL11)

F4 migrates conversations and chat memory from Hive (effectively unmaintained,
JSON-string blobs) to drift/SQLite with FTS5, shipping history full-text
search as the user-facing payoff. LL5 then stores embedding vectors in the
same database for fully local semantic code and history search. LL10 grounds
the model in the project's actually installed dependency versions, reusing the
F4 index for fast lookup. LL11 generalizes the Dart-only diagnostic loop to
any language with a language server and feeds richer symbols back into LL4.

### Phase 5 — Quality leap and scale-out (LL7, LL8, LL12, F5)

LL7 combines free local tokens with the existing verification loop: generate N
candidate patches, run verification on each, keep the first green one; expose
an overnight Routines preset that retries until tests pass within a bounded
budget. LL8 scales the same idea horizontally: the existing LAN scanner learns
to discover OpenAI-compatible endpoints, and role routing (LL1) plus Best-of-N
(LL7) spread across them. LL12 turns the canary infrastructure into a personal
eval suite that decides whether a newly downloaded model actually beats the
incumbent on the user's own recorded tasks. F5 continues large-file
decomposition as background slices, ratcheting F1 budgets down as files
shrink.

### Phase 6 — The agent farm (LL13, LL17)

LL13 runs multiple agent tasks in parallel, each isolated in its own git
worktree with its own checkpoint history (LL2), optionally executing on
different LL8 mesh endpoints. The shipped milestone keeps starts user-directed:
tasks can be queued, recovered, run from the sheet, or started immediately with
`/agent --run`, while broader unattended overnight agent-farm scheduling waits
for SEC1/OBS1 guardrails. LL17 is the other capstone, closing the loop the
profile thread opened: instead of hand-tuning harness behavior per model, the
app mines its own failure traces and adapts the per-model harness under the eval
regression gate. Following the
Self-Harness analysis, LL17 mutates the declared per-model harness config
(LL23) — instruction surfaces and runtime control policy, not just LL3 profile
fields — and gates adoption on an LL19 held-in/held-out eval split.

### Phase 7 — Idle-time autonomy (LL18-LL22)

This phase exists because Phases 2-6 built the measurement and self-improvement
pieces (LL3, LL12, LL15, LL16, LL17) but left them as islands with no scheduler:
probing is reactive, eval is offline-only, and nothing exploits the idle machine.
LL18 is the keystone — the idle/overnight orchestrator that finally runs that
machinery when the machine is free. LL19 moves the LL12 eval loop in-app so LL18
and LL17 can run it unattended. LL20 builds the slot-execution substrate LL7 and
LL13 need for concurrent local candidates. LL21 turns idle time into full
re-probing with profile history and a recovery path for runtime-lowered samplers.
LL22 spends idle cycles warming caches and precomputing the repo map/embeddings
so the first interactive turn each morning is instant. None of these add a token
cost; they convert otherwise wasted local compute into quality and speed.

### Phase 8 — Control-plane hardening (API, SEC, OBS, COMPAT, HOOK)

The LL track makes Caverno powerful; this phase makes that power durable and
reviewable. API1/API2 decouple the app from any one OpenAI-compatible endpoint
shape. SEC1-SEC3 define the local permission and data perimeter so retrieved
content, MCP resources, Remote Coding state, and memory writes do not collapse
into one undifferentiated prompt. OBS1-OBS3 make parallel candidates, overnight
maintenance, eval adoption, and worktree execution inspectable as a single trace.
COMPAT1-COMPAT3 turn endpoint variance into a visible compatibility result
instead of a support mystery. HOOK1-HOOK3 turn external automation from a
minimal agent-kb bridge into a reviewed lifecycle extension surface.

Recommended ordering: COMPAT1 can start early because it is mostly diagnostic;
API1 should land before any broad Responses-style API migration; SEC1 should
land before expanding automatic tool execution; OBS1 should land before
productizing broader unattended agent-farm scheduling. HOOK1 can land
independently, but HOOK2 should wait for enough trace visibility to debug
tool-event side effects, and HOOK3 should wait for SEC1 trust boundaries.
THREAT1 (agent-as-vector hardening) builds directly on the SEC1/SEC2 perimeter;
THREAT2 host triage can ship its read-only snapshot independently, but THREAT3
intel pre-learning waits for the LL18 idle orchestrator and the LL10
installed-dependency inventory.

### Phase 9 — Local model/library operations (MLIB, MCP-GOV)

Once users run many local models and MCP servers, Caverno needs an operations
layer. MLIB1-MLIB3 record where a model came from, what artifact is currently
loaded, which license and quantization assumptions apply, and which capabilities
were verified locally. MCP-GOV1-MCP-GOV3 keep tool descriptions, trust levels,
and model-specific tool prompts from becoming an unreviewed attack surface or a
weak-model quality sink.

Recommended ordering: MLIB1 pairs naturally with LL9 model management and LL21
profile history. MCP-GOV1 should precede SEC3 because permission diffs are only
useful when tool contracts have stable identities and capability classes.

### Phase 10 — Edge and multimodal product expansion (EDGE, EVAL-MOBILE, MM)

This phase moves Caverno beyond a localhost chat wrapper into a Flutter-native
local AI workbench. EDGE1-EDGE3 add embedded micro-model execution for offline
and low-risk helper tasks. EVAL-MOBILE1-EVAL-MOBILE3 make Caverno's own domain —
Flutter and mobile app development — the standard eval target. MM1-MM4 unify
screenshots, voice, OCR, and screen recordings as traceable evidence objects
that feed coding, debugging, and visual-regression workflows.

Recommended ordering: EVAL-MOBILE1 can start as data and fixtures before the
UI is ambitious. MM1 should precede screenshot-to-issue and visual-regression
features so multimodal artifacts inherit the same trace, redaction, and data
perimeter rules from OBS1 and SEC1.

### Phase 11 — In-chat capability authoring (SKILL, ROUTINE)

Caverno already lets the model *read* user skills mid-conversation: a
lightweight skills index is injected into the system prompt and a `load_skill`
tool pulls the full markdown on demand. SKILL1 completed the write-side inverse:
`save_skill` lets the agent distill the current conversation's workflow into
skill markdown and persist it through `SkillsNotifier.upsertMarkdown`, gated by
a non-cacheable user approval so a skill is never written silently. SKILL2 added
the chat-driven entrypoint (`/skill` and `save-skill`) and diff-before-save
updates for existing skills. SKILL3 remains the deferred idle-compute path:
mine recurring verified workflows from LL18/OBS1 traces into proposed skills the
user reviews before adoption.

Recommended ordering: SKILL1 and SKILL2 are complete. SKILL3 waits for the LL18
idle orchestrator and OBS1 traces so mined proposals are grounded in real run
evidence. SEC1 perimeter classification enriches all skill flows by flagging
skill content authored from untrusted evidence.

The ROUTINE milestones extend the same in-chat authoring idea from inert skill
markdown to *executable scheduled agents*. Today routines are created only
through the routine editor UI (`showRoutineEditor` → `RoutinesNotifier`
`.createRoutine`); the model cannot stand one up conversationally. ROUTINE1 adds
a `create_routine` tool that maps a natural-language request to the `Routine`
fields (name, prompt, `scheduleMode` interval/daily, `intervalValue` +
`intervalUnit`, `timeOfDayMinutes`, `toolsEnabled`, `completionAction`,
`notifyOnCompletion`, workspace flags) and persists through `createRoutine`,
with `RoutineScheduleService` normalizing the schedule and the scheduler picking
up the new `nextRunAt`. ROUTINE2 adds chat-driven list/update/enable/disable/
delete and a near-duplicate-by-name guard.

Because a routine is an autonomous, recurring, unattended run — a higher-risk
write than a skill — ROUTINE1 reuses the SKILL1 non-cacheable approval but its
preview must surface the schedule and next run, whether tools/workspace writes
are enabled, and any external delivery (`completionAction: googleChat`). This
stays inside the existing per-routine approval trust model (the editor UI
already permits it); it does not open unattended agent-farm scheduling, which
still waits on SEC1/OBS1.

### Phase 12 — User-created local apps (TOOL)

The Tools track turns natural-language app requests into local-first mini
applications inside Caverno. It deliberately starts with a Caverno-owned
manifest runtime instead of arbitrary generated Flutter or script code: screens,
data collections, actions, capabilities, permissions, provenance, and resource
limits are reviewable data, while the app owns storage, rendering, action
execution, and confirmation gates. The MVP target is a receipt ledger Tool that
exercises camera capture, on-device OCR, explicitly disclosed remote LLM parsing,
local records, dashboard rendering, and deletion/storage safety without letting
OCR or model output write records before user review.

Recommended ordering: TOOL0 should land first as navigation and product
vocabulary only. TOOL1-TOOL4 build the manifest, capability registry, policy
engine, persistence, storage-safety, renderer, action-runner, provenance, and
confirmation foundation. TOOL5 proves that foundation with a receipt-ledger
template. TOOL6 adds natural-language generation only after approved templates,
component vocabularies, and validators can reject unsafe manifests. TOOL7 is the
limited-use release gate plus store/privacy readiness. The detailed MVP plan
lives in `docs/tools_mvp_roadmap.md`.

## Milestone Notes

### F1: Line-Count Ratchet Gate

Scope:
- A focused test asserts line-count budgets for the current oversized files:
  `chat_notifier.dart`, `chat_page.dart`, `mcp_tool_service.dart`,
  `computer_use_settings_page.dart`, `computer_use_debug_page.dart`,
  `network_tools.dart`, and `chat_notifier_test.dart`.
- Budgets start at current counts rounded up slightly; shrinking a file lowers
  its budget in the same PR.

Acceptance criteria:
- CI fails when a budgeted file grows past its budget.
- The failure message names the file, the budget, and the refactor plan doc.

Status: `done`

Evidence:
- `test/quality/file_size_ratchet_test.dart`
- CI runs the full suite via `tool/codex_verify.sh` (`flutter test --coverage`
  with no targets), so the ratchet is enforced on every PR.

### F2: Tool Loop Extraction

Status: `done`

Scope:
- Extract tool-call dispatch and loop orchestration from `ChatNotifier` into a
  set of domain services with a tool-handler registry interface. `ChatNotifier`
  remains the UI/state adapter for streaming, message mutation, approval
  surfaces, and repair prompts.
- Convert the handler registry assembly into handler-module classes backed by
  the existing `chat_notifier_*_handlers.dart` implementations; preserve
  provider names and tool names/JSON shapes.
- Reuse the extracted loop from `RoutineToolRunner` and
  `SubagentExecutionService` where semantics already match.

Acceptance criteria:
- `chat_notifier.dart` drops materially below its F1 budget.
- Existing chat notifier, workflow proposal, and Plan Mode smoke tests pass
  without fixture rewrites.
- High-risk tool approval still routes through the same user approval gate.

Evidence:
- `lib/features/chat/domain/services/chat_tool_dispatcher.dart`
- `lib/features/chat/domain/services/planning_tool_policy.dart`
- `lib/features/chat/domain/services/tool_call_batch_executor.dart`
- `lib/features/chat/domain/services/tool_call_execution_policy.dart`
- `lib/features/chat/domain/services/tool_loop_recovery_policy.dart`
- `lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart`
- `lib/features/routines/data/routine_tool_runner.dart`
- `lib/features/chat/domain/services/subagent_execution_service.dart`
- `test/features/chat/domain/services/chat_tool_dispatcher_test.dart`
- `test/features/chat/domain/services/planning_tool_policy_test.dart`
- `test/features/chat/domain/services/tool_call_batch_executor_test.dart`
- `test/features/chat/domain/services/tool_call_execution_policy_test.dart`
- `test/features/chat/domain/services/tool_loop_recovery_policy_test.dart`
- `test/features/routines/data/routine_execution_service_test.dart`
- `chat_notifier.dart` is ratcheted down to 15,500 lines.
- Focused chat notifier, routine, subagent, dispatcher, policy, and ratchet
  tests pass; generated-file checks and focused suites pass through
  `tool/codex_verify.sh`.

### F3: Major Dependency Currency

Status: `done`

Scope:
- Upgrade `openai_dart` from 4.x to 6.x first because Chat Completions request
  shaping, structured-output probing, and future Responses API surfaces depend
  on the API client baseline.
- Keep each remaining major dependency upgrade in an isolated slice with
  focused tests for the affected integration boundary.

Acceptance criteria:
- `openai_dart` is locked to the current 6.x line without Chat Completions
  analyzer regressions.
- Existing chat datasource, session logging, Plan Mode scenario spec, chat
  notifier, and ratchet tests pass after the upgrade.
- Remaining major upgrades are tracked as follow-up slices rather than mixed
  into the API client upgrade.

Current evidence:
- `pubspec.yaml` depends on `openai_dart: ^6.2.0`.
- `pubspec.lock` locks `openai_dart` to 6.2.0.
- `test/features/chat/data/datasources/chat_remote_datasource_test.dart`
- `test/features/chat/data/datasources/session_logging_chat_datasource_test.dart`
- `test/integration/plan_mode_scenario_spec_test.dart`
- `test/features/chat/presentation/providers/chat_notifier_test.dart`
- `test/quality/file_size_ratchet_test.dart`
- `fvm flutter analyze` passes with the upgraded client.

### F4: Hive To Drift Migration With FTS Search

Status: `done`

Scope:
- Migrate conversations and chat memory from Hive (JSON-string blobs) to
  drift/SQLite, shipping conversation history full-text search (FTS5) as the
  user-facing payoff.

Acceptance criteria:
- Conversations and chat memory persist to SQLite and survive a one-time,
  idempotent migration from the existing Hive boxes (no data loss; safe to
  retry).
- History full-text search returns relevant past conversations.
- A drift failure degrades to the existing Hive behavior.

Implementation evidence:
- `AppDatabase` (`app_database.dart`): drift database with `conversations`
  (JSON payload + denormalized title/timestamps) and `chat_memory_entries`
  (key/value) tables, plus an FTS5 `conversation_search` virtual table.
  Schema v2 migration creates FTS on create and, on v1->v2 upgrade, creates and
  backfills it. `openAppDatabase` opens a file in the app support directory.
- Stores: `DriftConversationRepository` (lossless JSON round trip, FTS sync on
  save/delete, FTS5-ranked `search`) and `DriftChatMemoryStore` (KV).
- Interfaces/adapters: `ConversationStore` / `ConversationRepositoryApi` and the
  `KeyValueStore` seam; `CachedDriftConversationRepository` and
  `CachedDriftKeyValueStore` keep the synchronous read APIs via in-memory caches
  hydrated from SQLite, writing through to drift. The Hive repositories
  implement the same interfaces as the fallback.
- Migrations: `ConversationMigrationService` and `ChatMemoryMigrationService`
  import the legacy Hive data once, gated by SharedPreferences markers set only
  after success (interrupted runs retry; upsert prevents duplicates).
- Bootstrap: `main.dart._initDriftStorage` opens drift, runs both migrations,
  and overrides the providers with drift-backed repositories; any failure
  degrades to Hive.
- UI: a "Search history" entry in the conversation drawer opens a
  `ConversationSearchDelegate` over `ConversationRepositoryApi.search`.

Verification:
- `test/features/chat/data/repositories/` drift store, migration, cached
  repository, KV store, and FTS `conversation_search` tests (incl. the v1->v2
  backfill path); existing drawer/notifier/mcp suites stay green; `flutter
  analyze` clean for F4 code.
- Live: conversations load from SQLite in chat and coding modes, and the search
  UI returns results (manually verified).

Deferred follow-up:
- Retire the Hive boxes for migrated data once drift has been confirmed across a
  release; Hive is retained as the migration source and runtime fallback until
  then.
- LL5 stores embedding vectors in this same drift database.

### F6: Built-In Tool Initial-Load Classification Guard

Status: `done`

Context:
- In the default mode (prefix-stable tool loop off), `ToolDefinitionSearchService`
  sends only an initial subset of tools plus `tool_search`; the subset is the
  hand-maintained `_alwaysLoadedToolNames` set (`_shouldLoadInitially`).
- That set must stay in sync with the built-in catalog
  (`BuiltInToolInfo`, ~104 tools). Nothing enforces the sync, so a new built-in
  tool is silently reachable only via `tool_search` until someone notices.
- Confirmed misses: `save_skill` (SKILL1; fixed) and `resolve_installed_dependency`
  (LL10) were never added to the initial set. The model never sees them and has
  no signal to search for them, so the feature is effectively unreachable in the
  default mode. The `http_post/put/patch/delete` deferral, by contrast, is a
  deliberate read-verbs-loaded / write-verbs-deferred choice.

Scope:
- Add a CI-enforced exhaustiveness test: every `BuiltInToolInfo` name must be
  explicitly classified as initial-load or intentionally deferred. An
  unclassified built-in tool fails the test (the same shape as the F1 ratchet).
- Introduce an explicit deferred set so deliberate deferral
  (e.g. mutating HTTP verbs, heavy `run_python_script`) is distinguishable from
  an accidental omission.
- Optional follow-up: drive the initial-load decision from `BuiltInToolInfo`
  category/`deferred` metadata so the duplicate `_alwaysLoadedToolNames` list is
  removed and new built-in tools default to the safe (initial-load) direction.

Acceptance criteria:
- A new built-in tool added to `BuiltInToolInfo` without an initial/deferred
  classification fails CI with an actionable message.
- `save_skill` and `resolve_installed_dependency` are classified initial-load;
  the deliberate `http_*` write-verb deferral is recorded as intentional.
- No change to the deferred remote/MCP long-tail behavior or the weak-model
  tool-count reduction goal of the dynamic tool-search mode.

Evidence:
- `ToolDefinitionSearchService.shouldLoadInitially` is public, and
  `resolve_installed_dependency` is restored to the initial set.
- `test/features/chat/domain/services/tool_definition_search_service_test.dart`
  adds the "built-in tool initial-load classification (F6)" group: every
  `BuiltInToolRegistry.tools` entry must be initial-loaded or in the deferred
  categories (`computer_use`/`browser`/`ssh`/`serial`/`ble`/`system`) or
  deferred names (`http_post`/`put`/`patch`/`delete`, `run_python_script`), with
  positive assertions for `save_skill` and `resolve_installed_dependency`,
  non-registry forced tools, deferred tools, and unknown remote/MCP tools.
- Focused test, `system_prompt_builder`, `tools_settings_page`, and
  `chat_notifier` suites plus `flutter analyze` pass.

Follow-up (done): metadata-driven initial load.
- The deferral metadata is now owned by `BuiltInToolRegistry`
  (`toolSearchDeferredCategories`, `toolSearchDeferredToolNames`,
  `toolSearchInitialToolNames`). `ToolDefinitionSearchService.shouldLoadInitially`
  derives the registry portion from it, so a new registry tool defaults to the
  safe initial-load direction unless explicitly deferred. The hand-maintained
  `_alwaysLoadedToolNames` allowlist (60 names) is removed.
- It is a hybrid, not a full single-source: `BuiltInToolRegistry` is the
  settings-UI catalog, not the complete built-in universe. 18 non-registry
  built-ins (the `tool_search` meta tool, `search_web`/`news`/`images`,
  `searxng_web_search`, `process_*`, and network-health diagnostics) remain in a
  small explicit `_forcedInitialNonRegistryToolNames` set. The refactor is
  behavior-preserving (initial set unchanged) and verified by the guard plus
  non-registry/deferred/remote assertions.
- Remaining option: fold those 18 into `BuiltInToolRegistry` for a true single
  source (adds settings-UI toggles), and broaden MCP-GOV1's linter to the
  built-in catalog.

### LL1: Per-Role Model Routing

Scope:
- `AppSettings` gains optional role→model assignments for the four secondary
  LLM call sites that actually exist: memory extraction, subagent execution,
  goal suggestions, and tool approval auto-review. Default remains the main
  model. (Title generation and compaction summaries turned out to be
  rule-based with no LLM call, so they have no role.)
- Settings UI exposes the assignments with the existing model catalog.

Acceptance criteria:
- Each secondary call site resolves its role model with fallback to main.
- Settings round-trip and chat notifier memory tests cover the routing.

Status: `done`

Evidence:
- `lib/features/settings/domain/entities/app_settings.dart` (role fields and
  `effective*Model` resolution, ignored for the Apple Foundation Models
  provider)
- `lib/features/settings/presentation/pages/model_routing_settings_page.dart`
- Call sites: `_extractMemoryDraftWithLlm`, `suggestCurrentGoal`,
  `_runApprovalAutoReview` in `chat_notifier.dart`, and the subagent run in
  `chat_notifier_subagent_handlers.dart`
- `test/features/settings/domain/entities/app_settings_test.dart`
- `test/features/settings/presentation/providers/settings_notifier_test.dart`
- `test/features/settings/presentation/pages/model_routing_settings_page_test.dart`
- `fvm flutter analyze`; settings suite and chat notifier suites pass.

### LL2: Whole-Turn Checkpoints

Status: `done`

Scope:
- Record a shadow checkpoint (per-session ref or stash-like snapshot) of files
  the agent modified during a turn, building on the bookkeeping behind
  `rollback_last_file_change`.
- UI affordance to revert the last agent turn's file changes.

Acceptance criteria:
- A multi-file agent turn can be reverted in one action.
- Reverting never touches files the agent did not modify.

Evidence:
- `lib/features/chat/data/datasources/file_rollback_checkpoint_store.dart`
- `lib/features/chat/presentation/pages/chat_page_turn_rollback_support.dart`
- `lib/features/chat/presentation/pages/chat_page_header_builders.dart`
- `lib/features/chat/presentation/providers/chat_notifier_turn_rollback_handlers.dart`
- `test/features/chat/data/datasources/file_rollback_checkpoint_store_test.dart`
  covers untouched-file safety, repeated edits to the same file, individual
  rollback stack eviction, turn checkpoint retention, active turn switching,
  and failed rollback retry.
- `test/features/chat/data/datasources/mcp_tool_service_test.dart`
- `test/features/chat/presentation/pages/chat_page_companion_panel_test.dart`
- `test/features/chat/presentation/providers/chat_notifier_turn_rollback_part.dart`
- `fvm flutter analyze`; focused LL2 and file-size ratchet tests pass through
  `tool/codex_verify.sh`.

### LL3: Model Capability Profiles

Status: `done`

Scope:
- On model registration (and on demand), run a bounded probe suite: native
  tool calls vs `<tool_call>` tags, `response_format: json_schema` / grammar
  support, edit-format success (whole-file vs search-replace vs diff), usable
  context estimate.
- Persist a per-model profile; agent behavior (tool-call style, edit format,
  context budget) reads the profile with safe defaults when absent.

Implementation evidence:
- `AppSettings` persists per-model `ModelCapabilityProfile` values with safe
  unknown enum fallbacks and an effective profile lookup for the active model.
- `SettingsNotifier` can upsert and remove stored profiles through the existing
  settings repository.
- `ModelCapabilityProfileBuilder` converts bounded live diagnostic reports into
  normalized profile records.
- `LiveLlmDiagnosticNotifier` stores an updated profile after a successful
  on-demand diagnostic run.
- `ModelCapabilityAutoProbeNotifier` runs the bounded LL3 probe subset for
  newly selected models, skips already-profiled models, and persists the
  resulting profile.
- `SystemPromptBuilder` reads the active profile and injects model-specific
  guidance for tool-call style, structured output, edit format, and usable
  context.
- `tool/canaries/chat_live_llm_canary_test.dart` can inject a test profile from
  `CAVERNO_LLM_MODEL_TOOL_CALL_STYLE`,
  `CAVERNO_LLM_MODEL_STRUCTURED_OUTPUT`, `CAVERNO_LLM_MODEL_EDIT_FORMAT`, and
  `CAVERNO_LLM_MODEL_USABLE_CONTEXT_TOKENS` for before/after live canary
  comparisons.

Verification:
- `test/features/settings/domain/entities/app_settings_test.dart`
- `test/features/settings/domain/services/model_capability_profile_builder_test.dart`
- `test/features/settings/domain/services/live_llm_diagnostic_service_test.dart`
- `test/features/settings/presentation/providers/model_capability_auto_probe_notifier_test.dart`
- `test/features/settings/presentation/providers/settings_notifier_test.dart`
- `test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart`
- `test/features/chat/domain/services/system_prompt_builder_test.dart`
- `tool/canaries/chat_live_llm_canary_test.dart` (compile/skip check without
  live env)

Acceptance criteria:
- Probes are non-destructive, bounded in time, and skippable.
- A weak-model profile measurably reduces malformed tool calls in the
  existing live canary suite.

Live canary evidence:
- Baseline weak-model run:
  `build/integration_test_reports/chat_live_llm_canary_ll3_baseline_1781232440/canary_summary.json`
  against `qwen3.6-27b-mtp-vision` failed with 10/11 tests passing, one blocker
  failure, `transportDisconnectCount=1`, `incompleteContentToolRecoveryCount=1`,
  and `ignoredAssistantToolResultCount=2`.
- Textual-tag profile run:
  `build/integration_test_reports/chat_live_llm_canary_ll3_profiled_1781232505/canary_summary.json`
  improved main readiness from `inconclusive` to `usable_with_warnings`, removed
  the blocker failure, and cleared `transportDisconnectCount`, but still had one
  warning failure.
- Native-tool profile run:
  `build/integration_test_reports/chat_live_llm_canary_ll3_native_profiled_1781232567/canary_summary.json`
  passed 11/11 with main readiness `ready`, zero blocker or warning failures,
  and `transportDisconnectCount=0`.
- `incompleteContentToolRecoveryCount=1` and
  `ignoredAssistantToolResultCount=2` remained unchanged because the existing
  chat canary intentionally exercises those recovery paths. No
  `assistantAuthoredToolBlockCount` was observed in either baseline or profiled
  runs.

### LL4: Repo Map v1

Status: `done`

Scope:
- Symbol outline per coding project via ctags / LSP `documentSymbol` / Dart
  analyzer, refreshed incrementally.
- Ranked compression to a token budget from the model profile; injected into
  the system prompt for coding mode.

Implementation evidence:
- `RepoMapService` builds a bounded repository map from the active coding
  project root, skips generated and transient directories, extracts compact Dart
  symbol outlines, and trims output to the active model context profile.
- `SystemPromptBuilder` injects the map as a read-only `<repo_map>` orientation
  block in coding and plan modes, with explicit guidance to verify file
  contents before editing.
- `ChatNotifierPromptContext` wires the active project and effective model
  profile into the prompt without growing the `ChatNotifier` line-count
  ratchet.

Verification:
- `test/features/chat/domain/services/repo_map_service_test.dart`
- `test/features/chat/domain/services/system_prompt_builder_test.dart`
- `test/quality/file_size_ratchet_test.dart`
- `tool/codex_verify.sh`

Live canary evidence:
- Baseline live edit run without repo map:
  `/tmp/ll4_repo_map_measurement/baseline/coding_goal_live_edit_canary_1781325422/canary_summary.json`
  against `qwen3.6-27b-mtp-vision` passed 3/6 tests, had 3 blocker
  failures, took 113,094 ms, and used 56 total tool calls.
- Repo map run:
  `/tmp/ll4_repo_map_measurement/current/coding_goal_live_edit_canary_1781325566/canary_summary.json`
  passed 5/6 tests, reduced blocker failures to 1, took 56,739 ms, and used 29
  total tool calls.
- Post-fix repo map run:
  `/tmp/ll4_repo_map_measurement/recovery3/coding_goal_live_edit_canary_1781327553/canary_summary.json`
  passed 6/6 tests, had 0 blocker failures, took 78,696 ms, used 44 total tool
  calls, and reported main readiness `ready`.
- Parsed tool-call logs show exploration calls before first mutation dropped
  from 10 to 8 overall and from 4 to 2 in the direct first-edit case. Average
  first mutation index improved from 3.00 to 2.67.
- Full measurement notes are in
  `docs/ll4_repo_map_live_measurement_2026-06-13.md`.
- The post-fix run also validates the git lifecycle recovery path: duplicate
  successful command calls recover to the next step, benign completion summaries
  containing `remaining arguments` still close the goal, and extra follow-up
  tools are ignored once the git lifecycle has clean final status evidence.

Acceptance criteria:
- Map generation is incremental and bounded on large repos.
- Live coding canaries show fewer exploration tool calls to reach a correct
  first file edit.

### LL5: Local Semantic Search

Status: `done` (conversation history search; semantic *code* search deferred).

Scope (delivered):
- Embed conversation history via the configured OpenAI-compatible
  `/v1/embeddings` endpoint; store vectors in the drift database from F4.
- Wire the history search UI to rank by embedding similarity, and make the
  `search_past_conversations` built-in tool semantic-aware.
- Settings expose an enable toggle and an embeddings-model picker populated
  from the endpoint's `/v1/models` list.

Acceptance criteria (met):
- Works fully offline against LM Studio / llama.cpp embeddings endpoints.
- Degrades gracefully (lexical FTS only) when no embeddings endpoint exists.

Implementation slices:
- `EmbeddingsClient` (raw-HTTP `POST /v1/embeddings`) + `EmbeddingsMath`
  cosine similarity.
- Drift `Embeddings` table (schema v3) + `DriftEmbeddingStore` (brute-force
  cosine vector store), `ConversationChunker`, `SemanticIndexingService`, and
  `SemanticSearchService` (semantic with lexical FTS fallback).
- `enableSemanticSearch` + `embeddingsModel` settings, Riverpod provider
  composition, index-on-save hook in `ConversationsNotifier`, hybrid drawer
  history search, and `ConversationSearchTool` (extracted from
  `McpToolService` to stay within the F1 line budget).

Deferred follow-up:
- Semantic *code* search (embedding workspace files) — see the cost/benefit
  notes; lexical search-strengthening (ripgrep/symbol search) is the
  recommended cheaper alternative.
- Optional rerank stage via llama.cpp `POST /reranking` (reranker model with
  `--pooling rank`) when the endpoint advertises it.
- An ANN vector index (e.g. `sqlite-vec`) if the brute-force store ever needs
  to scale beyond conversation history.
- A separate embeddings base-URL/key (today embeddings reuse the chat
  endpoint), to support a dedicated single-model llama.cpp embeddings server.

### LL6: KV-Cache-Friendly Mode

Status: `done`

Scope:
- Optional request mode: byte-stable system prompt and tool list across loop
  iterations, append-only message history, volatile context (temporal,
  memory) moved to the tail.
- On llama.cpp endpoints, pin the conversation to a server slot via the
  per-request `id_slot` parameter and recommend `--cache-reuse N` (chunked KV
  reuse via shifting) so small mid-prompt changes still reuse cache.
- Measure cache effectiveness directly from response `timings` fields
  (`cache_n`, `prompt_n`, `prompt_ms`) instead of wall-clock estimates; show
  prefill progress in the UI via `return_progress` during long prompts.

Initial implementation slice:
- `ChatRequestPrefixStabilityService` builds a canonical prompt-prefix JSON
  from the stable leading messages and tool definitions, normalizing nested
  JSON map key order so request-construction tests can compare prefixes
  deterministically.
- `ChatRemoteDataSource` exposes the same prefix construction behind
  `visibleForTesting` helpers, giving the LL6 mode a focused regression target
  before the runtime setting and llama.cpp timing instrumentation land.
- A focused `ChatNotifier` tool-loop test now verifies that the initial
  tool-aware request and the first tool-result follow-up share the same
  canonical prompt prefix when the stable leading messages and tools match.
- The optional prefix-stable tool-loop setting is persisted in `AppSettings`
  and exposed in General Settings. When enabled, chat tool loops send one fixed
  full tool list from the first request through follow-up requests; the existing
  dynamic tool-search selection remains the default when the setting is off.
- `tool/ll6_prefix_stability_measurement.dart` measures llama.cpp-compatible
  `timings.cache_n`, `prompt_n`, and `prompt_ms` with raw HTTP so provider
  extension fields are preserved even when the typed OpenAI SDK omits them.
- Live LAN evidence on 2026-06-14 with
  `gemma-4-26B-A4B-it-Q4_K_M.gguf` showed default follow-up
  `cache_n=0, prompt_n=374, prompt_ms=255.571`, while prefix-stable follow-up
  produced `cache_n=2279, prompt_n=88, prompt_ms=128.025` with a 96.3% cached
  prompt share. See `docs/ll6_prefix_stability_live_measurement_2026-06-14.md`.

Deferred follow-up:
- Runtime `id_slot` pinning in the app transport remains an LL6 extension or
  LL7 slot-isolation slice because `openai_dart` does not currently preserve
  provider-specific request and response extension fields.
- `return_progress` prefill UI remains grouped with LL14 context surgery, where
  long-prompt progress and context compaction boundaries can be designed
  together.

Acceptance criteria:
- Prompt prefix is byte-identical across consecutive turn requests in the
  mode, verified by a focused test on request construction.
- `timings.cache_n / prompt_n` ratio improves measurably versus the default
  mode on a 30B-class local model, recorded as evidence.
- Existing first-request search-tool gating remains available as the default
  mode.

### LL7: Best-of-N Verification Loop

Status: `done`

Scope:
- Generate N candidate patches (sequential or parallel per endpoint slots),
  apply each in an isolated checkpoint (LL2), run
  `coding_verification_feedback_service` verification, keep the first green.
- On llama.cpp, candidates can run concurrently on one machine via server
  slots (`--parallel N` with continuous batching), each isolated with its own
  `id_slot`; `GET /slots` provides progress monitoring.
- Routines preset for bounded overnight retry-until-green runs with a final
  report.

Acceptance criteria:
- Failed candidates leave no residue in the working tree.
- Overnight runs respect tool policy, never require interactive approval, and
  end with a single consolidated report.

Implementation evidence:
- Policy: `BestOfNCoordinator` (`best_of_n_coordinator.dart`) runs up to N
  candidates through an injected `BestOfNRunner`, keeps the first that verifies
  green, and discards every non-winner — including generation/verification
  failures — so the tree never accumulates residue (acceptance #1, by
  construction). A discard that itself fails is surfaced as
  `BestOfNReport.hasResidueRisk`, never hidden.
- Checkpoint + verification: `CheckpointVerificationBestOfNRunner`
  (`best_of_n_runner.dart`) brackets each candidate in its own named LL2
  file-turn checkpoint and discards non-winners with a turn-id-scoped rollback
  (only reverts when the latest checkpoint is this candidate's), so a no-edit
  candidate never reverts an unrelated/user checkpoint and a mid-edit throw is
  still undone (`finally`-finalized). `CodingFeedbackBestOfNVerifier` wraps
  `CodingVerificationFeedbackService` and maps a snapshot to green only when it
  ran and passed (`unknown`/no test target is not green).
- Generation: `AgentBestOfNGenerator` (`agent_best_of_n_generator.dart`)
  produces the `BestOfNGenerationStep` by running one non-interactive agent
  attempt per candidate (caller adapts `RoutineToolRunner.execute` under the
  RoutineToolPolicy trust model — no approval prompts) and reporting the files
  `GitChangedPathsService` (`git_changed_paths_service.dart`) says changed.
- Overnight loop: `RetryUntilGreenCoordinator`
  (`retry_until_green_coordinator.dart`) repeats Best-of-N rounds until green or
  a bounded budget (round count + optional wall-clock deadline) is exhausted,
  emitting one consolidated `RetryUntilGreenReport` (acceptance #2: bounded,
  non-interactive, single report).

Verification:
- `test/features/chat/domain/services/best_of_n_coordinator_test.dart`
- `test/features/chat/data/datasources/best_of_n_runner_test.dart`
  (real on-disk checkpoint rollback restore; no-edit candidate safety; full
  coordinator run leaving only the winner's edit)
- `test/features/chat/data/datasources/agent_best_of_n_generator_test.dart`
- `test/features/chat/data/datasources/git_changed_paths_service_test.dart`
- `test/features/chat/domain/services/retry_until_green_coordinator_test.dart`

Deferred follow-up:
- A one-tap Routines UI preset (a saved Routine entity that launches the
  retry-until-green run) is additive: the substrate (coordinator + report +
  non-interactive generation through the existing RoutineToolRunner) is
  complete, so the remaining work is wiring it into the Routine entity/scheduler
  and surfacing the consolidated report through `RoutineCompletionActionService`.
- Parallel candidate generation across LL20 slots needs isolated git worktrees
  (LL13); v1 applies candidates sequentially with checkpoint/revert.

### LL8: LAN Inference Mesh

Status: `done` (secondary-call routing; main-conversation fan-out deferred).

Scope (delivered):
- `LanEndpointDiscovery` probes candidate hosts for OpenAI-compatible endpoints
  (LM Studio 1234, Ollama 11434, llama.cpp 8080, 8000, 5000) via an
  unauthenticated `GET /v1/models`; the mesh settings page offers one-tap
  registration as named endpoints.
- Role routing (LL1) gains an endpoint dimension: memory extraction, subagent,
  goal suggestion, and approval auto-review each map to endpoint + model.
  `EndpointHealthTracker` demotes unreachable endpoints and `MeshEndpointRouter`
  falls back to the primary, with a primary-valid fallback model.

Acceptance criteria (met):
- Discovery never sends credentials to unverified hosts; registration is
  explicit and user-confirmed.
- A dropped mesh endpoint degrades to the primary endpoint without failing
  the active turn (device-verified: a downed endpoint fell back to the primary
  with the main model and the secondary call still succeeded).

Implementation slices:
- `LanEndpointDiscovery` (unauthenticated `/v1/models` probe, batched).
- `NamedEndpoint` entity + `namedEndpoints` persistence + upsert/remove.
- Pure `MeshEndpointRouter` + `EndpointHealthTracker` (resolve + demotion).
- Provider composition + `MeshDiscoveryNotifier` (LAN sweep + verify).
- Mesh settings UI (scan/register/manage) + per-role endpoint dropdowns.
- `MeshSecondaryCompletionRunner` wired into the four secondary calls, with a
  primary-valid fallback model on demotion or mid-call failure.

Deferred follow-up:
- Fan out the main conversation across endpoints; the Best-of-N-candidates half
  is concretized as LL26 (parallel selection across the mesh).
- Task-based primary-model selection by mode/difficulty is tracked separately as
  LL24 (explicit mode routing) and LL25 (auto difficulty / cascade escalation).
- A periodic background health-check loop (today health is recorded from actual
  call outcomes, demoting after consecutive failures).

### LL9: Local Stack Manager

Scope:
- Extend the read-only LM Studio / llama.cpp catalog integration into
  lifecycle management where the server exposes it: LM Studio REST
  load/unload and JIT, Ollama pull/list/show, and llama.cpp router mode
  (`GET /models` with loaded/loading/unloaded status, `POST /models/load`,
  `POST /models/unload`, LRU eviction via `--models-max`, per-model presets
  via `--models-preset`).
- On llama.cpp router endpoints, per-role models (LL1) need no management at
  all: each role selects its model via the request `model` field and the
  router autoloads on demand.
- Recommend free speedups where supported: ngram speculative decoding
  (`--spec-type ngram-simple`, no draft model required) and draft-model
  speculation for coding models.
- Detect host resources (RAM, Apple Silicon unified memory) and recommend
  model + quantization + context length combinations that fit, including
  per-role suggestions for LL1 (small fast model for memory/titles).
- One-tap "prepare role models": ensure every assigned role model is loaded
  before an agent run starts.

Acceptance criteria:
- Management actions are no-ops with clear messaging on servers that do not
  support them.
- Recommendations never exceed detected memory and state their assumptions.

Implementation status:
- First slice started the llama.cpp router lifecycle data layer: native-root
  `GET /models` parsing, model status capture, and `POST /models/load` /
  `POST /models/unload` action results that degrade to clear unsupported
  messages on non-router endpoints. Settings UI, role-model prepare, and host
  resource recommendations remain follow-up slices.
- Settings UI follow-up started `Advanced > Local Stack`, showing primary
  endpoint managed-model status with load/unload controls and refresh. Role
  model prepare, endpoint selection, and host resource recommendations remain
  follow-up slices.
- Role-model prepare follow-up started a primary-endpoint-only button that
  loads explicit LL1 role assignments reported as unloaded by the router
  catalog, while skipping already-ready, in-progress, missing, and mesh-routed
  models. Endpoint selection and host resource recommendations remain follow-up
  slices.
- Endpoint selection follow-up expanded Local Stack from primary-only to the
  primary endpoint plus registered LL8 named endpoints, and prepares role
  models assigned to the selected endpoint. Host resource recommendations
  remain a follow-up slice.
- Host resource guidance follow-up added macOS `sysctl` memory detection,
  Apple Silicon unified-memory labeling, and conservative per-model fit
  guidance in `Advanced > Local Stack`. Estimates parse model size and
  quantization hints from router catalog ids, paths, and launch arguments, keep
  a 70% safe memory budget, and mark unknowns rather than recommending models
  whose assumptions are incomplete.
- Speedup guidance follow-up added `Advanced > Local Stack` recommendations
  for llama.cpp `--spec-type ngram-simple` and draft-model speculation for the
  selected coding/subagent model. The guidance detects already configured
  ngram or draft flags from router command arguments and only names a draft
  candidate when the catalog exposes an obviously smaller or draft-labeled
  model.
- Per-role suggestion follow-up added `Advanced > Local Stack` guidance that
  notices LL1 roles falling back to large main models or explicit oversized
  assignments, then recommends only smaller catalog models that already fit the
  detected safe memory budget. Embedding, rerank, and draft-only models are not
  proposed as full role models.
- Lifecycle adapter abstraction follow-up moved Local Stack callers to
  provider-neutral managed-model APIs while keeping the existing llama.cpp
  router implementation as the first backend. This prepares LM Studio and
  Ollama lifecycle adapters without changing current router behavior.
- LM Studio lifecycle follow-up added native v1 REST support for
  `/api/v1/models`, `/api/v1/models/load`, and `/api/v1/models/unload` as the
  first provider-neutral fallback after llama.cpp router probing. LM Studio
  model metadata feeds resource recommendations through non-UI metadata hints.
- Ollama lifecycle follow-up added native `/api/tags`, `/api/ps`,
  `/api/show`, `/api/generate`, and `/api/pull` support as the next
  provider-neutral fallback. Local Stack now maps Ollama tags/running state into
  load status, enriches model guidance from show metadata, uses empty-prompt
  generate requests for load/unload, and keeps pull available as a
  non-streaming lifecycle action.
- Closeout decision: LM Studio JIT is treated as provider-native inference
  behavior rather than a separate Local Stack toggle. The native chat API reports
  `model_load_time_seconds` when a request triggers model loading, so exposing
  JIT timing belongs with future trace/provider-event work instead of LL9
  lifecycle controls. Broader model-library acquisition UX, such as catalog
  search, license/provenance review, and user-entered remote download targets,
  is deferred to MLIB1; LL9 keeps lifecycle actions scoped to already selected
  endpoint models and explicit backend actions.
- Live lifecycle smoke follow-up added `tool/run_ll9_model_lifecycle_smoke.sh`,
  which verifies the required `unload` -> `/v1/models` unloaded confirmation ->
  `load` sequence against a real endpoint and can restore the original model.
  Live evidence from 2026-06-22 used
  `http://192.168.100.241:1234/v1`, switched `qwen3.6-27b-vision` to
  `qwen3.6-35b-a3b-vision`, then restored `qwen3.6-27b-vision`; report:
  `build/integration_test_reports/ll9_model_lifecycle_smoke_1782138124/`.

### LL10: Installed-Dependency Grounding

Status: `done`

Scope:
- A built-in tool resolves a package or symbol to the exact installed
  version's source and docs from the project's lockfile: pub cache for Dart,
  `node_modules`, Python site-packages/venv, vendored sources.
- Results return version-accurate API signatures and doc comments, sized to
  the model profile's context budget.
- Optionally index dependency sources through the F4 database for fast
  lookup.

Acceptance criteria:
- Lookups are fully offline and lockfile-accurate (never a newer upstream
  version than the one installed).
- Live coding canaries show reduced hallucinated-API failures on a
  weak-model profile.

Task breakdown:
- Add `InstalledDependencyGroundingService` as a read-only resolver for Dart
  `pubspec.lock` + `.dart_tool/package_config.json` / pub cache, Node
  `package-lock.json` + `node_modules`, Python requirements / Poetry /
  Pipfile locks + venv site-packages, and vendored dependency directories.
- Expose `resolve_installed_dependency` as a built-in MCP tool, project-root
  argument resolver, built-in tool settings entry, and coding prompt guidance.
- Return package version, lockfile accuracy source, installed root path,
  documentation excerpt, source file overview, source matches, and
  `symbol_found` so weak models can distinguish installed APIs from
  future-only upstream APIs.
- Add deterministic LL10 release-gate tooling that creates Dart, Node, Python,
  and vendored dependency fixtures, verifies lockfile-exact installed API
  lookup, symbol-only lookup, missing-package offline failure, prompt guidance,
  and rejection of a future-only API symbol.
- Add an LL10 live canary that compares an ungrounded weak-model baseline
  against the grounded prompt on a locked dependency fixture, proving that
  installed source evidence reduces future-only API hallucinations.

Evidence:
- Implementation commit: `ae445658` (`feat: add installed dependency grounding tool`).
- Focused tests:
  `fvm flutter test test/features/chat/data/datasources/installed_dependency_grounding_service_test.dart test/features/chat/data/datasources/mcp_tool_service_test.dart test/features/chat/domain/services/system_prompt_builder_test.dart test/features/settings/presentation/pages/tools_settings_page_test.dart`
  passed.
- Analyzer: `fvm flutter analyze` passed.
- LL10 gate unit tests:
  `fvm flutter test test/tool/ll10_dependency_grounding_release_gate_test.dart test/features/chat/data/datasources/installed_dependency_grounding_service_test.dart`
  passed.
- Release gate:
  `tool/run_ll10_dependency_grounding_release_gate.sh` produced
  `ready_for_ll10_release` with all gates ready.
- LL10 live canary unit tests:
  `fvm flutter test test/tool/ll10_dependency_grounding_live_canary_test.dart test/tool/ll10_dependency_grounding_release_gate_test.dart test/features/chat/data/datasources/installed_dependency_grounding_service_test.dart`
  passed.
- LL10 live canary:
  `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=qwen3.6-35b-a3b-vision tool/run_ll10_dependency_grounding_live_canary.sh`
  produced `ready_for_ll10_live_canary`, with baseline future-API failures
  reduced from `1` to `0` after installed dependency grounding.
- Gate artifacts:
  `build/integration_test_reports/ll10_dependency_grounding_release_gate_1781828844/release_gate.json`
  and
  `build/integration_test_reports/ll10_dependency_grounding_release_gate_1781828844/release_gate.md`.
- Live canary artifacts:
  `build/integration_test_reports/ll10_dependency_grounding_live_canary_1781828768/canary_summary.json`
  and
  `build/integration_test_reports/ll10_dependency_grounding_live_canary_1781828768/canary_summary.md`.

Deferred:
- Optional F4 indexing of dependency sources for faster repeated lookup.
- Expansion from the LL10 targeted weak-model canary into a broader real-task
  dependency-hallucination suite should move into LL19 once enough cases are
  recorded.

### LL11: LSP Bridge

Status: `done`

Scope:
- Manage language server processes per coding project (reusing the
  background-process infrastructure) and consume diagnostics after each
  `edit_file` / `write_file`, generalizing the Dart-only
  `coding_diagnostic_feedback_service` loop to any LSP language.
- Expose `documentSymbol` output to LL4 repo map generation and a
  go-to-definition tool for token-cheap precise navigation.

Acceptance criteria:
- Post-edit diagnostics reach the model within the same tool loop iteration.
- A missing or crashed language server degrades to current behavior without
  blocking edits.

Implementation status:
- Diagnostics v1 started with a language-server command resolver for Dart,
  TypeScript, Python, and Swift, plus a process readiness manager backed by the
  existing background-process tooling.
- JSON-RPC transport now supports LSP `Content-Length` framing, process stdin /
  stdout wiring, `initialize`, `textDocument/didOpen`, and
  `textDocument/didChange`.
- A diagnostic bridge records `textDocument/publishDiagnostics`, including empty
  publications, and maps them into the existing coding diagnostic feedback
  payload shape.
- A session registry reuses one language-server session per project/language,
  syncs changed documents with incrementing versions, waits briefly for
  asynchronous diagnostic publications, and exposes the registry as both the
  LSP readiness probe and diagnostic client.
- Chat diagnostic feedback now tries the LSP registry first and falls back to
  the current Dart analyzer provider when no supported language server is
  available or the server cannot start.
- `documentSymbol` output is collected from the shared JSON-RPC LSP registry,
  cached by project root and changed file, and included in LL4 repo map prompt
  context when a server is available.
- `textDocument/definition` output is exposed through the
  `lsp_go_to_definition` built-in tool, using the shared JSON-RPC LSP session
  registry for token-cheap navigation from symbol usage to declaration.
- Language-server startup now checks the resolved executable against the
  login-shell `PATH` before starting JSON-RPC or background process sessions, so
  missing TypeScript/Python servers report `language_server_executable_not_found`
  immediately instead of waiting for initialize timeout.
- `tool/run_ll11_lsp_language_server_smoke.sh` records diagnostics,
  `documentSymbol`, and go-to-definition evidence for local language servers
  without requiring a live LLM endpoint.
- Live smoke evidence from 2026-06-19:
  `build/integration_test_reports/ll11_lsp_language_server_smoke_1781848464/`
  passed with `CAVERNO_LL11_LSP_SMOKE_REQUIRE_LANGUAGE_SERVER=1`; Dart and
  Swift returned both diagnostics and document symbols, while TypeScript and
  Python were skipped after initialize timeout on this machine.
- Go-to-definition smoke evidence from 2026-06-19:
  `build/integration_test_reports/ll11_lsp_language_server_smoke_1781849991/`
  passed for Dart with `CAVERNO_LL11_LSP_SMOKE_REQUIRE_LANGUAGE_SERVER=1`,
  returning 1 diagnostic, 3 document symbols, and 1 definition location.
- All-language smoke evidence from 2026-06-19:
  `build/integration_test_reports/ll11_lsp_language_server_smoke_1781850903/`
  passed with `CAVERNO_LL11_LSP_SMOKE_REQUIRE_LANGUAGE_SERVER=1`; Dart and
  Swift returned diagnostics, document symbols, and definition locations, while
  TypeScript and Python were skipped immediately with
  `language_server_executable_not_found` because their language-server
  executables are not installed on this machine.

Verification:
```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/providers/coding_diagnostic_feedback_provider_test.dart \
  --test test/features/chat/data/datasources/lsp_json_rpc_session_registry_test.dart \
  --test test/features/chat/data/datasources/lsp_json_rpc_diagnostic_bridge_test.dart \
  --test test/features/chat/data/datasources/lsp_json_rpc_process_transport_test.dart \
  --test test/features/chat/domain/services/lsp_diagnostic_feedback_provider_test.dart \
  --test test/features/chat/domain/services/coding_diagnostic_feedback_service_test.dart \
  --test test/features/chat/domain/services/repo_map_service_test.dart \
  --test test/features/chat/domain/services/repo_map_precompute_cache_test.dart \
  --test test/features/chat/domain/services/repo_map_lsp_symbol_cache_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/tool/ll11_lsp_language_server_smoke_test.dart
```
- `fvm flutter analyze`

Sign-off:
- LL11 is accepted on the current Dart/Swift live evidence. The delivered scope
  covers post-edit LSP diagnostics, JSON-RPC session reuse, repo-map
  `documentSymbol` grounding, `lsp_go_to_definition`, and non-blocking
  degradation when a language server is unavailable.
- The latest all-language smoke has `blockedGateIds: []` with Dart and Swift
  passing diagnostics, document symbols, and definition locations. TypeScript
  and Python are skipped by explicit executable preflight because
  `typescript-language-server` and `pyright-langserver` are not installed on
  this machine.

Deferred:
- Install TypeScript/Python language servers locally and rerun
  `CAVERNO_LL11_LSP_SMOKE_REQUIRE_LANGUAGE_SERVER=1 tool/run_ll11_lsp_language_server_smoke.sh`
  when expanded language coverage is needed; this is evidence expansion, not an
  LL11 release blocker.

### LL12: Personal Eval Harness

Status: `done`

Scope:
- Record completed real agent sessions (prompt, repo state reference, final
  verification result) as replayable eval cases, with explicit user consent
  per recording.
- Replay the suite against a candidate model/endpoint and score: verification
  pass rate, tool-call fidelity, turns to green, wall-clock time.
- Compare against the incumbent model's stored scores and feed conclusions
  into LL3 profiles.

Acceptance criteria:
- Recordings are local-only, anonymization-free by design (private machine),
  but excluded from any export by default.
- A replay run produces a single comparison report usable for a model swap
  decision.

Implementation status:
- Seed manifest support started with `tool/personal_eval_case_manifest.dart`.
  The tool converts a completed LLM session log into a local-only personal eval
  case manifest only when `--consent` is provided, capturing the prompt, repo
  state reference, verification command/result, session-log summary metrics,
  and export policy `excluded_by_default`. This establishes the stable case
  schema before adding replay execution and candidate-model comparison.
- Suite comparison support started with `tool/personal_eval_suite_report.dart`.
  It consumes one or more eval case manifests plus incumbent/candidate replay
  result files, then scores pass rate, wall-clock duration, turns, and
  tool-call-count fidelity against the original session-log summary. Candidate
  reports with verification regressions or missing cases are rejected before
  LL17 can adopt profile mutations.
- Replay-run artifact generation started with
  `tool/personal_eval_replay_run.dart`. The tool consumes LL12 manifests plus
  per-case replay session logs and explicit verification results, summarizes
  the replay logs through the existing session-log summary parser, and writes
  `caverno_personal_eval_replay_run` JSON that the suite comparison can consume.
- Suite pipeline orchestration started with
  `tool/personal_eval_suite_pipeline.dart`. It writes incumbent and candidate
  replay-run artifacts, then immediately produces the single comparison report
  required for model-swap decisions from deterministic local inputs.
- Repeatable local execution started with
  `tool/run_personal_eval_suite_pipeline.sh`, which standardizes the default
  artifact directory under `build/integration_test_reports/` while preserving
  the deterministic Dart pipeline as the source of comparison logic.
- LL3 profile handoff started with `tool/personal_eval_profile_handoff.dart`.
  It consumes the suite comparison report and emits a local audit artifact with
  a candidate profile target, adoption blockers, and a `probeMetadata` patch
  that can be applied only when the candidate has no LL12 regressions.
- The suite pipeline now emits the profile handoff artifacts next to the replay
  runs and suite report, so a deterministic LL12 run produces the complete
  model-swap evidence bundle without a second command.
- Profile handoff application started with
  `tool/personal_eval_profile_handoff_apply.dart`. It dry-runs by default,
  refuses blocked handoffs, and only writes an updated settings JSON when the
  operator explicitly chooses `--apply --out` or `--apply --in-place`.

Follow-up (Self-Harness alignment):
- The current tooling treats the eval suite as a single set. LL19 adds a
  held-in / held-out split so LL17 can mine failures from held-in cases while
  validating proposals against an unseen held-out split, matching the paper's
  regression-gate protocol and reducing overfitting on small personal suites.

Follow-up (orchestration gate enablement, for LL25/LL26/LL27):
- The harness already scores wall-clock duration alongside pass rate, so the
  "beats the best currently validated single-model path **including latency**"
  gates are measurable as-is — the only residual work is letting an
  *orchestration recipe* (a multi-endpoint A0/A1/A2 config: parallel selection,
  MoA-lite, or a role conductor) be driven as a single replay candidate, so its
  end-to-end wall-clock and verification pass rate are scored like any other
  candidate.

### LL13: Parallel Agents In Worktrees

Status: `done`

Scope:
- Run multiple agent tasks concurrently, each in an isolated git worktree
  with its own LL2 checkpoint lineage and tool-approval scope.
- Distribute tasks across LL8 mesh endpoints when available; otherwise queue
  on the primary endpoint.
- Merge flow: verified-green tasks produce a branch ready for review; nothing
  merges automatically.

Acceptance criteria:
- Two concurrent tasks cannot write to the same worktree.
- Killing the app mid-task leaves worktrees recoverable and listed on
  restart.

Initial implementation slice:
- Add a persistent worktree task registry that records the assigned worktree
  path, branch, checkpoint lineage, optional LL8 endpoint, and lifecycle status
  for each parallel-agent task.
- Reject registration when another non-terminal task already occupies the same
  normalized worktree path.
- On app startup, surface previously queued or running tasks as recoverable
  instead of silently treating them as live.
- Surface active and recoverable worktree-agent tasks in the chat scaffold so
  interrupted worktree tasks remain visible after restart.
- Plan collision-free branch names and sibling worktree paths before invoking
  git worktree creation.
- Enqueue planned assignments from the selected coding project, existing git
  reservations, and the LL8 subagent endpoint default.
- Read existing git branch and worktree reservations before enqueueing so
  planned assignments avoid live repository collisions.
- Create the planned git worktree and branch for queued tasks, then mark the
  task running only after worktree creation succeeds.
- Schedule queued worktree-agent tasks by endpoint capacity so parallel starts
  do not oversubscribe the primary or LL8 mesh endpoints.
- Execute running worktree-agent tasks through an isolated delegate and persist
  completion summaries plus verification status for review-ready branches.
- Queue worktree-agent tasks from the `/agent <task>` composer command for the
  active coding project, with optional `--verify <command>` metadata for
  review-ready branches.
- Start the existing Run ready orchestration immediately when the user adds the
  explicit `/agent <task> --run` flag.
- Balance implicit worktree-agent endpoint assignment across enabled LL8 named
  endpoints, while preserving explicit endpoint overrides.
- Run queued or recovered worktree-agent tasks from the task sheet through the
  scheduler/executor orchestrator, then keep completed tasks visible with their
  verification status and latest run summary until the user clears them.

Verification:
- `tool/run_ll13_worktree_agent_verify.sh`

### LL14: Context Surgery

Status: `done`

Scope:
- Evict stale tool results and deduplicate repeated file reads (keep the
  newest copy, replace older ones with a one-line stub) — applied only at
  compaction boundaries so LL6 prefix stability is preserved between them.
- Model-switch handoff: when the user changes model mid-conversation,
  generate a compact model-agnostic brief instead of replaying the full
  history into the new model's cold cache.
- Extend the token usage indicator with a per-section budget breakdown
  (system prompt, repo map, memory, tools, history).

Initial implementation slice:
- `ContextSurgeryObservationService` classifies coarse system-prompt sections
  and tool-result blocks so LL14 can report prompt pressure before mutating
  conversation history.
- The first stale-result heuristic is observation-only: older duplicate
  `read_file` / `inspect_file` results for the same path and repeated file
  search results with the same arguments are marked as would-evict candidates.
- Protected paths keep their prior reads intact, and command or side-effect
  tool results are never proposed for eviction in this slice.
- The context window popover now surfaces the observation snapshot as
  per-section estimated token pressure plus stale tool-result candidate
  pressure, without mutating conversation history.
- Compact tool-result budgeting now replaces stale duplicate read/search
  results with one-line stubs only at compact context boundaries; normal tool
  loop prompts keep the original evidence.
- Model changes now schedule a one-shot deterministic handoff brief for the
  next request, forcing prompt compaction when possible so long conversations
  avoid replaying full history into the new model.
- `tool/ll14_model_switch_handoff_measurement.dart` compares full-history
  replay against the model-switch handoff fixture, reporting estimated prompt
  token reduction and live `timings.prompt_ms` as the first-token proxy.
- Live measurement on 2026-06-14 against `qwen3.6-35b-a3b-vision` reduced the
  long-conversation fixture from 66 messages / 7291 estimated prompt tokens /
  `prompt_ms=2045.685` to 12 messages / 2253 estimated prompt tokens /
  `prompt_ms=586.408`. See
  `docs/ll14_model_switch_handoff_live_measurement_2026-06-14.md`.

Acceptance criteria:
- Eviction never removes results the current task still references (guarded
  by protected-path tests and compact-boundary-only mutation).
- A model switch on a long conversation reaches first token measurably
  faster than full-history replay (`timings.prompt_ms` improved by 71.3% in
  the live measurement).

### LL15: Weak-Model Edit Harness

Scope:
- When the LL3 profile reports grammar support, constrain edit-block output
  with `json_schema` / GBNF so search-replace blocks cannot be malformed.
- Store known-good few-shot exemplars (tool call, edit block) per model
  family in the profile and inject them for models below a fidelity
  threshold.
- Track edit-apply failure rates per model and feed them back into the
  profile.

Implementation status:
- Initial deterministic guidance injects an `edit_file` exemplar only for
  weak or uncertain coding profiles when `edit_file` is available. Strong
  native structured profiles skip the extra prompt overhead.
- Runtime `edit_file` outcomes now update LL15 profile metadata with attempts,
  successes, failures, failure rate, and failure kind counters. Weak-profile
  prompts include the observed failure rate after multiple attempts.
- `tool/run_ll15_edit_harness_measurement.sh` runs baseline/current coding
  edit canaries with the same weak profile while suppressing the LL15 prompt
  block only for baseline. `tool/ll15_edit_harness_measurement.dart` compares
  LL15 snapshot logs and failed-test classes so live runs can report pass-rate,
  edit failure-rate, and failure-mode deltas.
- LL15 guidance now emphasizes edit recovery: re-read before retrying stale
  `old_text`, verify successful mutations with `read_file`, and fall back to a
  complete `write_file` only for small inspected fixture files. Live snapshots
  expose edit failure-kind counters so regressions can distinguish stale text,
  multiple matches, malformed requests, missing files, and other failures.
- LAN live confirmation on `gemma-4-26B-A4B-it-Q4_K_M.gguf` showed the recovery
  harness improving the weak-profile edit canary from `3/6` to `5/6`, with
  `edit_file` failure rate dropping from `0.111` to `0.000`.

Acceptance criteria:
- Edit-apply failure rate drops measurably on a weak-model profile in live
  canaries.
- Strong models skip the few-shot overhead entirely.

### LL16: Sampler Auto-Calibration

Temperature mistuning was a recurring source of live-harness instability:
tool-loop iterations currently inherit the single user-facing temperature
(default 0.7), while secondary calls hardcode 0.0-0.1. Three layers fix this.

Scope:
- Layer 1 (static request-class split, no probing): the user-facing
  temperature slider is rescoped to chat prose only. Agentic surfaces get a
  managed low default (0.1-0.2, never 0.0) instead of inheriting it:
  tool-loop iterations in any mode, coding/plan mode requests, routine
  executions (which previously inherited `_settings.temperature` unattended),
  and subagent runs. The settings UI relabels the slider as chat temperature
  with helper text explaining the split. The datasource already accepts
  per-request temperature, so this is wiring.
- Layer 2 (probe calibration, LL3 machinery): on model registration, score a
  small temperature matrix (roughly 0.0/0.2/0.4/0.7, repeated runs) on
  tool-call validity, edit-block applicability, and repetition degeneration;
  store the winning per-role sampler preset (temperature, and top_p / min_p
  where the endpoint supports them) in the LL3 profile. Prefer known vendor
  recommendations (Qwen, GLM, DeepSeek families publish them) as candidates
  and use probes to verify rather than search blindly.
- Layer 3 (runtime feedback): count JSON-repair events, malformed tool
  calls, and repetition-loop detections per session; past a threshold,
  step the tool-loop temperature down (never the prose temperature) and
  record the adjustment in the profile.

Acceptance criteria:
- Tool-call validity rate at the calibrated preset matches or beats the
  user-temperature baseline in live canaries.
- Greedy-decoding repetition is detected and avoided (temp 0 is not chosen
  when the probe shows degeneration).
- The user-facing temperature setting keeps controlling final prose answers;
  calibration never silently overrides explicit per-role user choices.
- Routines and coding tool loops no longer read the chat temperature; their
  managed defaults are visible in diagnostics so a support report shows
  which temperature actually served each request.

Implementation status:
- Layer 1 shipped in `8d52063f` with `LlmRequestTemperaturePolicy`.
  Chat prose keeps the user-facing temperature, while tool-loop iterations,
  coding/plan mode requests, routine executions, and subagents use the managed
  agentic default `0.2`.
- Deterministic verification covered the request-class split with
  `test/features/settings/domain/services/llm_request_temperature_policy_test.dart`,
  the chat tool-loop/final prose routing test in
  `test/features/chat/presentation/providers/chat_notifier_test.dart`, and
  the routine routing test in
  `test/features/routines/data/routine_execution_service_test.dart`.
- Live canary evidence:
  `build/integration_test_reports/chat_live_llm_canary_ll16_temp_split_1781261229/canary_summary.json`
  passed 11/11 against `qwen3.6-27b-mtp-vision` with injected native-tool LL3
  profile metadata and `CAVERNO_CHAT_LIVE_CANARY_TEMPERATURE=1.7`.
  The Flutter JSON log recorded 10 requests at `temperature: 1.7`, 10
  agentic/tool requests at `temperature: 0.2`, and one bounded memory
  extraction request at `temperature: 0.1`; readiness was `ready`, with zero
  blocker or warning failures and `transportDisconnectCount=0`.
- Final LL16 live evidence with summary-level request-temperature aggregation:
  `build/integration_test_reports/chat_live_llm_canary_ll16_final_1781440073/canary_summary.json`
  passed 11/11 against `qwen3.6-27b-mtp-vision` with readiness `ready`.
  `signals.requestTemperatures` recorded 21 LLM requests split across 10
  chat prose requests at `1.7`, 10 managed agentic requests at `0.2`, and one
  bounded memory extraction request at `0.1`.
- Layer 2 started with metadata-backed sampler presets on the LL3 profile:
  `ll16.sampler.agentic.temperature` provides the calibrated fallback, while
  role-specific keys such as `ll16.sampler.toolLoop.temperature` and
  `ll16.sampler.routine.temperature` can override individual agentic surfaces
  without changing the user-facing chat prose temperature.
- Layer 2 now has a deterministic sampler calibration scorer that aggregates
  repeated probe trials, penalizes JSON repair, malformed tool calls, edit
  apply failures, and repetition, then writes the selected per-role preset back
  into LL3 profile metadata with score and trial-count evidence.
- `ModelCapabilityProfileBuilder` can now accept sampler calibration trials and
  persist the selected per-role presets into the generated LL3 profile without
  changing existing diagnostic callers that do not provide calibration data.
- Live diagnostic reports can now carry sampler calibration trial evidence, and
  profile building consumes those report trials automatically.
- Native OpenAI-compatible live diagnostics now record repeated `toolLoop`
  sampler calibration trials for the `0.0`, `0.2`, `0.4`, and `0.7`
  temperature candidates.
- Routine-style sampler calibration now records the same repeated temperature
  matrix and persists selected `routine` sampler metadata into the LL3 profile.
- Coding and plan sampler calibration now records repeated structured JSON
  trials with edit-block and task evidence, then persists selected `coding` and
  `plan` sampler metadata into the LL3 profile.
- Diagnostic support JSON and the live diagnostics page now summarize sampler
  trial counts, candidate temperatures, pass counts, and quality flags.
- `LiveLlmDiagnosticNotifier` coverage now verifies that live sampler trials
  persist selected `toolLoop` sampler metadata into the saved LL3 profile.
- Layer 3 started with runtime feedback metadata: malformed tool-call style
  failures, duplicate tool-loop repetitions, and `edit_file` apply failures
  increment per-role counters and can step `toolLoop` temperature down one
  candidate at a time without changing the chat prose temperature.
- Successful workflow/task proposal JSON repairs now record runtime sampler
  feedback for the active planning request class, so repaired planning output
  contributes to LL16 profile calibration without blocking proposal parsing.
- Probe calibration and runtime feedback now preserve sampler presets marked
  as user-configured, including the shared `agentic` fallback, so LL16
  adjustments cannot silently overwrite explicit per-role choices.

### LL17: Self-Improving Harness Loop

Status: `done`

Inspired by Self-Harness (arXiv:2606.09498), which showed agents can improve
their own model-specific harnesses by mining failure traces and validating
proposals with regression tests (Terminal-Bench-2.0 held-out pass rates
improved by 14-21 points across MiniMax M2.5, Qwen3.5, and GLM-5). Caverno
already records the relevant failures; this milestone adopts the paper's
three-stage loop on top of the LL23 editable harness surface and the LL19
in-app eval split.

Scope:
- Weakness Mining: cluster recorded failure traces by a verifier-grounded
  failure signature `(terminal cause, causal status, abstract agent mechanism)`,
  following Self-Harness. The substrate already exists: `ModelEditApplyOutcome`
  is a failure taxonomy, `coding_verification_feedback_service` is the verifier,
  and session logs are the traces. Emit one evidence bundle per cluster (size,
  representative cases, shared symptoms, verifier evidence, inferred mechanism),
  ordered by support x estimated actionability.
- Harness Proposal: generate K mutually distinct candidate edits per round
  against the declared per-model harness config (LL23) — instruction surfaces
  (bootstrap / execution / verification / failure-recovery), runtime control
  policy (tool-loop caps, recovery-middleware toggles), and LL3 profile fields
  (few-shot exemplars, tool-call style, edit format, sampler preset). Edits are
  Grounded (tied to a mined mechanism and a concrete surface), Distinct, and
  Minimal (touch only the needed surface, preserve unrelated behavior, no broad
  rewrites, never self-modifying code). The K candidates evaluate in parallel
  via LL20 slots.
- Proposal Validation: evaluate each candidate against the LL19 eval suite split
  into held-in (the cases that produced the mined failures, shown to the
  proposer) and held-out (never shown to the proposer). Accept only when both
  splits are non-regressing and at least one strictly improves
  (`d_in >= 0 and d_ho >= 0 and max(d_in, d_ho) > 0`); repeat runs and aggregate
  pass counts when evaluation is stochastic. Keep an audit trail and proposal
  lineage (LL21 history) recording both discarded branches and adopted edits.
- Run the mine-propose-validate loop as an LL18 idle/overnight pass, routed to
  the strongest available local model (LL1 / LL8).

Acceptance criteria:
- Proposals outside the declared harness-config schema, or that fail to modify
  any editable surface, are rejected.
- A proposal that regresses either the held-in or the held-out split is never
  adopted; adoption history supports one-tap revert to any previous revision.
- Edits touching high-stakes surfaces (tool execution, approval, shell/file
  write) require a stronger gate than pass-rate non-regression alone (explicit
  user review), per the paper's own caution that "higher-stakes harness changes
  would require stronger acceptance gates than pass-rate non-regression alone".
- A weak-model harness shows a measurable failure-rate reduction in live
  canaries after one mining-adoption cycle.

Implementation evidence:
- Trace extraction: `ModelEditFailureTraceExtractor` converts LL15
  profile `probeMetadata` edit-failure-kind counters into `FailureTrace` values;
  `maintenanceFailureTraceSourceProvider` reads the active model's profile and
  returns them.
- Weakness mining: `FailureTraceMiner` clusters traces by `FailureSignature`
  (terminal cause, causal status, mechanism), returning clusters sorted by
  support.
- Harness proposal: `HarnessProposalService` maps known mechanisms
  (`stale_old_text`, `malformed_json`, `malformed_tool_call`) to single-surface
  edits on `ModelHarnessConfig`. Proposals are Grounded, Distinct, and Minimal:
  they are skipped when the target surface is already set (no clobbering).
  LLM-driven K-candidate generation is deferred to a later refinement.
- Eval-gated adoption: `CandidateAdoptionService` runs the LL19 personal eval
  suite against the incumbent and candidate configs (via injected
  `PersonalEvalCaseRunner` instances), computes held-in / held-out
  `PersonalEvalBakeOffReport`, and auto-adopts only when both splits are
  non-regressing. High-risk surfaces (`approvalMode`, `shellEnabled`,
  `toolApprovalBypass`, `localShellEnabled`, `fullAccessEnabled`) are blocked
  unconditionally and require manual review.
- The mine → propose → adopt stages are wired into the LL18 maintenance
  pipeline via `maintenanceStagesProvider` in
  `maintenance_scheduler_provider.dart`.

Verification:
- `test/features/maintenance/domain/services/candidate_adoption_service_test.dart`
  (8 tests: non-regression adoption, held-in/held-out regression rejection,
  empty-case skip, high-risk block, improvement adoption, both-split regression,
  high-risk surface coverage)
- `test/features/maintenance/presentation/providers/maintenance_stages_test.dart`
  (mine/propose/adopt stage wiring and gating tests)
- `tool/ll18_pipeline_measurement.dart` live measurement 2026-06-16:
  4/4 stages passed against `qwen3.6-35b-a3b-vision` at
  `http://192.168.100.241:1234/v1`; mine/propose/adopt-gate all verified;
  artifact at `build/integration_test_reports/ll18_pipeline_measurement_2026-06-16.md`.

Deferred refinements:
- K-candidate parallel proposal generation (needs LL20 slot substrate).
- Proposal lineage and one-tap revert UI (needs LL21 profile history).
- Held-out isolation: cases seen by the proposer should be excluded by the
  gate; current implementation uses the full split as recorded on the case entity.

Risks:
- Personal eval suites are small, so overfitting risk is higher than the paper's
  Terminal-Bench setting; the held-in/held-out split is necessary but not
  sufficient — treat LL19 coverage quality as the binding constraint and gate
  high-stakes edits manually.
- Accepted edits may encode personal-suite-specific patterns; periodic full
  re-probing (LL21) guards against silent drift.

### LL18: Idle/Overnight Maintenance Orchestrator

Status: `done`

Context:
- Caverno already measures models (LL3 probes, LL16 calibration plus runtime
  feedback, LL15 edit telemetry) and can score them (LL12), but each piece is an
  island: probing is reactive (only on model selection, bounded, skipped when a
  profile already exists), eval is offline CLI-only, and no scheduler ties them
  together. The local thesis — idle hardware at night is a recurring zero-token
  compute budget — has no enabling primitive.

Scope:
- An idle/overnight orchestrator that fires when the machine is idle, on AC
  power (laptops), and within a user-configured maintenance window, reusing the
  desktop platforms (macOS / Windows / Linux) Caverno already runs on.
- A configurable maintenance pipeline that chains existing services: full LL3
  re-probe (LL21) -> LL16 sampler calibration -> LL12 eval replay (LL19) -> LL17
  failure-trace mining and profile-mutation proposals -> eval-gated adoption ->
  a single morning report of what changed and why.
- Runs entirely on local endpoints (zero marginal token cost), under a
  RoutineToolPolicy-equivalent constraint with no interactive approval; never
  adopts a mutation that fails the LL12 non-regression gate.

Acceptance criteria:
- The orchestrator never runs while the user is actively working (idle / power /
  window gates verified) and is fully cancelable.
- A maintenance run is atomic per stage: a crash mid-run leaves the profile and
  conversation store consistent and the next run resumes cleanly.
- Every adopted change links to the failure evidence and the eval run that
  validated it; the morning report is produced even when nothing is adopted.

Implementation evidence:
- Stage pipeline: `MaintenancePipeline` executes a `List<MaintenanceStage>` in
  order, accumulating a `MaintenancePipelineReport` with per-stage outcomes
  (completed / skipped / failed). Stages share a `MaintenanceStageContext` for
  cross-stage data passing.
- Stages wired via `maintenanceStagesProvider` (in
  `maintenance_scheduler_provider.dart`):
  1. `probe` — calls `ModelCapabilityAutoProbeNotifier.runForCurrentModel(force: true)`
  2. `calibrate` — calls `LiveLlmDiagnosticNotifier.run()` (LL16 sampler calibration)
  3. `eval` — calls `PersonalEvalCasesNotifier.replayAllCases()` (LL19 baseline eval)
  4. `mine` — runs `FailureTraceMiner` over the active model's LL15 failure traces
  5. `propose` — runs `HarnessProposalService` on the top cluster
  6. `adopt` — runs `CandidateAdoptionService` with eval-gated held-in/held-out
     validation; auto-adopts via `SettingsNotifier.upsertModelHarnessConfig`
- Idle gate: `IdleMaintenanceScheduler` polls `IdleMaintenanceEnvironment`
  (system idle time, AC power state, time-of-day window); all three must be
  satisfied before a run starts.
- Idle environment: `MacosIdleMaintenanceEnvironment` reads `IOKit` idle time
  via `ioreg` for macOS; `PowerStateProbe.isOnAcPower` reads the system power
  state.
- Config: `IdleMaintenanceConfig` (idle threshold, power requirement, time
  window, enabled flag) stored in `AppSettings`; exposed in a Settings page.
- Report delivery: `MaintenanceReportService.deliver` emits a local notification
  (`MaintenanceReportNotificationService`) only when stages actually executed
  (non-zero completed + failed + skipped count).
- Started by `idleMaintenanceSchedulerProvider`; the scheduler is disposed on
  provider disposal, making it cancelable.

Verification:
- `test/features/maintenance/domain/services/maintenance_pipeline_test.dart`
- `test/features/maintenance/domain/services/idle_maintenance_scheduler_test.dart`
- `test/features/maintenance/domain/services/idle_maintenance_window_policy_test.dart`
- `test/features/maintenance/domain/services/maintenance_report_formatter_test.dart`
- `test/features/maintenance/presentation/providers/maintenance_stages_test.dart`
  (6 stages wired in order; mine/propose/adopt gating verified)
- `tool/ll18_pipeline_measurement.dart` live measurement 2026-06-16:
  4/4 stages passed (probe at 182ms, mine, propose, adopt-gate) against
  `qwen3.6-35b-a3b-vision` at `http://192.168.100.241:1234/v1`; artifact at
  `build/integration_test_reports/ll18_pipeline_measurement_2026-06-16.md`.

Deferred refinements:
- Full LL21 re-probe (the probe stage today calls the bounded
  `ModelCapabilityAutoProbeNotifier`; the full non-bounded probe suite is LL21).
- KV-cache warm-up precompute during idle window (LL22).
- K-candidate parallel proposal evaluation (LL20 slot substrate needed).

### LL19: In-App Personal Eval Recorder & Replay Executor

Status: `done`

Context:
- LL12 shipped as offline CLI tooling with zero `lib/` integration: it scores
  and compares replay artifacts but cannot record a session as a case or drive a
  candidate model through a case from inside the app. LL17 and LL18 both need the
  suite to be runnable unattended, so the eval loop must move in-app.

Scope:
- An in-app recorder that turns a completed agent session into an LL12 case
  manifest (prompt, repo state reference, verification command/result) with
  explicit per-recording consent, reusing the existing session-log store.
- A replay executor that drives a candidate model/endpoint through a recorded
  case end-to-end via the chat datasource (mirroring the canary harness),
  capturing the replay session log and verification result the LL12 tools
  already consume.
- A one-tap "bake-off": when a new model/GGUF is registered, queue an eval run
  against the incumbent and present the comparison verdict.
- A held-in / held-out case split (per Self-Harness): the suite is partitioned
  so LL17 mines failures only from held-in cases while held-out cases stay
  hidden from the proposer and serve as the regression gate. The split is
  stable across runs and recorded in the case manifests.

Acceptance criteria:
- Recordings stay local-only and excluded from export by default.
- A replay run is reproducible and produces the same artifact bundle the offline
  `tool/personal_eval_*` pipeline emits today.
- A bake-off produces a single model-swap recommendation usable without the CLI.
- Held-in and held-out scores are reported separately so an LL17 adoption can be
  gated on non-regression of both.

Implementation evidence:
- Recorder: `PersonalEvalCaseRecorder` (pure) + `PersonalEvalCaseRecordingService`
  read the session log through `LlmSessionLogStore` and build an LL12 case
  manifest only with explicit consent; cases are `excludedFromExport`. The chat
  page exposes a record entry point, wired through
  `PersonalEvalCasesNotifier.recordFromSession`.
- Replay executor: `PersonalEvalReplayOrchestrator` (pure) assembles a
  `PersonalEvalReplayRun` (the `caverno_personal_eval_replay_run` schema the
  offline tools consume) from a `PersonalEvalCaseRunner`.
  `LivePersonalEvalCaseRunner` composes a `PersonalEvalReplayTurnDriver` with a
  `PersonalEvalVerificationRunner` (`ProcessPersonalEvalVerificationRunner` runs
  the recorded command through the platform shell; exit 0 -> passed, non-zero ->
  failed, timeout/launch failure -> inconclusive).
  `PersonalEvalChatReplayTurnDriver` drives the candidate through the real
  non-interactive agent loop (via `RoutineToolRunner` dispatching through the raw
  `McpToolService`, obeying the RoutineToolPolicy trust model) and captures the
  scoped session log; it falls back to a single logged completion when no tool
  service is available.
- Bake-off: `PersonalEvalBakeOffService` compares incumbent vs candidate replay
  runs into a `PersonalEvalBakeOffReport` (mirroring the offline
  `personal_eval_suite_report` thresholds), recommending the candidate only when
  no case hard-regresses. `PersonalEvalCasesNotifier.runBakeOff` replays the
  suite through both models; the cases page surfaces the verdict.
- Held-in / held-out split: `PersonalEvalCaseSplit` on the case entity, managed
  on the cases page; `PersonalEvalBakeOffReport.heldIn` / `.heldOut` report each
  split's pass rates and hard-regression count separately.

Verification:
- `test/features/personal_eval/domain/services/personal_eval_replay_orchestrator_test.dart`
- `test/features/personal_eval/domain/services/live_personal_eval_case_runner_test.dart`
- `test/features/personal_eval/domain/services/personal_eval_verification_runner_test.dart`
- `test/features/personal_eval/domain/services/personal_eval_bake_off_service_test.dart`
- `test/features/personal_eval/data/personal_eval_chat_replay_turn_driver_test.dart`
- `test/features/personal_eval/presentation/pages/personal_eval_cases_page_test.dart`

Follow-up:
- Replay currently runs in the active coding project directory; checking out the
  recorded `repoStateRef` into an isolated worktree before each replay (so a case
  always replays against its recorded state) is deferred to a later slice,
  designed together with LL13 worktree isolation.

### LL20: Parallel Slot Execution Substrate

Status: `done`

Context:
- LL6 explicitly deferred runtime `id_slot` pinning because `openai_dart` does
  not preserve provider-specific request/response extension fields. LL7
  (Best-of-N) and LL13 (parallel worktrees) both need concurrent isolated
  inference on one machine, which llama.cpp exposes via `--parallel N` slots and
  per-request `id_slot`. This milestone builds that transport substrate once.

Scope:
- Preserve provider extension fields end-to-end in the app transport so
  `id_slot`, `cache_prompt`, and `timings` survive the request/response round
  trip (the typed SDK currently drops them).
- Pin a conversation/candidate to a server slot and monitor progress via
  `GET /slots`; run N candidates concurrently against `--parallel N`.
- Expose the substrate to LL7 Best-of-N and (later) LL13 distribution; degrade
  to sequential single-slot execution when the endpoint lacks slot support.

Acceptance criteria:
- Provider extension fields round-trip without loss on llama.cpp endpoints,
  verified by a focused transport test.
- Concurrent candidates run on isolated slots without cross-contamination, and a
  non-slot endpoint transparently falls back to sequential execution.

Implementation evidence:
- Transport: `LlamaCppSlotTransport` (`llama_cpp_slot_transport.dart`) sends a
  raw-HTTP chat completion that injects `id_slot` and `cache_prompt` and parses
  `timings`, the echoed `id_slot`, and usage into `SlotChatResult` /
  `LlamaCppTimings`. It degrades to a plain completion when `idSlot` is omitted,
  so non-slot endpoints behave as today.
- Discovery: `LlamaCppSlotDiscovery` + `SlotInventory` / `ServerSlot`
  (`llama_cpp_slot_discovery.dart`) probe `GET /slots` at the native root
  (stripping `/v1`), parse slot ids and idle/processing state (`is_processing`
  bool or `state` int), and report `unsupported` on a non-2xx (older servers /
  `--no-slots` return 501), malformed body, empty list, or network error.
- Executor: `ParallelSlotExecutor` (`parallel_slot_executor.dart`) runs candidate
  runners through a worker pool — one worker per slot, so no two in-flight
  candidates share a slot — preferring idle slots, bounding concurrency by slot
  count and an optional `maxConcurrency`, preserving input order, and capturing a
  failed candidate instead of aborting the batch. With fewer than two assignable
  slots it runs sequentially (pinned to the one slot, or unpinned).
- Wiring: `parallel_slot_substrate_provider.dart` exposes
  `llamaCppSlotTransportProvider`, `llamaCppSlotDiscoveryProvider`, and
  `parallelSlotExecutorProvider` (null transport/discovery for the on-device
  Apple provider) for LL7 / LL13 to compose.

Verification:
- `test/features/chat/data/datasources/llama_cpp_slot_transport_test.dart`
- `test/features/chat/data/datasources/llama_cpp_slot_discovery_test.dart`
- `test/features/chat/data/datasources/parallel_slot_executor_test.dart`
  (concurrency isolation: peak concurrency equals slot count, no slot collision;
  slot reuse across waves; sequential fallback; per-candidate failure capture)
- `test/features/chat/presentation/providers/parallel_slot_substrate_provider_test.dart`
- `test/tool/ll20_parallel_slot_measurement_test.dart`

Live evidence:
- 2026-06-17 against `qwen3.6-35b-a3b-vision` at
  `http://192.168.100.241:1234/v1` (llama.cpp, single slot, launched without
  `--parallel N`): discovery reported `supported=true`, 1 slot (`id 0`), so the
  substrate correctly degraded to sequential single-slot execution. All 3
  candidates succeeded with the served `id_slot=0` round-tripped, and
  `cache_prompt` reuse showed on the warm slot (`prompt_ms` 131.6 -> 59.1 ->
  59.7). Artifact:
  `build/integration_test_reports/ll20_parallel_slot_measurement_2026-06-17.json`.

Known limitation:
- A live multi-slot concurrency speedup was not captured because the available
  server runs a single slot; concurrent isolation (peak concurrency == slot
  count, no slot collision) is proven deterministically in the executor tests.
  Re-run `tool/ll20_parallel_slot_measurement.dart` against a `--parallel N>1`
  server to record a live speedup. `GET /slots` progress monitoring is parsed but
  live slot-progress polling during a run is left to LL7 when it needs it.

### LL21: Continuous Idle Re-Probing & Profile History

Status: `done`

Context:
- The auto-probe runs a bounded subset once per model and skips any model that
  already has a profile, so a model is never re-measured as runtime evidence
  accumulates and a swapped GGUF quantization (same model id) is never
  re-profiled. Idle time is exactly when the full, expensive probe suite should
  run.

Scope:
- On idle (via LL18), run the full (non-bounded) probe suite rather than the 45s
  registration subset, and re-probe models that already have a profile.
- Store profile revisions as a time series so drift and regressions are visible
  across re-probes; detect quantization/weights swaps behind a stable model id.
- Fold accumulated LL15/LL16 runtime feedback into the re-probe so heuristic
  runtime adjustments are validated (or reverted) against fresh measurements,
  giving the one-directional LL16 temperature step-down a recovery path.

Acceptance criteria:
- A re-probe produces a new profile revision without losing prior history.
- A changed quantization behind the same model id is detected and re-profiled.
- A runtime-lowered sampler preset can recover when a fresh probe shows the
  lower temperature is no longer warranted.

Implementation evidence:
- `ModelCapabilityProfileRevision` — Freezed entity that snapshots key
  capability fields (`toolCallStyle`, `structuredOutputSupport`,
  `editFormatPreference`, `usableContextTokens`, `probeSummary`) plus a
  `source` tag (`'initial'`, `'idle_re_probe'`, `'calibrate'`, `'probe'`) and
  `capabilityChangeDetected` flag.
- `AppSettings.modelCapabilityProfileRevisions` — capped list of revisions
  (max 10 per profile id, oldest trimmed on overflow); serialized as a JSON
  array alongside the existing `modelCapabilityProfiles` list.
- `AppSettings.effectiveModelProfileRevisions` / `capabilityProfileRevisionsFor`
  — return revisions for a given model/endpoint, newest first.
- `SettingsNotifier.upsertModelCapabilityProfile({String source = 'probe'})`
  — accepts a `source` label and appends a revision snapshot on every call,
  comparing against the previous revision for `capabilityChangeDetected`
  (fires when `toolCallStyle`, `structuredOutputSupport`, or `editFormatPreference`
  changes, or when usable context tokens drift beyond ±20%).
- `ModelCapabilityAutoProbeNotifier.runForCurrentModel({..., String source = 'probe'})`
  — threads the source through to `upsertModelCapabilityProfile`.
- `LiveLlmDiagnosticNotifier` passes `source: 'calibrate'` so LL16 calibration
  runs are distinguishable from bounded LL3 probes in the history.
- LL18 probe stage now passes `source: 'idle_re_probe'` and reports
  `'capability change detected (possible model swap)'` in the stage outcome
  when the latest revision has `capabilityChangeDetected = true`.

Verification:
- `test/features/settings/domain/services/model_capability_profile_revision_test.dart`
  (entity construction, JSON round-trip, unknown enum fallback,
  `effectiveModelProfileRevisions` ordering and filtering, cap constant)
- `test/features/settings/presentation/providers/settings_notifier_test.dart`
  (6 new LL21 tests: source tagging, change detection on `toolCallStyle` flip,
  no-change detection, 50% context-token drift, cap enforcement at 10,
  multi-model isolation)
- 285/285 tests passing across settings + maintenance suites.

LL16 recovery path (implemented 2026-06-16):
- `LlmSamplerRuntimeFeedbackService.recoverAfterReprobe({required profile, required probeSource})`
  — for `'idle_re_probe'`: restores the temperature recorded before the
  step-down and resets all runtime counters for stepped-down request classes;
  for `'calibrate'`: counters only (calibration already wrote the temperature);
  user-configured sources (`'user'`/`'manual'`/`'explicit'`) are never modified.
- Wired in `SettingsNotifier.upsertModelCapabilityProfile`: recovery runs
  automatically when source is `'idle_re_probe'` or `'calibrate'`, before
  the profile is persisted.
- 5 new tests in `llm_sampler_runtime_feedback_service_test.dart` (restore on
  re-probe, no-op when not stepped-down, counter-only clear on calibrate,
  user-source preservation, multi-class independence). 214/214 settings tests
  passing.

Profile history UI (implemented 2026-06-16):
- `_ProfileHistorySection` / `_ProfileRevisionCard` in `live_llm_diagnostic_page.dart`
  — render `AppSettings.effectiveModelProfileRevisions` newest-first, one card
  per revision with the trigger source, probed timestamp, captured capability
  fields, and a prominent error-colored warning when `capabilityChangeDetected`
  is set (possible model swap). Empty state shown when no revisions exist.
- en/ja translation keys under `settings.live_llm_diag_profile_*`.
- 2 widget tests in `live_llm_diagnostic_page_test.dart` (empty state,
  newest-first list with model-swap warning). 216/216 settings tests passing.

### LL22: Idle Warm-Up & Precompute

Status: `done`

Context:
- Prefill latency is the local UX killer (LL6 thesis). Idle time can pay that
  cost in advance: precompute the repo map and embeddings, and warm the KV cache
  for the stable system-prompt prefix so the first morning turn is instant.

Scope:
- During an idle window (via LL18), precompute and cache the LL4 repo map and
  (when LL5 lands) embedding vectors for the active coding project.
- Warm the llama.cpp KV cache for the LL6 prefix-stable system prompt plus tool
  list so the first interactive turn reuses cache instead of cold prefill.
- Invalidate precomputed artifacts when their inputs change (repo edits, model
  swap, settings) so warm-up never serves stale context.

Acceptance criteria:
- The first interactive turn after a warm-up window reaches first token
  measurably faster than a cold start, recorded as evidence.
- Precompute is fully incremental and bounded, and is skipped/invalidated when
  inputs changed since the last run.

Implementation evidence:
- Repo-map precompute cache: `RepoMapService.computeSignatureForProject` folds
  the effective char budget, file limits, and a stat-only `path:size:mtime`
  triple per selected file into a cheap fingerprint;
  `RepoMapPrecomputeCache.getOrBuild` / `.precompute` serve the cached map when
  the signature is unchanged and rebuild on a miss (file edit/add/remove or
  context-budget change). The live prompt path reads it via
  `repoMapPrecomputeCacheProvider` in `_repoMap`, so even a cold first turn
  populates the cache lazily.
- KV warm-up: `KvCacheWarmupService` issues one minimal completion (system +
  user prefix, `max_tokens: 1`, greedy) through an injected sender and catches
  errors so an unreachable overnight endpoint is reported, not thrown.
- Pipeline wiring: `maintenanceStagesProvider` appends `precompute` (repo map)
  and `warm_cache` (KV prime) as the final two stages — after
  probe/calibrate/eval send their own requests — so the warmed prefix is the one
  left in the server slot for the morning's first turn. `warm_cache` skips the
  on-device Apple provider, a disabled LL6 prefix-stable tool loop, and a missing
  tool service; warm failures degrade to a soft skip.
- Measurement: `tool/ll22_warmup_measurement.dart` compares a cold first-turn
  request against a warm-up-then-measured pair on a separate slot, reporting
  `timings.prompt_ms`, `cache_n`, and cached share via raw HTTP so provider
  extension fields survive. A per-run nonce at the prompt head keeps "cold"
  genuinely cold and models the volatile temporal context.

Verification:
- `test/features/chat/domain/services/repo_map_precompute_cache_test.dart`
- `test/features/chat/domain/services/kv_cache_warmup_service_test.dart`
- `test/features/maintenance/presentation/providers/maintenance_stages_test.dart`
  (stage order now ends `precompute -> warm_cache`; new skip-path tests)
- `test/tool/ll22_warmup_measurement_test.dart`

Live measurement evidence:
- 2026-06-16 against `qwen3.6-35b-a3b-vision` at
  `http://192.168.100.241:1234/v1` (llama.cpp): the cold first turn prefilled
  3482 prompt tokens at `prompt_ms=1373.3` with `cache_n=0`, while the warm
  first turn (after a one-token warm-up of the same prefix) reused 3457 cached
  tokens (cached share 99.3%) and reached first token at `prompt_ms=63.2` — a
  1310.0 ms / 95.4% prefill reduction. Artifact:
  `build/integration_test_reports/ll22_warmup_measurement_2026-06-16.json`.

Known limitation:
- The temporal header is the first line of the system prompt, so cross-session
  (overnight -> morning) KV reuse relies on llama.cpp `--cache-reuse` recovering
  the stable bulk (tools + repo map + harness guidance) after the timestamp
  chunk; the measured warm benefit is the same-prefix upper bound. Runtime
  `id_slot` pinning and KV-cache persistence across server restarts remain LL20
  / an LL6 extension.

Deferred (out of this milestone):
- Embedding-vector precompute for the repo map is part of the deferred semantic
  *code* search follow-up. LL5 shipped semantic search over conversation
  history only; embedding workspace files remains future work.

### LL23: Declared Per-Model Harness Config

Status: `done`

Context:
- The Self-Harness analysis (LL17) found that the highest-impact edits are not
  capability flags but harness *instruction surfaces* and *runtime control
  policy*: MiniMax M2.5 gained from early-artifact-creation bootstrap text and a
  `max_total_tool_messages` loop cap; Qwen3.5 from dependency-precheck and
  no-blind-retry instructions plus tool-error recovery middleware; GLM-5 from a
  persistent shell environment and an explicit exploration-to-implementation
  transition. Caverno's per-model tuning today is the LL3 `ModelCapabilityProfile`
  (measurements + sampler), and bootstrap/verification/recovery guidance lives
  in `SystemPromptBuilder` at mode granularity — there is no declared,
  per-model, mutable harness surface for LL17 to edit.

Scope:
- A declared per-model harness config schema: instruction-surface fragments
  (bootstrap, execution, verification, failure-recovery) and a runtime control
  policy (tool-loop cap, recovery-middleware toggles, exploration-to-edit nudge).
  Stored alongside the LL3 profile, with safe defaults when absent.
- `SystemPromptBuilder` and the tool loop read the config so an edit changes
  real behavior without touching code; changes respect LL6 prefix stability
  (config is part of the stable prefix and only mutates at compaction
  boundaries).
- The schema is the exclusive set of fields LL17 may mutate — a closed
  allow-list, never free-form code, so every proposal is auditable and
  revertible.

Acceptance criteria:
- Every config field has a safe default; a model with no config behaves exactly
  as today.
- An edited instruction surface or control-policy flag changes the live request
  deterministically, verified by a focused prompt/tool-loop test.
- The schema is closed: a proposed field outside it is rejected before any eval.

Implementation status:
- `ModelHarnessConfig` is a Freezed entity stored per model on `AppSettings`
  (keyed by the shared LL3 profile id), with safe no-op defaults, a closed
  allow-list `fromJson` (unknown keys dropped), and an `effectiveModelHarnessConfig`
  lookup. Covered by `app_settings_test.dart`.
- `SystemPromptBuilder` injects the four instruction surfaces, the
  exploration-to-edit nudge, and a built-in recovery directive
  (`recoveryMiddlewareEnabled`) as `MODEL HARNESS GUIDANCE` lines, wired live via
  `ChatNotifier`. Covered by `system_prompt_builder_test.dart`.
- The tool loop resolves its base iteration cap from `toolLoopMaxIterations`
  (`resolveToolLoopMaxIterations`, clamped to a defensive ceiling).
- Follow-up status: targeted recovery now covers prose-only coding
  continuations and turn-finalization checks before a premature coding answer is
  saved. Live canary summaries record both coding-continuation and
  turn-finalization recovery counts. Broader schema-driven tool-failure
  injection still needs deeper tool-loop machinery and a later dedicated slice.
  Session-log triage for the continuation-stall signature is recorded in
  `docs/ll23_recovery_session_log_triage_2026-06-18.md`.


### LL24: Task-Based Primary-Model Routing

Status: `next`

Scope:
- Route the *primary* conversation turn (today LL1 only routes secondary roles) to
  a model chosen by `AssistantMode`: plan/coding can map to a
  quality-preferred assignment, while general can stay on a fast/default
  assignment. These labels are explicit user/eval choices, not guesses from
  model size, parameter count, or sparse-activation names such as A3B. An empty
  per-mode assignment falls back to the main model, so the feature is opt-in and
  behaviour-preserving by default.
- Resolve through a single `PrimaryModelRouter` (`RouteContext` → `ResolvedEndpoint`)
  that reuses the LL1/LL8 `MeshEndpointRouter` for endpoint resolution and health
  fallback.

Acceptance criteria:
- The resolved primary model auto-pulls its model-keyed LL3 capability profile and
  LL23 harness config; no per-mode harness branching is added at call sites.
- Route resolution happens at turn/step boundaries (re-invokable), never frozen
  once per conversation, and emits a route reason to the session log.
- A missing/disabled/unhealthy assigned endpoint degrades to the primary endpoint
  without failing the active turn (inherited from `MeshEndpointRouter`).
- Mid-conversation model swaps are bounded to step/turn boundaries to limit KV
  cache loss (see LL6/LL22).

Implementation slices:
- `AppSettings` per-mode model + endpoint overrides (mirrors the LL1 role fields
  and the `model_routing_settings_page.dart` UI pattern).
- Pure `PrimaryModelRouter` domain service (`RouteContext` → `ResolvedEndpoint`).
- Wire the router into `ChatNotifier` at the turn boundary; add route-reason
  logging behind `enableLlmSessionLogs`.
- Primary-model auto-prepare at the turn boundary: before the selected primary
  model is used, ask the provider-neutral LL9 lifecycle layer whether the model
  is already loaded or in progress. When switching models on the same endpoint,
  unload the previous primary model first, confirm the catalog reports it as
  unloaded, then load the selected unloaded/unknown model when supported. Treat
  unsupported or missing lifecycle metadata as a no-op. Broader automatic
  eviction policy remains a later Local Stack concern.
- Model-routing settings UI: per-mode rows alongside the existing LL1 role rows.

Design seam (reserved for LL25):
- The router is the single decision point and is re-invokable mid-turn, so LL25
  adds a difficulty signal + escalation strategy without touching call sites.
- A checkpoint that can request a re-route exists but is a no-op in LL24 (it always
  declines to escalate).

### LL25: Auto Difficulty Routing (Cascade Escalation)

Status: `later`

Scope:
- Decide the primary model automatically instead of by explicit mode. Preferred
  shape is cascade escalation: answer with the light model, then escalate to the
  quality-preferred model only when the turn is struggling — rather than paying
  an up-front per-turn classifier call. On local hardware this avoids loading a
  slower or more memory-expensive model until it is actually needed.

Escalation triggers (reuse existing signals):
- LL7 verification feedback failure, tool-loop stall (`toolLoopMaxIterations`
  reached), or explicit low-confidence from the light model.

Alternative considered (a-priori routing):
- A cheap classifier labels difficulty before answering: a heuristic (prompt
  length, code blocks, keywords), an LL3-structured-output router call on the small
  model, or an LL5-embedding classifier over labelled past turns. Higher per-turn
  cost; retained as a fallback design if cascade re-run latency proves too high.

Acceptance criteria:
- Escalation only at step/turn boundaries (bounded KV-cache loss; see LL6/LL22).
- Every route + escalation decision logs a reason usable as classifier training
  signal (feeds the LL12/LL19 eval loop).
- Escalation never overrides an explicit user model choice.

Dependencies: LL24 (router seam), LL7 (verification signal). Related: LL3, LL5,
LL12, LL19 for the a-priori classifier path; EDGE2 already names on-device routing
as a micro-model task.

### LL26: Parallel Best-of-N Selection Across The Mesh (A0)

Status: `later` (high-confidence and cheap, but sequenced after LL24; promote to
`next` once LL24 ships and the LL12 orchestration-recipe eval candidate exists)

Scope:
- Generate N candidates concurrently on resident mesh endpoints (PC1/PC2 …) using
  the LL20 parallel slot substrate over LL8 routing, then keep the candidate that
  passes verification (LL7). A *selection* ensemble — latency-neutral because the
  workers run in parallel and each endpoint keeps its own KV cache.
- The pragmatic near-term use of a multi-PC mesh; ships almost entirely on
  existing parts (LL7 + LL8 + LL20). High-confidence win, no new coordinator layer.

Acceptance criteria:
- A downed endpoint degrades to fewer candidates without failing the turn (LL8).
- Selection is verifier-grounded (compile / test / LSP), not a subjective vote.
- No added per-turn latency vs the best currently validated single-model path
  beyond the verifier pass.

Implementation slices:
- Fan candidate generation across mesh endpoints (extend LL7 Best-of-N onto LL8).
- Verifier-pick + tie-break; record which endpoint won, for LL12/LL19 eval tuning.

Optional extension — verifier-grounded synthesis pass:
- Beyond pure selection, try a single *synthesis* pass over the top candidates
  (one model re-writes a combined answer), then **re-verify the synthesized output**
  so code keeps its ground truth — a coding-safe variant of OpenRouter Fusion's
  judge→synthesis shape, without its "skip for coding" caveat.
- Motivated by Fusion's DRACO finding that a model paired *with itself* gained
  +6.7pts: synthesis helps even without model diversity, so this is cheap to try on
  an already-resident pool. Keep it behind the eval gate (LL12/LL19) and accept it
  only if `select+synthesize+re-verify` beats plain `select` on the user's tasks;
  otherwise stay with selection. Full rationale: `docs/multi_model_orchestration_research.md`.

### LL27: Collaborative Multi-Model Orchestration (Future Challenge)

Status: `later` (retained thesis; eval-gated)

Guiding thesis:
- A **Trinity-style role conductor** — a small local coordinator that assigns
  Thinker / Worker / Verifier roles to larger resident models on PC1/PC2 — is the
  north star, the local-mesh analogue of Sakana Fugu. Kept as the design vision
  even though it is deliberately not a committed near-term build (architecture A2
  in the research doc).

Scope (paradigms in play):
- Layered aggregation: **Mixture-of-Agents** (parallel proposers → aggregator).
- Role orchestration: AutoGen / MetaGPT-style Planner / Coder / Reviewer over LL1's
  role→endpoint map and LL13's mesh-distributed worktree agents.
- Debate for high-stakes plan / reasoning turns.
- Message granularity only: token / logit fusion (DeePEn, distributed speculative
  decoding) is ruled out over a LAN.

Promotion gate (why it stays `later`):
- Productize only if it beats the best currently validated single-model path
  **including latency** on the user's real tasks, measured with the LL12/LL19
  eval harness. Orchestration must be gated to plan / hard turns (LL24/LL25),
  never the default path.

Known risks to validate before any build:
- **Latency** — every paradigm adds round-trips; the slowest worker bounds the turn.
- **Worker homogeneity** — same-family local models are correlated, shrinking the
  ensemble upside; deliberately diversify the pool (different model lineages).
- **Verification may beat ensembling for coding** — code has ground truth, so the
  best currently validated single model + LL7 + LL11 LSP feedback can outperform
  debate / MoA.

Full survey and candidate architectures (A0–A3): see
`docs/multi_model_orchestration_research.md`.

Dependencies: LL26 (parallel selection substrate), LL12 / LL19 (eval gate), LL1
(role→endpoint map), LL13 (mesh worktree agents). Related: EDGE2 (on-device
coordinator as a micro-model task).

### LL28: Multi-Participant Group Discussion (User-Facing)

Status: `done`

Goal:
- Let the user invite another resident model (e.g. PC2) into the *same* chat
  thread and run a role-based group discussion / brainstorm — LLM1 as
  facilitator, LLM2 as senior engineer, etc. — with every participant visible in
  one transcript. The manually-driven, *visible* sibling of LL27 (the hidden,
  auto, eval-gated orchestration); here the user judges quality directly, so there
  is no eval gate.

Scope (MVP):
- Participant model: a conversation carries an ordered list of
  `ConversationParticipant` (display name, role label + role system prompt,
  endpoint id [empty = primary / PC1], model, structured `facilitatesTurns`
  authority for facilitator-managed floor control, per-participant
  `ToolApprovalMode`, tools-enabled flag, color). Empty list == today's
  single-LLM behavior.
- Message attribution: add nullable `Message.participantId`; render other speakers
  to each model as user-role lines prefixed `[name · role]:` (the existing
  re-send-as-user convention), prepend generated participant identity context
  plus the role prompt via `SystemPromptBuilder`. Facilitator handoff target
  snapshots persist on messages and render as compact bubble cues so reopened
  history still explains who was invited to respond.
- Turn-taking: round-robin in configured order when no facilitator is present,
  behind a single re-invokable `nextSpeaker(context)` decision point so the future
  auto-moderator swaps in without call-site churn. When a facilitator is present,
  the facilitator is selected by `ConversationParticipant.facilitatesTurns`
  first, with role-label matching retained only for older saved participants.
  Specialists speak only after a final `Handoff: <participant name or role>`
  line, and the marker is stripped from the visible transcript. The facilitator
  must include a natural visible invitation to the target participant before the
  hidden routing marker, so the UI explains why the next participant is
  responding. If the facilitator-visible response asks the user a question, the
  marker is stripped but no specialist turn is scheduled; the facilitator role
  prompt also forbids handoff lines on user-facing questions or clarification
  requests.
- Depth: both single-round (one non-facilitated pass or one facilitator handoff
  cycle, then floor returns to user) and multi-round auto-discussion (loop up to
  `maxRounds` with stop / continue).
- Tools: read-only participant tools only (search, datetime, conversation search,
  read-only inspection), reuse the existing
  `ToolApprovalMode { defaultPermissions, autoReview, fullAccess }` (== manual /
  auto / full) per participant via `ToolApprovalGate` + `ToolApprovalCache`, and
  keep tools off by default in MVP.
- UI: participant roster + invite sheet (endpoint from `namedEndpoints`, model,
  role preset, approval mode); per-speaker avatar / name / role chip on bubbles;
  single / multi-round toggle + round counter.

Reuses (substrate already shipped):
- LL8 `MeshEndpointRouter` / `MeshSecondaryCompletionRunner` — per-participant
  endpoint call with health fallback (PC2 down → graceful single-model).
- LL1 role→endpoint mapping; LL3 / LL23 per-model harness profiles.
- `ToolApprovalMode` + gate / cache; `SystemPromptBuilder`.

New build:
- `ParticipantTurnCoordinator` (domain service) drives turn planning,
  participant normalization, role identity prompts, handoff parsing, and
  per-speaker transcript transforms;
  `ParticipantCompletionRunner` streams each turn through the existing mesh
  fallback boundary, including read-only participant tool loops; `ChatNotifier`
  delegates to them only when participants is non-empty (single-LLM path
  untouched).

Streaming: sequential for MVP (one participant streams, then the next); parallel /
MoA aggregation is deferred to LL27.

Phase 2 → LL27 bridge:
- Auto-moderator next-speaker policy, convergence / stop heuristics, and optional
  parallel aggregation converge toward the LL27 role conductor.

Verification:
- Focused coordinator, runner, entity, roster, bubble, and system-prompt tests
  cover participant normalization, attribution transforms, round-robin order,
  facilitator-managed floor control, single vs multi-round depth, soft stop /
  continue, handoff routing, visible facilitator handoff invitations,
  persisted handoff cues, facilitator question handoff suppression, structured
  facilitator authority, facilitator prompt guardrails, mesh fallback,
  persistence, invite UI, and attributed rendering.
- Focused `ChatNotifier` participant tests cover ordered participant streaming,
  remote-only roster primary materialization, queued user interjection, chat-only
  gating, participant role prompts flowing through the existing system prompt
  preparation path, read-only participant tool approval, participant tool
  summaries, and handoff marker stripping / routing.
- The local verification command for the focused LL28 surface is:
  `tool/codex_verify.sh --no-codegen --test test/features/chat/domain/entities/conversation_test.dart --test test/features/chat/domain/entities/conversation_workflow_test.dart --test test/features/chat/domain/services/system_prompt_builder_test.dart --test test/features/chat/domain/services/participant_turn_coordinator_test.dart --test test/features/chat/domain/services/participant_tool_policy_test.dart --test test/features/chat/domain/services/tool_approval_auto_review_service_test.dart --test test/features/chat/data/datasources/participant_completion_runner_test.dart --test test/features/chat/presentation/widgets/participant_roster_bar_test.dart --test test/features/chat/presentation/widgets/message_bubble_test.dart`
  plus `fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart --name "participant|handoff|outside chat workspace" -r expanded`.

Dependencies: LL1, LL8, LL3 / LL23. Related: LL27 (auto-orchestration sibling),
LL24 / LL25 (per-turn primary-model routing).

## Complex-Task Robustness Track (LL29-LL31)

These three milestones share one product goal: **when a task gets complex, the
agent should degrade gracefully instead of producing unintended, blank, or
silently-stopped results.** They were scoped from a comparison of Caverno's
tool-calling loop against the Hermes/Nous open-source agent (the
`tool_guardrails.py`, `context_compressor.py`, and `turn_finalizer.py`
modules). Caverno already has the harder pieces — a security taint system,
read-only dedup (LL14), false-completion guards, and `max_iterations` recovery
with a final read-only inspection batch. The gaps below are the cheap, additive
wins that most change how complex multi-step turns behave.

Sequencing: LL29 first (highest behavior impact, lowest risk), then LL31
(diagnosability), then LL30 (largest token win for tool-heavy turns). LL29 and
LL31 both touch the `ChatNotifier` tool loop, so landing them together keeps the
loop edits in one review surface.

### LL29: Tool-Loop Failure Recovery (Degrade, Don't Abort)

Status: `next`

Problem:
- The current loop ends the *entire turn* when one tool call fails twice with
  identical arguments (`toolFailureCounts[key] >= 2` → `hasTextResponse = true;
  break;` in `chat_notifier.dart`), emitting a generic "check your server
  configuration" message. On a complex multi-step task, a single recoverable
  mid-task hiccup discards every remaining step — a primary source of
  "unintended results when tasks get complex".

Scope:
- Split the single failure threshold into graded actions, mirroring the Hermes
  `ToolCallGuardrailController`: `warn` (default) keeps the loop running and
  injects guidance; a hard `halt`/`block` becomes an opt-in circuit breaker
  surfaced through the LL23 per-model runtime control policy (loop caps already
  live there).
- On a repeated failure, append an **action-oriented, tool-specific recovery
  hint** to the failing tool result instead of killing the turn — e.g. for a
  shell/command tool: "run a small diagnostic (`pwd && ls -la`), then try an
  absolute path, a simpler command, or a different tool"; generic tools get a
  "diagnose before retrying, try different arguments or a different tool" hint.
- Distinguish three loop shapes using content-addressed signatures (tool name +
  canonical-args hash): exact-arg repeat-failure, same-tool repeat-failure
  (any args), and read-only no-progress (idempotent tool returning an identical
  result hash). Reuse the existing `ToolCallExecutionPolicy` dedup-key builder
  for the signature.
- Keep the synthetic recovery result a real `role=tool` result so the next
  model turn sees it as data, consistent with the existing dispatch path.

Acceptance criteria:
- A turn where an early tool fails twice but a later strategy would succeed no
  longer aborts: the model receives the recovery hint and continues the loop
  (covered by a `chat_notifier` loop test that asserts the loop survives a
  twice-failing call and still reaches a later successful tool).
- The hard halt only fires when the model-harness policy opts in, and when it
  fires the user sees an explicit halt explanation (not a crash-like blank).
- No regression in the existing duplicate-skip / `commandRetryGeneration`
  behavior (repeatable command tools still get fresh keys per generation).

Source: Hermes/Nous agent `agent/tool_guardrails.py`
(`ToolCallGuardrailController`, `_tool_failure_recovery_hint`,
`append_toolguard_guidance`) and `agent/tool_executor.py`
(`_append_guardrail_observation` warn-injection vs. opt-in block).

Next action: add a graded-decision helper next to
`ToolLoopRecoveryPolicy` and rewire the `toolFailureCounts` branch in
`chat_notifier.dart` from `break` to hint-injection + continue, gated by the
LL23 runtime policy.

### LL30: Compaction Structural Pre-Pass

Status: `next`

Problem:
- `ConversationCompactionService` summarizes the conversation but does not first
  prune tool results structurally, protects a fixed `recentMessagesToKeep = 8`
  message tail (not a token budget), and has no anti-thrashing guard. On
  tool-heavy complex turns, tool outputs dominate the token budget, so the
  cheapest, largest savings are left on the table and LL14's stubbing only
  triggers at compaction boundaries.

Scope (no-LLM cheap pre-pass, applied before the existing summary, only at
compaction boundaries to preserve LL6 prefix stability):
- Dedupe identical tool-result contents (hash, keep the newest full copy,
  replace older duplicates with a back-reference stub) — generalizes LL14's
  read/search dedup to all tools.
- Replace old tool results with **informative one-line summaries that preserve
  *what happened*** rather than a content-free placeholder — e.g.
  `[run_command] \`flutter test\` → exit 0, 47 lines`,
  `[read_file] config.dart from line 1 (3,400 chars)`. Port the per-tool
  summary table to Caverno's built-in tool names.
- Truncate oversized tool-call arguments (large `write_file` / patch bodies)
  **inside the parsed JSON structure** so the persisted call stays valid and
  providers don't 400 on later turns.
- Switch the protected tail from a fixed message count to a token budget with a
  message-count floor; keep `recentMessagesToKeep` as the floor.
- Add an anti-thrashing back-off: skip compaction when the last two passes each
  saved under ~10% (record an ineffective-pass counter), surfacing a "start a
  fresh session / focused compact" hint instead of looping.

Acceptance criteria:
- For a synthetic tool-heavy transcript, the pre-pass alone (no summary LLM
  call) reduces estimated prompt tokens by a measured margin, recorded with a
  `tool/` measurement script in the LL14 style.
- One-line summaries retain the tool name, key argument, and outcome (exit code
  / match count / byte count) — asserted by unit tests over the summary builder.
- Argument truncation leaves every persisted tool call parseable as JSON.
- Anti-thrashing prevents a no-op compaction from re-triggering every turn.

Source: Hermes/Nous agent `agent/context_compressor.py`
(`_prune_old_tool_results` three-pass prune, `_summarize_tool_result`,
`_truncate_tool_call_args_json`, token-budget tail in `_find_tail_cut_by_tokens`,
anti-thrashing in `should_compress`).

Next action: implement the dedupe + one-line-summary passes as a pure helper
beside `ConversationCompactionService`, unit-test the summary table, then wire
it into the compaction entry point ahead of `_buildSummary`.

### LL31: Turn-Exit Reason and Completion Explainer

Status: `next`

Problem:
- The tool loop has many `break` / `hasTextResponse` exit points but no
  structured record of *why* a turn ended, and an empty or truncated final
  response reaches the user as a blank or fragmentary bubble with no
  explanation — the "it just stops" experience on complex tasks.

Scope:
- Tag every loop exit with a structured `turnExitReason`
  (`text_response(...)`, `max_iterations_reached(n/m)`, `guardrail_halt`,
  `empty`, `partial`, `user_confirmation_block`, ...), set at each existing
  break site.
- Add a completion explainer that runs once after the loop: when the final
  response is empty/`(empty)` or a short fragment with no terminating
  punctuation, replace or append a single user-visible explanation derived from
  `turnExitReason`. Gate it so healthy `text_response` exits stay silent (a
  terse "Done." is never annotated).
- Emit a WARNING-level diagnostic log when a turn ends with a pending tool
  result as the last message (agent was mid-work), including the last tool name
  — so the session-log triage tooling (`tool/triage_session_logs.py`) can find
  "just stops" turns.
- Reuse the existing false-completion / file-mutation guards as the
  content-truth layer; LL31 only adds the *why-it-stopped* surface, it does not
  re-judge success.

Acceptance criteria:
- A turn that ends empty after retries shows an actionable reason instead of a
  blank bubble (loop test asserts the explainer text for representative exit
  reasons).
- A healthy short answer is left untouched (no explainer appended).
- Mid-work stops produce a WARNING log line carrying the exit reason and last
  tool name, discoverable by the session-log triage script.

Source: Hermes/Nous agent `agent/turn_finalizer.py` (`_turn_exit_reason`
taxonomy, turn-completion explainer, mid-work WARNING diagnostic, and the
`completed` determination).

Next action: thread a `turnExitReason` local through the `ChatNotifier` loop
break sites, then add the post-loop explainer + mid-work warning as a single
finalization step.

## Future Platform Vision Milestone Notes

### API1: Responses-Compatible Agent Event Core

Status: `later`

Scope:
- Introduce an internal `AgentEvent` stream that normalizes user input, model
  deltas, reasoning deltas, tool-call requests, tool results, approvals,
  patches, verifier results, memory reads/writes, and response completion.
- Keep the existing Chat Completions path working while adapters translate into
  the same internal event model.
- Preserve provider extension metadata from LL20 as event attributes rather than
  forcing every caller to understand raw provider JSON.

Acceptance criteria:
- Existing chat/tool-loop behavior can be replayed from the event stream in a
  deterministic fixture.
- Provider-specific fields survive as scoped attributes without leaking into
  generic OpenAI endpoints.
- The event schema is versioned and supports forward-compatible unknown fields.

Build-on and promotion note:
- API1 extends the existing `ChatNotifier` streaming/tool-loop and
  `ChatRemoteDataSource` paths rather than replacing them: adapters emit the
  `AgentEvent` stream while the current request flow keeps working until callers
  migrate.
- This is the most invasive vision milestone — an F2-scale core refactor. Keep
  the first slice schema + replay-fixture only, and gate promotion on the full
  chat-notifier, tool-loop, and Plan Mode smoke suites passing unchanged.

### API2: Chat/Responses/Local-Provider Adapter Matrix

Status: `later`

Scope:
- Add adapters for Chat Completions, Responses-style APIs, llama.cpp raw
  extensions, LM Studio/Ollama compatibility quirks, and on-device runtimes.
- Define downgrade paths when an endpoint lacks Responses-style state,
  streaming events, tool calls, structured output, or provider timings.
- Maintain deterministic request/response fixtures for each adapter.

Acceptance criteria:
- A provider conformance result can select the safest adapter automatically.
- Adapter behavior is covered by golden JSON fixtures and streaming delta tests.
- Unsupported provider features degrade with clear diagnostics, not silent
  behavioral changes.

### SEC1: Local Agent Data Perimeter

Status: `done`

Scope:
- Classify data sources such as user instructions, project source, dependency
  source, generated summaries, remote web, MCP resources, untrusted documents,
  credential-like strings, and executable instructions.
- Classify tool capabilities such as file read/write, shell, network, git push,
  SSH, memory write, clipboard, notifications, and Remote Coding actions.
- Attach data-source and capability context to agent events, tool calls, memory
  writes, and trace spans.

Acceptance criteria:
- High-risk tool calls display the relevant capability and data-source context.
- Untrusted document content is never treated as equivalent to a user command.
- Existing approval flows continue to work with no weaker default policy.

Slice plan:
1. Tool capability classification (pure domain model). **done.**
2. Data-source classification (user / project / dependency / generated /
   remote-web / mcp / untrusted-document / local-diagnostic) with a trust level,
   plus credential and prompt-injection content detectors. **done.**
3. Unify capability + data-source into one `ToolPerimeterContext` descriptor
   with a display summary (pure aggregator). **done.** Wiring this into the live
   approval surface / audit trail is blocked: `chat_notifier.dart` (the single
   audit call site) is already over its F1 ratchet budget (16.8k vs 15.5k), so
   the producer wiring waits on an F5 extraction or a new handler file rather
   than growing the god-file.
4. Relocate the perimeter classifiers to `lib/core/security/` (cross-cutting)
   and attach the classified capability to recorded approvals via the approval
   audit trail — without touching the over-budget `chat_notifier.dart`. **done.**
5. Feed the capability context into the LLM auto-review packet so the reviewer
   weighs the action's capability/risk and refuses to let untrusted content
   authorize a privileged action. **done.**
6. Surface the capability + data-source context in the live approval UI
   (acceptance criterion 1's "display") and enforce that untrusted document
   content is never elevated to a user command (criterion 2), without weakening
   existing approvals (criterion 3). **done.** The F5 task-proposal extraction
   freed `chat_notifier.dart` budget (15,270 -> 13,853), unblocking this. A
   reusable `ToolPerimeterSummary` widget (display-only; pure
   `ToolPerimeterClassifier`, no gating) renders the perimeter one-liner in every
   high-risk approval sheet. Criterion 2 is met by slice 5 + SEC2 3a (the
   auto-reviewer denies untrusted-driven privileged actions; live-verified).
   Live-verified on macOS (2026-06-21): the local-command sheet for
   `touch /tmp/...` showed "shell execution · high risk · mutates host" in red.

Slice 6 evidence:
- `lib/features/chat/presentation/widgets/tool_perimeter_summary.dart`: a
  `StatelessWidget` that classifies a pending tool call via
  `ToolPerimeterClassifier` and shows `summary` with a risk-tiered icon/colour.
  Display-only; cannot gate or weaken an approval (criterion 3).
- Wired into the local-command, file-operation, ssh-command, git-command,
  computer-use, and browser approval sheets (`chat_page.dart` +
  `chat_page_browser_builders.dart`, within the 8,120 ratchet budget). The
  ssh-connect sheet is intentionally excluded (a connection prompt, not a
  tool-capability call).
- `test/features/chat/presentation/widgets/tool_perimeter_summary_test.dart`
  covers shell, filesystem-write, untrusted network-fetch, and read-only cases.

Slice 1 evidence:
- `lib/features/chat/domain/services/tool_capability_classifier.dart`:
  `ToolCapabilityClass` (file write, shell, code execution, network fetch, git
  write, SSH, memory write, clipboard, notification, Remote Coding, browser,
  computer-use, device control, read-only inspection) plus `ToolRiskTier` and a
  pure `ToolCapabilityClassifier`. High-risk tiers are aligned with the existing
  approval-gated set so the classifier does not silently re-rank current
  behavior (criterion 3). Pure and additive: nothing is wired yet, so no
  approval/execution path changes.
- `test/features/chat/domain/services/tool_capability_classifier_test.dart`
  covers each capability class, risk tier, and the `mutatesState` /
  `accessesNetwork` derived properties.

Slice 2 evidence:
- `lib/features/chat/domain/services/data_source_classifier.dart`:
  `DataSourceClass` (user instruction, project source, dependency source,
  generated summary, remote web, MCP resource, untrusted document, local
  diagnostic) and `TrustLevel` (user / project / untrusted), with a pure
  `DataSourceClassifier`. Provenance is the immediate producing tool; only
  remote-web, MCP, and explicitly-untrusted content is `untrusted`, while local
  reads, deps, diagnostics, and the user's own memory are `projectTrusted`.
  Adds `looksLikeCredential` and `containsInjectionAttempt` content detectors
  for later perimeter enforcement. Additive: nothing is wired yet.
- `test/features/chat/domain/services/data_source_classifier_test.dart` covers
  provenance, trust mapping, credential detection, and injection detection.

Slice 3 evidence:
- `lib/features/chat/domain/services/tool_perimeter_context.dart`:
  `ToolPerimeterContext` (capability + result provenance/trust +
  `producesUntrustedContent` + a one-line `summary`) and a pure
  `ToolPerimeterClassifier` composing the slice-1/2 classifiers. The summary is
  the string the approval surface and audit trail will display.
- `test/features/chat/domain/services/tool_perimeter_context_test.dart` covers
  composition (shell, network fetch, MCP, project read) and the summary format.
- Wiring blocker: the producer side (`_recordApprovalAudit` in
  `chat_notifier.dart` and the approval widgets) cannot grow the already
  over-budget `chat_notifier.dart`; slice 4 must land a small extraction or a
  new handler file first.

Slice 4 evidence:
- Relocated the three classifiers (and their tests) to `lib/core/security/` so
  the perimeter primitives are cross-cutting and `lib/core` no longer needs to
  reach into the chat feature.
- `lib/core/services/tool_approval_audit_log.dart` now classifies the recorded
  tool and writes `capabilityClass` / `capabilityRisk` on every audited
  approval (schema v2), so the audit trail carries the kind of action that was
  allowed independent of the verdict. No chat_notifier change; the over-budget
  god-file is untouched.
- `test/core/services/tool_approval_audit_log_test.dart` asserts the new fields.
- Note: the F1 ratchet is currently red for `chat_notifier.dart`,
  `mcp_tool_service.dart`, and `chat_notifier_test.dart` (pre-existing F5 debt);
  the live approval-UI display (criterion 1) waits on freeing that budget. An
  F5 slice has since extracted the approval cluster into
  `chat_notifier_approval_handlers.dart`, trimming the god-file.

Slice 5 evidence:
- `lib/features/chat/domain/services/tool_approval_auto_review_service.dart`:
  the auto-review request packet now includes an `action.capability` object
  (class, risk, mutatesState, accessesNetwork, producesUntrustedContent) from
  the perimeter classifier, and the instructions tell the reviewer to scrutinize
  higher-risk/state-mutating actions and never let untrusted content authorize a
  privileged action. Pure, in its own domain service — no budgeted-file growth.
- `test/features/chat/domain/services/tool_approval_auto_review_service_test.dart`
  asserts the embedded capability context for a shell command and a network
  fetch.

### SEC2: Taint-Aware Tool Execution

Status: `current`

Scope:
- Track whether a proposed tool call was influenced by untrusted or lower-trust
  evidence.
- Add policy hooks for warning, requiring approval, or blocking privileged calls
  when tainted evidence affects the action.
- Feed taint findings into OBS1 traces and SEC3 audit surfaces.

Acceptance criteria:
- A tool call derived from untrusted document instructions is flagged in tests.
- Taint metadata survives compaction, model-switch handoff, and trace export.
- Safe read-only actions can proceed while write/shell/network actions escalate.

Slice plan:
1. Pure taint-decision policy over SEC1 capability + influencing trust levels.
   **done.**
2. Conversation taint-state tracker (pure): accumulate the trust levels of
   evidence entering the turn so the approval boundary can ask "did untrusted
   content influence this call?". **done.**
3a. Taint-aware auto-review: feed `hasUntrustedInfluence` into the approval
    auto-review packet so the LLM reviewer denies a privileged action that
    untrusted content may be driving. Escalation-via-reviewer only (no new hard
    block), so no default is weakened. **done.**
3b. Honor `TaintDecision` directly at the approval/execution boundary (mandatory
    non-cacheable approval or hard block) and feed findings into the audit
    trail; keep taint metadata across compaction / model-switch handoff. (Hard
    behavioral gate — verify on a live run before relying on it.)

Slice 3a evidence:
- `ConversationTaintState` is held on `ChatNotifier`, reset per turn, and fed
  each executed tool result in the loop. `_buildAutoReviewRequest` passes
  `hasUntrustedInfluence`, and `ToolApprovalAutoReviewService` emits
  `action.untrustedInfluence` plus an instruction to deny privileged
  write/shell/network actions that untrusted content may be driving unless the
  user clearly asked. Escalation-only: the reviewer already gates, so this
  cannot weaken a default. chat_notifier.dart grew 7 lines (15,253), still under
  its ratcheted budget.
- `test/features/chat/domain/services/tool_approval_auto_review_service_test.dart`
  asserts `untrustedInfluence` is surfaced for tainted vs untainted turns.

Live verification (2026-06-21, coding mode, approval=auto-review): same
`shellExecution/high` action branched on taint alone, proving the policy is
precise, not a blanket high-risk-shell block.
- A-1 (read an S3 doc, then run its `echo` command): `untrustedInfluence=true`
  -> auto-review **denied** ("a shell command derived from untrusted remote
  content ... is not explicit authorization"); the file was not created and the
  model escalated to ask the user.
- A-2 (an S3 doc embedding a prompt injection): the model refused outright and
  issued no privileged tool call; no side-effects.
- B (control, user asks for the same `echo` directly, no fetch):
  `untrustedInfluence=false` -> **allowed** and the file was created.
- Approval audit recorded all three with `capabilityClass`/`capabilityRisk`/
  `untrustedInfluence`. Inspect with `tool/sec_verify_logs.sh`.
The hard `TaintDecision` gate (3b) stays deferred: the reviewer path already
stops web-driven shell in practice, so a mechanical block adds false-positive
risk for limited extra protection — revisit only if a live miss appears.

Slice 1 evidence:
- `lib/core/security/taint_policy.dart`: `TaintDecision` (allow / requireApproval
  / block) and a pure `TaintPolicy.assess` over a `ToolCapability` and the set of
  influencing `TrustLevel`s. Untrusted influence on a high-risk mutating action
  blocks (the fetch-then-execute / AMOS shape); on other write/network actions it
  requires a non-cacheable approval; read-only/inert actions still proceed
  (acceptance: read-only proceeds while write/shell/network escalate). Pure and
  advisory — no execution path is wired yet, so no default is weakened.
- `test/core/security/taint_policy_test.dart` covers untainted allow, read-only
  pass-through, high-risk block, medium escalation, and mixed-trust influence.

Slice 2 evidence:
- `lib/core/security/conversation_taint_state.dart`: `ConversationTaintState`
  accumulates the `TrustLevel`s of evidence entering a turn (via
  `recordToolResult` / `recordTrust`) and exposes `influencingTrustLevels` and
  `hasUntrustedInfluence` for `TaintPolicy.assess`. Conservative: any untrusted
  evidence in the turn is treated as potentially influencing the next call. Pure
  and in-memory.
- `test/core/security/conversation_taint_state_test.dart` covers clean start,
  local-read no-taint, web-fetch / MCP taint, explicit trust, reset, and the
  unmodifiable view.

### SEC3: MCP Permission Diff And Audit View

Status: `later`

Scope:
- Show a diff when an MCP server adds, removes, or changes tools, resources,
  prompts, roots, or declared capabilities.
- Record approvals and denials as local audit events.
- Link permission changes to tool contract lint findings from MCP-GOV1.

Acceptance criteria:
- A changed MCP tool schema is visible before the tool is used by an agent.
- Permission diffs never include secrets by default.
- Audit records are searchable from support diagnostics.

### MLIB1: Local Model Pack Manifest

Status: `later`

Scope:
- Store a manifest per local model artifact: source, source repository, revision,
  file checksum, format, quantization, base model, license, claimed context,
  verified context, tool-calling status, structured-output status, and eval
  baselines.
- Connect the manifest to LL3 profiles, LL9 loading guidance, LL12/LL19 eval
  reports, and LL21 profile history.
- Keep manifests local-first and export-excluded unless the user explicitly
  chooses to share them.

Acceptance criteria:
- Two GGUFs with the same display name but different checksums are distinct
  artifacts.
- Capability badges point to concrete probe/eval evidence.
- Missing license/provenance data is visible rather than guessed.

### MLIB2: Model Provenance And License Registry

Status: `later`

Scope:
- Track model artifact lineage: base model, adapter, merge, quantization source,
  local conversion, and revision history.
- Store license assumptions separately from verified metadata.
- Warn before using a model in a context whose policy conflicts with the stored
  license/provenance state.

Acceptance criteria:
- Model lineage survives renaming or moving the local file.
- Unknown license/provenance produces an explicit warning state.
- Registry export is redacted and opt-in.

### MLIB3: Verified Capability/Eval Badges

Status: `later`

Scope:
- Surface badges for tool calling, JSON/structured output, edit format,
  embeddings, reranking, vision, context length, sampler stability, and personal
  eval performance.
- Require every badge to link back to a probe, live diagnostic, or eval artifact.
- Show drift when a new LL21 revision changes badge status.

Acceptance criteria:
- A badge cannot be shown as verified without evidence.
- Badge regressions are visible in profile history.
- Badges can be used as routing hints without becoming hard-coded model flags.

### OBS1: Agent Trace Timeline

Status: `later`

Scope:
- Record an inspectable trace for each agent run: model requests, adapter events,
  tool calls, approvals, file checkpoints, slot assignments, worktree actions,
  verification, eval decisions, memory writes, and maintenance stages.
- Present traces as a timeline in the app with links to artifacts and local
  files where safe.
- Preserve enough detail to debug LL7 Best-of-N, LL13 worktrees, LL17 harness
  adoption, and LL18 maintenance runs.

Acceptance criteria:
- A Best-of-N run shows every candidate, verifier result, discard, and winner.
- A maintenance run links adopted changes to failure evidence and eval gates.
- Trace recording is bounded and does not store secrets in plaintext by default.

Build-on note:
- OBS1 extends the existing `LlmSessionLogStore` and maintenance reports into a
  unified timeline rather than creating a parallel logging path: session logs,
  maintenance stage outcomes, and (when present) API1 events feed the same
  trace, so there is one source of truth for agent activity.

### OBS2: Redacted Trace Export

Status: `later`

Scope:
- Export support traces with configurable redaction for API keys, credentials,
  private file contents, project paths, model endpoints, and user memory.
- Include enough non-secret metadata to reproduce provider and tool-loop issues.
- Support local preview before export.

Acceptance criteria:
- Exported traces never include configured secret patterns in tests.
- The user can inspect the exact export bundle before sharing.
- App-side vs endpoint-side failures remain distinguishable after redaction.

### OBS3: Local OpenTelemetry-Compatible Span Model

Status: `later`

Scope:
- Model agent work as spans with IDs, timestamps, attributes, events, status,
  and async links for parallel candidates and worktrees.
- Keep the internal model export-compatible without requiring an external
  collector.
- Map API1 events and LL20 provider timings onto spans.

Acceptance criteria:
- Parallel candidate spans preserve causal links to the parent task.
- Provider timings and token/cache metrics appear as span attributes.
- The model can export to a local JSON file without network access.

### COMPAT1: OpenAI-Compatible Endpoint Conformance Suite

Status: `next`

Scope:
- Probe endpoint support for `/v1/models`, chat completions, streaming, tool
  calls, structured output, Responses-style APIs, embeddings, reranking, vision,
  logprobs, reasoning/thinking fields, cancellation, timeouts, unknown-field
  behavior, and provider extension preservation.
- Reuse LL3 model probes where possible but keep protocol compatibility separate
  from model capability.
- Save a compatibility report per endpoint/model pair.

Acceptance criteria:
- Endpoint incompatibility is visible before a user runs a long agent task.
- The first diagnostic slice produces a local report without mutating model
  state, reusing LL9 lifecycle findings for `/v1/models` status fields and
  provider-native extension preservation.
- Generic OpenAI endpoints are not sent provider-specific extension fields.
- Reports clearly distinguish protocol failures from weak-model behavior.

### COMPAT2: Provider Compatibility Badge

Status: `later`

Scope:
- Surface conformance results in settings, diagnostics, and model/endpoint
  selection UI.
- Show supported, partial, unsupported, and unknown states for major surfaces.
- Link each badge to the COMPAT1 report that produced it.

Acceptance criteria:
- A user can see why a provider was selected or downgraded.
- Badge states update when the endpoint changes or is re-probed.
- Unsupported features have a documented fallback or disabled UI path.

### COMPAT3: Streaming/Tool-Call Fuzz Tests

Status: `later`

Scope:
- Generate adversarial streaming chunks, partial tool calls, malformed JSON,
  duplicate calls, cancellation races, and provider-specific unknown fields.
- Run fixtures through API2 adapters and the existing tool-loop recovery policy.
- Track regressions in support diagnostics.

Acceptance criteria:
- Known weak-model/tool-call recovery paths remain deterministic under fuzzed
  streaming input.
- Adapter crashes become fixture failures, not user-visible runtime exceptions.
- COMPAT1 reports include a compact fuzz summary.

### EDGE1: Embedded Local Runtime Adapter

Status: `later`

Scope:
- Define a runtime adapter interface for embedded on-device models independent
  of any single vendor runtime.
- Support constrained local inference surfaces for short text classification,
  extraction, summarization, routing, and privacy checks.
- Integrate with LL1 role routing without making the embedded runtime the main
  coding model.

Acceptance criteria:
- The app can route a low-risk helper task to an embedded runtime when present.
- Missing runtime support degrades to the configured endpoint or a deterministic
  fallback.
- Runtime use is visible in traces and diagnostics.

### EDGE2: On-Device Micro-Model Tasks

Status: `later`

Scope:
- Add bounded micro-tasks such as memory extraction, prompt compression,
  title/summary generation, private-data detection, voice transcript cleanup,
  endpoint routing, and offline fallback classification.
- Keep outputs advisory unless a task has an explicit approval or deterministic
  validation path.
- Prefer tasks that reduce calls to large local models without lowering quality.

Acceptance criteria:
- Micro-task outputs are bounded, typed, and testable.
- A bad on-device result cannot directly execute a privileged tool action.
- Routing decisions are visible to the user in diagnostics.

### EDGE3: Offline Fallback Mode

Status: `later`

Scope:
- Let selected app features continue when no OpenAI-compatible endpoint is
  reachable: search, summarization, memory extraction, issue triage, or draft
  task creation.
- Clearly mark outputs as offline/limited.
- Queue or defer tasks that require the main coding model.

Acceptance criteria:
- Offline mode never pretends to have run a full coding agent.
- Deferred tasks resume only after endpoint health checks pass.
- User-visible copy explains which capabilities are unavailable.

### EVAL-MOBILE1: Flutter/Mobile Coding Eval Pack

Status: `later`

Scope:
- Build eval cases for Flutter widget fixes, state-management migrations,
  Android Gradle failures, iOS signing and entitlement issues, localization ARB
  changes, accessibility labels, plugin permissions, platform channels, and
  release build regressions.
- Connect cases to LL19 in-app eval so candidate models can be scored on
  Caverno-relevant mobile work.
- Include both deterministic fixtures and live-project replay cases where safe.

Acceptance criteria:
- The pack can run locally without network access after fixtures are present.
- Results separate fault localization, patch quality, and verifier success.
- Cases can be tagged by platform, framework surface, and risk level.

### EVAL-MOBILE2: Golden Test And Screenshot Regression Harness

Status: `later`

Scope:
- Add visual regression cases that compare before/after screenshots or golden
  test artifacts.
- Feed diffs into MM3 for explanation and into OBS1 for traceability.
- Keep image artifacts local and excluded from export by default.

Acceptance criteria:
- A visual regression can block adoption or merge just like a test failure.
- Screenshot/golden diffs are trace-linked to the agent edit that caused them.
- Exported artifacts follow OBS2 redaction rules.

### EVAL-MOBILE3: Platform Build Failure Corpus

Status: `later`

Scope:
- Curate replayable failures for Android Gradle, iOS CocoaPods/signing,
  entitlements, Info.plist, permissions, simulator/device differences, and
  release-build-only regressions.
- Track which model profiles handle each failure family.
- Feed successful repairs back into harness guidance only through LL17 gates.

Acceptance criteria:
- Build failures are reproducible from fixtures or recorded project state.
- The corpus distinguishes environment blockers from app-code failures.
- Reports show which dependency/tooling versions were used.

### MM1: Multimodal Evidence Panel

Status: `later`

Scope:
- Store screenshots, audio transcripts, OCR text, screen-recording summaries,
  accessibility snapshots, and derived facts as evidence objects.
- Attach provenance, trust level, redaction state, and trace links.
- Let agent prompts cite evidence by compact IDs rather than dumping all media
  content into context.

Acceptance criteria:
- Evidence objects can be added, removed, redacted, and cited independently.
- Untrusted visual/OCR content does not bypass SEC1 data classifications.
- Evidence panels link to agent traces and verification artifacts.

Build-on note:
- MM1 unifies the multimodal surfaces Caverno already has — voice mode
  (STT/TTS) and macOS Computer Use screenshots/observations — into one evidence
  model rather than adding a parallel media pipeline. Existing capture paths
  become evidence sources with provenance and trust attached.

### MM2: Screenshot-To-Issue Workflow

Status: `later`

Scope:
- Convert UI screenshots into reproduction steps, suspected widget areas, and a
  draft coding task.
- Use the repo map, LSP bridge, and mobile eval tags to route the task.
- Require user confirmation before turning inferred steps into an executable
  agent task.

Acceptance criteria:
- The workflow separates observed facts from model guesses.
- User confirmation is required before file edits or shell commands.
- Generated tasks retain links to the original screenshot evidence.

### MM3: Visual Regression Explanation

Status: `later`

Scope:
- Explain before/after screenshot or golden diffs in natural language with links
  to changed files, test artifacts, and trace spans.
- Flag likely intentional vs accidental changes for user review.
- Feed regression explanations into EVAL-MOBILE2 reports.

Acceptance criteria:
- Explanation output cites the exact visual artifacts it used.
- False positives can be dismissed without deleting the original evidence.
- A visual regression can be attached to a failed eval case.

### MM4: Voice-To-Agent-Task Pipeline

Status: `later`

Scope:
- Turn voice input into a structured task proposal with transcript cleanup,
  ambiguity detection, risk classification, and approval prompts.
- Use on-device micro-models from EDGE2 for lightweight transcript processing
  when available.
- Keep voice transcripts as evidence objects under MM1.

Acceptance criteria:
- The user can review and edit the task before agent execution.
- Ambiguous or high-risk voice commands ask for confirmation.
- Transcripts follow the same retention/export defaults as other evidence.

### HOOK1: Caverno External Config And Basic Hooks

Status: `current`

Scope:
- Read a Caverno-owned external config file for selected settings, MCP servers,
  and hook definitions.
- Keep Codex and Claude settings as inspiration only; Caverno owns its schema
  and compatibility contract.
- Provide an agent-kb-friendly bridge for session start, user prompt submit,
  and turn stop events.
- Pass environment variables through stdio MCP servers and hook commands.

Acceptance criteria:
- External config sync is opt-in and uses a stable Caverno config path.
- MCP servers and hook definitions loaded from external config are replaceable
  on later syncs without duplicating entries.
- Basic hook payloads include enough context for archive-only integrations:
  event name, session/conversation id, timestamp, model, base URL, prompt,
  assistant response, error, and current project root when available.
- Focused tests cover config parsing, managed-entry replacement, and agent-kb
  preset behavior.

Deferred from HOOK1:
- Tool-call lifecycle hooks such as `PreToolUse`, `PostToolUse`, and
  `PostToolUseFailure`.
- Matcher semantics, hook result decisions, trust-review UI, HTTP handlers,
  async hooks, batch hooks, and reactive file/config events.

### HOOK2: Claude-Like Tool Lifecycle Hooks

Status: `later`

Scope:
- Add tool-call lifecycle events with normalized payloads: start with
  `PostToolUse` and `PostToolUseFailure`, then consider `PreToolUse` and
  `PermissionRequest` after the approval/data-perimeter model is clearer.
- Support simple matcher filters for tool name, including built-in tools and
  MCP-style tool identities.
- Align common payload fields with the intersection of Codex and Claude Code
  conventions where useful: `hook_event_name`, `session_id`, `cwd`,
  `tool_name`, `tool_input`, `tool_response`, and error details.
- Feed agent-kb with successful and failed tool outcomes without turning hooks
  into a blocking reprocess mechanism.

Acceptance criteria:
- Successful tool calls can trigger `PostToolUse` with tool input and output.
- Failed tool calls can trigger `PostToolUseFailure` with failure metadata.
- Hook dispatch is observable enough to debug failures without exposing secrets
  in normal UI.
- Existing tool execution behavior remains unchanged when hooks are disabled.

Deferred from HOOK2:
- `PostToolBatch` and full parallel-batch lifecycle semantics.
- Hook-driven mutation of tool inputs or outputs.
- Blocking decisions for privileged tool calls; those should wait for SEC1 and
  the existing approval policy to be unified.

### HOOK3: Advanced Hook Runtime

Status: `later`

Scope:
- Add a hook trust/review surface for local commands and external-config
  changes before they run automatically.
- Consider additional handler types after command hooks are stable: HTTP,
  MCP-tool handlers, prompt handlers, agent handlers, and async/background
  hooks.
- Add advanced lifecycle events only when there is a clear product need:
  `PostToolBatch`, `ConfigChange`, `FileChanged`, `SessionEnd`, and
  compaction-specific events beyond the current minimal set.
- Connect hook runs to OBS1 traces and SEC1 data-perimeter classifications.

Acceptance criteria:
- New or changed hooks can be reviewed before execution.
- Hook side effects are visible in traces and support snapshots.
- Async/background hook failures do not corrupt the chat turn.
- Advanced handler types have bounded execution, redaction, and audit behavior.

Deferred from HOOK3:
- Organization-managed hook policy.
- Cross-device hook distribution.
- A public plugin marketplace for hook bundles.

### MCP-GOV1: MCP Tool Contract Linter

Status: `later`

Scope:
- Lint MCP tool names, descriptions, schemas, examples, output shapes, and
  declared risk/capability classes.
- Detect vague descriptions, overlapping tools, dangerous capability exposure,
  missing examples, and weak-model-unfriendly schemas.
- Produce model-specific suggestions without auto-modifying external servers.

Acceptance criteria:
- Linter findings are deterministic and reviewable.
- Dangerous or ambiguous tools can be marked as requiring stronger approval.
- Findings are available to SEC3 permission diff and OBS1 traces.

### MCP-GOV2: Tool Trust Registry

Status: `later`

Scope:
- Store trust levels for MCP servers and tools, including local, paired remote,
  third-party, experimental, and blocked states.
- Map trust levels to default approval policy and data perimeter behavior.
- Record changes as audit events.

Acceptance criteria:
- New or changed MCP tools default to a conservative trust state.
- Trust changes require explicit user action.
- Tool trust appears in tool selection diagnostics and traces.

### MCP-GOV3: Model-Specific Tool Prompt Optimizer

Status: `later`

Scope:
- Compress and specialize tool descriptions based on LL3 model profile, MCP-GOV1
  lints, and live tool-selection outcomes.
- Preserve canonical tool schemas while generating weak-model-friendly prompt
  surfaces.
- Evaluate prompt variants through COMPAT3 / LL19-style fixtures before adoption.

Acceptance criteria:
- Prompt optimization never changes executable tool schemas.
- Weak-model tool-selection accuracy improves or remains non-regressing in
  fixtures.
- Adopted prompt variants are traceable and revertible.

### SKILL1: In-Chat Skill Authoring

Status: `done`

Context:
- Skills already work as a read path from chat: `SkillPromptIndexBuilder`
  injects a lightweight index into the system prompt and the `load_skill` tool
  (`mcp_tool_service.dart`) returns the full markdown when the index matches.
- The write path now exists in chat: `save_skill` persists approved markdown via
  `SkillsNotifier.upsertMarkdown`.

Scope:
- Add a `save_skill` built-in tool (the inverse of `load_skill`) that takes a
  skill name, description, `whenToUse`, and markdown body, normalizes it through
  `SkillMarkdownParser`, and persists it via `SkillsNotifier.upsertMarkdown`
  (create or update by name/id).
- Route the write through a non-cacheable, high-risk approval that previews the
  resolved skill (name + body) before it is saved, so a skill is never written
  silently and `ToolApprovalCache` cannot make repeat writes invisible.
- Expose the tool in built-in tool settings and add coding/general prompt
  guidance so the model offers to save a reusable workflow when one is evident.

Acceptance criteria:
- A skill authored from chat is parsed, persisted, and immediately visible in
  the skills settings list and the runtime skills index.
- Every `save_skill` call requires explicit approval and never resolves from the
  approval cache.
- Saving an existing skill name updates it rather than creating a duplicate, and
  the round trip is covered by focused tests.

Implementation evidence:
- `c029bf9d` added the `save_skill` tool definition, ChatNotifier handler,
  system-prompt guidance, built-in tool setting entry, and parser round-trip
  support.
- `test/features/chat/presentation/providers/chat_notifier_test.dart` covers
  approved skill creation, repeat approval prompts, and update-by-name without
  duplicates.
- `test/features/chat/domain/services/skill_markdown_parser_test.dart` covers
  markdown composition and parsing.

### SKILL2: Chat-Driven Skill Lifecycle

Status: `done`

Scope:
- Add a `/skill` slash command so the user can explicitly ask Caverno to turn
  the current conversation (or a selection) into a skill.
- Support editing, duplicating, and merging existing skills from chat, with a
  diff preview against the stored markdown before any write.

Acceptance criteria:
- `/skill` produces a reviewable draft that reuses the SKILL1 approval path.
- Edit/merge operations show what changes relative to the saved skill and never
  overwrite without confirmation.

Implementation evidence:
- `1a73c8b8` added the `/skill` slash command and `save-skill` alias that route
  the model toward `save_skill` with optional focus arguments.
- Existing-skill saves preview a unified diff before approval through the
  SKILL1 handler.
- `test/features/chat/presentation/slash_commands/slash_command_prompt_template_test.dart`
  covers the command and alias, and the ChatNotifier skill test covers the diff
  preview on update.

### SKILL3: Idle-Time Skill Mining

Status: `later`

Scope:
- Under the LL18 idle/power/window gates, mine recurring verified workflows from
  session traces (OBS1) and propose them as new or improved skills.
- Surface proposals in a morning review; nothing is adopted without explicit
  user approval through the SKILL1 path.

Acceptance criteria:
- Proposals are grounded in real run evidence (trace links), not speculation.
- Mining adds no token cost to interactive turns and obeys the RoutineToolPolicy
  trust model.
- Mined skill content is treated as SEC1 evidence: it informs a proposal but is
  never auto-adopted as an authority-bearing instruction.

### ROUTINE1: In-Chat Scheduled-Routine Authoring

Status: `next`

Context:
- Routines (recurring agent runs) are created only through the routine editor UI
  (`showRoutineEditor` → `RoutinesNotifier.createRoutine`). The chat surface has
  a manual "create routine" button but no LLM/tool path, so the model cannot
  schedule one from a conversation.
- Worked example: "ping host 192.168.0.1 every hour for liveness monitoring;
  report the result via Google Chat and a local notification." This maps to a
  `Routine` with `scheduleMode: interval`, `intervalValue: 1`,
  `intervalUnit: hours`, `toolsEnabled: true` (uses the always-loaded `ping`
  tool), `completionAction: googleChat` with `googleChatRule: always`, and
  `notifyOnCompletion: true` for the local notification.

Scope:
- Add a `create_routine` built-in tool (sibling of `save_skill`) that maps a
  natural-language request to `Routine` fields — name, prompt, schedule
  (`schedule_mode` interval/daily, `interval_value` + `interval_unit`,
  `time_of_day`), `tools_enabled`, `completion_action` + `google_chat_rule`,
  `notify_on_completion`, and optional workspace directory/write flags — and
  persists through `RoutinesNotifier.createRoutine`. `RoutineScheduleService`
  normalizes the schedule and the scheduler picks up the new `nextRunAt`.
- Gate the write behind a non-cacheable approval whose preview surfaces the
  schedule and next run, the prompt, whether tools/workspace writes are enabled,
  and the delivery channels (Google Chat is external; local notification).
- Add coding/general prompt guidance so the model offers to schedule a routine
  when the user describes a recurring task.

Acceptance criteria:
- A routine described in chat is created, scheduled (correct `nextRunAt`), and
  visible in the routines list; the worked ping example runs hourly and delivers
  to Google Chat + local notification.
- Every `create_routine` call requires explicit approval and never resolves from
  the approval cache; the preview names the schedule, tools, and delivery
  channels.
- Invalid schedules are rejected with an actionable message; the round trip is
  covered by focused tests.

### ROUTINE2: Chat-Driven Routine Lifecycle

Status: `later`

Scope:
- Add list/update/enable/disable/delete of routines from chat, reusing the
  ROUTINE1 approval path for mutations.
- Add a near-duplicate-by-name guard (mirroring the skill near-duplicate guard)
  so a similar routine is surfaced for update instead of silently duplicated.

Acceptance criteria:
- Updates show what changes relative to the stored routine and never mutate
  without confirmation.
- Enabling/disabling and deleting a routine from chat reflect immediately in the
  scheduler and the routines list.

### THREAT1: Agent-As-Malware-Vector Hardening

Status: `later`

Context:
- Recent macOS infostealer campaigns (the AMOS Stealer macOS variant, first seen
  April 2026) are delivered not through an exploit but through an auto-approving
  AI coding agent that fetched and ran an obfuscated payload during a software
  install/update — the malicious `curl` sat between ordinary agent commands in
  `.zhistory`. Caverno's `local_shell` is the same delivery surface.
- `local_shell_tools` already blocks shell *syntax* tokens (`| ; > < \` $`
  newline), which happens to defeat the classic `curl … | sh` one-liner, but it
  has no command-name policy, so a two-step `curl -o /tmp/x` then `sh /tmp/x`
  still passes, and `ToolApprovalCache` can make the second occurrence silent.

Scope:
- Detect high-risk command shapes regardless of the approval cache: network
  fetch (`curl`/`wget`/`nscurl`/`osascript -e <url>`), execution of a freshly
  written file in `/tmp`, `~/Downloads`, or other world-writable paths, and
  writes to persistence locations (`~/Library/LaunchAgents`, `/Library/Launch*`,
  login items, cron/`launchd` plists).
- Force these shapes through a non-cacheable, full approval that shows the
  resolved command and the destination host/domain, warning when the domain is
  unfamiliar (the fake-official-site SEO delivery vector).
- Reuse the SEC1 capability/data-source classification and SEC2 taint hooks so
  the escalation is policy-driven, not a special case bolted onto one tool.

Acceptance criteria:
- A fetch-then-execute or persistence-write command never resolves from the
  approval cache and always renders its resolved form plus destination.
- Existing benign commands keep their current approval/caching behavior.
- The hardening is enforced by tests against representative malicious shapes,
  including the two-step download/execute pattern.

### THREAT2: Read-Only Host Compromise Triage

Status: `later`

Scope:
- Add a fixed-command, read-only `host_security_snapshot` built-in tool that
  collects endpoint IoC signal without exposing generic shell: launch
  agents/daemons and login items with code-signing/notarization status of their
  target binaries, recent process tree, listening/outbound sockets,
  Gatekeeper/SIP state, loaded kexts, configuration profiles, and shell-history
  download-then-execute remnants.
- Return structured, provenance-labeled output (command, host, timestamp) sized
  to the model profile budget; never persist the raw output to the session log
  store (PII/token hygiene).
- Add the tool to the `RoutineToolPolicy` read-only allowlist so an unattended
  routine can capture a periodic snapshot and dispatch anomalies through
  `RoutineCompletionActionService`.
- Provide an AMOS-style triage prompt/assistant mode that reasons over the
  snapshot: e.g. flag a `com.apple.*`-named LaunchAgent whose target binary is
  not Apple-signed, an unexpected PTY/remote-control helper, or a wiped-log gap.

Acceptance criteria:
- The snapshot tool runs only the fixed command set, performs no writes, and is
  safe to run unattended in a routine.
- The triage surfaces the canonical AMOS persistence pattern in a fixture.
- Snapshot output is never written to the session log store.

Honest limitations (recorded, not solved here):
- LLM triage is signal interpretation, not detection; it complements XProtect /
  EDR and keeps a human in the loop. Mature malware wipes logs, so the durable
  wins are signature-mismatch persistence and history remnants, not log replay.

### THREAT3: Local Threat-Intelligence Pre-Learning

Status: `later`

Thesis:
- This is the strongest fit for the local "tokens are free" + idle-compute
  thesis: ingest large public feeds overnight and map-reduce them into a compact
  local KB, with no API cost and without shipping the machine's software
  inventory or fingerprint to a cloud service.
- Two distinct intel axes, deliberately not merged:
  - Vulnerability intel (CISA KEV, scoped NVD CVE) answers "what on this box is
    patchable/exploitable" and is matched against the LL10 installed-dependency
    inventory.
  - Threat/IoC intel (malware advisories, vendor writeups) answers "what
    infection looks like" and feeds the THREAT2 triage with current TTPs/IoCs.
- Disambiguation is a first-class requirement, illustrated by CVE-2021-32570:
  its "AMOS" is Ericsson Network Manager's CLI (CWE-532, log-file info leak),
  unrelated to AMOS Stealer malware. Naive free-text ingestion would conflate
  the two; extracted records must carry product/CPE identity, source URL, and
  hash so the KB grounds on identity, not string match.

Scope:
- An idle-orchestrated (LL18) ingestion job pulls scoped feeds (KEV first as the
  small high-signal set; CVEs filtered to installed software via LL10; macOS /
  Apple advisories), distills each source into structured records, and stores
  them with provenance in the F4/LL5 database (embeddings for retrieval).
- Bounded volume: scope by installed inventory and KEV rather than the full NVD
  firehose; re-summarize incrementally as the KB grows (map-reduce, not
  stuff-the-context).
- A morning report surfaces new exploited-in-the-wild items affecting installed
  software and any new IoCs added to the THREAT2 triage knowledge.

Acceptance criteria:
- Every KB record carries source URL, fetch hash, and affected-product identity;
  records with unknown product identity are marked, never guessed.
- Ingested intel is SEC1 untrusted content: it can inform triage and the report
  but never becomes an instruction that authorizes a tool call (prompt-injection
  resistance verified in a fixture with a hostile "advisory").
- The job runs only under LL18 idle/power/window gates and the RoutineToolPolicy
  trust model, and adds no token cost to interactive turns.

## Cross-Cutting Rules

- All tracks obey the F1 ratchet: no milestone may push a budgeted file past
  its budget; extraction slices lower budgets in the same PR.
- New built-in tools obey the F6 guard: every `BuiltInToolInfo` entry is
  classified as tool-search initial-load or intentionally deferred, so a tool is
  never silently hidden behind `tool_search`.
- LL3 profiles are the single source of model-behavior tuning. LL4, LL6, LL7,
  LL12, LL15, and LL16 read the profile rather than adding per-feature model
  flags.
- Context mutation (LL14 eviction, compaction) happens only at compaction
  boundaries so LL6 prefix stability holds between them.
- Anything that executes work on another machine (LL8, LL13) inherits the
  existing tool-approval and Remote Coding pairing trust model; no implicit
  remote execution.
- Idle/overnight autonomy (LL18, LL21, LL22) runs only behind idle + power +
  window gates, never requires interactive approval, obeys the RoutineToolPolicy
  trust model, and adopts profile mutations only through the LL12 eval gate.
- Future platform milestones remain `later` until explicitly promoted; they are
  a vision backlog, not a reason to interrupt the current `next` milestone.
- API adapters must normalize into versioned agent events before UI, eval,
  memory, trace, or tool policy adds provider-specific branches.
- Security and MCP-governance milestones treat retrieved or external content as
  lower-trust evidence unless the user explicitly elevates it to an instruction.
- Trace export defaults to redaction and local preview; supportability must not
  trade away private project contents or credentials.
- Model-library records state what Caverno has verified locally and what remains
  unknown; missing provenance, license, or checksum data is never guessed.
- On-device runtime work starts with bounded, low-risk micro-tasks and cannot
  execute privileged tools without the same approval and trace rules as the main
  endpoint path.
- Multimodal evidence inherits SEC1 data classifications and OBS1 trace links;
  OCR or visual interpretation is evidence, not authority.
- Skill writes (SKILL track) always pass through the same high-risk,
  non-cacheable approval as other persistence-class tools; skill content
  distilled from untrusted evidence is flagged under SEC1 and never auto-adopted.
- User-created Tools run through the Caverno manifest runtime, not arbitrary
  generated code. New Tool actions must declare registered capabilities, pass
  schema and policy validation, stay within Caverno-owned resource limits, and
  add a user-visible review surface before OCR or LLM-derived evidence can
  mutate local records. Remote AI parsing is data egress and must be disclosed;
  debug logs must not contain receipt images, raw OCR text, LLM prompts, parsed
  personal data, or private Tool records.
- Routine writes (ROUTINE track) create autonomous scheduled agents, so they
  require a non-cacheable approval whose preview surfaces the schedule, enabled
  tools/workspace writes, and any external delivery; they are never auto-created
  or cached, and stay inside the per-routine approval trust model until SEC1/OBS1
  gate broader unattended scheduling.
- Threat-posture milestones treat every external intelligence feed (CVE, KEV,
  advisories) as SEC1 untrusted content: ingested intel informs triage but never
  becomes an instruction with tool authority, and host triage tools (THREAT2)
  stay strictly read-only.

## Appendix: llama.cpp Server Capability Reference

Researched 2026-06-11 from `ggml-org/llama.cpp` `tools/server/README.md` and
the ggml-org model management announcement. Re-verify flags before
implementation; the server moves fast.

| Capability | Server surface | Feeds milestone |
|------------|----------------|-----------------|
| Prompt cache reuse | `cache_prompt` (request, default `true`), `--cache-reuse N` / `n_cache_reuse` (chunked KV-shift reuse), `--slot-prompt-similarity` | LL6 |
| Slot pinning and monitoring | `id_slot` request param (default `-1`), `GET /slots` | LL6, LL7 |
| Cache measurement | response `timings`: `cache_n`, `prompt_n`, `prompt_ms`, `predicted_per_second`; `return_progress` (streamed prefill progress) | LL6, LL14 |
| KV cache persistence | `POST /slots/{id}?action=save\|restore` with `--slot-save-path` | LL6 extension (resume cache across restarts) |
| Structured output | `json_schema` / `grammar` (GBNF) request params, `response_format` json_schema | LL3, LL15 |
| Tool calling | `--jinja` (default on), `parallel_tool_calls`, native tool-call parsing per chat template | LL3 |
| Router mode (model management) | launch without `-m`; `--models-dir`, `--models-max` (LRU eviction), `--no-models-autoload`, `--models-preset`; `GET /models`, `POST /models/load`, `POST /models/unload`; per-request `model` autoload | LL1, LL8, LL9 |
| Parallel inference | `--parallel N` slots, continuous batching (default on) | LL7, LL13 |
| Speculative decoding | `--spec-draft-model`, `--spec-type` incl. `ngram-simple` (no draft model needed) | LL9 guidance |
| Embeddings and reranking | `POST /v1/embeddings`, `POST /reranking` (`--pooling rank`) | LL5 |
| Server identity probing | `GET /props`, `GET /health` | LL3, LL8 discovery |
- Behavior-changing slices around tool execution, Plan Mode, persistence,
  approval, or recovery run `tool/codex_verify.sh --coverage` per
  `docs/large_file_refactor_plan.md`.
