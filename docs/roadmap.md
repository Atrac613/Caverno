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
  `COMPAT<number>`, `HOOK<number>`, `EDGE<number>`,
  `EVAL-MOBILE<number>`, `MM<number>`, `MCP-GOV<number>`,
  `SKILL<number>`, and `ROUTINE<number>` for future platform vision
  milestones, also documented in `docs/local_llm_agent_roadmap.md`.
- Use `TOOL<number>` for the user-created Tools workspace and manifest runtime
  milestones documented in `docs/tools_mvp_roadmap.md`.
- Use `FORK<number>` for conversation fork/branching (chat + coding)
  milestones documented in this file under "Conversation Fork Track".
- Use `CLI<number>` for the headless runtime and user-facing terminal client
  milestones documented in this file under "Caverno CLI Track".
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
| Remote Coding | RC0 | done | Ship the P0 LAN mobile control safety gate for existing desktop coding projects. | Use `dart run tool/remote_coding_p0_release_gate.dart` before P0 release review. |
| Remote Coding | RC1 | later | Harden Remote Coding for product use with reconnect resilience, support diagnostics, and multi-device evidence. | Keep light manual smoke as sufficient until P1 release evidence becomes a release priority. |
| Caverno CLI | CLI0 | done | Establish a no-window production-path canary and freeze the terminal execution contract. | Keep the passing three-headless-plus-one-macOS comparison gate as the shared CLI baseline. |
| Caverno CLI | CLI1 | done | Extract a shared application execution runtime without changing GUI behavior. | Use the shared typed runtime and CLI1 parity evidence as the terminal frontend boundary. |
| Caverno CLI | CLI2 | done | Ship the interactive terminal MVP on the shared execution runtime. | Preserve the passing terminal and three-headless-plus-one-macOS parity gates as the CLI2 baseline; keep persistence, resume, and concurrent ownership in CLI3. |
| Caverno CLI | CLI3 | done | Reuse production persistence and enforce cross-process ownership before conversation resume. | Preserve the persistence, resume, migration-retry, and direct-lock contention gates as the CLI3 baseline. |
| Caverno CLI | CLI4 | later | Package and release the terminal client with automation-grade diagnostics. | The F5 dependency is satisfied; resume with macOS archive, launcher, checksum, and packaged-process gates, and require the signed packaged doctor for promotion. |
| Tools | TOOL0 | next | Add the Tools product surface as an empty workspace without changing LLM tool-calling behavior. | Start with navigation, naming, localization, and a safe empty state; keep manifest runtime and creation flows for TOOL1+. |
| Foundation | F1 | done | Add a CI-enforced line-count ratchet for oversized files so god-file growth reverses instead of compounding. | Lower budgets in the same PR whenever a refactor slice shrinks a budgeted file. |
| Foundation | F2 | done | Extract the tool-call loop from `ChatNotifier` behind a handler registry shared with routines and subagents. | Use the extracted dispatcher, policies, and routine batch executor as the baseline for F3, LL6, and LL7. |
| Foundation | F3 | done | Keep major dependencies current, starting with `openai_dart` 6.x. | `openai_dart` is on 6.2.0; remaining major upgrades (serious_python 2, etc.) are tracked as isolated follow-up slices. |
| Foundation | F5 | current | Stabilize package boundaries while continuing behavior-preserving large-file decomposition. | Continue ChatPage Tranche 3 with a focused workflow-editor action contract, then extract task-menu handlers as a separate slice. |
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
| Local LLM | LL5 | done | Local semantic history search via `/v1/embeddings`, stored in the F4 drift database. | Conversation history indexed + drift vector store + hybrid semantic/FTS history search UI + semantic-aware `search_past_conversations` shipped and device-verified; degrades to lexical FTS when no embeddings endpoint exists. Semantic *code* search is a deferred follow-up. Branch `feature/ll5-semantic-search` merged to main. |
| Local LLM | LL8 | done | LAN inference mesh: discover and register OpenAI-compatible endpoints, route secondary calls per role with health fallback. | Discovery probe (unauthenticated `GET /v1/models`) + named-endpoint registry + mesh settings UI + per-role endpoint routing for secondary calls with primary fallback shipped and device-verified. Full-mesh main-conversation fan-out and a periodic health-check loop are deferred follow-ups. Branch `feature/ll8-lan-inference-mesh` is already integrated into main. |
| Local LLM | LL9 | done | Local stack manager: model lifecycle controls and hardware-aware model guidance. | `Advanced > Local Stack` manages primary and LL8 endpoints across llama.cpp router, LM Studio, and Ollama, with role-model prepare, resource fit guidance, speedup guidance, and focused verification. |
| Local LLM | LL10 | done | Installed-dependency grounding: resolve APIs from the project's locked dependency sources, offline. | Use `tool/run_ll10_dependency_grounding_release_gate.sh` and `tool/run_ll10_dependency_grounding_live_canary.sh` to verify lockfile-exact source/docs grounding, future-only API rejection, and weak-model failure reduction. |
| Local LLM | LL11 | done | LSP bridge: post-edit diagnostics feedback and symbol data for the repo map. | Use `tool/run_ll11_lsp_language_server_smoke.sh` as the LL11 regression evidence; Dart/Swift live evidence is signed off, with TypeScript/Python rerun optional after installing their language servers. |
| Local LLM | LL13 | done | Parallel agents in isolated git worktrees, optionally distributed over the LL8 mesh. | Use `tool/run_ll13_worktree_agent_verify.sh` as regression evidence for registry persistence, recovery listing, worktree reservation/planning, `/agent` queueing and `--run`, materialization, endpoint balancing/capacity, orchestration, execution result persistence, run summaries, and review-ready visibility. Broader unattended agent-farm scheduling is deferred until SEC1/OBS1 guardrails. |
| Local LLM | LL31 | next | Turn-exit reason + completion explainer: tag every loop exit and replace blank/partial responses with a "why it stopped" explanation. Lead milestone — also the instrument that produces the evidence LL29/LL30 are gated on. | Thread a `turnExitReason` through the loop break sites, add a post-loop explainer + mid-work WARNING log, then run `tool/triage_session_logs.py` over real complex-task sessions. |
| Local LLM | LL29 | next | Tool-loop failure recovery: degrade gracefully on repeated tool failures instead of aborting the whole turn (inject a recovery hint and keep iterating; hard halt is opt-in). Gated on LL31 evidence. | Confirm tool-call abort dominates the LL31 exit-reason distribution first; if so, rewire the `toolFailureCounts` branch in `chat_notifier.dart` from `break` to graded warn/halt with action-oriented hints. |
| Local LLM | LL30 | next | Compaction structural pre-pass: dedupe + one-line-summarize old tool results and token-budget the protected tail before summarizing. Gated on LL31 evidence. | Confirm context bloat dominates the LL31 triage first; if so, build the pure prune/summary helper beside `ConversationCompactionService` and measure token savings in the LL14 style. |
| Local LLM | LL33 | current | Turn provenance: correlate the session log to the on-screen conversation (turnId + assistantMessageId) and record applied post-LLM transforms (guard notices), so log↔UI is traceable and guard firings are a direct triage signal instead of inferred from leaked notice prose. | Landed correlation keys + transform record + triage distribution; extend transforms to truncation/file-save/recovery next, defer Level 3 event-sourcing. |
| Platform Vision | API1 | later | Normalize Chat Completions, Responses-style APIs, and local-provider extensions into one Agent Event Core. | Promote only after the current LL backlog is stable; first slice defines the event schema and replay fixture. |
| Platform Vision | SEC1 | later | Define the Local Agent Data Perimeter for data classes, tool capabilities, and trust boundaries. | Start before expanding unattended or cross-machine tool execution beyond current approval gates. |
| Platform Vision | OBS1 | later | Build an Agent Trace Timeline for model calls, tools, checkpoints, slots, evals, and maintenance runs. | Start before making LL13 parallel worktrees a product-facing agent-farm feature. |
| Platform Vision | COMPAT1 | next | Add an OpenAI-compatible endpoint conformance suite for protocol and provider-behavior diagnostics. | Start with a diagnostic CLI seeded by LL9 live lifecycle evidence; keep model capability separate from endpoint protocol support. |
| Platform Vision | HOOK1 | current | Caverno-owned external config and basic lifecycle hook bridge for agent-kb and other local integrations. | Keep the first slice scoped to config sync, MCP server import, and session/prompt/stop hooks; defer tool-event parity to HOOK2. |
| Platform Vision | HOOK2 | later | Claude-like lifecycle hook flexibility with tool-event hooks, matchers, and normalized payloads. | Start with `PostToolUse` and `PostToolUseFailure` so agent-kb can archive successful and failed tool outcomes. |
| Platform Vision | HOOK3 | later | Advanced hook runtime: trust review, richer handler types, async execution, batch hooks, and reactive config/file events. | Keep deferred until SEC1/OBS1 define trust boundaries and trace visibility for hook side effects. |
| Platform Vision | MLIB1 | later | Store Local Model Pack manifests with provenance, checksum, quantization, license, and verified capability metadata. | Pair with LL9 model management and LL21 profile history when model-library UX becomes active. |
| Platform Vision | EDGE1 | later | Add an embedded local runtime adapter for bounded on-device micro-model tasks. | Keep first tasks low-risk and advisory: routing, memory extraction, privacy screening, and offline fallback. |
| Platform Vision | EVAL-MOBILE1 | later | Create a Flutter/mobile coding eval pack for Caverno-relevant app-development failures. | Start as local fixtures before UI productization; connect results to LL19 replay. |
| Platform Vision | MM1 | later | Treat screenshots, voice, OCR, and screen recordings as first-class multimodal evidence. | Land after SEC1/OBS1 so evidence inherits trust, redaction, and trace behavior. |
| Platform Vision | MCP-GOV1 | later | Lint MCP tool contracts for schema clarity, dangerous capabilities, and weak-model tool-selection quality. | Start before SEC3 permission diff and MCP trust-registry UX. |
| Skills | SKILL1 | done | Author skills from chat: capture the current conversation's workflow as a reusable skill via a `save_skill` tool behind a non-cacheable approval. | Shipped in `c029bf9d`: `save_skill` writes through `SkillsNotifier.upsertMarkdown`, requires fresh explicit approval, and focused tests cover create/update behavior. |
| Skills | SKILL2 | done | Drive skill lifecycle from chat with `/skill`, update-by-name, and diff-before-save review. | Shipped in `1a73c8b8`: `/skill` and `save-skill` route to `save_skill`, and existing-skill updates preview a diff before approval. |
| Routines | ROUTINE1 | next | Author scheduled routines from chat: a `create_routine` tool behind a non-cacheable approval (e.g. "ping 192.168.0.1 hourly; notify via Google Chat and a local notification"). | First slice ships `create_routine` writing through `RoutinesNotifier.createRoutine`, with approval surfacing schedule, tools, and delivery channels (Google Chat + local notification). |
| Routines | ROUTINE2 | later | Manage routines from chat: list/update/enable/disable/delete plus a near-duplicate-by-name guard. | Start after ROUTINE1 ships; reuse the SKILL2 lifecycle pattern and the skill near-duplicate guard. |
| Skills | SKILL3 | later | Mine recurring verified workflows into proposed skills during idle windows. | Wait for LL18/OBS1 evidence so proposals are grounded in traces and remain user-reviewed before adoption. |
| Fork | FORK1 | next | Chat conversation fork: branch a new thread from any message, copying history up to that point with parent linkage and drawer grouping. | Add `parentConversationId`/fork-origin fields to `Conversation`, reuse `_createConversation`/`save`, and add a per-message "fork here" affordance. |
| Fork | FORK2 | later | Coding conversation fork: reproduce the worktree/git + LL2 file state as of the fork point into an isolated worktree/branch (never shared with the parent), with a non-git snapshot fallback. Gated on FORK1 + LL2 + LL13. | Seed a fresh worktree from the parent's turn commit or LL2 checkpoint; carry `projectId`; assign a new `worktreePath`/branch. |
| Fork | FORK3 | later | Fork-tree navigation and compare: drawer fork tree, jump-to-parent, and parent-vs-fork diff. | Start after FORK1/FORK2 ship; reuse `TurnDiff` rendering for the compare view. |

Foundation F5 and the future platform vision milestones are
detailed in `docs/local_llm_agent_roadmap.md`. The user-created Tools MVP is
detailed in `docs/tools_mvp_roadmap.md`. Conversation fork milestones are
detailed below under "Conversation Fork Track".

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
| SEC | SEC1 | later | Make data classes, trust boundaries, and tool capabilities first-class policy inputs. |
| OBS | OBS1 | later | Make agent work inspectable as a timeline of model calls, tools, checkpoints, evals, and maintenance decisions. |
| COMPAT | COMPAT1 | next | Turn endpoint variance into a conformance report and compatibility badge. |
| MLIB | MLIB1 | later | Treat local models as managed artifacts with provenance, checksum, license, and verified capabilities. |
| HOOK | HOOK1-HOOK3 | current/later | Evolve external config hooks from the current basic bridge into a Claude-like lifecycle system. |
| MCP-GOV | MCP-GOV1 | later | Govern MCP tools through contract linting, trust levels, and model-specific prompt optimization. |
| EDGE | EDGE1 | later | Use embedded on-device runtimes for bounded low-risk micro-tasks and offline fallback. |
| EVAL-MOBILE | EVAL-MOBILE1 | later | Measure coding agents on Flutter/mobile failures that match Caverno's product domain. |
| MM | MM1 | later | Treat screenshots, voice, OCR, and screen recordings as traceable multimodal evidence. |
| SKILL | SKILL1-SKILL3 | done/later | In-chat skill authoring and `/skill` are done; idle-time skill mining remains deferred until trace-backed proposals are available. |
| TOOL | TOOL0-TOOL7 | next/later | Build the user-created Tools workspace through a capability-gated local manifest runtime rather than arbitrary generated code. |
| ROUTINE | ROUTINE1-ROUTINE2 | next/later | Create scheduled routines from chat (interval/daily, tools, Google Chat + local notification delivery), then manage their lifecycle from chat. |

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
