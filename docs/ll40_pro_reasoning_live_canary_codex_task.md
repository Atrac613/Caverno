# LL40 Pro Reasoning Live Canary Closure

## Task

- Goal: Close LL40's remaining production gate with reproducible multi-host,
  single-host degradation, cancellation, and session-log evidence.
- User-visible behavior: Pro Reasoning completes a visible chat turn, reports
  the hosts and stage progress it actually uses, and still produces an answer
  after degradation, deadline expiry, or cancellation.
- Non-goals: Replacing the prose rubric with a code verifier, raising
  llama.cpp parallel slots on one GPU, or expanding Pro Reasoning into Coding
  or Plan workspaces.

## Context

- Affected files or components: `ProReasoningRunNotifier`,
  `ProReasoningCandidateExplorer`, the Pro composer controls, chat persistence,
  LLM session logging, live-canary tooling, and LL40 roadmap evidence.
- Related docs: `docs/pro_reasoning_chat_mode_design.md` and LL40 in
  `docs/local_llm_agent_roadmap.md`.
- Reference implementation or pattern: `tool/run_chat_live_llm_canary.sh`,
  consent-gated canaries under `tool/canaries/`, and the report conventions in
  `build/integration_test_reports/`.
- Known quirks, compatibility rules, or release gates: candidates fan out
  across healthy hosts, never across slots on one GPU. A candidate endpoint
  must not cold-load an unloaded LM Studio model. Session logs are sensitive
  and must obey both the settings toggle and `CAVERNO_SESSION_LOG_ENABLED`.

## Implementation Notes

- Preferred approach: Commit the already verified local implementation first,
  then run each live workstream independently and record exact artifacts and
  outcomes. Add the smallest deterministic harness needed to make a live path
  reproducible; keep environment-specific URLs, keys, and session logs out of
  Git.
- Constraints: Preserve the ChatNotifier and aggregate file-size ratchets.
  Keep stage 2 and stage 5 tool access read-only or empty after untrusted web
  evidence. Preserve the target conversation and Pro usage attribution across
  all five stages.
- Generated files needed: AppSettings Freezed and JSON outputs are already
  generated and must remain idempotent.
- Migration or data compatibility concerns: Existing settings load with Pro
  Reasoning disabled and no pinned Pro endpoint or model.

## Workstreams

### A. Verified implementation checkpoint

Status: `complete`

- Commit the settings, routing, transport, orchestration, lifecycle, UI,
  localization, instrumentation, and deterministic tests that are already
  green.
- Re-run focused verification after staging to prove the checkpoint contains
  no unrelated changes.

Result: committed as `431a38d7` (`feat: add Pro Reasoning chat mode`).

### B. Multi-host execution

Status: `complete`

- Preflight at least two reachable endpoints without loading a cold model.
- Run one Standard Pro turn and verify candidates are distributed across the
  responding hosts while each host has at most one candidate in flight.
- Verify the visible user question and final assistant response are persisted
  in the same conversation.

Result: `pro_reasoning_live_canary_1786589936` passed in 248.674 s with two
candidates assigned to `primary-host` and `secondary-host`, all five stages,
one visible user question, one assistant response, one conversation ID, and no
stage errors.

### C. Single-host degradation

Status: `complete`

- Repeat the same workload with only one healthy endpoint.
- Verify candidate execution is sequential, progress names the one surviving
  host, and synthesis still completes before the preset deadline.

Result: the `single_host` scenario in
`pro_reasoning_live_canary_1786590203` passed in 82.505 s with two candidates,
one endpoint label, all five stages, and no stage errors.

### D. Mid-exploration cancellation

Status: `complete`

- Cancel after at least one candidate has completed and another request is in
  flight.
- Verify active transports close promptly, completed candidates are retained,
  and synthesis produces a visible answer from partial evidence.

Result: the `cancel` scenario in `pro_reasoning_live_canary_1786590203`
attempted two candidates, retained one, skipped critique, and completed visible
partial synthesis in 53.205 s. The post-cancel boundary remained under 30 s.

### E. Evidence and release decision

Status: `complete`

- Inspect the `pro_reasoning_*` operations and run summary for a shared
  conversation ID, Pro usage role, selected route/model, hosts, slots, stage
  timings, failures, cancellation, deadline status, and winner.
- Verify disabled session logging emits no Pro prompt records.
- Fix any live finding, re-run repository verification, and update LL40 to
  `done` only when B-D pass. Otherwise keep `in progress` with the exact blocker.

Result: enabled runs recorded frame, investigate, candidate, critique,
synthesis, and summary operations under one conversation and only
`proReasoning` usage attribution. The `logging_disabled` scenario in
`pro_reasoning_live_canary_1786590412` completed in 64.868 s and wrote zero Pro
operations with `CAVERNO_SESSION_LOG_ENABLED=0`. LL40 is now `done`.

## Similar-Pattern Search

- Search terms: `CAVERNO_CHAT_LIVE_CANARY`, `canary_summary.json`,
  `pro_reasoning_`, `sendHiddenPrompt`, `ModelUsageRole.proReasoning`,
  `CAVERNO_SESSION_LOG_ENABLED`, and `closeActiveTransports`.
- Files or modules inspected: chat live-canary runner and fixture, Pro
  orchestration services/providers, chat persistence, session-log store,
  endpoint health and routing, and existing LL37 evidence task documents.
- Follow-up tasks found: LL26 can use LL40's host-placement and timing evidence
  when its coding verifier-backed implementation starts.

## Acceptance Criteria

- Required behavior: B-D each produce an answer and E can attribute every
  stage to one run and conversation. Multi-host execution uses at least two
  hosts; single-host execution never overlaps candidates on that host.
- Edge cases: An unavailable endpoint, unsupported `/slots`, unsupported
  thinking override, a slow failed warm request, an empty candidate, and an
  in-flight cancellation do not lose the visible turn.
- Failure paths: Zero survivors, deadline expiry, synthesis failure, or a route
  fallback surfaces a visible result or error and leaves no orphaned owner or
  transport.
- Accessibility, localization, or platform expectations: Pro controls and
  progress remain keyboard reachable and localized in English and Japanese.

## Verification

```bash
tool/codex_verify.sh --no-codegen --no-analyze
fvm flutter analyze
fvm dart run build_runner build --delete-conflicting-outputs
git diff --check
```

Live runner:

```bash
CAVERNO_LIVE_LLM_DATA_EXPORT_ACK=1 \
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PRO_REASONING_SECONDARY_BASE_URL=... \
CAVERNO_PRO_REASONING_SECONDARY_API_KEY=... \
CAVERNO_PRO_REASONING_SECONDARY_MODEL=... \
tool/run_pro_reasoning_live_canary.sh
```

Artifacts are under `build/integration_test_reports/` and are not committed.
The canary takes only explicitly supplied endpoints and never persists keys.

## Handoff Notes

- Summary: All five closure workstreams completed on 2026-08-13. The live
  inventory kept the loaded local LM Studio model and loaded LAN llama.cpp
  model, excluded two timed-out historical addresses, and de-duplicated the LAN
  alias of the local LM Studio host.
- Tests run: 7,315 root Flutter tests, 84 package tests, 10 notification relay
  tests, 13 Python triage tests, full analysis, generated-output idempotence,
  translations, file-size ratchets, and diff checks passed after all workstreams
  completed.
- Coverage or low-coverage notes: Deterministic tests cover routing,
  cancellation, persistence, logging gates, host placement, and UI dispatch.
  Live runs cover the production provider lifecycle and actual heterogeneous
  transports. Comparative answer-quality measurement remains an LL26/LL27
  research question, not an LL40 release blocker.
- Risks or follow-ups: Reachable host inventory and loaded-model state can
  drift between runs. Refresh them immediately before every canary. The first
  run under `pro_reasoning_live_canary_1786589893` is harness-only failure
  evidence: Flutter returned synthetic HTTP 400 responses before the canary
  restored the original `HttpOverrides` value.
