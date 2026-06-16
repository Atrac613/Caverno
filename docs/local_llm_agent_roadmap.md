# Local LLM Agent Roadmap

This document plans the next major Caverno arc: making Caverno the strongest
coding agent specialized for local LLMs, while paying down the structural debt
that would otherwise block that work.

It introduces two tracks following the conventions in `docs/roadmap.md`:

- `F<number>` — Foundation track: refactoring, dependency currency, storage.
- `LL<number>` — Local LLM Agent track: features that attack local-LLM-specific
  constraints (small context, heterogeneous model capability, slow inference)
  and weaponize the one local asset: zero marginal token cost.

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

## Milestone Index

| Track | Milestone | Status | Size | Depends on | Goal |
|-------|-----------|--------|------|------------|------|
| Foundation | F1 | done | S | — | CI-enforced line-count ratchet for oversized files. |
| Foundation | F2 | done | M | F1 | Extract the tool-call loop from `ChatNotifier` behind a handler registry. |
| Foundation | F3 | done | M | — | Major dependency upgrades, `openai_dart` 6.x first. |
| Foundation | F4 | later | L | — | Migrate conversations/chat memory from Hive to drift (SQLite) with FTS history search. |
| Foundation | F5 | later | ongoing | F2 | Continue large-file decomposition per `docs/large_file_refactor_plan.md` phases 2-4. |
| Local LLM | LL1 | done | S | — | Per-role model routing (memory extraction, subagents, goal suggestions, approval auto-review on a small fast model). |
| Local LLM | LL2 | done | S-M | — | Whole-turn checkpoints via shadow git, building on `rollback_last_file_change`. |
| Local LLM | LL3 | done | M | F3 (openai_dart) | Model capability profiles with automatic probing on model registration. |
| Local LLM | LL4 | done | M | LL3 | Repo map v1: ranked, compressed symbol outline injected into the system prompt. |
| Local LLM | LL5 | later | M | F4, LL4 | Local semantic code search via `/v1/embeddings`, stored in the drift database. |
| Local LLM | LL6 | done | M-L | F2, F3, LL3 | KV-cache-friendly prefix-stable request mode. |
| Local LLM | LL7 | later | M | F2, LL3 | Best-of-N patch generation gated by verification, plus overnight retry-until-green Routines. |
| Local LLM | LL8 | later | M | LL1 | LAN inference mesh: discover and route across multiple OpenAI-compatible endpoints. |
| Local LLM | LL9 | later | M | — | Local stack manager: model load/unload control and hardware-aware model guidance. |
| Local LLM | LL10 | later | M | — | Installed-dependency grounding: resolve APIs from the project's locked dependency sources, offline. |
| Local LLM | LL11 | later | M-L | — | LSP bridge: post-edit diagnostics feedback and symbol data for the repo map. |
| Local LLM | LL12 | done | M | LL3 | Personal eval harness: replay recorded real tasks to score new models. |
| Local LLM | LL13 | later | L | F2, LL2 | Parallel agents in isolated git worktrees, optionally distributed over the LL8 mesh. |
| Local LLM | LL14 | done | M | LL6 | Context surgery: stale tool-result eviction, file-read dedup, model-switch handoff brief. |
| Local LLM | LL15 | done | S-M | LL3 | Weak-model edit harness: grammar-constrained edit blocks and profile-stored few-shot exemplars. |
| Local LLM | LL16 | done | S-M | LL3 | Sampler auto-calibration: probed per-role temperature/sampler presets with runtime feedback. |
| Local LLM | LL17 | done | L | LL3, LL19, LL23 | Self-improving harness loop: cluster failure traces by verifier-grounded signature, propose minimal harness-config edits, adopt only on held-in/held-out non-regression. |
| Local LLM | LL18 | done | L | LL3, LL12, LL16, LL19 | Idle/overnight maintenance orchestrator: detect idle + AC power + night window, then chain probe → calibrate → eval → mine → eval-gated adopt and emit a morning report. |
| Local LLM | LL19 | done | M | LL12 | In-app personal eval recorder and replay executor: record sessions to eval cases and drive a candidate model through them end-to-end. |
| Local LLM | LL20 | later | M | F3, LL6 | Parallel slot execution substrate: preserve provider extension fields, pin `id_slot`, and run `--parallel N` candidates concurrently. Unblocks LL7/LL13. |
| Local LLM | LL21 | done | M | LL3, LL18 | Continuous idle re-probing and profile history: full (non-bounded) probe on idle, time-series profile versions, model-drift / quant-swap detection. |
| Local LLM | LL22 | later | M | LL4, LL6, LL18 | Idle warm-up and precompute: precompute repo map / embeddings and warm the KV cache so the first morning turn is instant. |
| Local LLM | LL23 | done | M | LL3, LL6 | Declared per-model harness config: instruction surfaces (bootstrap/verify/recovery) and runtime control policy (loop caps, recovery middleware) as a mutable schema LL17 edits. |

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
different LL8 mesh endpoints. This is the capstone: a home lab running several
unattended coding tasks overnight, each verified green before merge. LL17 is
the other capstone, closing the loop the profile thread opened: instead of
hand-tuning harness behavior per model, the app mines its own failure traces
and adapts the per-model harness under the eval regression gate. Following the
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

Scope:
- Embed code chunks and conversation history via the configured
  OpenAI-compatible `/v1/embeddings` endpoint; store vectors in the drift
  database from F4.
- Expose a `semantic_search` built-in tool and wire history search UI.
- Optional rerank stage via llama.cpp `POST /reranking` (reranker model with
  `--pooling rank`) when the endpoint advertises it.

Acceptance criteria:
- Works fully offline against LM Studio / llama.cpp embeddings endpoints.
- Degrades gracefully (lexical FTS only) when no embeddings endpoint exists.

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

### LL8: LAN Inference Mesh

Scope:
- Extend `LanScanService` host probing to detect OpenAI-compatible endpoints
  (LM Studio 1234, Ollama 11434, llama.cpp 8080, custom ports) via
  `GET /v1/models`, and offer one-tap registration as named endpoints.
- Role routing (LL1) gains an endpoint dimension: a role maps to
  endpoint + model. Health checks demote unreachable endpoints with fallback
  to the primary.
- Subagents and Best-of-N candidates (LL7) may fan out across endpoints.

Acceptance criteria:
- Discovery never sends credentials to unverified hosts; registration is
  explicit and user-confirmed.
- A dropped mesh endpoint degrades to the primary endpoint without failing
  the active turn.

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

### LL10: Installed-Dependency Grounding

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

### LL11: LSP Bridge

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

### LL13: Parallel Agents In Worktrees

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

Status: `later`

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

Deferred refinements:
- Profile history UI: show the revision list in the model settings page so the
  user can see when the last idle re-probe ran and whether a model swap was
  detected.

### LL22: Idle Warm-Up & Precompute

Status: `later`

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
- Follow-up: `recoveryMiddlewareEnabled` currently primes recovery at the prompt
  level. Upgrading it to true on-failure dynamic injection (re-sending a
  targeted recovery message when a tool actually fails) needs deeper tool-loop
  machinery and live-canary coverage, deferred to a later slice.

## Cross-Cutting Rules

- All tracks obey the F1 ratchet: no milestone may push a budgeted file past
  its budget; extraction slices lower budgets in the same PR.
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
