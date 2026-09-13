# Caverno Roadmap

This roadmap is the cross-track index for Caverno implementation work. It keeps
milestone identifiers stable so planning notes, test reports, and release
handoffs can refer to the same unit of work over time.

## Reading This Roadmap

Start with [Active Focus](#active-focus) to select work. Open the owning track
document for scope, dependencies, acceptance criteria, and dated evidence.
This is a cross-track selection index, not an exhaustive copy of every track's
milestones. An omitted row does not mean a capability is unplanned.

| Area | Owning documents |
|---|---|
| Goal-driven work | [Anabasis roadmap](anabasis_roadmap.md), [Plan Mode roadmap](plan_mode_roadmap.md) |
| Project continuity vision | [Anabasis Project Vision](anabasis_project_vision.md); independent of ANA4 completion |
| Local execution, foundation, knowledge, and platform milestones | [Local LLM Agent Roadmap](local_llm_agent_roadmap.md#milestone-index) |
| User-created Tools | [Tools MVP Roadmap](tools_mvp_roadmap.md) |
| Terminal and conversation branching | [CLI roadmap](caverno_cli_roadmap.md), [Fork roadmap](conversation_fork_roadmap.md) |
| Watch and remote interaction | [Watch roadmap](apple_watch_roadmap.md), [security follow-up](security_followup_review_2026-08-24.md) |
| macOS Computer Use | [Grounding release roadmap](macos_computer_use_element_grounding_release_roadmap.md) |
| User memory continuity | [Portable Memory And Model Continuity](portable_memory_investigation_2026-09-06.md) |
| Repository developer efficiency | [Developer Efficiency Roadmap](codex_developer_efficiency_roadmap.md) |
| Completed work | [Completed Roadmap Baselines](roadmap_completed_baselines.md) |

Update a milestone's owning document and its index row together. Keep historical
investigation notes in the owner document, while its current summary and next
action explain which earlier proposals have been superseded. Future visions
become implementation milestones only through an explicit promotion decision.

## Milestone Conventions

- Use `MEM<number>` for portable memory and model-continuity milestones,
  documented in `docs/portable_memory_investigation_2026-09-06.md`.
- Use `PM<number>` for Plan Mode milestones in `docs/plan_mode_roadmap.md`.
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
  milestones documented in `docs/conversation_fork_roadmap.md`.
- Use `CLI<number>` for the headless runtime and user-facing terminal client
  milestones documented in `docs/caverno_cli_roadmap.md`.
- Use `WATCH<number>` for the Apple Watch companion milestones documented in
  `docs/apple_watch_roadmap.md`, with the shipped design in
  `docs/apple_watch_companion.md`.
- Use `ANA<number>` for Anabasis orchestrator milestones — epistemic grounding,
  task decomposition, delegation, and acceptance — documented in
  `docs/anabasis_roadmap.md`, with the design in
  `docs/ANABASIS_ORCHESTRATOR_ARCHITECTURE.md`.
- Use `DX<number>` for repository developer-efficiency milestones — reducing
  model-visible command output while preserving complete diagnostics —
  documented in `docs/codex_developer_efficiency_roadmap.md`.
- Use one of these statuses: `done`, `current`, `next`, `blocked`, `later`.
- Every active milestone should record scope, acceptance criteria, verification
  evidence, and the next action.
- Prefer small follow-up commits that complete one milestone slice at a time.
- `done` records completion of the named scope; it does not imply that later
  integration work or a current release gate has passed. Keep completed rows
  in the baseline archive and unfinished rows in the matching status group.

## Active Focus

Structural review: 2026-09-13, against local main `70466c022` and the
owning roadmap documents. This aligns status placement and current summaries;
it does not rerun historical release, device, or live-model gates.
`current` means unfinished track scope, not simultaneous implementation.
`next` is a candidate within a track, not a commitment to start every candidate.

### Recommended Next Slice

ANA3 closed on 2026-09-13: run 12 of the worktree canary wrote an acceptance on
the worktree route's own evidence — a branch, a green verification command, and
one changed file — after a turn restricted to `accept_task` asked for it. Two
prose asks in the same run got prose answers, which reproduces the `update_goal`
finding on a second tool. ANA0 through ANA3 are now all `done`.

That makes **ANA4 the promotion decision**, not another ANA3 slice. Before
promoting it, settle its completion boundary: one goal carried end to end, with
the project vision explicitly independent of it. The one acceptance route still
unobserved is a *subagent* result — it passes no audit level, so it rests on the
parent's word alone and is a different claim from the one run 12 settled.

Scoping ANA4 on 2026-09-13 found two things already broken rather than unbuilt,
and both are fixed: ANA2's contradiction policy had no production caller, so
every acceptance was written without the premise check; and the acceptance detail
had no production reader, so `[accepted]` told the next turn nothing about what
it rested on. ANA4's third acceptance criterion — the evidence behind an
acceptance accessible from the workspace — is met as a result. Two ceilings were
hit landing it, and one is a standing hazard: the frozen RAG2 development
declaration replays against the **live working tree** and its five chat source
roots now sit at exactly 512 of a frozen 512-file cap, so the next file added
under `lib/features/chat/domain/{entities,services}` or
`presentation/providers` fails a blocked track's evaluation with a
RAG-shaped error. Pinning that replay to the commit it was frozen at is the
repair; it belongs to the RAG track.

This is an implementation recommendation, not a release sign-off.
[Security promotion gates](#security-promotion-gates) still apply. Keep one
implementation slice active.

### In Progress

| Track | Milestone | Status | Goal | Next action |
|-------|-----------|--------|------|-------------|
| Remote Coding | RC1 | current | Add authenticated confidential transport, downgrade rejection, bounded unauthenticated connections/frames, reconnect resilience, support diagnostics, and multi-device evidence. | Reconnect resilience is implemented. The remaining evidence is the iOS/Android LAN soak, support-packet review, and multi-device household check; consult the security follow-up and promotion records before release. |
| Foundation | F5 | current | Stabilize package boundaries while continuing behavior-preserving large-file decomposition. | Characterize the unowned `NetworkTools` route, interface, and path-MTU cluster selected by the 2026-07-18 full boundary inventory before extracting code. |
| Knowledge Currency | KC1 | current | Measure claim correctness, not only tool coverage: classify version-sensitive prose and code-artifact claims, compare asserted values with a fixture oracle, and record separate truth (`correct` / `stale` / `unscorable`) and grounding (`supported` / `contradicted` / `absent`) verdicts plus prompt/tool/none provenance. | Three measurements cover classes 2 and 4 and separate correctness from grounding. Finish the class 1 oracle and class 3 verdict shape before closing the gate; see [KC1](local_llm_agent_roadmap.md#kc1-cutoff-exposure-census) and `docs/knowledge_currency_track_design.md`. |
| Local LLM | LL33 | current | Turn provenance: correlate the session log to the on-screen conversation (turnId + assistantMessageId) and record applied post-LLM transforms (guard notices), so log↔UI is traceable and guard firings are a direct triage signal instead of inferred from leaked notice prose. | Landed correlation keys + transform record + triage distribution; extend transforms to truncation/file-save/recovery next, defer Level 3 event-sourcing. |
| Security | SEC1 | current | Reopen the Local Agent Data Perimeter where the audit found incomplete capability and trust classification. | Classify every HTTP/browser action and result, and distinguish host-wide reads from project reads. Routine external MCP is now deny-by-default (SEC4.4c); reviewed grants remain a later slice. |
| Security | SEC4 | current | Close the runtime trust, egress, transport, and local-data findings recorded in the 2026-08-14 audit and 2026-08-24 follow-up. | Every finding in the 2026-08-14 audit and the 2026-08-24 follow-up now carries a remediation record, measured 2026-09-06: SA-16 closed by SEC4.7c, and SA-02 — the only High with no status at all — recorded against the shipped quarantine. SA-18 was already closed by SEC4.6j on 2026-08-23, five days before the text that called it partial. What is left is SA-09's reviewed routine MCP grants, which the audit calls a later slice: external MCP tools are denied in routines today, and granting them needs server identity, tool name, schema digest, and reviewed read-only intent bound together. |
| Platform Vision | HOOK1 | current | Caverno-owned external config and basic lifecycle hook bridge for agent-kb and other local integrations. | The SEC4.2 fail-closed import and exact-review boundary is complete. Defer tool-event parity to HOOK2 while SEC1/OBS1 establish trust and trace contracts. |
| Watch | WATCH5 | current | Carry a pending approval to the phone over push, actionable where the device is granted that kind. | Push delivery, lock-screen approval, and native withdrawal have hardware evidence dated 2026-09-09/10. Complete the remaining device matrix; see [WATCH5](apple_watch_roadmap.md#watch5-push-originated-notification-actions). |

### Ready Candidates

| Track | Milestone | Status | Goal | Next action |
|-------|-----------|--------|------|-------------|
| Tools | TOOL0 | next | Add the Tools product surface as an empty workspace without changing LLM tool-calling behavior. | Start with navigation, naming, localization, and a safe empty state; keep manifest runtime and creation flows for TOOL1+. |
| Retrieval | RAG3R | next | Determine whether a dedicated post-answer groundedness detector is materially new, locally runnable, and capable of meeting the frozen RAG3 gates. | Start with artifact, license, runtime, and one synthetic five-evidence feasibility probe for Beyond Document Grounding, MiniCheck, and FactCG. Only a runnable candidate with a credible path to p95 <= 1,200 ms may receive a separately frozen 20-case non-promotion contract. Reuse KC1's truth-versus-grounding label separation, but do not couple KC1 delivery to RAG3. No production or promotion wiring. Research: `docs/rag_groundedness_detector_research_2026-09-01.md`. |
| Knowledge Currency | KC2 | next | Push measured toolchain and dependency ground truth into the prompt while preserving the datetime anchor that `SystemPromptBuilder` already emits unconditionally. | Content settled by KC1's second measurement 2026-09-03: carry **what changed**, not only which version — a delta block cut stale claims from 76% to 28% over 75 claims, fixing every API it covered and none it did not. The version list stays because it is what fixes class 4. The open question is now coverage, not mechanism: recency window, project imports, or the symbols a draft actually used. Extract a shared LL10 dependency inventory, attest locked versus installed versions as exact/mismatch/unverifiable, omit non-exact versions from authoritative context, cache by project/metadata fingerprints, and keep the block in the dynamic tail. |
| Platform Vision | COMPAT1 | next | Add an OpenAI-compatible endpoint conformance suite for protocol and provider-behavior diagnostics. | Start with a diagnostic CLI seeded by LL9 live lifecycle evidence; keep model capability separate from endpoint protocol support. |
| Routines | ROUTINE3 | next | In-chat `/loop <interval> <prompt>`: repeat a prompt inside the current conversation on an interval, keeping its history, tool-approval cache, workspace lease, and thread identity. Distinct from ROUTINE1's `create_routine`, which persists a catalog entity that runs against its own isolated context. | Reuse `GoalAutoContinueSafeBoundary` for the resend veto and honor the LL38 steering/queue owner-receipt contract; model-paced intervals and push-woken background ticks are follow-ups. Scoped 2026-09-01. |
| Remote Coding | RC2 | next | Retire the notification-relay QR path now that pairing sets push up over the authenticated socket. | Gated on the WATCH5 device check, not on design: removing the fallback before the push path is proven on hardware takes away the manual re-setup route that the 2026-09-09 diagnosis needed. Delete the desktop bell and its QR dialog (`remote_coding_settings_page.dart`), `state.relayPairingPayload` with the `showQr` argument and its expiry timer, the mobile `_scanNotificationRelayCode`, and `authorizeNotificationRelayFromQr`. Keep `createNotificationRelayPairingPayload` — the WSS `requestNotificationRelay` handler calls the same method with `showQr: false`, so the challenge and delegation machinery is shared, not legacy. Keep `supportsNotificationRelaySetup` and make its false branch an explicit error: version skew between a desktop and a phone is real even when backward compatibility is not a goal, and today that branch is the only thing standing between skew and silence. The bell is also the only per-device "push configured" indicator, so replace it with text in the device subtitle. The mobile bell and status banner stay: `disable()` writes a flag that `enableAfterPairing` refuses to cross, so the bell is the only way back from an explicit disable or an OS denial, and the banner is the only surface that names `unavailable`. Decided 2026-09-09. |
| Fork | FORK1 | next | Chat conversation fork: branch a new thread from any message, copying history up to that point with parent linkage and drawer grouping. | Add `parentConversationId`/fork-origin fields to `Conversation`, reuse `_createConversation`/`save`, and add a per-message "fork here" affordance. |

### Blocked — Reopen Only With New Evidence

| Track | Milestone | Status | Goal | Next action |
|-------|-----------|--------|------|-------------|
| Heuristic Removal | HEU3 | blocked | Completion claims. Premise corrected 2026-08-27: ground truth verifies a claim but cannot detect one, so this needs structured self-report or unconditional fact-stating, not a conversion. | Baseline taken: file-claim guards fire 2-3 times in 715 turns and the narrated-transcript guard never has; the measured substitute collapsed from 22 to 3 turns once harness-injected results were separated from refusals. Prerequisite instrument landed 2026-09-02: `ToolResultOrigin` makes 17 producers declare harness-feedback vs policy-refusal, and `tool/analyze_tool_results.py` reports the split plus the undeclared codes. Building it found three producers no hand-maintained list contained, one of them the corpus's most frequent. Still blocked: the declaration has to accumulate in post-change sessions before a refusal rate is readable, and the self-report design remains unmade. Re-measured 2026-09-11: only 32 never-reached-a-tool results exist post-instrument (17 declared / 15 undeclared) against the 715 turns the original collapse was decided over, so the gate is nowhere near met. That pass closed the one real undeclared producer (`anabasis_parent_authority_refused`, 8 of 15; the 3 `browser_peer_verification_unavailable` were pre-instrument builds, not a gap) and added a third origin, `malformed`, after a live defect showed a rejected-before-execution git command being counted as a policy refusal. |
| Retrieval | RAG3 | blocked | Add bounded vector retrieval, weighted RRF, context budgeting, and an active-project `search_knowledge` tool. | No measured candidate is eligible. The frozen hybrid candidate failed the unavailable-evidence gate; deterministic score, intent, and cross-arm policies lack a support signal; verbose semantic filtering misses the latency gate; compact v3 misses both quality and latency gates. Current candidate families are closed. Persistence, tools, prompts, promotion, and runtime wiring remain blocked. Evidence: `docs/rag3_post_v3_entry_contract_2026-09-01.md`. |
| Retrieval | RAG4 | blocked | Federate agent-kb memories and wiki pages with current local project evidence through the existing reviewed stdio MCP boundary. | Keep databases separate, label historical versus current authority, fail open to local search, and require additive versioned `kb_search` provenance plus a distinct Caverno source identity. HOOK2 is not a prerequisite. Blocked upstream: `kb_search` returns no timestamp, wiki hits carry no confidence or source agent, and agent-kb archiving rejects any agent outside `{claude, codex}`. |

### Deferred Backlog

| Track | Milestone | Status | Goal | Next action |
|-------|-----------|--------|------|-------------|
| Heuristic Removal | HEU4 | later | Git write confirmation. Measured 2026-08-27: 8 of 12 confirmation questions go unrecognised, including two in English and Japanese, so the assistant asks and commits without waiting. | Held deliberately: there is no token to route to, and the structural fix is moving confirmations onto `ask_user_question` rather than replacing a predicate. Blast radius is bounded by the (cacheable) git approval gate. |
| Heuristic Removal | HEU5 | later | Replace the tool-role acceptance carve-outs. | Blocked on the tool-role regeneration measurement; do not change on current evidence. First measured misfire 2026-09-11 (session 9174dbd1): `looksLikeBackgroundProcessCompletionClaim` has CJK positive markers but CJK negatives only for failure, so a Japanese answer denying completion matched on its own denial and cost a full regeneration (24.8k prompt tokens) per poll of a ten-minute release, while the same answer in English cost nothing. Patched with the negated completion words only -- bare negation suffixes would trade the cost bug for a safety hole. |
| Heuristic Removal | HEU6 | later | Reduce proposal, goal-suggestion, and memory-extraction prose parsing. | Largest surface, lowest stakes; may stay best-effort by decision. |
| Caverno CLI | CLI4 | later | Package and release the terminal client with automation-grade diagnostics. | The F5 dependency is satisfied; resume with macOS archive, launcher, checksum, and packaged-process gates, and require the signed packaged doctor for promotion. |
| Retrieval | RAG5 | later | Evaluate deterministic `none`/local/agent-kb/both routing in shadow before automatic retrieval changes prompts or cost. | Activate routes only after precision, recall, unnecessary-retrieval, answer-quality, latency, and token gates pass. |
| Retrieval | RAG6 | later | Decide whether optional local reranking or ANN vector search is justified by measured quality and scale. | A documented No-Go is successful completion when 20k latency/RSS or reranker quality/VRAM gates do not justify new dependencies. |
| Knowledge Currency | KC3 | later | Extend LL10 with installed version-delta evidence: bounded CHANGELOG/migration sections and declared deprecations from the attested local package source. | The lookup already exists as a prototype: `tool/kc1_cutoff_oracle.dart` answers KC3's stated acceptance case — the symbol exists in both versions but the installed one deprecates it — so what KC3 adds is the LL10 response envelope and containment, not the resolution. Close the deprecated-but-still-present blind spot without a second resolver or knowledge store. Add a new public tool name only if tool-discovery evaluation rejects an LL10 query mode; preserve containment, provenance, and response budgets. |
| Knowledge Currency | KC4 | later | Nominate cutoff-sensitive claims from visible prose, response code blocks, changed dependency-using code, and LL11 deprecation diagnostics; let only ground-truth evidence render the verdict. | The nomination stage is measured (KC1's third measurement, 2026-09-03): a symbol index catches 25 of 25 deprecation-class stale usages, misses only staleness that is not a symbol at all, and flags 14 of 30 correct answers on bare-name collisions — so the "verdict from ground truth only" clause is load-bearing, not boilerplate, and LL11 `deprecated_member_use` is what must decide. Reuse existing recovery plumbing with a bounded turn-evidence adapter for artifacts. Annotate rather than block when verification is unavailable. Shadow precision and recall must include a stale API that appears only in edited code. |
| Knowledge Currency | KC5 | later | Record a per-model `knowledgeCutoff` date and its source so the gap can be stated as context and used to nominate verification. | Never from self-report and never treat the date as proof that a specific claim is stale. `unknown` recorded honestly beats a probed number nobody trusts; whether an LL39-style dated-fact probe can beat a static table is open. |
| Local LLM | LL29 | later | Tool-loop failure recovery: degrade gracefully on repeated tool failures instead of aborting the whole turn (inject a recovery hint and keep iterating; hard halt is opt-in). | The original 1.6% corpus basis was withdrawn on 2026-08-06; the separate coding-canary population measured 14.2%. Keep deferred until representative evidence settles the recovery gate. See [LL29](local_llm_agent_roadmap.md#ll29-tool-loop-failure-recovery-degrade-dont-abort). |
| Local LLM | LL32 | later | Deferred subdirectory instruction and skill discovery: surface newly reachable `CLAUDE.md` / rules / skill files as paths only, once per session, when a tool touches a path outside the startup discovery chain. | Corroborated 2026-07-21 by Grok Build shipping the same design; stays behind the Grounded Verification Track. |
| Local LLM | LL41 | later | Deterministic goal verification contract: a goal may carry a user-declared verification command (plus acceptance criteria) whose exit code is ground truth for the auto-continue stop decision. No verifier or judge is added — LL37's "no inline stage while a user is present" decision stands. | Gate: promote only once an LL31 turn-exit triage measures how often interactive goals end in `awaitingConfirmation` or stop on `noProgress`; today's evidence is a single session, not a rate. Scoped 2026-09-01. |
| Platform Vision | API1 | later | Normalize Chat Completions, Responses-style APIs, and local-provider extensions into one Agent Event Core. | Promote only after the current LL backlog is stable; first slice defines the event schema and replay fixture. |
| Platform Vision | OBS1 | later | Build an Agent Trace Timeline for model calls, tools, checkpoints, slots, evals, and maintenance runs. | Start before making LL13 parallel worktrees a product-facing agent-farm feature. |
| Platform Vision | HOOK2 | later | Claude-like lifecycle hook flexibility with tool-event hooks, matchers, and normalized payloads. | Start with `PostToolUse` and `PostToolUseFailure` so agent-kb can archive successful and failed tool outcomes. |
| Platform Vision | HOOK3 | later | Advanced hook runtime: richer review UX, handler types, async execution, batch hooks, and reactive config/file events. | The SEC4.2 prerequisite is complete; keep deferred until SEC1/OBS1 define trust boundaries and trace visibility for hook side effects. |
| Platform Vision | MLIB1 | later | Store Local Model Pack manifests with provenance, checksum, quantization, license, and verified capability metadata. | Pair with LL9 model management and LL21 profile history when model-library UX becomes active. |
| Platform Vision | EDGE1 | later | Add an embedded local runtime adapter for bounded on-device micro-model tasks. | Keep first tasks low-risk and advisory: routing, memory extraction, privacy screening, and offline fallback. |
| Platform Vision | EVAL-MOBILE1 | later | Create a Flutter/mobile coding eval pack for Caverno-relevant app-development failures. | Start as local fixtures before UI productization; connect results to LL19 replay. |
| Platform Vision | MM1 | later | Treat screenshots, voice, OCR, and screen recordings as first-class multimodal evidence. | Land after SEC1/OBS1 so evidence inherits trust, redaction, and trace behavior. |
| Platform Vision | MCP-GOV1 | later | Lint MCP tool contracts for schema clarity, dangerous capabilities, and weak-model tool-selection quality. | Start before SEC3 permission diff and MCP trust-registry UX. |
| Routines | ROUTINE2 | later | Manage routines from chat: list/update/enable/disable/delete plus a near-duplicate-by-name guard. | Start after ROUTINE1 ships; reuse the SKILL2 lifecycle pattern and the skill near-duplicate guard. |
| Skills | SKILL3 | later | Mine recurring verified workflows into proposed skills during idle windows. | Wait for LL18/OBS1 evidence so proposals are grounded in traces and remain user-reviewed before adoption. |
| Fork | FORK2 | later | Coding conversation fork: reproduce the worktree/git + LL2 file state as of the fork point into an isolated worktree/branch (never shared with the parent), with a non-git snapshot fallback. Gated on FORK1 + LL2 + LL13. | Seed a fresh worktree from the parent's turn commit or LL2 checkpoint; carry `projectId`; assign a new `worktreePath`/branch. |
| Fork | FORK3 | later | Fork-tree navigation and compare: drawer fork tree, jump-to-parent, and parent-vs-fork diff. | Start after FORK1/FORK2 ship; reuse `TurnDiff` rendering for the compare view. |
| Watch | WATCH12 | later | Say what a running turn is actually doing: the tool in flight, and whether verification is behind mutation. | Needs a general active-tool field (`activeToolName` is participant-only) and evidence that the glance is under-informative. Do not start on either. |
| Anabasis | ANA4 | later | Dedicated workspace for carrying one goal through completion, with state beside the conversation. | Define the single-goal journey after ANA3 closure and integration scope are settled. See [ANA4](anabasis_roadmap.md#ana4-anabasis-workspace); the broader [project vision](anabasis_project_vision.md) is independent. |
| Memory Continuity | MEM1 | later | Export and restore versioned user-owned memory, including pending review and suppression state. | Freeze the archive/expiry contract, then implement a codec and clean-store restore with rollback and cross-process ownership evidence. See `docs/portable_memory_investigation_2026-09-06.md`; settings export alone is not memory portability. |
| Memory Continuity | MEM2 | later | Measure fact, preference, and constraint continuity across model changes. | After MEM1, freeze synthetic cases and thresholds; compare at least two model configurations with memory/no-memory controls. Do not equate shared memory with identical personality. |
| Memory Continuity | MEM3 | later | Preserve memory evidence and correction history. | Add source-message references, assertion origin, and supersession semantics with legacy decoding and archive compatibility. Reuse the existing memory store and approval boundaries. |

## Completed Baselines

Completed milestone summaries and dated security closure records are kept in
[Completed Roadmap Baselines](roadmap_completed_baselines.md). They are
separate from active work and do not imply a current release sign-off.

## Security Promotion Gates

The canonical security finding record is
[Security Audit](security_audit_2026-08-14.md), with evidence and the patch plan
in [Security Follow-Up Review](security_followup_review_2026-08-24.md). Its P0 exit criteria, including
follow-up findings SA-19 and SA-20, override feature-track promotion. Schema-only
and empty Tools work may proceed independently, but TOOL effect integration,
HOOK2/HOOK3, executable integration expansion, HTML Preview promotion, and
Remote Coding product promotion remain gated by their SEC4 owner. Consult
the finding record for current closure evidence; the dated closed queue is in
[Completed Roadmap Baselines](roadmap_completed_baselines.md#security-follow-up-queue-2026-08-24).

## Memory Continuity Track

Investigation and acceptance criteria:
[Portable Memory And Model Continuity](portable_memory_investigation_2026-09-06.md).

All three milestones remain `later`; this proposal does not displace current
work. MEM1 is the first slice within this track. It builds on F4 storage and CLI3
memory ownership. MEM2 evaluates model behavior separately from deterministic
archive fidelity; MEM3 adds evidence and correction history without blocking the
initial archive contract.

Workflow learning reuses completed SKILL1/SKILL2 and planned SKILL3 in
`docs/local_llm_agent_roadmap.md`; no duplicate skill-mining milestone is added.
The proposal does not reopen RAG3's blocked retrieval candidates.

## Codex Developer Efficiency Track

Scope, acceptance criteria, milestone status, and evidence:
[Codex Developer Efficiency Roadmap](codex_developer_efficiency_roadmap.md).

## Plan Mode Track

Scope, acceptance criteria, milestone status, and evidence:
[Plan Mode Roadmap](plan_mode_roadmap.md).

## Caverno CLI Track

Scope, acceptance criteria, milestone status, and evidence:
[Caverno CLI Roadmap](caverno_cli_roadmap.md).

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

Scope, acceptance criteria, milestone status, and evidence:
[Conversation Fork Roadmap](conversation_fork_roadmap.md).

## Apple Watch Companion Track

Scope, acceptance criteria, milestone status, and evidence:
[Apple Watch Companion Roadmap](apple_watch_roadmap.md).

## Anabasis Orchestrator Track

Scope, acceptance criteria, milestone status, and evidence:
[Anabasis Roadmap](anabasis_roadmap.md).

## Anabasis Project Vision

Status: future vision; independent of ANA4 completion.

The long-term destination is continuous project management across multiple
goals and conversations: preserve intent and decisions, reconcile new evidence,
and help the user choose and complete the next meaningful goal.

[Anabasis Project Vision](anabasis_project_vision.md) owns this direction and
the proposed delivery sequence. ANA4 remains the bounded single-goal workspace.
No ANA5 or later milestone is assigned yet; promote one evidence-backed slice
at a time after ANA4 experience identifies the next missing capability.

## Foundation, Local LLM Agent, And Future Platform Vision Tracks

The complete milestone index, dependency order, implementation evidence, and
platform backlog live in [Local LLM Agent Roadmap](local_llm_agent_roadmap.md).
Use its milestone index for coverage and this roadmap's Active Focus for
cross-track selection. The phase plan describes dependency order, not a queue
of work to start simultaneously.

The user-created Tools product has its own
[Tools MVP Roadmap](tools_mvp_roadmap.md). The independent
[Anabasis Project Vision](anabasis_project_vision.md) describes the destination
beyond ANA4 without reserving implementation milestones.

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
