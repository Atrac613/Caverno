# Caverno Roadmap

This roadmap is the cross-track index for Caverno implementation work. It keeps
milestone identifiers stable so planning notes, test reports, and release
handoffs can refer to the same unit of work over time.

## Milestone Conventions

- Use `PM<number>` for Plan Mode milestones.
- Keep `M<number>` for the existing macOS Computer Use milestones documented in
  `docs/macos_computer_use_helper_architecture.md`.
- Use `F<number>` for Foundation (refactoring, dependency currency, storage)
  milestones and `LL<number>` for Local LLM Agent milestones, both documented
  in `docs/local_llm_agent_roadmap.md`.
- Use `API<number>`, `SEC<number>`, `MLIB<number>`, `OBS<number>`,
  `COMPAT<number>`, `HOOK<number>`, `RAG<number>`, `EDGE<number>`,
  `EVAL-MOBILE<number>`, `MM<number>`, `MCP-GOV<number>`,
  `SKILL<number>`, and `ROUTINE<number>` for future platform vision
  milestones, also documented in `docs/local_llm_agent_roadmap.md`.
- Use `KC<number>` for Knowledge Currency milestones — training-cutoff
  exposure measurement, environment ground truth in the prompt, and
  version-delta documentation — also documented in
  `docs/local_llm_agent_roadmap.md` with a full design in
  `docs/knowledge_currency_track_design.md`.
- Use `TOOL<number>` for the user-created Tools workspace and manifest runtime
  milestones documented in `docs/tools_mvp_roadmap.md`.
- Use `HEU<number>` for text-heuristic removal milestones — replacing prose
  pattern matching with ground truth, structured self-report, or structured
  elicitation so decisions stop being bound to the languages someone happened
  to enumerate — documented in `docs/text_heuristic_inventory.md`.
- Use `FORK<number>` for conversation fork/branching (chat + coding)
  milestones documented in this file under "Conversation Fork Track".
- Use `CLI<number>` for the headless runtime and user-facing terminal client
  milestones documented in this file under "Caverno CLI Track".
- Use `WATCH<number>` for the Apple Watch companion milestones documented in
  this file under "Apple Watch Companion Track", with the shipped design in
  `docs/apple_watch_companion.md`.
- Use `ANA<number>` for Anabasis orchestrator milestones — epistemic grounding,
  task decomposition, delegation, and acceptance — documented in this file
  under "Anabasis Orchestrator Track", with the design in
  `docs/ANABASIS_ORCHESTRATOR_ARCHITECTURE.md`.
- Use `DX<number>` for repository developer-efficiency milestones — reducing
  model-visible command output while preserving complete diagnostics —
  documented in this file under "Codex Developer Efficiency Track".
- Use one of these statuses: `done`, `current`, `next`, `blocked`, `later`.
- Every active milestone should record scope, acceptance criteria, verification
  evidence, and the next action.
- Prefer small follow-up commits that complete one milestone slice at a time.

## Active Focus

| Track | Milestone | Status | Goal | Next action |
|-------|-----------|--------|------|-------------|
| Plan Mode | PM3 | done | Finish scenario harness decomposition and keep deterministic smoke coverage stable. | Keep the extracted support modules covered while working on report quality. |
| Plan Mode | PM4 | done | Make deterministic Plan Mode reports easy to review and fail for actionable warnings. | Keep warning reasons and quality blockers aligned across suite report formats. |
| Plan Mode | PM5 | done | Stabilize live Plan Mode smoke runs against OpenAI-compatible endpoints. | Keep the PM5 live gate in the release checklist while preparing the MVP handoff. |
| Plan Mode | PM6 | done | Convert Plan Mode deterministic and live evidence into an MVP handoff. | Use the MVP handoff during release review and choose the next Plan Mode milestone before new implementation. |
| Plan Mode | PM7 | done | Turn the MVP handoff into a product release readiness gate. | Use the release checklist for Plan Mode release review. |
| Plan Mode | PM8 | done | Make live gate failures operationally easy to triage. | Use the PM5 gate artifact index and failure triage order during release review. |
| Plan Mode | PM9 | done | Polish product UX for saved plans, approval, execution progress, recovery, and completion. | Keep task state guidance visible while expanding scenario coverage. |
| Plan Mode | PM10 | done | Expand Plan Mode scenario coverage beyond the MVP smoke and ping canary gate. | Use the scenario coverage rules before promoting canaries into smoke. |
| Plan Mode | PM11 | done | Validate model and endpoint compatibility for Plan Mode product use. | Use compatibility notes before classifying live failures as app regressions. |
| Plan Mode | PM12 | done | Define the final release candidate gate. | Use the release candidate gate for final Plan Mode sign-off before opening a new productization track. |
| Plan Mode | PM13 | done | Execute the Plan Mode release candidate gate and record the sign-off decision. | Use the PM14 rerun warning sign-off to drive PM15 manual UX review. |
| Plan Mode | PM14 | done | Burn down release candidate blockers and warnings. | Keep the PM14 evidence attached to the PM13 rerun sign-off. |
| Plan Mode | PM15 | done | Finalize the Plan Mode product UX. | Use the PM15 UX sign-off while starting PM16 settings and compatibility guidance. |
| Plan Mode | PM16 | done | Productize settings and compatibility guidance. | Use the settings preflight copy while starting PM17 supportability. |
| Plan Mode | PM17 | done | Improve supportability for user and reviewer reports. | Use the support snapshot while preparing PM18 release packaging. |
| Plan Mode | PM18 | done | Prepare Plan Mode release packaging. | Use the release package while defining PM19 post-release guardrails. |
| Plan Mode | PM19 | done | Define post-release guardrails. | Use the guardrails for scheduled monitoring and open new PM milestones only when post-release evidence requires it. |
| Plan Mode | PM20 | done | Refresh the release candidate decision with final PM5 gate evidence. | Use the final sign-off as the current Plan Mode productization baseline. |
| Computer Use | M31R | done | Refresh the current Computer Use evidence baseline before element-grounded work. | Run `bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs`. |
| Computer Use | M52 | done | Ship element-grounded Computer Use through the product release rollout. | Use `bash tool/run_macos_computer_use_m52_product_release_rollout.sh` for final product release evidence. |
| Computer Use | M53 | done | Keep post-release Computer Use operations guarded after product rollout. | Use `bash tool/run_macos_computer_use_m53_post_release_guardrails.sh` for scheduled post-release evidence. |
| Computer Use | M54 | done | Decide whether post-release Computer Use rollout can expand safely. | Use `bash tool/run_macos_computer_use_m54_rollout_expansion_gate.sh` for rollout expansion evidence. |
| Computer Use | M55 | done | Review post-expansion Computer Use evidence and decide whether to continue, hold, pause, or roll back. | Use `bash tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh` for post-expansion monitoring evidence. |
| Computer Use | M56 | done | Hand off the approved post-expansion rollout decision to the next user-operated rollout branch. | Use `bash tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh` for rollout decision handoff evidence. |
| Remote Coding | RC0 | done | Ship the P0 LAN mobile control safety gate for existing desktop coding projects. | Keep the P0 regression gate, including SEC4.5b `transportContainment`. Pinned WSS landed in SEC4.5c. |
| Remote Coding | RC1 | current | Add authenticated confidential transport, downgrade rejection, bounded unauthenticated connections/frames, reconnect resilience, support diagnostics, and multi-device evidence. | SEC4.5g same-device pending-interaction ownership is complete. Continue with reconnect resilience and product-promotion evidence. |
| Caverno CLI | CLI0 | done | Establish a no-window production-path canary and freeze the terminal execution contract. | Keep the passing three-headless-plus-one-macOS comparison gate as the shared CLI baseline. |
| Caverno CLI | CLI1 | done | Extract a shared application execution runtime without changing GUI behavior. | Use the shared typed runtime and CLI1 parity evidence as the terminal frontend boundary. |
| Caverno CLI | CLI2 | done | Ship the interactive terminal MVP on the shared execution runtime. | Preserve the passing terminal and three-headless-plus-one-macOS parity gates as the CLI2 baseline; keep persistence, resume, and concurrent ownership in CLI3. |
| Caverno CLI | CLI3 | done | Reuse production persistence and enforce cross-process ownership before conversation resume. | Preserve the persistence, resume, migration-retry, and direct-lock contention gates as the CLI3 baseline. |
| Developer Experience | DX1 | done | Bound Flutter-test output for coding agents while preserving complete reports and actionable failure diagnostics. | Keep the quiet wrapper as the default test path and retain tested streaming-plus-capture behavior for `--verbose`. |
| Developer Experience | DX2 | done | Make repository discovery summary-first without weakening exact follow-up searches or `rg` exit semantics. | Keep `tool/codex_rg.sh` for broad discovery and raw `rg` for exact or security-sensitive follow-up. |
| Developer Experience | DX3 | done | Make selected long-running release, build, and live-canary entrypoints log-first for agent runs. | Agents use `--quiet-output`; human-operated commands retain raw streaming by default. |
| Developer Experience | DX4 | done | Reduce broad source and Git reads through progressive inspection rather than lossy evidence summarization. | Maintain the locate-then-read and stat-then-diff guidance; add tooling only if future evidence shows repeated over-reading. |
| Heuristic Removal | HEU1 | done | Make production release approval decidable only from a structured answer, never from prose. | Landed in `ef6af66d`: approval is decided by a per-release token, prose predicates run in shadow, and a six-language table asserts the coordinator verdict. Watch `[ProductionRelease] Shadow divergence` before deleting the predicates. |
| Heuristic Removal | HEU2 | done | Stop discarding structured tool evidence at the claim-notice boundary. | Landed in `9cc6b68c`: `outcome` survives the freeze, reviving the typed mutation path, the no-op-mutation check, and the structured test-count path. HEU3 is unblocked. |
| Heuristic Removal | HEU3 | blocked | Completion claims. Premise corrected 2026-08-27: ground truth verifies a claim but cannot detect one, so this needs structured self-report or unconditional fact-stating, not a conversion. | Baseline taken: file-claim guards fire 2-3 times in 715 turns and the narrated-transcript guard never has; the measured substitute collapsed from 22 to 3 turns once harness-injected results were separated from refusals. Prerequisite instrument landed 2026-09-02: `ToolResultOrigin` makes 17 producers declare harness-feedback vs policy-refusal, and `tool/analyze_tool_results.py` reports the split plus the undeclared codes. Building it found three producers no hand-maintained list contained, one of them the corpus's most frequent. Still blocked: the declaration has to accumulate in post-change sessions before a refusal rate is readable, and the self-report design remains unmade. |
| Heuristic Removal | HEU4 | later | Git write confirmation. Measured 2026-08-27: 8 of 12 confirmation questions go unrecognised, including two in English and Japanese, so the assistant asks and commits without waiting. | Held deliberately: there is no token to route to, and the structural fix is moving confirmations onto `ask_user_question` rather than replacing a predicate. Blast radius is bounded by the (cacheable) git approval gate. |
| Heuristic Removal | HEU5 | later | Replace the tool-role acceptance carve-outs. | Blocked on the tool-role regeneration measurement; do not change on current evidence. |
| Heuristic Removal | HEU6 | later | Reduce proposal, goal-suggestion, and memory-extraction prose parsing. | Largest surface, lowest stakes; may stay best-effort by decision. |
| Caverno CLI | CLI4 | later | Package and release the terminal client with automation-grade diagnostics. | The F5 dependency is satisfied; resume with macOS archive, launcher, checksum, and packaged-process gates, and require the signed packaged doctor for promotion. |
| Tools | TOOL0 | next | Add the Tools product surface as an empty workspace without changing LLM tool-calling behavior. | Start with navigation, naming, localization, and a safe empty state; keep manifest runtime and creation flows for TOOL1+. |
| Foundation | F1 | done | Add a CI-enforced line-count ratchet for oversized files so god-file growth reverses instead of compounding. | Lower budgets in the same PR whenever a refactor slice shrinks a budgeted file. |
| Foundation | F2 | done | Extract the tool-call loop from `ChatNotifier` behind a handler registry shared with routines and subagents. | Use the extracted dispatcher, policies, and routine batch executor as the baseline for F3, LL6, and LL7. |
| Foundation | F3 | done | Keep major dependencies current, starting with `openai_dart` 6.x. | `openai_dart` is on 6.2.0; remaining major upgrades (serious_python 2, etc.) are tracked as isolated follow-up slices. |
| Foundation | F5 | current | Stabilize package boundaries while continuing behavior-preserving large-file decomposition. | Characterize the unowned `NetworkTools` route, interface, and path-MTU cluster selected by the 2026-07-18 full boundary inventory before extracting code. |
| Local LLM | LL1 | done | Route secondary LLM calls (memory extraction, subagents, goal suggestions, approval auto-review) to a configurable small model. | Surface the routing settings in user docs when LL9 model guidance lands. |
| Local LLM | LL2 | done | Whole-turn file-change checkpoints with one-action revert. | Keep checkpoint store and UI rollback coverage green while using LL2 as the safety net for later agent changes. |
| Local LLM | LL3 | done | Persist model capability profiles, run bounded probes on model selection, and feed profile guidance into agent prompts. | Use the LL3 profile-injection canary evidence as the baseline for LL4, LL6, LL7, and LL15. |
| Local LLM | LL4 | done | Repo map v1: ranked, compressed symbol outline injected into the coding-mode system prompt. | Now precomputed/cached during idle via LL22. |
| Local LLM | LL6 | done | KV-cache-friendly prefix-stable request mode. | Stable tool list across loop iterations shipped; runtime `id_slot` pinning is deferred to LL20. |
| Local LLM | LL12 | done | Personal eval harness (offline CLI) to score new models on recorded tasks. | In-app recorder/replay shipped in LL19. |
| Local LLM | LL14 | done | Context surgery: stale tool-result eviction, file-read dedup, model-switch handoff brief. | Eviction stays at compaction boundaries to preserve LL6 prefix stability. |
| Local LLM | LL15 | done | Weak-model edit harness: grammar-constrained edit blocks and per-model exemplars. | Edit failure-rate telemetry feeds the LL3 profile. |
| Local LLM | LL16 | done | Sampler auto-calibration: probed per-role temperature/sampler presets with runtime feedback. | LL21 idle re-probe provides the recovery path for runtime step-downs. |
| Local LLM | LL17 | done | Self-improving harness loop: mine failure traces, propose minimal harness edits, eval-gated adoption. | High-stakes surfaces require manual review; runs as an LL18 idle stage. |
| Local LLM | LL18 | done | Idle/overnight maintenance orchestrator chaining probe -> calibrate -> eval -> mine -> propose -> adopt. | LL22 appends the trailing precompute/warm-up stages. |
| Local LLM | LL19 | done | In-app personal eval recorder and replay executor with held-in/held-out split. | Bake-off verdict surfaced in the cases UI. |
| Local LLM | LL21 | done | Continuous idle re-probing and profile history with model-drift detection. | Profile history UI lives in the live LLM diagnostic page. |
| Local LLM | LL22 | done | Idle warm-up and precompute: cache the repo map and warm the prefix KV cache so the first morning turn is fast. | Use `tool/ll22_warmup_measurement.dart` to record cold-vs-warm `prompt_ms`. |
| Local LLM | LL23 | done | Declared per-model harness config (instruction surfaces + runtime control policy) as the closed schema LL17 edits. | Focused coding-goal repeat canary and the Qwen3.6 main LLM gate are green after saved-validation preservation and active-task target-scope hardening. |
| Local LLM | LL20 | done | Parallel slot execution substrate: preserve provider extension fields, pin `id_slot`, run `--parallel N` candidates. | Unblocked LL7 (Best-of-N) and LL13 (parallel worktrees); compose the slot transport/discovery/executor providers. |
| Local LLM | LL7 | done | Best-of-N patch generation gated by verification, plus overnight retry-until-green Routines. | Sequential checkpoint/verify with a consolidated report; a one-tap Routines UI preset and LL13-parallel generation are deferred follow-ups. |
| Foundation | F4 | done | Migrate conversations/chat memory from Hive to drift (SQLite) with FTS5 history search. | Migration + drift backend + FTS history search UI shipped and verified; retiring Hive is a deferred follow-up. Branch `feature/f4-drift-migration` integrated into main. |
| Foundation | F6 | done | Guard the built-in tool catalog against silent tool-search omissions: every built-in tool must be explicitly classified as initial-load or intentionally deferred, enforced in CI. | Exhaustiveness test shipped; initial-load is now metadata-driven from `BuiltInToolRegistry` (deferral sets owned there, hand-maintained allowlist removed, new registry tools default to initial). 18 non-registry built-ins remain in a small explicit set; folding them into the registry is the only leftover. |
| Local LLM | LL5 | done | Local semantic history search via `/v1/embeddings`, stored in the F4 drift database. | Conversation history indexed + drift vector store + hybrid semantic/FTS history search UI + semantic-aware `search_past_conversations` shipped and device-verified; degrades to lexical FTS when no embeddings endpoint exists. Semantic *code* search is now owned by RAG1-RAG3. Branch `feature/ll5-semantic-search` merged to main. |
| Retrieval | RAG1 | done | Establish a versioned retrieval, answer-grounding, latency, resource, and token evaluation contract before production RAG work. | Completed on 2026-08-25. Clean lexical, vector/hybrid, answer/citation, resource, and token measurements are consolidated in `docs/rag1_completion_audit_2026-08-25.md`; the known-bad arm remains detectable and production retrieval is unchanged. Its raw no-answer result remains frozen, while RAG2 later replaced that promotion question with passage-role scoring. |
| Retrieval | RAG2 | done | Index active-project code and Markdown as provenance-bearing Knowledge Objects in additive drift/SQLite + FTS5 storage. | Complete caller-declared roots, Git-backed acquisition, atomic generation storage, durable Drift/SQLite hosting, incremental FTS5, identity-scoped MATCH, and provenance projection are Go. The frozen v1 raw no-answer decision remains No-Go. The unchanged candidate passes the separately committed v2 passage-role holdout with 14/14 answer support, 4/4 Japanese support, 2/2 expected abstention, zero only-irrelevant unavailable cases, and 3,776/6,000 context tokens. RAG2 offline lexical retrieval is Go; runtime passage role remains unknown and production wiring stays deferred to RAG3. Evidence: `docs/rag2_investigation_handoff_2026-08-25.md`. |
| Retrieval | RAG3 | blocked | Add bounded vector retrieval, weighted RRF, context budgeting, and an active-project `search_knowledge` tool. | No measured candidate is eligible. The frozen hybrid candidate failed the unavailable-evidence gate; deterministic score, intent, and cross-arm policies lack a support signal; verbose semantic filtering misses the latency gate; compact v3 misses both quality and latency gates. Current candidate families are closed. Persistence, tools, prompts, promotion, and runtime wiring remain blocked. Evidence: `docs/rag3_post_v3_entry_contract_2026-09-01.md`. |
| Retrieval | RAG3R | next | Determine whether a dedicated post-answer groundedness detector is materially new, locally runnable, and capable of meeting the frozen RAG3 gates. | Start with artifact, license, runtime, and one synthetic five-evidence feasibility probe for Beyond Document Grounding, MiniCheck, and FactCG. Only a runnable candidate with a credible path to p95 <= 1,200 ms may receive a separately frozen 20-case non-promotion contract. Reuse KC1's truth-versus-grounding label separation, but do not couple KC1 delivery to RAG3. No production or promotion wiring. Research: `docs/rag_groundedness_detector_research_2026-09-01.md`. |
| Retrieval | RAG4 | blocked | Federate agent-kb memories and wiki pages with current local project evidence through the existing reviewed stdio MCP boundary. | Keep databases separate, label historical versus current authority, fail open to local search, and require additive versioned `kb_search` provenance plus a distinct Caverno source identity. HOOK2 is not a prerequisite. Blocked upstream: `kb_search` returns no timestamp, wiki hits carry no confidence or source agent, and agent-kb archiving rejects any agent outside `{claude, codex}`. |
| Retrieval | RAG5 | later | Evaluate deterministic `none`/local/agent-kb/both routing in shadow before automatic retrieval changes prompts or cost. | Activate routes only after precision, recall, unnecessary-retrieval, answer-quality, latency, and token gates pass. |
| Retrieval | RAG6 | later | Decide whether optional local reranking or ANN vector search is justified by measured quality and scale. | A documented No-Go is successful completion when 20k latency/RSS or reranker quality/VRAM gates do not justify new dependencies. |
| Knowledge Currency | KC1 | current | Measure claim correctness, not only tool coverage: classify version-sensitive prose and code-artifact claims, compare asserted values with a fixture oracle, and record separate truth (`correct` / `stale` / `unscorable`) and grounding (`supported` / `contradicted` / `absent`) verdicts plus prompt/tool/none provenance. | First slice landed 2026-09-03: paired replay, disk-derived oracle, negative control, separate truth/grounding axes, classes 2 and 4. Over 60 claims the asymmetry is the result — naming the dependency took class 4 from 100% stale to 0%, while naming the version left class 2 unmoved at 58% against 65%. KC2 should carry what changed, not which version. Three measurements now: a delta block carrying *what changed* cut stale claims 76% to 28% and fixed every API it covered and none it did not, and an offline replay of the same responses showed a post-generation symbol index catches 25 of 25 deprecation-class stale usages — including the one the block could not reach — while flagging 14 of 30 correct answers on bare-name collisions, which is why KC4's verdict must come from LL11 rather than the pattern that triggered it. Next: class 1 needs a networked oracle and class 3 a different verdict shape; the §4 gate stays open until both. Evidence: `docs/knowledge_currency_track_design.md` §§ First/Second/Third measurement. |
| Knowledge Currency | KC2 | next | Push measured toolchain and dependency ground truth into the prompt while preserving the datetime anchor that `SystemPromptBuilder` already emits unconditionally. | Content settled by KC1's second measurement 2026-09-03: carry **what changed**, not only which version — a delta block cut stale claims from 76% to 28% over 75 claims, fixing every API it covered and none it did not. The version list stays because it is what fixes class 4. The open question is now coverage, not mechanism: recency window, project imports, or the symbols a draft actually used. Extract a shared LL10 dependency inventory, attest locked versus installed versions as exact/mismatch/unverifiable, omit non-exact versions from authoritative context, cache by project/metadata fingerprints, and keep the block in the dynamic tail. |
| Knowledge Currency | KC3 | later | Extend LL10 with installed version-delta evidence: bounded CHANGELOG/migration sections and declared deprecations from the attested local package source. | The lookup already exists as a prototype: `tool/kc1_cutoff_oracle.dart` answers KC3's stated acceptance case — the symbol exists in both versions but the installed one deprecates it — so what KC3 adds is the LL10 response envelope and containment, not the resolution. Close the deprecated-but-still-present blind spot without a second resolver or knowledge store. Add a new public tool name only if tool-discovery evaluation rejects an LL10 query mode; preserve containment, provenance, and response budgets. |
| Knowledge Currency | KC4 | later | Nominate cutoff-sensitive claims from visible prose, response code blocks, changed dependency-using code, and LL11 deprecation diagnostics; let only ground-truth evidence render the verdict. | The nomination stage is measured (KC1's third measurement, 2026-09-03): a symbol index catches 25 of 25 deprecation-class stale usages, misses only staleness that is not a symbol at all, and flags 14 of 30 correct answers on bare-name collisions — so the "verdict from ground truth only" clause is load-bearing, not boilerplate, and LL11 `deprecated_member_use` is what must decide. Reuse existing recovery plumbing with a bounded turn-evidence adapter for artifacts. Annotate rather than block when verification is unavailable. Shadow precision and recall must include a stale API that appears only in edited code. |
| Knowledge Currency | KC5 | later | Record a per-model `knowledgeCutoff` date and its source so the gap can be stated as context and used to nominate verification. | Never from self-report and never treat the date as proof that a specific claim is stale. `unknown` recorded honestly beats a probed number nobody trusts; whether an LL39-style dated-fact probe can beat a static table is open. |
| Local LLM | LL8 | done | LAN inference mesh: discover and register OpenAI-compatible endpoints, route secondary calls per role with health fallback. | Discovery probe (unauthenticated `GET /v1/models`) + named-endpoint registry + mesh settings UI + per-role endpoint routing for secondary calls with primary fallback shipped and device-verified. Full-mesh main-conversation fan-out and a periodic health-check loop are deferred follow-ups. Branch `feature/ll8-lan-inference-mesh` is already integrated into main. |
| Local LLM | LL9 | done | Local stack manager: model lifecycle controls and hardware-aware model guidance. | `Advanced > Local Stack` manages primary and LL8 endpoints across llama.cpp router, LM Studio, and Ollama, with role-model prepare, resource fit guidance, speedup guidance, and focused verification. |
| Local LLM | LL10 | done | Installed-dependency grounding: resolve APIs from the project's locked dependency sources, offline. | Use `tool/run_ll10_dependency_grounding_release_gate.sh` and `tool/run_ll10_dependency_grounding_live_canary.sh` to verify lockfile-exact source/docs grounding, future-only API rejection, and weak-model failure reduction. |
| Local LLM | LL11 | done | LSP bridge: post-edit diagnostics feedback and symbol data for the repo map. | Use `tool/run_ll11_lsp_language_server_smoke.sh` as the LL11 regression evidence; Dart/Swift live evidence is signed off, with TypeScript/Python rerun optional after installing their language servers. |
| Local LLM | LL13 | done | Parallel agents in isolated git worktrees, optionally distributed over the LL8 mesh. | Use `tool/run_ll13_worktree_agent_verify.sh` as regression evidence for registry persistence, recovery listing, worktree reservation/planning, `/agent` queueing and `--run`, materialization, endpoint balancing/capacity, orchestration, execution result persistence, run summaries, and review-ready visibility. Broader unattended agent-farm scheduling is deferred until SEC1/OBS1 guardrails. |
| Local LLM | LL31 | done | Turn-exit reason + completion explainer: tag every loop exit and replace blank/partial responses with a "why it stopped" explanation. Lead milestone — also the instrument that produces the evidence LL29/LL30 are gated on. | Verified against code 2026-08-07: `ToolLoopExitReason` enumerates 12 exits, `tool_loop_exit_reason.dart` carries the completion explainer, `tool/triage_session_logs.py` consumes it, and live canary turns emit `[TurnExit] reason=...`. Keep the reason set closed when new break sites land. |
| Local LLM | LL29 | later | Tool-loop failure recovery: degrade gracefully on repeated tool failures instead of aborting the whole turn (inject a recovery hint and keep iterating; hard halt is opt-in). | Demoted 2026-07-21 — its LL31 evidence gate came back negative (`tool_failure_abort` 1.6% of 377 turns; redundant re-reads dominate instead). Scope preserved; promote if a later triage shows the abort path rising on a weaker model. |
| Local LLM | LL30 | done | Compaction structural pre-pass: dedupe + one-line-summarize old tool results and token-budget the protected tail before summarizing. | Shipped in two slices (`297d4f52` prune, `879b46f9` tail budget). The prune alone reached the capped summary half (`docs/ll30_prune_reaches_the_capped_half_2026-07-21.md`); the tail token budget is where post-compaction tokens actually fall. Anti-thrashing back-off and attachment eviction remain deferred follow-ups. |
| Local LLM | LL33 | current | Turn provenance: correlate the session log to the on-screen conversation (turnId + assistantMessageId) and record applied post-LLM transforms (guard notices), so log↔UI is traceable and guard firings are a direct triage signal instead of inferred from leaked notice prose. | Landed correlation keys + transform record + triage distribution; extend transforms to truncation/file-save/recovery next, defer Level 3 event-sourcing. |
| Local LLM | LL34 | done | Structured tool-result envelope: preserve producer-owned command, filesystem, process, diagnostic, and verification facts across the tool boundary; prefer those facts in guards and compact weak-model prompts while keeping outcome-free third-party MCP results on a measured lexical fallback. | Implementation and rollout are complete: direct rich first-party producers, typed-first consumers with provenance, current-turn mutation-backed file claims, outcome-preserving replay paths, session-log shadow markers, and an LL23 per-model summary-first toggle. Fresh grounded LAN canaries on `qwen3.6-27b-vision` recorded five typed comparisons across raw-first and summary-first runs (exit 1 x3, exit 0 x2), all `agree`, with no missing or disagreeing verdicts; the model-scoped summary-first MVP passed while the global default remains off. The deterministic measurement reduces estimated prompt tokens by 62.8%. |
| Local LLM | LL35 | done | Explicit goal-state tool with a real acknowledgement: goal terminal state now comes from a finally reconciled `update_goal(completed:/blocked_reason:/message:)`, all-completed structured tasks, or the user-confirmation path. Continuations prefer the typed active task and otherwise mine the first unchecked bounded `## Task checklist` item. Local-first: tool-call fidelity is an LL3 probe, and per-model `tool` / `tool_or_ask` / `ask` policy makes budget/no-work confirmation a first-class completion path. | Tool/ack/owner-safe finalization, denominator logging, next-step selection, fidelity profile storage, per-model settings/UI, confirmation summaries/actions, blocker/paused-cap persistence, and lexical terminal demotion are complete. The LL36 model-varied corpus expanded the final shadow sample to 37 comparisons (28 agree, 9 explained tool-accepted/lexical-missed, 0 lexical-only, 0 unknown), then removed the now-redundant lexical comparator and runtime marker producer. Historical markers remain triageable. |
| Local LLM | LL36 | done | Instrument for LL37 (as LL31 was for LL29/LL30) — heuristic demotion and firing audit: label every remaining lexical guard, emit an LL33 transform record on each firing, bar guards from setting terminal state, and delete lexical paths on measured firing records instead of on argument. | Complete: model-varied clean evidence measured 12 runs, 37 goal turns, 68/68 LL34 agreements, and real transform firings. The lexical goal-completion path was removed, prose workflow progress was made structurally advisory, and triage now reports deduplicated workflow failure-evidence sources. Pending-action recovery and the outcome-free third-party failure fallback remain by explicit No-Go decisions. Four post-change canaries passed on two models and two coding surfaces (`docs/ll36_delete_by_measurement_2026-08-10.md`). |
| Local LLM | LL37 | done | Objective verification for unattended runs only: the route-diverse panel runs at idle via LL18 against goals completed by routines / overnight retry-until-green / LL13 agents. No inline stage — while a user is present, LL35's confirmation rung is cheaper and more accurate than a local verifier. | Two measured routes pass the ten-case fidelity gate, converge through bounded persisted votes, and expose a privacy-filtered repair packet. Explicit confirmation can queue a distinct LL13 repair task without mutating or automatically running the source. LL13, Routine, and retry-until-green now feed the read-only fail-closed source. Scheduled Routines capture explicit objective contracts, successful mechanical verification, bounded content-hashed changed files, and implementation evidence. The LL7 retry preset rolls back failed candidates, preserves the green winner, and persists its frozen report; unavailable workspace tools fail closed. Legacy/incomplete records stay excluded and interactive chat remains structurally isolated. Parallel fan-out, automatic repair execution/retries, and strategist passes are separate future enhancements, not LL37 completion requirements. |
| Local LLM | LL38 | done | Mid-turn interruption (steering): a message typed while a turn is running joins that turn instead of waiting behind it, opt-in per send (`sendMessage(interrupt: true)`) so the queue keeps its owner-receipt contract. The interaction generation never advances, so the turn keeps its owner, tool results and partial output and no partial-response recovery path fires; an interruption no request ever carried is handed back to the queue at turn teardown. | Live-verified on `qwen3.6-35b-a3b-vision` with a queued control arm (`tool/run_turn_steering_live_canary.sh`); delivery and obedience are asserted separately. Extended 2026-08-07 to restart mid-stream, so an answer being written can be interrupted rather than only the gaps between requests (`docs/turn_steering_midstream_design.md`, 3/3 arms live). Reading the plain-chat path that document flagged as unverified then found three defects in the restart — a leftover subscription restarting a turn busy running a tool, a concurrent thread's stream cancelled by an interruption aimed elsewhere, and a tools-off turn re-issued tool-aware — all fixed by binding the stream to its turn owner. |
| Local LLM | LL32 | later | Deferred subdirectory instruction and skill discovery: surface newly reachable `CLAUDE.md` / rules / skill files as paths only, once per session, when a tool touches a path outside the startup discovery chain. | Corroborated 2026-07-21 by Grok Build shipping the same design; stays behind the Grounded Verification Track. |
| Local LLM | LL41 | later | Deterministic goal verification contract: a goal may carry a user-declared verification command (plus acceptance criteria) whose exit code is ground truth for the auto-continue stop decision. No verifier or judge is added — LL37's "no inline stage while a user is present" decision stands. | Gate: promote only once an LL31 turn-exit triage measures how often interactive goals end in `awaitingConfirmation` or stop on `noProgress`; today's evidence is a single session, not a rate. Scoped 2026-09-01. |
| Platform Vision | API1 | later | Normalize Chat Completions, Responses-style APIs, and local-provider extensions into one Agent Event Core. | Promote only after the current LL backlog is stable; first slice defines the event schema and replay fixture. |
| Security | SEC1 | current | Reopen the Local Agent Data Perimeter where the audit found incomplete capability and trust classification. | Classify every HTTP/browser action and result, and distinguish host-wide reads from project reads. Routine external MCP is now deny-by-default (SEC4.4c); reviewed grants remain a later slice. |
| Security | SEC2 | done | Enforce taint-aware execution before cached or full-access authorization. | SEC2.3b is complete: high-risk tainted mutations block, other tainted network/state actions require fresh approval, and cache/full-access regressions pass. |
| Security | SEC4 | current | Close the runtime trust, egress, transport, and local-data findings recorded in the 2026-08-14 audit and 2026-08-24 follow-up. | Continue SEC4.7/SA-16 supply-chain hardening. SEC4.5g completed same-device Remote Coding interaction ownership on 2026-08-24. |
| Platform Vision | OBS1 | later | Build an Agent Trace Timeline for model calls, tools, checkpoints, slots, evals, and maintenance runs. | Start before making LL13 parallel worktrees a product-facing agent-farm feature. |
| Platform Vision | COMPAT1 | next | Add an OpenAI-compatible endpoint conformance suite for protocol and provider-behavior diagnostics. | Start with a diagnostic CLI seeded by LL9 live lifecycle evidence; keep model capability separate from endpoint protocol support. |
| Platform Vision | HOOK1 | current | Caverno-owned external config and basic lifecycle hook bridge for agent-kb and other local integrations. | The SEC4.2 fail-closed import and exact-review boundary is complete. Defer tool-event parity to HOOK2 while SEC1/OBS1 establish trust and trace contracts. |
| Platform Vision | HOOK2 | later | Claude-like lifecycle hook flexibility with tool-event hooks, matchers, and normalized payloads. | Start with `PostToolUse` and `PostToolUseFailure` so agent-kb can archive successful and failed tool outcomes. |
| Platform Vision | HOOK3 | later | Advanced hook runtime: richer review UX, handler types, async execution, batch hooks, and reactive config/file events. | The SEC4.2 prerequisite is complete; keep deferred until SEC1/OBS1 define trust boundaries and trace visibility for hook side effects. |
| Platform Vision | MLIB1 | later | Store Local Model Pack manifests with provenance, checksum, quantization, license, and verified capability metadata. | Pair with LL9 model management and LL21 profile history when model-library UX becomes active. |
| Platform Vision | EDGE1 | later | Add an embedded local runtime adapter for bounded on-device micro-model tasks. | Keep first tasks low-risk and advisory: routing, memory extraction, privacy screening, and offline fallback. |
| Platform Vision | EVAL-MOBILE1 | later | Create a Flutter/mobile coding eval pack for Caverno-relevant app-development failures. | Start as local fixtures before UI productization; connect results to LL19 replay. |
| Platform Vision | MM1 | later | Treat screenshots, voice, OCR, and screen recordings as first-class multimodal evidence. | Land after SEC1/OBS1 so evidence inherits trust, redaction, and trace behavior. |
| Platform Vision | MCP-GOV1 | later | Lint MCP tool contracts for schema clarity, dangerous capabilities, and weak-model tool-selection quality. | Start before SEC3 permission diff and MCP trust-registry UX. |
| Skills | SKILL1 | done | Author skills from chat: capture the current conversation's workflow as a reusable skill via a `save_skill` tool behind a non-cacheable approval. | Shipped in `c029bf9d`: `save_skill` writes through `SkillsNotifier.upsertMarkdown`, requires fresh explicit approval, and focused tests cover create/update behavior. |
| Skills | SKILL2 | done | Drive skill lifecycle from chat with `/skill`, update-by-name, and diff-before-save review. | Shipped in `1a73c8b8`: `/skill` and `save-skill` route to `save_skill`, and existing-skill updates preview a diff before approval. |
| Routines | ROUTINE1 | done | Author scheduled routines from chat: a `create_routine` tool behind a non-cacheable approval (e.g. "ping 192.168.0.1 hourly; notify via Google Chat and a local notification"). | Shipped: `create_routine` is in the handler catalog and in the approval-required set beside `save_skill`, writing through `RoutinesNotifier` via `create_routine_notifier_runtime_store.dart` with a digest-checked receipt. ROUTINE2 owns list/update/enable/disable/delete. |
| Routines | ROUTINE2 | later | Manage routines from chat: list/update/enable/disable/delete plus a near-duplicate-by-name guard. | Start after ROUTINE1 ships; reuse the SKILL2 lifecycle pattern and the skill near-duplicate guard. |
| Routines | ROUTINE3 | next | In-chat `/loop <interval> <prompt>`: repeat a prompt inside the current conversation on an interval, keeping its history, tool-approval cache, workspace lease, and thread identity. Distinct from ROUTINE1's `create_routine`, which persists a catalog entity that runs against its own isolated context. | Reuse `GoalAutoContinueSafeBoundary` for the resend veto and honor the LL38 steering/queue owner-receipt contract; model-paced intervals and push-woken background ticks are follow-ups. Scoped 2026-09-01. |
| Skills | SKILL3 | later | Mine recurring verified workflows into proposed skills during idle windows. | Wait for LL18/OBS1 evidence so proposals are grounded in traces and remain user-reviewed before adoption. |
| Fork | FORK1 | next | Chat conversation fork: branch a new thread from any message, copying history up to that point with parent linkage and drawer grouping. | Add `parentConversationId`/fork-origin fields to `Conversation`, reuse `_createConversation`/`save`, and add a per-message "fork here" affordance. |
| Fork | FORK2 | later | Coding conversation fork: reproduce the worktree/git + LL2 file state as of the fork point into an isolated worktree/branch (never shared with the parent), with a non-git snapshot fallback. Gated on FORK1 + LL2 + LL13. | Seed a fresh worktree from the parent's turn commit or LL2 checkpoint; carry `projectId`; assign a new `worktreePath`/branch. |
| Fork | FORK3 | later | Fork-tree navigation and compare: drawer fork tree, jump-to-parent, and parent-vs-fork diff. | Start after FORK1/FORK2 ship; reuse `TurnDiff` rendering for the compare view. |
| Watch | WATCH1 | done | Apple Watch companion: approvals and questions from the wrist, a running-turn glance with cancel, dictated prompts spoken back, and Approve/Deny on the approval notification itself. | Shipped 2026-09-01 (`docs/apple_watch_companion.md`). Nothing has been run end to end yet; that is WATCH2. |
| Watch | WATCH2 | done | Prove the companion actually works: the native/Dart bridge boundary is the one seam unit tests cannot reach. Verified 2026-09-01/02 on paired simulators, including a live `ask_user_question` answered from the wrist. Ten defects surfaced, all fixed. | Closed. Approvals of the file/shell/git kinds cannot arise on iOS by design, so that path is verified through WATCH6's work or a Remote Coding turn, not here. |
| Watch | WATCH3 | done | Bind a deferred watch command to the conversation it was composed against, so a queued `sendMessage` cannot land in whichever thread happens to be current when it is finally delivered. | Shipped 2026-09-01. The watch stamps the thread; the phone refuses a mismatch with its own code and still accepts unstamped commands from older watch builds. |
| Watch | WATCH4 | done | Glanceable surfaces and thread choice: Smart Stack widget plus switching the mirrored conversation from the watch. | Shipped 2026-09-01. Thread switching is verified; the widget's App Group data path is not, because an unsigned simulator build applies no entitlements. Confirm it on a signed build. |
| Watch | WATCH5 | blocked | Approve/Deny on a push-delivered notification, not only a locally raised one. | Blocked on a contract that does not exist: no push carries an approval, only a run-completion. Do not build the delegate plumbing until a push needs to carry one. |
| Watch | WATCH6 | done | Dismiss an approval or question dialog on the phone when the watch resolves it. | Shipped 2026-09-02 and verified on paired simulators: answering from the wrist closes the phone's sheet. Dismissal pops by route name, so it is a no-op when the dialog is not topmost. |
| Watch | WATCH7 | done | Make the wrist screen a message thread rather than a status glance: bubbles with tails, relative timestamp headers, a typing indicator, and a pinned compose bar. | Shipped 2026-09-02. The frame now carries the tail of the thread; verified on the watch simulator, including the fallback for a watch newer than its phone. |
| Watch | WATCH8 | done | Keep Watch snapshots ordered across iPhone process restarts without allowing a delayed old frame to resurrect resolved state. | Completed 2026-09-04. Frames now carry a source identity and start time in addition to their per-source sequence; verified with the Watch process kept alive across an iPhone restart. |
| Watch | WATCH9 | next | Put coding-thread state on the wrist: workspace mode and the conversation goal, with `awaitingConfirmation` surfaced as an interaction to answer rather than as idle. | Re-measure maximal snapshot headroom in a multi-byte script before adding fields; the transcript already spends most of the 16 KB budget. |
| Watch | WATCH10 | next | Raise the actionable approval notification for a Remote Coding turn, so a blocked desktop agent reaches the wrist at all. Today it reaches it through no path whatsoever. | Not WATCH5: the client holds a live WebSocket, so this needs no push contract. Route the action to `RemoteCodingClientNotifier`, which `approvalNotificationActionsProvider` does not reach today. |
| Watch | WATCH11 | later | Show and resolve Remote Coding approvals and questions in the companion itself, labelled with the host that owns them. | Gate on WATCH10. Record the SEC4.5g reading — the watch is the client phone's peripheral, so the principal set does not widen — before shipping. |
| Watch | WATCH12 | later | Say what a running turn is actually doing: the tool in flight, and whether verification is behind mutation. | Needs a general active-tool field (`activeToolName` is participant-only) and evidence that the glance is under-informative. Do not start on either. |

| Anabasis | ANA0 | current | Complete the epistemic grounding: produce `assumption`/`material` on contract items, implement the `userConfirmedAssumption` confirmation path, enforce the parent's read-only tool authority, and project the result. | PRs 1 through 3d are done. Restricting the marker to what a plan asserts took marks on open questions to zero and separated the arms 67% against 17%. PR 3e then defined materiality by consequence and took its discrimination from +0.06 to +0.44, so PR 4 blocks on `material` and builds a per-assumption approval. |
| Anabasis | ANA1 | next | Decompose work into tasks with preconditions (task accepted / assumption confirmed / question resolved) and a derived `ready`. | Do not start before ANA0's canary is green. First substantially new implementation in the track. |
| Anabasis | ANA2 | later | Delegate ready tasks onto the existing `spawn_subagent` and `WorktreeAgentTask` infrastructure. | Mapping and scheduling policy only; no new execution machinery. |
| Anabasis | ANA3 | later | Separate `produced` / `verified` / `accepted` with one writer each, add parent semantic judgment, escalate user-only decisions. | Blocked on ANA1/ANA2. Requires the ownership table in the design doc §10 to be honoured. |
| Anabasis | ANA4 | later | Dedicated Anabasis workspace (`WorkspaceMode`), state panel beside the conversation. | Surface work; deliberately last so the boundary is proven before it gets a UI. |

Foundation F5 and the future platform vision milestones are
detailed in `docs/local_llm_agent_roadmap.md`. The user-created Tools MVP is
detailed in `docs/tools_mvp_roadmap.md`. Conversation fork milestones are
detailed below under "Conversation Fork Track", Apple Watch companion
milestones under "Apple Watch Companion Track", and Anabasis orchestrator
milestones under "Anabasis Orchestrator Track". Repository-side Codex output
efficiency is detailed below under "Codex Developer Efficiency Track" and is
kept separate from the in-app Local LLM milestones.

The canonical security finding record is
`docs/security_audit_2026-08-14.md`, with the current evidence and patch plan in
`docs/security_followup_review_2026-08-24.md`. Its P0 exit criteria, including
follow-up findings SA-19 and SA-20, override feature-track promotion. Schema-only
and empty Tools work may proceed independently, but TOOL effect integration,
HOOK2/HOOK3, executable integration expansion, HTML Preview promotion, and
Remote Coding product promotion remain gated by their SEC4 owner.

### Security Follow-Up Queue (2026-08-24)

| Order | Milestone | Status | Finding | Goal | Exit evidence |
|---|---|---|---|---|---|
| 1 | SEC4.4g | done | SA-19 | Separate opaque native-shell execution from project-contained commands and require fresh host-write authority before cache, auto-review, or Full Access. | Completed 2026-08-24: foreground shell execution, `background:true`, and `process_start` require fresh non-cacheable `opaque_host_write` approval; internal argv reads retain their fast path. |
| 2 | SEC4.3e | done | SA-20 | Constrain HTML Preview file exposure and active-content egress. | Completed 2026-08-24: entry-directory web assets load through a symlink-aware allowlist; CSP, response headers, and WebView interception block external egress. |
| 3 | SEC4.3f | done | SA-21 | Apply bounded streaming and decompression limits to application-owned MCP and QR inputs. | Completed 2026-08-24: MCP HTTP/stdio and parse limits are bounded; settings QR import rejects oversized Base64/compressed input and caps chunked gzip output before decoding. |
| 4 | SEC4.6k | done | SA-22 | Enforce owner-only sensitive log storage and structured diagnostic redaction. | Completed 2026-08-24: sensitive logs use owner-only modes; MCP diagnostics redact structured secrets and omit bodies; fresh installs default session logging off while stored choices remain unchanged. |
| 5 | SEC4.5g / RC1 | done | SA-23 | Recheck pending-interaction origin and enforce device ownership at resolution. | Completed 2026-08-24: paired devices are separate principals; only the active initiating device can view or resolve its pending interactions, while same-device reconnects retain access. |
| 6 | WATCH-SEC | done | SA-24 | Record the Apple Watch resolution channel and check pending origin, not just owner presence, before showing an interaction on the wrist. | Completed 2026-09-02: the watch filter now checks `origin` the way the Remote Coding gate does, so a remote interaction that lost its owner id stays off the watch. The channel itself is documented in `docs/security_followup_review_2026-08-24.md`. |

Keep each row as a separate task and focused PR. Remaining SEC4.7/SA-16 work is
still required, but follows the two High severity release blockers unless the
affected local-command and HTML Preview capabilities are absent from the release
artifact under the audit risk-acceptance policy.

## Codex Developer Efficiency Track

This track controls output produced by repository development commands and
consumed by external coding agents. It does not change Caverno's product prompt
or tool-result behavior; LL34 continues to own the in-app summary-first policy.
The measurement baseline and prioritization are recorded in
`docs/codex_output_efficiency_investigation_2026-09-04.md`.

### DX1: Flutter Test Output Summarization

Status: **done**.

- Scope: route Flutter tests through the JSON reporter, keep complete JSON and
  stdout logs, and print only a success verdict or bounded failure evidence.
- Acceptance: preserve the test exit status, surface load/compile failures and
  incomplete runs, retain a raw escape hatch, and make the quiet path the
  `tool/codex_verify.sh` default.
- Evidence: PR #188 is present in current history; the 2026-09-04 focused run
  passed 334 tests and reduced default model-visible test output from 844,725
  to 137 bytes. Five summarizer regression tests passed.
- Follow-up completed: `--verbose` now streams the expanded reporter while
  retaining the complete stdout artifact. Its streaming and default-capture
  contracts are covered by repository-side regression tests.

### DX2: Summary-First Repository Discovery

Status: **done**.

- Scope: add `tool/codex_rg.sh` for discovery searches only. Report match and
  file counts, a deterministic bounded hit set, explicit truncation, and the
  complete artifact path; retain `--raw` for exact output.
- Acceptance: preserve `rg` exit codes for matches, no matches, and errors;
  cover invalid patterns, path and binary handling, result limits, and complete
  artifact retention; measure output characters and raw follow-up frequency.
- Promotion gate: diagnosis completeness must remain intact. The wrapper must
  not replace targeted raw searches used for exact or security-sensitive review.
- Evidence: 19 repository-side tests cover the wrapper, shared output helper,
  selected scripts, and the focused verification contract.
  A 3,241-line repository search produced 1,886 visible bytes
  instead of 367,396 raw bytes, a 99.49% reduction, while retaining a
  1,341,927-byte complete JSON artifact. The `--raw` path is tested; future
  agent sessions should be sampled for raw follow-up frequency before changing
  the default limits. Non-match output modes fail closed with a `--raw`
  diagnostic, unexpected non-JSON output fails closed, and saved evidence uses
  owner-only permissions.

### DX3: Log-First Long-Running Commands

Status: **done**.

- Scope: add an agent-oriented quiet path to selected release, build, and live
  canary entrypoints that currently stream complete output.
- Acceptance: preserve the full log and exact exit status, emit bounded stage
  heartbeats, and show failure markers plus a diagnostic tail on failure. Keep
  human-operated raw output available.
- Implemented entrypoints: `tool/release_ios_macos.sh`,
  `tool/publish_macos_sparkle_release.sh`,
  `tool/run_turn_steering_live_canary.sh`, and
  `tool/run_pro_reasoning_live_canary.sh`.
- Boundary: do not begin with a generic arbitrary-command wrapper; preserve the
  release scripts' existing success/failure interpretation first.
- Evidence: the repository-side integration suite covers quiet success,
  failure status and diagnostic tails, heartbeats, raw streaming, release and
  appcast logs, and both live-canary log/snapshot paths. Existing Dart script
  contracts pass eight focused tests. Quiet execution handles SIGINT/SIGTERM,
  reaps its command and heartbeat processes, and creates logs with owner-only
  permissions.

### DX4: Progressive Source And Git Inspection

Status: **done**.

- Scope: locate files and symbols before bounded source reads, then begin Git
  review with stats and paths before inspecting material diffs directly.
- Acceptance: reduce broad reads without hiding source or diff evidence needed
  for correctness and security review.
- Evidence: the 10-session baseline found search, polling, and source reads at
  76.67% of recorded output. `AGENTS.md` and `CLAUDE.md` now require bounded
  discovery, 200-300-line source regions, stat/path-first Git review, and direct
  inspection of every material diff. No lossy source or diff wrapper was added.

## Plan Mode Track

### PM1: Deterministic Scenario Baseline

Status: `done`

Scope:
- Keep deterministic Plan Mode scenarios runnable on macOS.
- Store suite reports, logs, screenshots, and failure artifacts under
  `build/integration_test_reports`.
- Provide scenario filtering through `CAVERNO_PLAN_MODE_SCENARIOS` and tag
  filtering through `CAVERNO_PLAN_MODE_TAGS`.

Acceptance criteria:
- `host_health_scaffold` runs in fake mode.
- Scenario reports include logs, artifacts, screenshots, and diagnostics.
- Report paths are stable enough for follow-up tooling.

Evidence:
- `integration_test/plan_mode_scenario_test.dart`
- `integration_test/test_support/plan_mode_scenario_config.dart`
- `integration_test/test_support/plan_mode_suite_report.dart`

### PM2: Harness Support Module Decomposition

Status: `done`

Scope:
- Move reusable scenario helpers out of the top-level scenario test.
- Add focused coverage for pure support logic.
- Keep the parent scenario test responsible for orchestration, not low-level
  policy details.

Acceptance criteria:
- Planning decisions, post-scenario settle, failure artifacts, task drift,
  execution progress, workflow execution wait, approval UI, and proposal wait
  have focused support modules.
- Each extracted policy has a focused unit or widget test where practical.
- `flutter analyze` passes after each extraction.

Evidence:
- `integration_test/test_support/plan_mode_planning_decisions.dart`
- `integration_test/test_support/plan_mode_workflow_execution_completion.dart`
- `integration_test/test_support/plan_mode_approval_ui.dart`
- `integration_test/test_support/plan_mode_planning_proposal_wait.dart`

### PM3: Scenario Harness Completion

Status: `done`

Scope:
- Reduce `integration_test/plan_mode_scenario_test.dart` to readable scenario
  orchestration.
- Extract report assembly and file writing from `_runScenario`.
- Keep diagnostics and heartbeat completion behavior unchanged.

Acceptance criteria:
- The scenario test stays below roughly 700 lines.
- Scenario report writing is covered by focused tests.
- `host_health_scaffold` still passes on macOS after the extraction.

Evidence:
- `integration_test/plan_mode_scenario_test.dart` is reduced to roughly 680
  lines.
- `integration_test/test_support/plan_mode_scenario_reporting.dart`
- `integration_test/test_support/plan_mode_prompt_submission.dart`
- `test/integration_support/plan_mode_scenario_reporting_test.dart`
- `dart format`
- Focused report writer tests
- `flutter analyze`
- `CAVERNO_PLAN_MODE_SCENARIOS=host_health_scaffold flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact`

Next action:
- Continue with PM4 deterministic report quality checks.

### PM4: Deterministic Report Quality Gate

Status: `done`

Scope:
- Make deterministic Plan Mode reports suitable for PR review.
- Ensure warnings, task drift, artifact mismatches, and convergence failures are
  visible and actionable.
- Keep the report summary compact enough to scan.

Acceptance criteria:
- Deterministic smoke scenarios pass with expected artifacts.
- Warning policy failures identify the blocking scenario and reason.
- Suite Markdown, JSON, and XML outputs are aligned.

Evidence:
- `integration_test/test_support/plan_mode_warning_policy.dart`
- `integration_test/test_support/plan_mode_report_summary.dart`
- `integration_test/test_support/plan_mode_suite_report.dart`
- `integration_test/test_support/plan_mode_scenario_reporting.dart`
- `test/integration_support/plan_mode_report_summary_test.dart`
- `test/integration_support/plan_mode_suite_report_test.dart`
- `test/integration_support/plan_mode_scenario_reporting_test.dart`
- `fvm flutter test test/integration_support/plan_mode_report_summary_test.dart test/integration_support/plan_mode_suite_report_test.dart test/integration_support/plan_mode_scenario_reporting_test.dart`
- `fvm flutter analyze`
- `CAVERNO_PLAN_MODE_TAGS=smoke fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact`

Next action:
- Continue with PM5 live LLM smoke stabilization.

### PM5: Live LLM Smoke Stabilization

Status: `done`

Scope:
- Keep live Plan Mode runs stable against OpenAI-compatible endpoints.
- Preserve actionable timeout, stall, and convergence diagnostics.
- Validate the ping CLI convergence path and clarify/recovery paths.

Acceptance criteria:
- `live_host_health_scaffold` passes with no unexpected warnings.
- `live_clarify_recovery` demonstrates decision recovery.
- Ping CLI live canary produces the expected files and final answer.

Evidence:
- `tool/run_plan_mode_live_test.sh`
- `tool/run_plan_mode_ping_cli_live_canary.sh`
- `tool/run_plan_mode_pm5_live_gate.sh`
- `integration_test/test_support/plan_mode_live_harness_execution.dart`
- `integration_test/test_support/plan_mode_canary_summary.dart`
- `test/integration_support/plan_mode_live_harness_execution_test.dart`
- `test/integration_support/plan_mode_canary_summary_test.dart`
- `test/tool/run_plan_mode_pm5_live_gate_test.dart`
- `docs/plan_mode_ping_cli_stabilization_playbook.md`
- `fvm flutter test test/integration_support/plan_mode_canary_summary_test.dart test/integration_support/plan_mode_live_harness_execution_test.dart test/tool/run_plan_mode_pm5_live_gate_test.dart test/tool/run_plan_mode_live_test_test.dart test/integration/plan_mode_scenario_spec_test.dart`
- `fvm flutter analyze`
- `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma-4-26B-A4B-it-Q4_K_M.gguf CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma-4-26B-A4B-it-Q4_K_M.gguf CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE=1 CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- Latest ping canary report: `build/integration_test_reports/plan_mode_ping_cli_canary_1778555057/canary_summary.json`
- Latest ping canary result: 1 run, 1 passed, 0 failed, 0 warnings, 0 report quality blockers, no task drift.

Next action:
- Continue with PM6 Plan Mode MVP handoff documentation.

### PM6: Plan Mode MVP Handoff

Status: `done`

Scope:
- Convert deterministic and live evidence into a compact MVP handoff.
- Document the shortest path from local smoke to live confidence.
- Keep commands and expected artifacts discoverable from README and docs.

Acceptance criteria:
- README points to the canonical Plan Mode verification path.
- The stabilization playbook reflects the current scenario names and gates.
- MVP handoff includes deterministic status, live status, warnings, and known
  blockers.

Evidence:
- `README.md`
- `docs/plan_mode_mvp_handoff.md`
- `docs/plan_mode_ping_cli_stabilization_playbook.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the MVP handoff during release review and choose the next Plan Mode
  milestone before new implementation.

### PM7: Plan Mode Release Readiness

Status: `done`

Scope:
- Turn the PM6 MVP handoff into a release readiness checklist.
- Fix the required order for deterministic smoke, static analysis, and the PM5
  live gate.
- Make pass, warning, blocker, and exception decisions explicit enough for a
  release review.
- Keep the checklist focused on product release decisions rather than
  stabilization history.

Acceptance criteria:
- A release checklist names the exact commands to run before shipping Plan Mode.
- The checklist maps report fields to release decisions.
- Known external prerequisites are separated from app-side blockers.
- The README and MVP handoff point to the release checklist.

Evidence:
- `docs/plan_mode_release_readiness_checklist.md`
- `README.md`
- `docs/plan_mode_mvp_handoff.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the release checklist for Plan Mode release review and continue with PM8
  live gate failure operations.

### PM8: Live Gate Failure Operations

Status: `done`

Scope:
- Make PM5 live gate failures easy to triage without reading every raw log
  first.
- Connect failure classes, report paths, warning summaries, and task drift
  signals to the stabilization playbook.
- Improve scripts or docs so the latest useful artifact paths are easy to find.

Acceptance criteria:
- A failed PM5 gate points reviewers to the latest summary, suite report, and
  run log.
- Failure classes have documented first investigation steps.
- Endpoint/model availability failures are clearly separated from app workflow
  regressions.
- The playbook and release checklist agree on the failure triage order.

Evidence:
- `tool/run_plan_mode_pm5_live_gate.sh`
- `test/tool/run_plan_mode_pm5_live_gate_test.dart`
- `docs/plan_mode_release_readiness_checklist.md`
- `docs/plan_mode_ping_cli_stabilization_playbook.md`
- `README.md`
- `fvm flutter test test/tool/run_plan_mode_pm5_live_gate_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the PM5 gate artifact index and failure triage order during release
  review, then continue with PM9 product UX polish.

### PM9: Plan Mode Product UX Polish

Status: `done`

Scope:
- Review saved plan, approval, task progress, recovery, blocked, and completion
  states from a product user perspective.
- Improve user-facing copy and state transitions where the workflow is correct
  but hard to understand.
- Keep harness-only fallback behavior separate from product UI expectations.

Acceptance criteria:
- Plan approval and task progress states are understandable without reading
  harness logs.
- Blocked and recovery states explain what happened and what the user can do.
- Completion states do not leave stale or contradictory task status visible.
- Product-facing strings stay aligned with the existing English-only code and
  documentation rules.

Evidence:
- `lib/features/chat/presentation/pages/chat_page.dart`
- `lib/features/chat/presentation/widgets/plan/plan_hydrated_task_row.dart`
- `assets/translations/en.json`
- `assets/translations/ja.json`
- `test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart`
- `fvm flutter test test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart test/features/chat/presentation/widgets/plan/compact_plan_footer_card_test.dart test/features/chat/presentation/widgets/plan/timeline_plan_card_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Keep task state guidance visible while expanding scenario coverage in PM10.

### PM10: Plan Mode Scenario Coverage Expansion

Status: `done`

Scope:
- Decide which MVP-adjacent live canaries should become regular coverage.
- Keep new scenarios in canary status until they have stable diagnostics and
  clear promotion criteria.
- Evaluate whether `live_readme_first_canary` is ready for smoke promotion.

Acceptance criteria:
- Candidate scenarios are grouped as smoke, canary, or long-run coverage.
- Each new canary has artifact expectations, task drift checks, and warning
  policy expectations.
- Smoke promotion requires stable PM5 gate behavior and no recurring
  unexpected warnings.
- README and roadmap document the scenario classification rules.

Evidence:
- `docs/plan_mode_scenario_coverage.md`
- `README.md`
- `test/integration/plan_mode_scenario_spec_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/integration/plan_mode_scenario_spec_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the scenario coverage rules before promoting canaries into smoke, then
  continue with PM11 model and endpoint compatibility.

### PM11: Model and Endpoint Compatibility

Status: `done`

Scope:
- Document supported and risky OpenAI-compatible endpoint behavior for Plan
  Mode.
- Capture model differences around tool calling, JSON repair, streaming tags,
  and long-running task completion.
- Define recommended settings and known limitations for product use.

Acceptance criteria:
- Compatibility notes distinguish endpoint failures from model behavior
  limitations.
- Recommended live test environment variables and model assumptions are
  discoverable from the release docs.
- Known limitations include a suggested mitigation or a clear unsupported
  boundary.
- Compatibility findings are backed by deterministic tests, live evidence, or
  documented manual validation.

Evidence:
- `docs/plan_mode_model_endpoint_compatibility.md`
- `docs/plan_mode_release_readiness_checklist.md`
- `docs/plan_mode_mvp_handoff.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use compatibility notes before classifying live failures as app regressions,
  then continue with PM12 release candidate gate definition.

### PM12: Plan Mode Release Candidate Gate

Status: `done`

Scope:
- Define the final release candidate gate for Plan Mode.
- Combine deterministic smoke, PM5 live gate, selected canaries, compatibility
  notes, and manual UX review into one sign-off flow.
- Record the artifact bundle and decision owner expectations for release
  review.

Acceptance criteria:
- The release candidate checklist has one ordered command and review flow.
- Required artifacts and manual review notes are named explicitly.
- Exceptions require a documented reason and follow-up milestone.
- The final gate can be repeated by a reviewer who did not perform the
  stabilization work.

Evidence:
- `docs/plan_mode_release_candidate_gate.md`
- `docs/plan_mode_release_readiness_checklist.md`
- `docs/plan_mode_scenario_coverage.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the release candidate gate for final Plan Mode sign-off before opening a
  new productization track.

### PM13: Release Candidate Execution

Status: `done`

Scope:
- Execute the PM12 release candidate gate end to end.
- Record the deterministic smoke, static analysis, PM5 live gate, selected
  canary, compatibility, and manual UX review results.
- Produce a release candidate sign-off decision that can drive product release
  or focused follow-up work.

Acceptance criteria:
- The PM12 gate is run in its documented order.
- All required artifact paths are recorded in the sign-off record.
- The decision is one of `pass`, `warning`, `blocked`, or
  `blocked: environment`.
- Any warning or blocker is converted into a PM14 follow-up item or a
  documented exception with an owner.

Evidence:
- `docs/plan_mode_release_candidate_signoff_2026-05-13.md`
- `docs/plan_mode_release_candidate_signoff_2026-05-13_rerun.md`
- `docs/plan_mode_release_candidate_signoff_2026-05-13_pm14_rerun.md`
- `docs/plan_mode_live_smoke_compatibility_triage.md`
- `docs/plan_mode_release_candidate_gate.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `build/integration_test_reports/plan_mode_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_suite_macos_report.md`
- `build/integration_test_reports/plan_mode_suite_macos_report.xml`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.md`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.xml`
- `CAVERNO_PLAN_MODE_TAGS=smoke fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact`
- `fvm flutter analyze`
- `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma-4-26B-A4B-it-Q4_K_M.gguf CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- PM5 live gate result: `blocked: environment` because
  `192.168.100.241:1234` was not reachable during endpoint preflight.
- Rerun command:
  `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma4-26b-vision CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- Rerun PM5 live gate result: `blocked: environment` because
  `gemma4-26b-vision` reached live smoke but failed `live_clarify_recovery`
  with `streamDisconnect`, 5 unexpected warnings, 7 report quality blockers,
  and 1 task drift finding.
- PM14 rerun command:
  `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma4-26b-vision CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- PM14 rerun PM5 live gate result: passed with live smoke 3/3 and Ping CLI
  canary 1/1.
- PM14 rerun selected canaries: `live_readme_first_canary` passed, and
  `tool/run_plan_mode_convergence_full_pass.sh` passed focused regressions,
  static analysis, and 3 live README convergence iterations.

Next action:
- Use the PM14 rerun warning sign-off to drive PM15 manual UX review before
  promoting the release candidate decision from `warning` to `pass`.

### PM14: Release Blocker Burn-Down

Status: `done`

Scope:
- Resolve warnings and blockers found during PM13 release candidate execution.
- Keep app-side regressions, endpoint limitations, and accepted exceptions
  separate.
- Update release readiness, compatibility, or scenario coverage docs when a
  finding changes the release boundary.

Acceptance criteria:
- Every PM13 warning or blocker has a fix, documented exception, or explicit
  release deferral.
- Fixed issues include focused tests or updated release evidence.
- The release candidate gate can be rerun without the same unexplained
  warning or blocker.

Next action:
- Keep the PM14 completion evidence attached to the PM13 rerun sign-off while
  PM15 closes the remaining manual UX review warning.

### PM15: Product UX Finalization

Status: `done`

Scope:
- Polish the user-facing Plan Mode experience after RC findings are known.
- Review saved plan approval, task progress, blocked states, recovery, retries,
  and completion.
- Keep harness behavior and product behavior visibly separate.

Acceptance criteria:
- Core Plan Mode states are understandable without reading logs.
- Recovery and blocked states explain the user's next available action.
- Completion leaves no stale or contradictory task status visible.
- User-facing strings and tests cover any changed UX behavior.

Evidence:
- `docs/plan_mode_product_ux_finalization_2026-05-13.md`
- `lib/features/chat/presentation/widgets/plan/timeline_plan_card.dart`
- `lib/features/chat/presentation/widgets/plan/plan_hydrated_task_row.dart`
- `test/features/chat/presentation/widgets/plan/timeline_plan_card_test.dart`
- `test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart`
- `test/features/chat/presentation/widgets/plan/compact_plan_footer_card_test.dart`
- `test/features/chat/presentation/widgets/plan/plan_review_sheet_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/features/chat/presentation/widgets/plan/timeline_plan_card_test.dart test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart test/features/chat/presentation/widgets/plan/compact_plan_footer_card_test.dart test/features/chat/presentation/widgets/plan/plan_review_sheet_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM16 settings and compatibility UX.

### PM16: Settings and Compatibility UX

Status: `done`

Scope:
- Productize endpoint, model, API key, and preflight compatibility guidance.
- Make common environment failures understandable from settings or Plan Mode
  error surfaces.
- Preserve the PM11 compatibility boundary while reducing user confusion.

Acceptance criteria:
- Endpoint and model failures are distinguishable from Plan Mode workflow
  failures.
- Preflight failure messaging explains the configured endpoint, model, and
  next repair action.
- Settings and release docs stay aligned on supported compatibility behavior.

Evidence:
- `docs/plan_mode_settings_compatibility_ux_2026-05-13.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `lib/features/settings/presentation/pages/general_settings_page.dart`
- `assets/translations/en.json`
- `assets/translations/ja.json`
- `test/features/settings/presentation/pages/general_settings_page_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/features/settings/presentation/pages/general_settings_page_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM17 supportability.

### PM17: Supportability

Status: `done`

Scope:
- Define the diagnostic information needed for user reports and reviewer
  investigations.
- Improve access to Plan Mode logs, report paths, compatibility context, and
  troubleshooting guidance.
- Keep sensitive endpoint credentials out of exported diagnostics.

Acceptance criteria:
- A Plan Mode issue report can include non-secret settings, model identity,
  relevant artifact paths, and failure classification.
- Troubleshooting guidance maps common failures to the right release or
  compatibility document.
- Diagnostic output avoids API keys and other secrets.

Evidence:
- `docs/plan_mode_supportability_2026-05-13.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `lib/features/settings/presentation/pages/general_settings_page.dart`
- `assets/translations/en.json`
- `assets/translations/ja.json`
- `test/features/settings/presentation/pages/general_settings_page_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/features/settings/presentation/pages/general_settings_page_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM18 release packaging.

### PM18: Release Packaging

Status: `done`

Scope:
- Prepare Plan Mode release notes, user-facing documentation, known
  limitations, and screenshot or demo evidence.
- Align product copy with the final compatibility and exception decisions.
- Make the release package understandable without stabilization history.

Acceptance criteria:
- Release notes describe Plan Mode capability, requirements, and limitations.
- User-facing docs point to the supported setup and troubleshooting path.
- Store or demo assets reflect the final product behavior.

Evidence:
- `docs/plan_mode_release_package_2026-05-13.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM19 post-release guardrails.

### PM19: Post-Release Guardrails

Status: `done`

Scope:
- Define the post-release regression and canary cadence for Plan Mode.
- Set hotfix criteria for live gate failures, compatibility regressions, and
  user-reported workflow failures.
- Keep the release candidate gate reusable for future releases.

Acceptance criteria:
- Regression checks and selected canaries have an owner and cadence.
- Hotfix decision rules distinguish app regressions from endpoint or model
  availability failures.
- Future release work can reuse PM12 and PM13 artifacts without rebuilding the
  process.

Evidence:
- `docs/plan_mode_post_release_guardrails_2026-05-13.md`
- `docs/plan_mode_release_package_2026-05-13.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the guardrails for post-release monitoring and create the next PM
  milestone only from scheduled evidence or user reports.

### PM20: Final Release Candidate Evidence Refresh

Status: `done`

Scope:
- Refresh the release candidate decision after PM15 through PM19 completed the
  remaining productization work.
- Attach the latest PM5 live smoke rerun and Ping CLI canary evidence.
- Close the previous manual UX warning and the final
  `missingExpectedSavedTaskTargetFiles` live gate regression.
- Keep future PM work gated by post-release guardrail evidence, compatibility
  changes, or user reports.

Acceptance criteria:
- A final sign-off record upgrades the current Plan Mode release candidate
  decision to `pass`.
- The sign-off records the latest live smoke, Ping CLI canary, and product UX
  evidence paths.
- README and docs tests point reviewers to the final sign-off.
- The roadmap names PM20 as the current productization baseline.

Evidence:
- `docs/plan_mode_release_candidate_final_signoff_2026-05-13.md`
- `docs/plan_mode_product_ux_finalization_2026-05-13.md`
- `docs/plan_mode_release_package_2026-05-13.md`
- `docs/plan_mode_post_release_guardrails_2026-05-13.md`
- `build/integration_test_reports/plan_mode_live_suite_macos_1778676005689/plan_mode_live_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_ping_cli_canary_1778676312/canary_summary.json`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`

Next action:
- Use the final sign-off as the current Plan Mode productization baseline and
  open new PM milestones only from scheduled guardrail evidence, compatibility
  changes, or user reports.

## Caverno CLI Track

The long-term goal is a supported `caverno` terminal client for chat, coding,
and Plan Mode. The product CLI must reuse Caverno's execution behavior rather
than wrapping a test command or maintaining a second tool loop.

The current repository provides two useful but incomplete starting points:

- Coding Live canaries run `ChatNotifier` inside a `ProviderContainer` through
  `flutter test` without launching a desktop application window. They already
  exercise live OpenAI-compatible requests, built-in coding tools, session
  logs, Goal Auto-Continue, and independent artifact verifiers.
- Production-path Plan Mode canaries run
  `integration_test/plan_mode_scenario_test.dart -d macos`. They exercise the
  app composition and Plan Mode workflow path but launch the macOS app and keep
  test-only approval bypasses in the integration harness.
- `lib/main.dart` currently owns Flutter binding, localization, Hive,
  SharedPreferences, drift migration, window restoration, and provider
  overrides in one GUI composition root. A supported Dart executable cannot
  depend on that bootstrap unchanged.
- Pending approvals are represented as state and completed by UI listeners.
  A terminal frontend therefore needs an explicit approval presenter rather
  than implicit approval when no dialog is available.

Target architecture:

```text
Flutter GUI ---------+
                     +--> Caverno execution runtime --> LLM and tool policies
Terminal CLI --------+             |
                                   +--> repositories, session logs, checkpoints
```

Architecture constraints:

- Keep one prompt builder, tool dispatcher, tool-loop policy, Plan Mode state
  machine, Goal Auto-Continue implementation, and evidence guardrail stack.
- Keep frontend rendering outside the execution runtime. Flutter sheets and
  terminal prompts adapt the same typed pending approval and question events.
- Start with an in-process runtime. Preserve interfaces that permit a local
  daemon later, but do not introduce IPC until concurrent GUI/CLI evidence
  justifies it.
- Reuse the existing Caverno data directory and redacted session-log schema.
  Define locking and ownership before the GUI and CLI can mutate the same
  conversation or coding project concurrently.
- Non-interactive execution fails closed when a tool requires approval. A
  machine-readable denial must include the pending capability and a stable exit
  code; absence of a GUI must never become approval.
- Computer Use remains unavailable from a headless CLI until a dedicated host,
  fresh arming flow, and observable approval boundary exist. Result replay or a
  remembered coding-command rule must not authorize a physical desktop action.
- Preserve project-root containment, verifier protection, high-risk approval
  review, checkpoint/rollback behavior, and sensitive-log redaction across
  both frontends.
- Treat SIGINT as cancellation: stop new LLM/tool work, terminate owned child
  processes through the existing process lifecycle, flush logs, and preserve a
  resumable conversation state.
- Support human-readable streaming by default and a versioned `--json` event
  stream for automation. Do not parse formatted terminal prose to recover
  tool, approval, token, or completion state.

Verification policy:

- Frequent weak-model and repeated Live LLM canaries use the headless lane and
  must not launch a desktop application window.
- The macOS application lane remains a separate release and UI-change gate for
  app bootstrap, localization, proposal presentation, and approval rendering.
- Both lanes reuse the same scenario contract, short prompt, saved workflow
  assertions, post-validator, session-log schema, and report vocabulary.
- A headless pass does not replace the app-path smoke, and an app-path pass does
  not replace terminal TTY, exit-code, signal, and non-interactive tests.

### CLI0: Headless Production-Path Baseline And Contract

Status: `done`

Scope:
- Extract a reusable no-window execution driver from the current Coding Live
  canary container and Plan Mode live harness.
- Run the exact short TODO prompt through chat, coding, and Plan Mode runtime
  entrypoints without `-d macos`, while retaining the independent TODO
  verifier and report bundle.
- Record a terminal contract for command names, stdin/prompt input, streaming
  output, JSON events, exit codes, cancellation, configuration precedence, and
  approval behavior.
- Keep the current macOS production-path canary unchanged as the comparison
  lane.

Acceptance criteria:
- A headless Plan Mode TODO canary completes from a shell without opening or
  foregrounding Caverno.app.
- The headless and macOS lanes consume the same fixture, exact prompt,
  scenario-level expectations, and post-validator.
- Three consecutive headless runs record pass/fail, duration, tool-loop count,
  recovery count, approval decisions, and session-log paths.
- One macOS comparison run demonstrates which coverage remains UI-specific.
- The CLI contract explicitly denies approval-required actions in non-TTY mode
  and reserves Computer Use for a later armed host design.

Current evidence:
- `docs/caverno_cli_terminal_contract.md`
- `docs/cli0_headless_app_parity_codex_task.md`
- `tool/run_plan_mode_todo_app_headless_live_canary.sh`
- `tool/canaries/plan_mode_headless_scenario_canary_test.dart`
- `tool/plan_mode_headless_canary_summary.dart`
- `tool/run_plan_mode_todo_app_cli0_comparison.sh`
- `tool/plan_mode_cli0_comparison_summary.dart`
- `tool/run_coding_todo_app_minimal_prompt_live_canary.sh`
- `tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart`
- `tool/run_plan_mode_todo_app_live_canary.sh`
- `integration_test/plan_mode_scenario_test.dart`
- `integration_test/test_support/plan_mode_live_harness_execution.dart`
- `docs/production_path_todo_live_canary_codex_task.md`
- `build/integration_test_reports/plan_mode_todo_app_cli0_comparison_1784130590/cli0_comparison_summary.json`

Next action:
- Start CLI1 with the smallest frontend-neutral seam: define typed runtime
  events and approval ports, then move one one-shot chat turn through the new
  facade while preserving the existing Flutter result.

### CLI1: Shared Application Execution Runtime

Status: `done`

Scope:
- Move runtime composition out of `lib/main.dart` and test-only canary builders
  into a reusable application layer with explicit settings, repository, LLM,
  tool, approval, logging, and lifecycle ports.
- Keep `ChatNotifier` and Flutter pages as GUI adapters while moving terminal-
  relevant orchestration behind a frontend-neutral facade.
- Remove `dart:ui`, widget, window-manager, notification, and platform-plugin
  requirements from the code imported by a Dart CLI executable.
- Preserve existing behavior before changing command UX or persistence.

Acceptance criteria:
- GUI and headless tests instantiate the same runtime composition API.
- The execution runtime exposes typed streams for assistant text, tool
  lifecycle, approval requests, questions, workflow transitions, usage, and
  terminal completion.
- The pure runtime test target runs under `dart test` or an equivalent
  no-window runner without Flutter widget bindings.
- Existing chat, coding, Plan Mode, routine-tool, approval, and session-log
  regression suites remain green.

Dependencies:
- CLI0 contract and headless baseline.
- Continue the F2/F5 large-file decomposition pattern instead of adding a new
  orchestration state machine beside `ChatNotifier`.

Evidence:
- `docs/cli1_shared_execution_runtime_codex_task.md`
- `packages/caverno_execution_runtime/lib/src/caverno_execution_runtime.dart`
- `packages/caverno_execution_runtime/lib/src/caverno_runtime_event.dart`
- `packages/caverno_execution_runtime/lib/src/caverno_runtime_ports.dart`
- `lib/features/chat/presentation/providers/caverno_execution_runtime_provider.dart`
- `packages/caverno_execution_runtime/test/caverno_execution_runtime_test.dart`
- `test/features/chat/presentation/providers/chat_notifier_execution_runtime_part.dart`
- `build/integration_test_reports/cli1_live/plan_mode_todo_app_cli0_comparison_1784149029/headless/`
- `build/integration_test_reports/cli1_macos_after_harness_fix/plan_mode_todo_app_live_canary_1784152249/plan_mode/plan_mode_live_suite_macos_report.json`
- Repository-standard verification passed Flutter analysis and 347 focused/full
  tests across the runtime, `ChatNotifier`, harness, and scenario configuration.

Next action:
- Start CLI2 with a one-shot `chat` command and a terminal presenter over the
  shared event stream. Keep coding and Plan Mode commands behind approval,
  cancellation, and exit-code tests.

### CLI2: Interactive Terminal MVP

Status: `done`

Scope:
- Add a supported `caverno` executable with `chat`, `coding`, and `plan`
  commands. Coding and Plan Mode require an explicit project root.
- Stream assistant output and concise tool lifecycle events to a TTY.
- Render typed approval, question, workflow-decision, and recovery events as
  terminal interactions using the same underlying policies as the GUI.
- Provide `--json` and stdin input for automation while keeping mutation
  approvals fail-closed when no TTY is attached.

Acceptance criteria:
- `caverno chat <prompt>`, `caverno coding --project <path> <prompt>`, and
  `caverno plan --project <path> <prompt>` use the shared runtime.
- Successful, blocked, denied, cancelled, transport-failed, and verification-
  failed outcomes have documented stable exit codes.
- Interactive local command, git, file, browser, and user-question boundaries
  are covered by terminal presenter tests.
- CLI output never leaks API keys, unredacted approval packets, or protected
  verifier content.
- The CLI does not advertise Computer Use support.

Dependencies:
- CLI1 shared runtime.

Evidence:
- `docs/cli2_interactive_terminal_mvp_codex_task.md`
- Terminal process smoke coverage passed for chat, coding, and Plan Mode,
  including human and JSON output, non-interactive approval denial, and SIGINT
  cancellation.
- `build/integration_test_reports/plan_mode_todo_app_cli0_comparison_1784165000/cli0_comparison_summary.json`
  recorded three consecutive passing headless runs and one passing macOS
  application-path run with Qwen3.6 27B Vision. All four runs had zero task
  drift and zero report-quality blockers under the strict comparison gate.

Next action:
- Preserve the terminal process and CLI0 parity gates as the CLI2 regression
  baseline. When CLI work resumes, start CLI3 with read-only `list` and `show`
  commands before adding cross-frontend resume or mutation.

### CLI3: Persistence, Resume, And Concurrent Ownership

Status: `done`

Scope:
- Reuse Caverno settings, drift conversations, memory, coding projects,
  checkpoints, routines, and session logs without test-only repositories.
- Add conversation listing and resume commands with stable identifiers.
- Define an execution lease for a conversation and coding project so GUI and
  CLI processes cannot perform conflicting mutations.
- Decide from measured contention whether direct storage locking is sufficient
  or a local Caverno daemon is justified.

Acceptance criteria:
- A conversation started in one frontend can be listed and resumed in the
  other without losing messages, workflow state, or provenance.
- Simultaneous execution against the same conversation/project is rejected or
  serialized with an actionable owner diagnostic.
- Storage migrations remain idempotent and recoverable when only the CLI is
  launched.
- Config precedence is deterministic: explicit CLI flags, environment,
  persisted Caverno settings, then built-in defaults.

Dependencies:
- CLI2 interactive MVP and F4 drift storage.

Evidence:
- `docs/cli3_shared_persistence_bootstrap_codex_task.md`
- `docs/cli3_read_only_conversation_commands_codex_task.md`
- `docs/cli3_execution_lease_foundation_codex_task.md`
- `docs/cli3_runtime_lease_integration_codex_task.md`
- `docs/cli3_conversation_resume_codex_task.md`
- `docs/cli3_gui_terminal_resume_smoke_codex_task.md`
- `lib/features/chat/application/persistence/caverno_persistence_bootstrap.dart`
  now owns the shared F4 migration, repository hydration, and database cleanup
  used by GUI and terminal frontends.
- `lib/features/terminal/application/caverno_cli_persistence.dart` routes the
  terminal runtime to the production drift repositories. Explicit data
  directories keep their SQLite database and migration markers in the same
  isolated root.
- Focused persistence and terminal-lifecycle tests passed, and a rebuilt macOS
  CLI process created the isolated drift store without starting MCP clients or
  producing a post-close persistence error on an early validation failure.
- `lib/features/terminal/application/caverno_conversation_query.dart` now emits
  redacted human output or schema-versioned `conversation_list` and
  `conversation_detail` events from exact drift repository reads.
- `lib/features/terminal/presentation/caverno_cli_process.dart` completes
  read-only queries before creating the Riverpod execution container, MCP
  clients, tools, or the LLM runtime. Completed migrations also avoid opening
  legacy conversation and chat-memory Hive boxes.
- Focused parser, query, and persistence tests cover bounded lists, exact-ID
  details, redaction, omitted attachment internals, missing IDs, and migration
  reader requirements.
- A rebuilt macOS executable emitted one empty `conversation_list` event from
  an isolated store on consecutive runs. The migrated second run still passed
  while both legacy data files were temporarily unreadable, confirming that
  the read-only path did not reopen those boxes.
- `CavernoExecutionLeaseService` now owns non-blocking OS file locks under each
  data root. Conversation and canonical workspace resources use hashed
  filenames, safe owner metadata, deterministic multi-resource ordering, and
  an in-process guard for POSIX process-scoped lock behavior.
- Separate-process tests cover contention, partial-acquisition rollback,
  independent resources and data roots, invalid diagnostics, and automatic
  recovery after abrupt owner exit.
- The macOS runner now bypasses duplicate-GUI activation only for CLI-shaped
  arguments. The full verification suite and a Debug macOS build passed, and
  the built executable returned its version through the terminal entry point.
- `CavernoExecutionRuntime` now acquires conversation and effective workspace
  leases before `run_started`, refreshes the authoritative conversation, and
  retains ownership until terminal persistence drains. Conflict, missing
  conversation, cancellation, preparation failure, completion, and shutdown
  paths have focused lifecycle coverage.
- GUI and terminal providers now resolve the same production data root for
  execution ownership. Explicit terminal data directories remain isolated,
  and Coding or Plan Mode leases the effective worktree instead of the source
  project when one is active.
- The migrated terminal path closes legacy conversation and chat-memory Hive
  boxes before execution and uses transient in-memory skill storage without
  exposing skill mutation tools. Packaged isolated and unreadable-legacy-file
  smokes reached runtime execution without Hive or provider errors.
- `tool/codex_verify.sh` passed with no generated-file drift, no analyzer
  findings, and 3,355 passing tests. A Debug macOS build passed, and two
  packaged Coding CLI processes using the same data root and workspace proved
  live contention: the second process emitted no `run_started`, returned
  `execution_lease_conflict`, and exited `75` while the first held ownership.
- `conversations resume` now resolves only a complete stable ID, selects the
  persisted conversation before ChatNotifier initialization, infers its saved
  Chat, Coding, or Plan Mode, and restores its saved project and worktree without
  accepting project reassignment.
- Headless resume startup defers unrelated empty-chat creation until the exact
  conversation is selected. This prevents a database-close race when a resume
  attempt loses its lease before normal chat initialization.
- Parser, notifier, terminal adapter, and runtime tests cover prompt-source
  conflicts, exact-ID enforcement, restored message history and planning
  workspace, missing project/worktree failures, refresh ordering, and live
  lease rejection. `tool/codex_verify.sh` passed with no generated-file drift,
  no analyzer findings, and 3,363 passing tests; a Debug macOS build also passed.
- A packaged isolated chat smoke against Qwen3.6 35B A3B Vision seeded a
  conversation, resumed its exact ID, and persisted the original and resumed
  user/assistant turns in order. Missing-ID resume returned
  `conversation_not_found` with exit `65`. A second packaged resume against a
  held conversation emitted only `execution_lease_conflict`, returned exit
  `75`, and produced neither `run_started` nor a post-close Drift exception.
- `caverno_gui_terminal_resume_test.dart` now writes separate Coding and Plan
  Mode conversations through the GUI-facing project and conversation notifiers
  into a temporary production drift database. It closes and reopens storage,
  resumes each exact ID through the terminal runtime lease, appends one
  deterministic terminal turn, and reopens storage again for final assertions.
- The cross-frontend smoke preserves the saved project, worktree, initial and
  appended messages, execution mode, workflow stage and tasks, source hash and
  timestamp, source references, and item provenance. Both cases emit
  `run_started` and `run_completed` with the saved worktree as the effective
  workspace. The focused gate passed 22 tests and the full gate passed 3,365
  tests with no generated-file drift or analyzer findings.
- `docs/cli3_terminal_project_persistence_codex_task.md`
- Terminal Coding and Plan Mode preparation now persists a generated canonical
  project record before activating a conversation. Application-default runs
  share the GUI shared-preferences registry, while an explicit data root owns
  an atomically replaced `coding_projects.json` registry and does not pollute
  application-default preferences.
- Deterministic restart tests create both execution modes in one terminal
  container, close and reopen the production drift database and project
  registry, resume each stable ID in a new container, append messages, and
  reopen storage again to verify mode, project ID, and message continuity. The
  focused gate passed 21 tests and the full gate passed 3,372 tests with no
  generated-file drift or analyzer findings.
- `docs/cli3_global_state_storage_scope_codex_task.md`
- Chat memory now has explicit storage-ownership evidence: sequential default
  frontend openings observe the same drift-backed profile, while separate
  explicit data roots cannot observe or overwrite each other's profile.
- Terminal routine composition now shares the GUI SharedPreferences registry
  only for the application-default root. Explicit data roots receive an
  atomically replaced local `routines.json` repository, so future provider
  initialization cannot cross into the default registry before routine commands
  are exposed. The focused gate passed 22 tests and the full gate passed 3,378
  tests with no generated-file drift or analyzer findings.
- `docs/cli3_chat_memory_atomic_merge_codex_task.md`
- Drift-backed chat-memory mutations now acquire a short global memory lease,
  refresh all six authoritative sections, and merge against that snapshot.
  Zone-scoped reentrancy keeps a composite session-memory update under one
  boundary without serializing the complete LLM turn.
- GUI and terminal bootstrap inject the same coordinator contract using their
  resolved data root. Conflicts retry for a bounded interval, stable timeouts
  identify unresolved contention, and every success or failure path releases
  ownership.
- A deterministic stale-cache regression opens two repositories before either
  writes, then proves distinct memories and conversation summaries from both
  frontend owners survive a database reopen. The focused gate passed 38 tests
  and the full gate passed 3,383 tests with no generated-file drift or analyzer
  findings.
- `docs/cli3_completion_audit_codex_task.md`
- Terminal LLM configuration now resolves through one tested flags,
  environment, persisted-settings, and built-in-default precedence helper.
  Blank higher-priority values fall through without exposing API-key values.
- Session-log composition keeps application-default runs on the GUI-compatible
  store. An explicit terminal data root owns `session_logs/` beneath that root,
  while `CAVERNO_SESSION_LOG_DIR` remains the dedicated highest-priority log
  override.
- Migration recovery now has an end-to-end retry regression: a failed first
  bootstrap closes its database and leaves the marker unset, then a second
  bootstrap migrates the legacy records and commits the marker without manual
  cleanup.
- `tool/cli3_contention_soak.dart` runs GUI-like and terminal-like workers as
  separate operating-system processes behind one start barrier. It exercises
  the same conversation, canonical workspace, and global chat-memory resources
  and emits redacted schema-versioned JSON and Markdown decision reports.
- Three consecutive two-worker, 100-iteration soaks completed all 200 runtime
  and 200 chat-memory operations per run with zero timeouts and zero invalid
  owner diagnostics. Runtime p95 was 5.454, 5.333, and 5.075 ms; chat-memory
  p95 was 6.317, 4.961, and 4.528 ms; throughput was 365.985, 362.857, and
  376.869 operations/s. All results stayed below the 250 ms p95 threshold, so
  the recorded decision is `direct_file_locking_sufficient`; a local daemon is
  not justified by current CLI3 contention evidence.
- A rebuilt Debug macOS application returned `Caverno 1.3.13` and a
  schema-versioned empty conversation list through the CLI entrypoint against
  an isolated data root, with both commands exiting successfully.
- The focused completion gate passed 14 tests. The final repository gate passed
  3,394 tests with no generated-file drift or analyzer findings.

Next action:
- Preserve the CLI3 runtime and doctor-foundation regression gates while CLI4
  packaging is paused. Keep terminal routine execution unavailable until its
  separate per-routine lease contract is defined.

### CLI4: Packaging, Automation, And Release Gate

Status: `later`

Scope:
- Package signed or checksummed executables for supported desktop platforms.
- Add shell completion, version/doctor output, signal handling, terminal
  capability detection, and upgrade guidance.
- Publish a CLI release gate combining pure runtime tests, TTY integration
  tests, non-interactive denial tests, headless Live LLM canaries, and one
  macOS app-path comparison smoke.
- Document unsupported tools and platform-specific degradation explicitly.

Acceptance criteria:
- Release artifacts run without a Flutter test runner or a visible Caverno app
  process.
- `caverno doctor` reports endpoint, model, configuration, storage, project,
  and tool-runtime readiness without exposing secrets.
- Automation consumes versioned JSON events and stable exit codes.
- The release gate proves approval, containment, cancellation, persistence,
  logging, and headless/app-path parity boundaries.

Dependencies:
- CLI3 persistence and ownership behavior.
- Completed: the F5 runtime package foundation is merged and the combined root
  and internal-package verification gate passes.

Current evidence:
- The doctor foundation has argument, configuration, bounded endpoint, model,
  storage, optional project, tool-policy, redaction, JSON, and exit-code tests.
  The focused repository gate passed 48 tests with no analyzer findings or
  generated-file drift.
- A fresh Debug macOS build is blocked at code signing because the timestamp
  service is unavailable. No packaged doctor evidence is claimed from the
  existing older app bundle.

Next action:
- Start from current `main` with architecture-stamped macOS archive tooling, a
  relative launcher, checksums, and packaged-process smokes. Restore signing
  timestamp connectivity before promotion, then rebuild the macOS app and run
  `doctor --json` through the packaged executable with an isolated data root.
  Treat that signed packaged doctor as a promotion and release gate, not as a
  prerequisite for starting CLI4 implementation.

## macOS Computer Use Track

The Computer Use milestones already use `M<number>` in
`docs/macos_computer_use_helper_architecture.md`. This roadmap keeps those IDs
intact and links them to MVP readiness.

| Milestone | Status | Summary |
|-----------|--------|---------|
| M1 | done | Permission-first onboarding and helper-owned overlay. |
| M2 | done | Capture, input, system-audio readiness, unsafe action hardening, and approval/arming gates for the debug embedded helper. |
| M3 | done | LaunchAgent-backed named XPC production IPC path. |
| M4 | done | Embedded-helper Screen & System Audio Recording, overlay, and onboarding sign-off gate. |
| M5 | done | Vision LLM observation tool surface. |
| M6 | done | Observe-action-observe loop hardening. |
| M7 | done | Release-helper artifact sign-off gate. |
| M8 | done | Release runtime sign-off gate, with manual TCC runtime evidence required. |
| M9 | done | User-operated manual TCC runbook boundary. |
| M10 | later | Helper IPC/runtime diagnostics for timeout headroom, path mismatches, and launch results. |
| M11 | later | Reusable Live LLM fixture evidence discovery and non-secret request metadata. |
| M12 | later | Real-app observe-only canaries for public-action boundary classification. |

MVP ready criteria live in `docs/macos_computer_use_mvp_checklist.md`.

## Conversation Fork Track

Conversation fork lets the user branch a new thread from any point in an
existing conversation. Chat fork is a pure history operation; coding fork must
also reproduce the on-disk/git state at the fork point, so it is a strict
superset gated on the LL2 checkpoint and LL13 worktree machinery. These
milestones use `FORK<number>` and are documented here rather than in the Local
LLM roadmap because they are a user-facing conversation-threading feature rather
than local-LLM execution work.

### FORK1: Chat Conversation Fork

Status: `next`

Scope:
- From any message in a chat-mode conversation, create a new conversation that
  copies the message history up to and including that message.
- Add `parentConversationId` and a fork-origin descriptor (fork message id and
  index) to `Conversation`; the child is independent and the parent is never
  mutated by child edits.
- Trim fork-point-invalid state from the copy: drop streaming/incomplete
  messages and any checkpoints or turn diffs recorded after the fork index.
- Surface a per-message "fork here" affordance and show the parent/child
  relationship in the conversation drawer.

Acceptance criteria:
- Forking at message N yields a new conversation containing `messages[0..N]` and
  the conversation-level metadata valid at that point.
- Editing or continuing the child does not change the parent, and vice versa.
- The new linkage fields round-trip through the drift repository.
- The drawer makes the fork relationship discoverable.
- Focused tests cover the fork builder, metadata trimming, and persistence.

Dependencies:
- New `Conversation` fields require a Freezed regeneration
  (`dart run build_runner build --delete-conflicting-outputs`).

Next action:
- Add the linkage fields, a fork path reusing `_createConversation`/`save`, and
  the per-message fork affordance.

### FORK2: Coding Conversation Fork

Status: `later`

Scope:
- Fork a coding-mode conversation at message N and reproduce the working-tree
  and git state as of that turn into an isolated git worktree/branch, reusing
  the LL13 worktree machinery seeded from the parent's turn commit or the LL2
  file checkpoint at the fork point.
- Never share a worktree between the parent and the fork; assign the fork a
  fresh `worktreePath`/branch while carrying `projectId`.
- Define a non-git fallback (file snapshot copy) and a clear collision policy
  when the project is not a git repository.

Acceptance criteria:
- Forking a coding thread creates a new conversation bound to a new
  worktree/branch whose tree matches the fork-point state.
- The parent worktree is untouched by the fork.
- The flow degrades safely (documented boundary or snapshot fallback) when the
  project is not a git repository.
- Verification follows the LL13 worktree-agent evidence style plus focused
  fork-point reproduction tests.

Dependencies:
- FORK1 (linkage + chat fork), LL2 (file checkpoints), LL13 (git worktrees).

Next action:
- Gate on FORK1 shipping, then seed a worktree from the fork-point commit or LL2
  checkpoint and bind it to the forked conversation.

### FORK3: Fork Tree Navigation And Compare

Status: `later`

Scope:
- Add a fork-tree view in the drawer, jump-to-parent navigation, and a
  parent-vs-fork comparison.
- Reuse the existing `TurnDiff` rendering for the compare view.

Acceptance criteria:
- The user can see the fork tree, jump to a fork's parent, and compare a fork
  against its parent.
- The compare view reuses existing diff rendering rather than a new diff stack.

Next action:
- Start after FORK1 and FORK2 ship.

## Apple Watch Companion Track

The companion exists to answer a blocked turn without taking the phone out.
Flutter does not run on watchOS, so it is a SwiftUI target embedded in
`Runner.app` talking to the Flutter app over `WCSession`; the design, and the
reasoning behind treating the watch as a peripheral of this device rather than
as a paired principal, is in `docs/apple_watch_companion.md`. These milestones
use `WATCH<number>` and live here rather than in the Local LLM roadmap because
this is a user-facing surface, not local-LLM execution work.

### WATCH1: Companion Bridge, Approvals, And Voice

Status: `done`

Scope:
- `WatchBridgePlugin` (`ios/Runner/AppDelegate.swift`) plus
  `WatchBridgeService` and `WatchSessionNotifier` on the Dart side: project
  `ChatState` outward as a bounded `WatchSnapshot`, apply `sendMessage`,
  `resolveApproval`, `resolveQuestion`, `cancelStreaming`, and
  `requestSnapshot` back onto `ChatNotifier`.
- watchOS app: running-turn glance with cancel, Approve/Deny with haptics, a
  tappable `ask_user_question` option list, and dictation with the reply read
  back by `AVSpeechSynthesizer`.
- Actionable approval notifications as the fallback for when the watch app is
  closed, which iOS forwards to the wrist with no watchOS code involved.

Acceptance criteria (met):
- The watch sees local-origin pending interactions and never one owned by
  another paired Remote Coding device, preserving SEC4.5g.
- A maximal snapshot stays inside the WatchConnectivity payload budget.
- Notification actions appear only when the approval id is known and the kind
  is a plain yes/no; SSH connect and computer-use stay read-only.
- `flutter analyze` clean of new issues, full suite green (8899 tests), and the
  watchOS target builds for `watchsimulator`.

Verification evidence:
- Commits `d3f46c89`, `473826d9`, `6af09bff`, `67955486` on
  `claude/apple-watch-app-features-d25b53`.
- `tool/flutter_test_quiet.sh` (44 new tests under `test/features/watch/` and
  `test/features/chat/.../pending_approval_*`).
- `xcodebuild -target "CavernoWatch Watch App" -sdk watchsimulator26.5` →
  BUILD SUCCEEDED; `AppDelegate.swift` typechecked against the real
  `Flutter.xcframework`.

Next action:
- None. The gap this leaves is that nothing has been run; see WATCH2.

### WATCH2: End-To-End Device Verification

Status: `done`

Scope:
- Run the companion. Every unit test crosses a fake bridge, so the
  `WatchBridgePlugin` <-> `WatchBridgeService` boundary — channel names, payload
  framing, `WCSession` activation and reachability, the embed phase, and
  installability — is the one seam the suite cannot reach.

Evidence (2026-09-01/02, iPhone 17 Pro Max / iOS 26.5 paired with Apple Watch
Series 11 / watchOS 26.5, against a LAN `qwen3.8-27b-vision`):
- The round trip works in both directions. The phone log shows the watch's
  `requestSnapshot` inbound and the answer going out as both
  `updateApplicationContext` and `sendMessageData`.
- A live turn renders on the watch: real conversation title, streaming status
  with elapsed seconds, and the answer arriving as deltas.
- **A pending `ask_user_question` was answered from the wrist.** The options
  rendered on the watch, tapping one resolved it, and the phone's model
  continued with "You chose Startup".
- Packaging is validated. `flutter build ipa --no-codesign` produces an archive
  whose only root product is `Runner.app`, with the companion at
  `Runner.app/Watch/` as a watchOS binary, and both bundles install.

Ten defects surfaced, none of which a green suite could catch:
`Cycle inside Runner` from the embed phase order; a leaked
`__new_conversation__` title sentinel; a missing `sessionReachabilityDidChange`
handler; a missing `SUPPORTED_PLATFORMS` that built the watch against the iOS
SDK; raw `<tool_use>` markup reaching the watch; a latched availability flag;
commands dropped before Dart subscribed; a missing `NSExtension` dictionary; and
absent `CFBundleVersion` on both watch targets. Raw markdown reaching the watch
label and speaker was fixed in the same pass.

Note on approvals: file, shell, and git approvals **cannot arise on iOS**.
`mcp_tool_service.dart` gates all three behind `isDesktopPlatform` by design —
"writing arbitrary paths on a sandboxed mobile OS is both risky and largely
unusable". The watch's approval path therefore serves a desktop-driven turn, or
the kinds mobile does have (BLE, SSH, browser, participant). That is a scoping
fact worth carrying into any further watch work, not a defect.

Environment notes that cost real time:
- Bare `flutter` on this machine is 3.47.0 while `.fvmrc` pins 3.44.8; the wrong
  one rewrites `.dart_tool/package_config.json` and makes a direct
  `xcodebuild archive` fail with `Type 'ui.HitTestResponse' not found`.
- CocoaPods dies on a non-UTF-8 `LANG` while reporting a stale spec repository.
- Simulator pairing needs no GUI (`xcrun simctl pair`), but app preferences live
  in the sandboxed container rather than where `simctl spawn defaults` writes,
  and cfprefsd caches them until the device is rebooted.
- A simulator configured for Japanese input turns typed ASCII into kana; set
  `AppleKeyboards` to English or drive entry through `simctl pbcopy`.

Next action:
- None. Remaining watch work is tracked as WATCH4's signed-build check and
  WATCH6.

### WATCH3: Deferred Watch Command Conversation Binding

Status: `done`

Scope:
- Bind a watch command to the conversation it was composed against.
  `WatchSessionClient.send` falls back to `transferUserInfo` when the phone is
  unreachable, which guarantees delivery but not promptness, and the command
  carries no conversation id. `resolveApproval` degrades safely because
  approval ids are unique and a stale one simply fails to resolve, but a
  `sendMessage` delivered minutes later lands in whichever thread is current
  by then.

Acceptance criteria:
- `sendMessage` carries the `conversationId` the watch was showing, and
  `_handleSendMessage` refuses it with a distinct code when it no longer
  matches, rather than sending into the wrong thread.
- The watch reports the refusal instead of silently dropping the text.
- A focused test covers the mismatch path.

Shipped 2026-09-01 (`1ed84dac`). The watch stamps the conversation it was
showing, and `_handleSendMessage` refuses a mismatch with `conversation_changed`
rather than sending into the wrong thread. An unstamped command is still
accepted, so a watch that has not synced the new app keeps working.

### WATCH4: Glanceable Surfaces And Thread Choice

Status: `done`

Scope:
- A Smart Stack widget showing whether anything is running or waiting, and
  switching which conversation the watch mirrors.

Shipped 2026-09-01 (`d9079b3f`, `9cd06fd7`):
- The snapshot carries the threads the watch may switch to, capped at the
  source, with a flag saying when the list was cut so the watch points at the
  iPhone instead of implying it is complete. `selectConversation` applies the
  choice and refuses a vanished id with its own code.
- `CavernoWatchWidgetExtension` is embedded in the watch app and reads a small
  record through the App Group. The record is counts and a status word, never
  conversation text: a widget renders without anyone opening anything.
- The glance is written only when the value actually changes and the timeline
  is reloaded only then; the timeline itself has no refresh policy. WidgetKit
  budget is finite and re-rendering an identical glance spends it for nothing.
  This is why `transferCurrentComplicationUserInfo` is not used at all — the
  watch app already has the state, so nothing needs to cross from the phone.

Not verified:
- The widget's data path. An unsigned simulator build applies no entitlements,
  so the App Group container does not exist and `UserDefaults(suiteName:)`
  returns nil. The store degrades to a no-op and the widget renders its idle
  state, which is the safe failure but also indistinguishable from "no work
  running". Confirming it needs a signed build.

Next action:
- Check the glance on a signed build. Circular, rectangular, and inline
  accessory families are already supported; this check is for the App Group
  data path, not another family implementation.

### WATCH5: Push-Originated Notification Actions

Status: `blocked`

Scope:
- Let Approve/Deny work on a notification delivered by push, not only one
  raised locally.

Why it is blocked rather than merely later (assessed 2026-09-01):
- **There is no approval to push.** The only notification the relay sends is
  `remote_coding_run_terminal`, a run *completion*. Attaching an approval
  category to it would put Approve/Deny on something that is not a decision.
  Carrying a real approval would mean adding fields to
  `RemoteCodingNotificationPayload`, which its own contract says is a
  privacy-boundary change requiring explicit review.
- The `firebase_messaging` limitation is real but secondary: it does not
  surface `actionIdentifier` on iOS, so the action would have to be read by a
  native `UNUserNotificationCenter` delegate. That plumbing is not worth
  writing before there is something for it to carry.
- Verifying any of this on a simulator is circular. A pushed notification is
  only displayed once notification permission is granted, and the app defers
  that request until it first raises a local notification — which happens when
  a background thread blocks on an approval. `xcrun simctl push` with a
  `caverno_approval` category was delivered and silently dropped for exactly
  this reason.

The local path already covers the case this milestone was meant to serve: an
approval raised on the phone carries Approve/Deny, and iOS forwards the
notification and its actions to a paired watch with no watchOS code involved.

Next action:
- None. Revisit only when a push genuinely needs to carry an approval — that
  is a Remote Coding decision, gated by `docs/remote_coding_fcm_release_gate.md`,
  not a watch one.

### WATCH6: Dismiss A Resolved Interaction On The Phone

Status: `done`

Scope:
- Close an approval or question dialog on the phone when it is resolved
  somewhere else — today, the Apple Watch.

Shipped 2026-09-02 (`8caa529c`):
- `ApprovalDialogPresenter` owns both halves. Twelve listeners were repeating
  the same open-on-id-change shape and none of them closed anything; they
  collapse into one helper.
- Dismissal pops by route name, not by popping the top route. `popUntil` with a
  name predicate closes the dialog when it is topmost and does nothing at all
  when something else is, so a mistimed resolution cannot take away the screen
  the user is looking at. A test pushes an unrelated route over an open
  approval sheet and asserts it survives.
- The route name lives beside the approval sheets rather than with the
  presenter: the sheets push the route, and a widget should not import from
  `pages/`.

Verified 2026-09-02 on paired simulators: a pending `ask_user_question`
answered from the wrist closes the phone's sheet, and the model continues from
that answer.

The refactor paid for itself against the line ratchet — `chat_page.dart` fell
38 lines and its library 52 — so both budgets were lowered rather than raised.

Next action:
- None.

### WATCH7: A Message Thread On The Wrist

Status: `done`

Scope:
- Replace the single-answer glance with the transcript a person expects when
  they raise their wrist mid-conversation.

Shipped 2026-09-02:
- `WatchSnapshot` carries `messages` — eight bubbles, 180 runes each with 400
  for the newest, plus a truncation flag. `lastAssistantText` stays for a watch
  that is newer than the phone it is paired with; `TranscriptView` falls back
  to it so that pairing shows one bubble rather than an empty thread. That
  fallback is the path that was actually exercised on the simulator, because
  the paired phone was running the previous build.
- The budget test now measures in a multi-byte script as well as ASCII. Every
  cap counts runes, so the ASCII-only measurement under-reported the payload
  threefold — the transcript is what made that headroom matter.
- A synthesized prompt never becomes a user bubble. Those envelopes are built
  for the request payload and do not reach `ChatState.messages` today; the
  guard is there because if one ever did, the watch would draw a `<tool_use>`
  blob in the person's own voice and read it aloud.
- `StatusView` and `VoiceView` are gone. Their controls live in the compose
  bar's "+" sheet and the navigation bar, so the scroll area holds only the
  exchange. Dictation moved to a `TextFieldLink`, which is what lets the
  collapsed field be drawn as a placeholder capsule.
- `isVoiceMode` follows the "Read replies" switch instead of being sent
  unconditionally, since it shapes the phone's answer for speech. That switch
  is now persisted and defaults off: the speaker moved from a screen you had to
  open onto the screen a raised wrist lands on, and leaving it on by default
  would have made every glance start talking.

Two defects were caught by looking at it rather than by compiling it:
- The transcript opened at the top of the thread. `onAppear` runs before the
  scroll view lays its content out; `defaultScrollAnchor(.bottom)` is the fix.
- An app-wide `.tint` — added to colour the toolbar button — repainted every
  `role: .destructive` button in the accent colour, so Stop and Deny rendered
  as ordinary blue buttons. The tint is now scoped to the one button.

Next action:
- None. Verified 2026-09-04 against a rebuilt iPhone app that sent the actual
  `messages` array to the paired watch rather than exercising the compatibility
  fallback.

### WATCH8: Restart-Safe Snapshot Ordering

Status: `done`

Scope:
- Preserve stale-frame rejection when `updateApplicationContext` and
  `sendMessage` arrive out of order, while accepting the first frame after the
  iPhone process restarts and its per-process sequence returns to one.

Completed 2026-09-04:
- `WatchSnapshot` now carries a random source instance id and the source start
  time. Sequence numbers remain small and monotonic within that source.
- `WatchSnapshotCursor` selects a newer source by start time, orders frames from
  that source by sequence, and rejects frames from retired sources. A legacy
  source-less phone remains compatible until a source-aware frame is accepted;
  source-less frames are rejected after that point so they cannot resurrect a
  resolved approval.
- The paired-simulator check used matching current iPhone and watch builds. An
  actual user message and streaming state arrived through the native/Dart
  bridge. The Watch process then stayed alive while only the iPhone app
  restarted; the reset-sequence frame replaced the old 38-second streaming
  state with the restarted app's current idle conversation.

Verification evidence:
- `tool/codex_verify.sh --no-codegen --test test/features/watch/` passed 61
  tests and all analyzers.
- `tool/watch_snapshot_cursor_smoke.swift` accepted old-source sequence 8, rejected 7,
  accepted new-source sequence 1, rejected delayed old-source sequence 9, and
  accepted new-source sequence 2.
- The Watch simulator target and the full iPhone simulator app with the embedded
  companion both built successfully.

Next action:
- None. WATCH4's signed-build App Group check remains the only open Watch
  verification item; WATCH5 remains blocked on a push approval contract.

### WATCH9: Goal State On The Wrist

Status: `next`

The companion mirrors `ChatState` and the conversation list, and nothing else.
A coding thread therefore reaches the wrist as bubbles with none of the state
that makes it a coding thread. The gap that matters is
`ConversationGoalStatus.awaitingConfirmation`: the harness has stopped
scheduling and is asking whether the objective was met, and `_statusFor`
renders that as `WatchTurnStatus.idle` — indistinguishable from finished. It is
a wrist-shaped decision the wrist cannot see. The measured behaviour behind it
is that the model does not volunteer `update_goal` but answers when asked, so
the ask is the whole mechanism.

Scope:
- Carry `workspaceMode` and a projected goal (`objective`, `status`,
  `completionSummary`, `blockedReason`) in `WatchSnapshot`, capped like the
  existing title and detail fields and counted in runes.
- Treat `awaitingConfirmation` as an attention state: its own
  `WatchTurnStatus`, included in `needsAttention` so the transcript's attention
  button, the glance, and the widget agree.
- Add `resolveGoal` (complete / keep going) to `WatchCommand.allowed`, routed
  through the same path the phone's goal menu uses rather than a second writer
  — `validationStatus` already has three writers and does not need a fourth
  shape of the problem.
- Label the thread picker with each thread's workspace mode.
  `ConversationsState.conversations` is unfiltered, so chat, coding, and
  routine threads are presented today as if they were the same kind of thing.

Acceptance criteria:
- A goal awaiting confirmation raises the same attention affordance an approval
  does, and answering it from the wrist moves the goal exactly as the phone's
  menu would.
- A blocked goal names its blocker instead of reading as idle.
- A maximal snapshot carrying a goal stays inside
  `watchSnapshotMaxEncodedBytes`, measured in a multi-byte script. The
  transcript already spends most of that budget, so this is the gate, not a
  formality.
- An older watch build ignores the new fields; an older phone leaves the goal
  affordance absent rather than empty, the way `lastAssistantText` already
  covers the reverse skew.

Dependencies:
- None beyond the shipped companion.

Next action:
- Re-measure maximal snapshot headroom first, then project the goal and add
  `resolveGoal`.

### WATCH10: Remote Coding Approvals As Notifications

Status: `next`

The Remote Coding server is desktop-only
(`Platform.isMacOS || isLinux || isWindows`); mobile is client-only. A blocked
desktop turn therefore lives in `RemoteCodingClientState` on the phone, and
nothing outside `features/remote_coding/` reads that provider —
`remoteCodingClientProvider` has three call sites, none of them the watch and
none of them `ChatNotifier`. `showPendingApprovalNotification` is called only
from `ChatNotifier`. The result is that a Mac waiting on `dart analyze` reaches
the wrist through no path at all: not the companion, and not a notification
either.

That contradicts `docs/apple_watch_companion.md`, which reasons that since
file, shell, and git approvals cannot arise on iOS, "the watch's approval path
therefore serves a desktop-driven turn". The intent is written down; the wiring
is not there. Fix the wiring, then fix the sentence.

This is not WATCH5. WATCH5 is blocked because no *push* carries an approval.
This path needs no push: the client holds a live WebSocket while connected and
the approval arrives on it. The notification is raised locally, and iOS
forwards it and its actions to the paired watch with no watchOS code involved
— the same mechanism WATCH1 already relies on.

Scope:
- Raise the actionable approval notification from the Remote Coding client when
  a pending approval arrives, reusing `showPendingApprovalNotification` and the
  `RemoteCodingNotificationReceiptStore` dedup that terminal notifications
  already use.
- Route Approve/Deny back through `RemoteCodingClientNotifier.resolveApproval`.
  `approvalNotificationActionsProvider` resolves only against
  `chatNotifierProvider`, so an action carrying a remote approval id resolves
  nothing at all today, silently.
- Name the host in the body. `RemoteCodingHost` carries the server name, and
  "wants to run: dart analyze" without saying which machine will run it is
  exactly the failure this must not ship.
- Suppress the notification while the Remote Coding page is foregrounded,
  matching the existing terminal-notification behaviour.

Acceptance criteria:
- All three remote approval kinds — `file`, `localCommand`, `gitCommand` — are
  bare yes/no decisions, so Approve/Deny is a truthful answer for each and the
  notification carries the actions for all three.
- The action resolves by approval id against the owning notifier. A stale id
  fails visibly rather than resolving whatever else is pending.
- Resolving on the desktop leaves no orphan notification on the phone.

Dependencies:
- None. Independent of WATCH9 and a prerequisite for WATCH11.

Next action:
- Add the client-side raise and the action route, then verify with a Mac
  server, an iPhone client, and a paired watch. Paired simulators are not
  sufficient here: the whole point is a three-device path.

### WATCH11: Remote Coding Interactions In The Companion

Status: `later`

Scope:
- Give `WatchSessionNotifier` a second input source alongside
  `chatNotifierProvider`: `remoteCodingClientProvider`.
- Decide precedence when a local interaction and a remote one block at the same
  time. One screen, one decision; `WatchApprovalMapper._byPriority` already
  ranks by consequence and the same principle has to extend across sources.
- Add a source label to `WatchApproval` carrying the server name, and render
  it. Approving a shell command without knowing which machine runs it is the
  failure mode this milestone exists to avoid, so the label is load-bearing
  rather than decoration.
- Route `resolveApproval` and `resolveQuestion` to the owning notifier, keeping
  the existing correlated-result wait so a failure stays on the screen where it
  happened.
- Keep the transcript local-only in this slice. Two transcripts on one wrist
  screen is a separate design problem, and the payload budget cannot carry both.

Trust model — a new judgement, not a restatement:
- SEC4.5g scopes a Remote Coding interaction to the paired device that started
  the turn. That device is the iPhone, and WATCH1 established the watch as a
  peripheral of this device rather than a principal of its own. Surfacing the
  phone's own remote-coding approval on the phone's own watch therefore does
  not widen the principal set.
- It is not a relaxation of `WatchApprovalMapper`'s `isOwnedByRemoteDevice`
  exclusion. That guard covers the desktop-as-server case and cannot fire on
  iOS, where `ChatState` never holds a remote-origin approval. Reaching remote
  coding means adding a second source, not widening the existing gate — and
  conflating the two would quietly undo SEC4.5g on desktop.
- Write the reading into `docs/apple_watch_companion.md` and record it beside
  SA-24 in `docs/security_followup_review_2026-08-24.md` before shipping.

Acceptance criteria:
- A pending approval on the connected desktop renders on the wrist naming its
  host, and answering it resolves that request over the WebSocket.
- A local interaction and a remote one pending together produce one screen with
  a decided, tested precedence.
- The snapshot carrying remote fields stays inside the payload budget in a
  multi-byte script.
- A remote interaction owned by a *different* paired device is still excluded.

Dependencies:
- WATCH10, which proves the client-side wiring and the host naming with far
  less machinery.

Next action:
- Gate on WATCH10 shipping, then settle cross-source precedence before writing
  any wire fields.

### WATCH12: Running Tool And Verification Readout

Status: `later`

Scope:
- Say what a turn is doing rather than only that it is streaming: the tool or
  command in flight, and whether the thread's `verificationGeneration` is
  behind its `mutationGeneration`.

Why this is `later` and not `next`:
- There is no general active-tool field to project. `activeToolName` lives on
  `ParticipantTurnRuntime` and is set only for participant turns, so this needs
  a new `ChatState` field, not a projection of an existing one.
- Nothing has shown that a wrist wants it. The evidence rule applies: build
  what a real session proves is missing, not what a status screen could
  plausibly hold.

Next action:
- None. Revisit if WATCH9 or WATCH11 usage shows the glance is
  under-informative.

## Anabasis Orchestrator Track

Anabasis is a parent orchestrator over Caverno's existing Goal, Plan,
provenance, subagent, and verification machinery — not a second coding agent
and not a fourth authoritative conversation state. The full design, including
the Existing Caverno Mapping that decides what may be built, is in
`docs/ANABASIS_ORCHESTRATOR_ARCHITECTURE.md`. The concept and naming reference
is `docs/anabasis_brand_story.md`; the superseded first plan, kept as the
record of why it was superseded, is `docs/anabasis_mvp_plan_superseded.md`.

These milestones use `ANA<number>` and live here rather than in the Local LLM
roadmap because this is orchestration policy and a user-facing surface, not
local-LLM execution work.

**Track rule, and the reason this track exists as a written design at all:**

> Anabasis reuses existing Caverno state whenever that state already expresses
> the required concept. New authoritative state is introduced only when an
> existing representation is demonstrably insufficient.

Three separate design passes each re-derived something Caverno already had
(`AnabasisState` ≈ `ConversationWorkflowSpec`; `AnabasisProjection` ≈
`ExecutionSnapshot`; "generate acceptance criteria" ≈ `acceptanceCriteria`,
already emitted). Check §3 of the design document before adding any type.

### ANA0: Epistemic Grounding

Status: `current`

Scope:
- Confirmation path: record a user's confirmation as a
  `ConversationContractSourceKind.userConfirmedAssumption` source, link it into
  the item's `sourceIds`, then set `confirmed = true`.
- Assumption producer: emit `assumption` / `material` per contract item from
  the planning JSON schema and proposal parsers.
- Parent execution identity and tool authority: `ModelUsageRole.anabasisParent`
  for accounting, an explicit executing-role parameter for authority, and a
  guard restricting the parent to `inspection | verification | delegation`.
- Projection: extend `ExecutionSnapshot` to carry assumption *items* alongside
  `blockingAssumptionCount`. Do not add a new projection class.

Ordering constraint (not negotiable), restated 2026-09-02:
- **A way to unblock lands before the guard is armed.**
  `MaterialContractAssumptionGuard` is already wired into the tool-loop guard
  chain and already refuses mutations while
  `assumption && material && !confirmed`. Arming it without a confirmation
  path refuses every mutation in the conversation permanently while the loop
  burns on verbatim retries.
- The earlier wording said the confirmation path must precede the *producer*.
  That is stricter than the hazard requires and it forced the confirm surface
  to be designed before anyone knew how many material assumptions a real plan
  produces — a number that decides whether the surface is a per-assumption
  approval or a batch review. The producer therefore ships in **shadow**: it
  writes the marks, and the guard is fed an empty blocking list until the
  surface is built to fit the measurement.
- The shadow is now implemented rather than assumed. It was neither, until
  2026-09-03: the feed site in `chat_notifier_tool_loop_batch.dart` read the
  spec's own `blockingAssumptions`, and the guard was unarmed only because no
  producer wrote `assumption: true`. PR 3a ended that without anyone noticing —
  `ContractItemMarks.parseBullet` makes a user typing `(assumed, material)`
  onto a plan-document bullet a producer, so the hazard was already reachable
  one hand-typed bullet away, before PR 3b. Arming now lives in
  `MaterialContractAssumptionArming.armed`, the single place PR 4 changes.

PR split:

| PR | Content | Status |
|---|---|---|
| 1 | Failing canary: confirming a material assumption unblocks mutation | done |
| 2 | Confirmation provenance — the transformation, no caller yet | done |
| 3a | Epistemic marks round-trip through the plan document | done |
| 3a2 | Guard arming stated at one site, so the shadow is implemented rather than accidental | done |
| 3b | Planning prompt emits marks; producer runs in shadow | done |
| 3c | Measure: material assumptions per plan, and how often the model over-asserts | done |
| 3d | Marks are for what the plan asserts: restrict the marker by item kind, enforce it centrally, report marks by kind, re-measure | done |
| 3e | Define materiality by consequence rather than by restating the word, and re-measure | done |
| 4 | Confirm surface sized to 3c (**per-assumption approval**, not batch review), guard armed in `MaterialContractAssumptionArming.armed`, parent authority policy, and **unskip the canary's reachability assertion** | next |
| 5 | `ExecutionSnapshot` extension and the Understanding panel | |

Supporting decision: the confirm surface is the **approval flow** — the guard
refuses at the moment a mutation is attempted, so a pending interaction raised
there is the only surface with no dead end. A plan-review-only affordance
would leave a blocked run with nowhere to answer. The open question 3c settles
is not *where* but *how many at once*.

Acceptance criteria:
- Confirming a material assumption unblocks mutation end to end.
- A material assumption is detected, marked, and never presented as a fact.
- The parent cannot call a workspace-mutating tool; delegation still works.
- Baseline for every canary is current Caverno, not a plain chat session.

Verification evidence:
- PR 1: `anabasis_assumption_confirmation_canary_test.dart` — 4 passing (the
  guard's existing block/unblock semantics and the confirmation's provenance
  shape) and 1 failing by design. The first version of that canary asserted
  only that some production file *mentions* `userConfirmedAssumption`, and it
  went green the moment the domain transformation existed with no caller
  anywhere — moving the value from "declared and never written" to "written
  and never called". It now asserts a caller as well, which is the weakest
  honest proxy for reachability a source scan can express.
- PR 2: `conversation_contract_provenance_confirmation_test.dart` — the three
  steps, guard unblocking end to end, idempotence, and a recorded limitation:
  `attachApprovedPlanSource` rebuilds provenance wholesale, so a re-approved
  plan starts from unconfirmed.
- Extraction: `chat_state.dart` sat at its ratchet ceiling with no margin, so
  the eleventh pending type could not be added without raising a budget the
  ratchet forbids raising. `PendingToolApproval` and its hierarchy moved to
  `pending_tool_approvals.dart` (684 lines to 162, re-exported, no importer
  changed), with a declared budget on the destination.
- PR 3a: `contract_item_marks_round_trip_test.dart` — marks survive build and
  projection, unmarked documents project exactly as before, a hand-typed
  marker is honoured, and marking never changes an item's `itemId`.
- PR 3a2: `anabasis_assumption_confirmation_canary_test.dart` gains a shadow
  group — a spec whose item does block is still handed an empty armed list,
  and the feed site no longer names `blockingAssumptions` at all. The second
  assertion is a source scan because the failure it guards is a one-line
  reversion at a single call site, and a behavioural test of the tool loop
  would not fail on it while the list stays empty for want of a producer.
- PR 3b: `anabasis_planning_prompt_marks_test.dart` — the proposal prompt, in
  both its full and compact forms, teaches a marker that
  `ContractItemMarks.parseBullet` actually accepts. The test reads the quoted
  marker forms back out of the generated prompt instead of restating them,
  because the two halves are string literals in different files and nothing
  else relates them. It also pins the marker to English while the fields around
  it are translated: `parseBullet` matches `assumed`/`material` and nothing
  else, so a translated marker is silently dropped.
- PR 3b, second defect found while building it: the planning prompt echoes the
  saved contract back before a revision, and that echo listed constraints,
  acceptance criteria, and open questions without their marks. A revision was
  therefore shown a contract in which nothing had ever been assumed, and would
  have laundered every assumption into a fact on the next pass — measured in
  PR 3c as the model declining to mark. The echo now renders marks through
  `ConversationPlanDocumentBuilder.markerFor`.
- PR 3b keeps the proposal JSON schema unchanged: the marker rides inside the
  item string and becomes a mark only in the plan document, which is the
  authoritative middle. Weak local models lose structured-output fidelity when
  a schema grows, and the round trip already existed.
- PR 3c instrument: `tool/ana0_assumption_marking_measurement.dart` plus
  `test/tool/ana0_assumption_marking_measurement_test.dart`. Six scenarios run
  in paired arms — `ungrounded` omits one load-bearing fact, `grounded` adds one
  message stating it, and nothing else differs. A constraint restating that fact
  is an assumption in the first arm and a fact in the second *by construction*,
  so an unmarked ungrounded plan is an over-assertion and a marked grounded plan
  is an over-mark, with no heuristic reading the model's prose to decide which.
  Scoring runs the production path: real prompt, real proposal parser, real plan
  document, real projection, marks counted off provenance.
- PR 3c instrument, verified before it is believed: 13 scripted-response tests
  fix the verdict for each case in advance, including the two that decide
  whether a number is honest — a response that is not a proposal is recorded
  `unparsed` rather than scored as a plan that marked nothing, and a transport
  failure is likewise never read as a model that declined to mark. A run that
  reached nothing must not look like a measurement.
- PR 3c result, `qwen3.8-27b-vision`, 36 requests, 18 per arm, 0 unparsed:

  | | ungrounded | grounded |
  |---|---|---|
  | material assumptions / plan | 0.28 | 0.06 |
  | assumption marks / plan | 0.78 | 0.22 |
  | open questions / plan | 2.17 | 2.50 |

  Over-assertion — a plan that neither marked anything nor asked anything — is
  1 in 18. Over-marking is 1 in 18. The +0.22 aggregate discrimination these
  averages show does not survive the by-kind breakdown recorded below; read
  that before using this table.
- **PR 4's surface question is answered: a per-assumption approval, not a batch
  review.** The per-plan distribution of material assumptions is 0 in 14 plans,
  1 in 3, and 2 in 1; grounded is 0 in 17 and 1 in 1. No plan produced more
  than two. A batch review is a surface for a list, and the measured list is
  zero, one or two items.
- **Correction, same day, from breaking the marks down by item kind — PR 4 is
  not ready to arm the guard.** Of the 14 marks the ungrounded arm produced,
  seven land on `openQuestions`, and four of the five *material* ones do. "An
  open question I am assuming" is not a coherent claim, and
  `ConversationContractItemProvenance.blocksExecution` does not look at `kind`,
  so arming the guard today would refuse mutations because of marked
  *questions*. On constraints — the only kind where the mark means what ANA0
  means by it — the arms are identical at 3 of 18 each, with one material mark
  on either side. The headline +0.22 discrimination was carried almost entirely
  by marked open questions; on constraints it is zero.

  | ungrounded marks | total | material |
  |---|---|---|
  | constraints | 5 | 1 |
  | acceptanceCriteria | 2 | 0 |
  | openQuestions | 7 | 4 |

  This was invisible in the summary because the instrument counts marks without
  their kind. It is the same failure as the two metric defects above, one level
  down: an aggregate that cannot express the distinction it is being asked
  about.
- The reason the model marks so little is visible in the responses and is not a
  capability limit: it routes unknowns into `openQuestions`, at roughly 2.2–2.5
  per plan, because the same prompt tells it to. The marker and that rule
  compete for the same content. This is a prompt-design question for PR 4, not
  a defect: an open question does not block execution and a material mark does,
  so which one the model reaches for decides whether the guard ever fires.
- Three transport and metric defects were found by running it, each by reading
  evidence rather than by reasoning about it:
  1. llama.cpp (b10523) answers a *chunked* request body with HTTP 500
     "attempting to parse an empty input". Dart's `HttpClient` chunks any body
     written without an explicit `contentLength`. Confirmed by an A/B with curl
     on the same body. Five other `tool/` measurement scripts still send
     chunked bodies and would fail the same way.
  2. The first over-assertion metric counted every unmarked ungrounded plan and
     scored 6 of 6. Reading the raw responses showed it was measuring the
     prompt's own "if important information is missing, use openQuestions"
     rule. A plan that asks about a fact has not asserted it.
  3. The corrected metric still required a *material* mark, and then flagged a
     plan that had marked three items as assumptions without calling any
     material. Marking non-materially is a claim about consequence, not about
     knowledge. With any mark counted as disposal, over-assertion is 1/18
     rather than 2/18.
- PR 3d result, same 36 requests, same model, 0 unparsed. Restricting the
  marker to what the plan asserts did not merely stop the miscounting — it
  moved the model:

  | | 3c | 3d |
  |---|---|---|
  | marks on open questions (both arms) | 8 | **0** |
  | marks on constraints, ungrounded | 5 | **24** |
  | marks on constraints, grounded | 3 | 7 |
  | ungrounded plans with any assumption mark | 3/18 | **12/18** |
  | grounded plans with any assumption mark | 3/18 | 3/18 |

  Plan-level discrimination is now 67% against 17%, where 3c had 3 of 18 on
  both sides. Telling the model where a mark *means* something did not
  redistribute a fixed budget of marks; it produced five times as many in the
  arm that should have them and left the other arm alone.
- **The weak link has moved to materiality, and that is what gates blocking.**
  Only `assumption && material && !confirmed` blocks, and material marks run
  28% ungrounded against 11% grounded — 2.5x, against 4x for marks overall. One
  grounded plan produced three material marks. So a guard armed on materiality
  today fires on a signal noticeably noisier than the one the model actually
  produces well. PR 4 has to decide deliberately whether it blocks on
  `material` or on `assumption`, and the answer is not free either way: the
  first under-fires and mis-fires, the second blocks roughly two thirds of
  ungrounded plans.
- Surface sizing is unchanged by 3d: at most three material assumptions in a
  plan, zero in 13 of 18 ungrounded plans. Still a per-assumption approval.
- PR 3e answers the question 3d opened, and reverses its worry. The old rule
  said to write `(assumed, material)` "when the plan would change materially" —
  a definition that restates the term. It now names the consequence: material
  when being wrong would make work done under the plan have to be **thrown away
  rather than adjusted** — a different architecture, data model, dependency or
  task set — and plain `(assumed)` when only a value, a detail or an ordering
  would change.

  | | 3d | 3e |
  |---|---|---|
  | material marks per plan, ungrounded | 0.33 | **0.56** |
  | material marks per plan, grounded | 0.28 | **0.11** |
  | material discrimination | +0.06 | **+0.44** |
  | plans with a material mark, ungrounded / grounded | 28% / 11% | **33% / 6%** |
  | over-mark | 2/18 | 1/18 |
  | over-assertion | 1/18 | **0/18** |

  **Materiality is no longer the weak link; it is now the strongest signal.**
  It separates the arms six to one, where marks overall separate under two to
  one — the grounded arm's plain-`(assumed)` rate rose to 44% once the two
  forms were distinguished, which costs nothing because a plain mark does not
  block. So the guard should block on `material`, and the decision PR 4 was
  going to have to make on judgement is settled by measurement instead.
- Both 3d and 3e reproduce the same lesson at the prompt level: the model was
  not failing at epistemics, it was being asked in terms it could not check.
  Naming where a mark belongs multiplied marks fivefold; naming what
  materiality costs multiplied its discrimination sevenfold. Neither change
  touched the model, the schema, or the parser.
- Evidence: `build/ana0/marking_3e.json` and `build/ana0/raw3e/`.
- Evidence: `build/ana0/marking_3d.json` and `build/ana0/raw3d/`, against
  `build/ana0/marking_r3.json` plus the raw responses under
  `build/ana0/raw3/`. Re-run with
  `fvm dart run tool/ana0_assumption_marking_measurement.dart --endpoint
  http://<host>:1234/v1/chat/completions --model <id> --repeats 3
  --out build/ana0/marking.json --dump-dir build/ana0/raw`.
- Full suite green (the PR 4 canary assertion the only skip); `flutter analyze`
  clean.
- Full suite green apart from the canary; `flutter analyze` clean.

Next action:
- PR 4, with its one open decision already settled by 3e: **block on
  `material`**, which `blocksExecution` already does. It separates the arms six
  to one and mis-fires once in eighteen grounded plans.
- Build the confirm surface as a **per-assumption approval** on the existing
  `PendingToolApproval` hierarchy — a `PendingAssumptionConfirmation` raised
  from the guard's refusal site in `chat_notifier_tool_loop_batch.dart`,
  resolving into `confirmMaterialAssumption`. The approval flow is the only
  surface with no dead end, and the registry answers by id from outside the
  thread, so a blocked background turn is not stranded. Sizing: at most three
  material assumptions in a plan, none in 12 of 18.

  Scoped 2026-09-03, with the obstacles named so PR 4 is not mistaken for a
  small change:
  - `pending_tool_approvals.dart` (527) and `thread_scoped_chat_state.dart`
    (238) are both **exactly at their ratchet ceilings**, which the ratchet
    forbids raising. The twelfth pending type needs the same extraction PR 2
    had to do for the eleventh.
  - The guard's blocking list is captured **once per batch**
    (`ownerBlockingAssumptions`). A confirmation mid-batch does not clear it,
    so it has to become a per-call read of current conversation state, and the
    ask-then-re-evaluate loop needs an itemId seen-set so a confirmation that
    fails to clear an item cannot spin.
  - The write-back is `ConversationsNotifier.updateCurrentWorkflow`, which
    resets `workflowSourceHash` and `workflowDerivedAt` unless
    `preserveWorkflowProjection` is set. A confirmation must preserve both; it
    changes provenance, not the plan.
  - The `execute:` closure the guard runs inside is already `async`, so the ask
    can be awaited there — but every await needs the
    `_isCurrentInteractionGeneration` check the surrounding loop uses.
- Arm `MaterialContractAssumptionArming.armed` and unskip the canary's
  reachability assertion **only once a human can answer the approval in the
  app**. A domain-only PR 4 that arms the guard reproduces the ordering hazard
  ANA0 has already recorded twice: the mutation is refused and the only way to
  clear it exists in tests. If PR 4 is split, the UI half carries the arming.

### ANA1: Decompose

Status: `next`

Scope:
- Precondition edges on `ConversationWorkflowTask`, covering all three blocking
  shapes: task accepted, assumption confirmed, question resolved.
- A derived `ready` predicate. Never stored — the graph determines it, and
  storing it would add a second writer.
- Decomposition rendered but not executed.

This is the first substantially new implementation in the track: no dependency
or precondition field exists on `ConversationWorkflowTask`,
`WorktreeAgentTask`, or `SubagentTask` today.

Next action:
- Blocked on ANA0. Open question to answer first: how a child inherits the
  parent's confirmed assumptions as premises without re-sending the contract.

### ANA2: Delegate

Status: `later`

Scope:
- Map ready tasks onto `spawn_subagent` (in-conversation children, depth fixed
  at 1) and `WorktreeAgentTask` (isolated branch work with verification and
  changed-file evidence). New code is the mapping and scheduling policy, not a
  runner.

Next action:
- Blocked on ANA1. Open question to answer first: what happens to a running
  child when an assumption it depended on is contradicted mid-flight —
  continue, cancel, invalidate, or restart, as a policy rather than a
  case-by-case call.

### ANA3: Accept

Status: `later`

Scope:
- `produced` / `verified` / `accepted` as distinct states. Both existing status
  enums collapse all three into `completed`.
- The four-level acceptance model: mechanical (`verificationCommand`), evidence
  (`changedFileEvidence`), semantic (the parent's own judgment), user
  (`awaitingConfirmation`).
- One writer per state, per §10 of the design document.

Standing principle to adopt before there is a second child agent:

> A child saying "done" means `produced`. It never means `accepted`. Only
> Anabasis writes `accepted`, and only on evidence.

Precedent for taking the ownership table seriously:
`ConversationExecutionValidationStatus` already has three writers, one of which
judges prose; a fourth exit-code writer was added and reverted after the
investigation found stderr outranking a clean exit 0.

Next action:
- Blocked on ANA1 and ANA2.

### ANA4: Anabasis Workspace

Status: `later`

Scope:
- A fourth `WorkspaceMode`, with project state beside the conversation rather
  than only in it.
- Widening `MaterialContractAssumptionGuard` beyond `WorkspaceMode.coding`,
  which today is where epistemic execution control is scoped by construction.

Deliberately last: the parent boundary and the acceptance model should be
proven before they get a surface.

Next action:
- Blocked on ANA0 through ANA3.

## Foundation, Local LLM Agent, And Future Platform Vision Tracks

The `F<number>` and `LL<number>` milestones, their dependency graph, and the
phase ordering live in `docs/local_llm_agent_roadmap.md`. That document also now
contains a future platform vision layer for the control-plane work that should
follow the current local-LLM execution arc.

Implementation summary:

- Phase 0: F1 (line-count ratchet), LL1 (per-role model routing).
- Phase 1: F2 (tool loop extraction), LL2 (whole-turn checkpoints).
- Phase 2: F3 (`openai_dart` 6.x and other major upgrades), LL3 (model
  capability profiles), LL9 (local stack manager).
- Phase 3: LL4 (repo map v1), LL6 (KV-cache-friendly mode), LL14 (context
  surgery), LL15 (weak-model edit harness), LL16 (sampler auto-calibration).
- Phase 4: F4 (Hive to drift/SQLite with FTS), then LL5 (local semantic
  search), LL10 (installed-dependency grounding), LL11 (LSP bridge).
- Phase 5: LL7 (Best-of-N verification loop), LL8 (LAN inference mesh),
  LL12 (personal eval harness), F5 (ongoing large-file decomposition per
  `docs/large_file_refactor_plan.md`).
- Phase 6: LL13 (parallel agents in isolated git worktrees over the mesh),
  LL17 (self-improving harness loop gated by the personal eval suite).
- Phase 7: LL18-LL22 (idle-time autonomy: maintenance orchestration,
  in-app eval, slot substrate, profile history, and warm-up/precompute).

Future platform vision summary:

| Prefix | Leading milestone | Status | Vision |
|--------|-------------------|--------|--------|
| API | API1 | later | Normalize provider APIs into a stable Agent Event Core before broader Responses-style migration. |
| SEC | SEC1/SEC2/SEC4 | current | Correct the data perimeter, enforce taint before trusted execution, and close the runtime security release blockers from the 2026-08-14 audit; SEC3 remains later. |
| OBS | OBS1 | later | Make agent work inspectable as a timeline of model calls, tools, checkpoints, evals, and maintenance decisions. |
| COMPAT | COMPAT1 | next | Turn endpoint variance into a conformance report and compatibility badge. |
| MLIB | MLIB1 | later | Treat local models as managed artifacts with provenance, checksum, license, and verified capabilities. |
| HOOK | HOOK1-HOOK3 | current/later | Evolve external config hooks from the current basic bridge into a Claude-like lifecycle system. |
| MCP-GOV | MCP-GOV1 | later | Govern MCP tools through contract linting, trust levels, and model-specific prompt optimization. |
| RAG | RAG1-RAG6 | done/later | RAG1's evaluation contract and the RAG2 offline local index are complete. RAG3 must measure bounded vector/RRF retrieval and context budgeting before exposing current-project evidence through `search_knowledge`; agent-kb federation follows behind the same contract. |
| KC | KC1-KC5 | next/later | Close the training-cutoff gap by pushing measured environment ground truth into the prompt, since the damaging case is not missing knowledge but a model that cannot tell which of its beliefs expired. |
| EDGE | EDGE1 | later | Use embedded on-device runtimes for bounded low-risk micro-tasks and offline fallback. |
| EVAL-MOBILE | EVAL-MOBILE1 | later | Measure coding agents on Flutter/mobile failures that match Caverno's product domain. |
| MM | MM1 | later | Treat screenshots, voice, OCR, and screen recordings as traceable multimodal evidence. |
| SKILL | SKILL1-SKILL3 | done/later | In-chat skill authoring and `/skill` are done; idle-time skill mining remains deferred until trace-backed proposals are available. |
| TOOL | TOOL0-TOOL7 | next/later | Build the user-created Tools workspace through a capability-gated local manifest runtime rather than arbitrary generated code. |
| ROUTINE | ROUTINE1-ROUTINE2 | done/later | Creating scheduled routines from chat is done (`create_routine`, approval-gated, writing through `RoutinesNotifier`); managing their lifecycle from chat remains deferred. |

These vision milestones should not displace the current `next` Local LLM
milestone unless one is explicitly promoted through the normal operating loop.

## Operating Loop

1. Pick one `current` or `next` milestone.
2. Split the milestone into one atomic implementation slice.
3. Add or update focused tests for the changed policy.
4. Run format, focused tests, analysis, and the relevant smoke gate.
5. Commit with a Conventional Commits message.
6. Move the milestone status only when acceptance criteria and evidence are
   complete.
7. For future platform vision milestones, promote only one leading milestone at
   a time from `later`; keep the first slice diagnostic or schema-only unless
   the milestone already has a clear safety and verification gate.
