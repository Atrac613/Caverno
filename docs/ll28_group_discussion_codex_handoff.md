# LL28 Codex Handoff: Multi-Participant Group Discussion

Filled from `docs/codex_task_template.md`. Roadmap entry: **LL28** in
`docs/local_llm_agent_roadmap.md` (Milestone Index + notes section). This doc is
the cold-start brief for implementing the MVP; the design rationale also lives in
the approved plan that produced LL28.

## Task

- **Goal:** Let the user invite a second resident model (e.g. one running on PC2)
  into the *same* chat thread and run a **role-based group discussion /
  brainstorm** — every participant visible in one transcript. Headline use case:
  LLM1 = facilitator, LLM2 = senior engineer, etc.
- **User-visible behavior:**
  - A **participant roster** above the composer showing the user + each invited
    LLM member (name, role chip, color).
  - An **invite** action to add a member: choose an endpoint (from registered
    mesh endpoints / `namedEndpoints`), a model, a **role preset** (facilitator /
    senior engineer / critic / …, editable), and an approval mode.
  - When the user posts, invited members reply in **round-robin order**; each
    reply bubble is **attributed** (avatar + name + role chip) so "who said what"
    is obvious.
  - A **single-round ↔ multi-round** toggle: single-round = each member speaks
    once then the floor returns to the user; multi-round = members auto-discuss up
    to `maxRounds` with a visible **stop / continue** control and round counter.
- **Non-goals (defer; do NOT build in this MVP):**
  - Auto-moderator turn policy (who-speaks-next decided by a coordinator model).
  - Parallel / Mixture-of-Agents aggregation (sequential streaming only here).
  - Per-participant tool calling beyond reusing the existing approval modes —
    ship with tools **off by default**; do not invent a new approval system.
  - These belong to Phase 2 and converge toward **LL27** (auto orchestration).

## Context

- **Affected files / components:**
  - `lib/features/chat/domain/entities/message.dart` — add nullable
    `String? participantId` (regenerate freezed/json).
  - `lib/features/chat/domain/entities/conversation.dart` — add
    `@Default([]) List<DiscussionParticipant> participants` and a small
    `DiscussionConfig` (turn policy, depth = singleRound | multiRound,
    `int maxRounds`); regenerate.
  - **New** `lib/features/chat/domain/entities/discussion_participant.dart`
    (Freezed): `id`, `displayName`, `roleLabel`, `roleSystemPrompt`,
    `endpointId` (empty = primary / PC1), `model`,
    `ToolApprovalMode toolApprovalMode` (default `defaultPermissions`),
    `bool toolsEnabled` (default `false`), `int colorValue`, `int order`,
    `bool enabled`.
  - **New** `lib/features/chat/domain/services/group_discussion_coordinator.dart`
    — drives turns (see Implementation Notes).
  - `lib/features/chat/presentation/providers/chat_notifier.dart` (+ part files)
    — delegate to the coordinator only when `conversation.participants` is
    non-empty; the single-LLM path stays untouched.
  - Chat UI under `lib/features/chat/presentation/widgets/` — participant roster,
    invite sheet, per-speaker bubble attribution, discussion controls; chat page
    wiring.
- **Related docs:** `docs/local_llm_agent_roadmap.md` (LL28, and LL27 as the
  sibling); `docs/multi_model_orchestration_research.md` (paradigm survey — LL28
  is the user-facing manual cousin of architectures A1/A2 there).
- **Reference implementations / patterns to reuse (do not rebuild):**
  - **Endpoint resolution + call with fallback:** `MeshEndpointRouter` /
    `ResolvedEndpoint` (`lib/features/settings/domain/services/mesh_endpoint_router.dart`)
    and `MeshSecondaryCompletionRunner` (used via `_meshRunner` /
    `_runSecondaryCompletion` in
    `lib/features/chat/presentation/providers/chat_notifier_mesh_routing.dart`).
    This already routes a call to a chosen endpoint and **demotes to primary when
    the endpoint is unreachable** — reuse it per participant.
  - **Registered endpoints (PC2):** `NamedEndpoint`
    (`lib/features/settings/domain/entities/app_settings.dart:572`),
    `settings.namedEndpoints`. The roster's endpoint picker selects from these;
    reuse the selection UI in
    `lib/features/settings/presentation/pages/mesh_settings_page.dart`.
  - **Approval modes (== the user's manual / auto / full):**
    `ToolApprovalMode { defaultPermissions, autoReview, fullAccess }`
    (`app_settings.dart:27`); follow the per-context precedent
    `chatApprovalMode` / `codingApprovalMode` (`app_settings.dart:714`). Reuse
    `ToolApprovalGate` (`lib/features/chat/domain/services/tool_approval_gate.dart`),
    `ToolApprovalCache`
    (`lib/features/chat/presentation/providers/tool_approval_cache.dart`), and
    `ToolApprovalAutoReviewService`.
  - **System prompt:** prepend each participant's `roleSystemPrompt` via
    `SystemPromptBuilder`.
  - **Attribution convention:** the chat loop already re-sends tool results as a
    **user-role** message (see CLAUDE.md "Tool Calling Flow") because some local
    servers handle tool/assistant-role poorly — reuse the same approach to attribute
    other speakers.
- **Known quirks / compatibility rules / gates:**
  - **No eval gate** for LL28 (unlike LL27): the user judges quality directly.
  - **KV-cache loss on mid-thread model swap** — switching the active model
    mid-conversation drops the prefix cache; keep this in mind for the per-turn
    endpoint switching (memory `caverno-prefix-stable-tool-loop`).
  - **LAN reachability under flutter_tester** — macOS Local Network Privacy blocks
    a LAN LLM IP from the test harness; tunnel via 127.0.0.1 for live tests
    (memory `caverno-lan-canary-local-network-privacy`).
  - English-only code/comments and Conventional Commits (CLAUDE.md, highest
    priority).

## Implementation Notes

- **Preferred approach:**
  - Build a **`GroupDiscussionCoordinator`** (domain service) that, given the
    shared transcript + ordered enabled participants + `DiscussionConfig`, drives
    turns:
    1. **Per-participant message view (attribution).** When calling participant
       *X*: render *X*'s own past turns as `assistant`; render **every other**
       speaker (the user and other members) as `user` role with content prefixed
       `[<displayName> · <roleLabel>]: …`; prepend *X*'s `roleSystemPrompt` via
       `SystemPromptBuilder`. Keep this transform **pure** (transcript → per-X
       `List<Message>`) so it is unit-testable.
    2. **Resolve + call.** Use `MeshEndpointRouter.resolve(...)` then run the
       completion via the existing `_meshRunner` path; tag the produced
       `Message.participantId = X.id`.
    3. **Single-round:** iterate enabled participants once in `order`.
    4. **Multi-round:** loop the order up to `maxRounds`, exposing stop / continue
       and a round counter; the user can interject at any time.
  - **Isolate "who speaks next" behind one function**
    `nextSpeaker(context) -> participant?` returning round-robin order for MVP, so
    the Phase-2 auto-moderator drops in by swapping that function with **no
    call-site churn** (mirrors the `RouteContext -> ResolvedEndpoint` shape in
    memory `caverno-model-routing-roadmap`).
  - **`ChatNotifier` delegates** to the coordinator only when
    `conversation.participants` is non-empty. Do not fold this into the existing
    single-LLM tool loop; the default 1:1 path must stay byte-for-byte unchanged.
  - **Streaming = sequential** (one participant streams to completion, then the
    next) — reuses the current single-stream UI and reads like a real discussion.
- **Constraints:** Riverpod `Notifier` / `NotifierProvider` (not BLoC); Freezed
  immutable entities; widgets ≤ 200 lines and split large `build` methods;
  `const` constructors; i18n via `assets/translations/{en,ja}.json`.
- **Generated files needed:** after editing any entity, run
  `dart run build_runner build --delete-conflicting-outputs` and commit the
  regenerated `*.freezed.dart` / `*.g.dart`.
- **Migration / data compatibility:** `Message.participantId` is **nullable** and
  `Conversation.participants` defaults to **empty**, so existing Hive-persisted
  conversations deserialize unchanged and behave exactly as today (single LLM,
  `participantId == null`). No migration step required.

## Similar-Pattern Search

Before finishing, confirm no parallel/duplicate path exists.

- **Search terms:** `ToolApprovalMode`, `chatApprovalMode`, `_meshRunner`,
  `_runSecondaryCompletion`, `namedEndpoints`, `MeshEndpointRouter`,
  `participantId`, `roleSystemPrompt`.
- **Files / modules to inspect:** `chat_notifier_mesh_routing.dart`,
  `mesh_endpoint_router.dart`, `tool_approval_gate.dart`, `tool_approval_cache.dart`,
  `app_settings.dart` (approval-mode + endpoint precedents), `message.dart`,
  `conversation.dart`.
- **Follow-up tasks to watch for:** any place that assumes exactly one assistant
  speaker per conversation (rendering, memory extraction, session logging) may
  need a `participantId`-aware branch.

## Acceptance Criteria

- **Required behavior:**
  - Inviting PC2 with a role and posting a prompt yields **round-robin** replies
    from each enabled member, each bubble attributed to the right participant.
  - Single-round returns the floor to the user after one pass; multi-round loops
    up to `maxRounds` and honors **stop / continue**.
  - Participants + `DiscussionConfig` persist on the `Conversation`;
    `participantId` persists on messages.
- **Edge cases:** zero participants == today's single-LLM behavior (no regression);
  one participant == effectively the classic flow with a name; duplicate-role
  labels allowed.
- **Failure paths:** **PC2 unreachable** → `MeshEndpointRouter` demotes to primary
  and the turn still completes (graceful single-model); a mid-discussion endpoint
  drop does not fail the whole turn.
- **Accessibility / localization / platform:** en + ja strings for all new UI;
  works on the supported desktop + mobile targets; respects dark mode.

## Verification

Use the smallest command set that proves the change.

```bash
tool/codex_verify.sh
```

For focused tests (coordinator behavior):

```bash
tool/codex_verify.sh --test test/features/chat/group_discussion_coordinator_test.dart
```

- **Unit:** test `GroupDiscussionCoordinator` with a fake `ChatDataSource` —
  attribution rendering, round-robin order, single vs multi-round, stop control,
  and PC2-down demotion (via `MeshEndpointRouter` fallback).
- **Live (manual):** register PC2 as a mesh endpoint, invite it with a role, send
  a brainstorm prompt, confirm PC1 + PC2 both reply correctly attributed; pull PC2
  offline and confirm graceful single-model fallback. For flutter_tester reaching
  a LAN IP, tunnel via loopback (memory `caverno-lan-canary-local-network-privacy`).
- `flutter analyze` and `flutter test` clean; regenerated Freezed files committed.

## Handoff Notes

- **Summary:** MVP = participant model + roles, round-robin, single/multi-round
  toggle, sequential streaming, attributed bubbles, roster + invite UI, tools off
  by default. Coordinator sits alongside `ChatNotifier`; the substrate (mesh
  router/runner, approval gate/cache, system prompt builder, NamedEndpoint
  settings) already exists and should be reused, not rebuilt.
- **Scope discipline:** keep this to one focused review pass. If per-participant
  tool loops grow large, split them into a follow-up task behind the existing
  approval modes.
- **Risks / follow-ups:** turn latency (slowest member bounds the round);
  same-family local models are correlated (diversify for real ensemble value);
  KV-cache loss on per-turn endpoint switches. Phase 2 (auto-moderator,
  convergence heuristics, parallel/MoA aggregation) is the bridge to **LL27** —
  design `nextSpeaker` so it slots in cleanly.
