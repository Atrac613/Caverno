# LL28 Codex Handoff: Participant Turn Coordination

Filled from `docs/codex_task_template.md`. Roadmap entry: **LL28** in
`docs/local_llm_agent_roadmap.md` (Milestone Index + notes section). This doc is
the cold-start brief for implementing the MVP. LL28's first shipped experience is
multi-participant group discussion, but the implementation should introduce a
neutral participant-turn substrate that can later power coding pair programming
without rewriting the core turn and attribution model.

## Task

- **Goal:** Let the user invite a second resident model (e.g. one running on PC2)
  into the *same* chat thread and run a **role-based group discussion /
  brainstorm** — every participant visible in one transcript. Headline use case:
  LLM1 = facilitator, LLM2 = senior engineer, etc.
- **Architecture goal:** Build the reusable substrate as participant turn
  coordination, not a discussion-only one-off. The MVP remains chat-only, but
  use neutral names and boundaries where possible (`ConversationParticipant`,
  `ParticipantTurnCoordinator`, `ParticipantCompletionRunner`,
  `ParticipantTurnConfig`) so coding-mode pair programming can become a later
  consumer.
- **User-visible behavior:**
  - A **participant roster** above the composer showing the user + each invited
    LLM member (name, role chip, color).
  - When the first non-primary LLM is invited, the current primary assistant is
    materialized in the roster as a participant too (`endpointId == ''`, current
    effective model, default role preset = facilitator, editable afterward). This
    keeps the headline "PC1 + PC2 discuss together" behavior explicit instead of
    making the invited PC2 model replace the classic assistant.
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
  - Coding-mode pair programming. Keep the substrate compatible with it, but do
    not add coding-driver / reviewer workflows in the LL28 MVP.
  - Auto-moderator turn policy (who-speaks-next decided by a coordinator model).
  - Parallel / Mixture-of-Agents aggregation (sequential streaming only here).
  - Per-participant tool calling beyond reusing the existing approval modes —
    ship with tools **off by default**; do not invent a new approval system.
  - These belong to Phase 2 and converge toward **LL27** (auto orchestration).

## Context

- **Affected files / components:**
  - `lib/features/chat/domain/entities/message.dart` — add nullable
    `String? participantId` plus a small persisted speaker snapshot
    (`participantDisplayName`, `participantRoleLabel`, `participantColorValue`)
    so historic bubbles remain attributed even after a participant is renamed,
    disabled, or hidden (regenerate freezed/json).
  - `lib/features/chat/domain/entities/conversation.dart` — add
    `@Default([]) List<ConversationParticipant> participants` and a small
    `ParticipantTurnConfig` (turn policy, depth = singleRound | multiRound,
    `int maxRounds`, transient runtime cursor lives in `ChatState`, not persisted
    config); regenerate.
  - **New** `lib/features/chat/domain/entities/conversation_participant.dart`
    (Freezed): `id`, `displayName`, `roleLabel`, `roleSystemPrompt`,
    `endpointId` (empty = primary / PC1), `model`,
    `ToolApprovalMode toolApprovalMode` (default `defaultPermissions`),
    `bool toolsEnabled` (default `false`), `int colorValue`, `int order`,
    `bool enabled`. Keep the entity role-neutral: it represents an assistant
    participant in a conversation, not only a debate/discussion speaker.
  - **New** `lib/features/chat/domain/services/participant_turn_coordinator.dart`
    — owns participant normalization, round-robin planning, transcript transforms,
    and stop/continue cursor logic (see Implementation Notes).
  - **New or extracted** completion boundary for participant turns, e.g.
    `ParticipantCompletionRunner` — adapts the coordinator's turn requests to the
    existing streaming + mesh fallback path without making the domain service
    depend on `ChatNotifier` private methods.
  - `lib/features/chat/presentation/providers/chat_notifier.dart` (+ part files)
    — delegate to the coordinator only when `conversation.participants` is
    non-empty; the single-LLM path stays untouched.
  - `lib/features/chat/presentation/providers/chat_state.dart` — add transient
    participant-turn runtime state such as active participant id, current round,
    stop-requested flag, and cursor for continuing a paused multi-round run.
  - Chat UI under `lib/features/chat/presentation/widgets/` — participant roster,
    invite sheet, per-speaker bubble attribution, discussion controls; chat page
    wiring.
- **Naming rule:** Prefer `Participant*`, `ConversationParticipant`, and
  `ParticipantTurn*` names for reusable domain/data code. Use `Discussion*` only
  for chat-specific UI labels, role presets, and LL28 MVP copy.
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
    the endpoint is unreachable** — reuse it per participant through an injected
    completion runner. Do not make the domain coordinator call the private
    `_runSecondaryCompletion` extension directly.
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

## Shared Substrate Shape

- **Participant identity:** A conversation can contain assistant participants
  with endpoint/model/role/display metadata. Chat discussion and future coding
  pair programming should both read the same participant list and message
  attribution fields.
- **Turn planning:** A neutral coordinator decides which participant should speak
  next, tracks the runtime cursor, and transforms shared conversation state into a
  participant-specific request view. The first policy is round-robin discussion;
  future policies can add coding driver/reviewer turns or auto-moderation.
- **Completion boundary:** A runner boundary owns streaming, mesh fallback,
  request logging, and provider-specific details. The coordinator should not know
  whether a turn is chat discussion, coding advice, or a future isolated-worktree
  action.
- **Permission boundary:** Participant metadata may record an approval mode, but
  tool execution and file edits stay behind the existing approval and coding
  tool paths. The LL28 MVP keeps participant tools disabled by default.

## Implementation Notes

- **Preferred approach:**
  - Build a **`ParticipantTurnCoordinator`** (domain service) that, given the
    shared transcript + ordered enabled participants + `ParticipantTurnConfig`, plans
    turns and produces participant-specific request payloads:
    0. **Normalize participants before a discussion starts.** If any invited
       non-primary participant exists and no primary participant exists, insert a
       primary participant with `endpointId == ''`, the current effective model,
       display name "Primary Assistant", `order = 0`, and the default facilitator
       role. Keep this participant editable in the roster. Deleting a participant
       that already has messages should disable/archive it rather than hard-delete
       the only attribution source.
    1. **Per-participant message view (attribution).** When calling participant
       *X*: render *X*'s own past turns as `assistant`; render **every other**
       speaker (the user and other members) as `user` role with content prefixed
       `[<displayName> · <roleLabel>]: …`; prepend *X*'s `roleSystemPrompt` via
       `SystemPromptBuilder`. Keep this transform **pure** (transcript → per-X
       `List<Message>`) so it is unit-testable.
    2. **Resolve + call through a boundary.** The coordinator should return a
       turn request (`participant`, transformed messages, model, endpoint id,
       tool policy), then `ChatNotifier` or a small presentation/data adapter
       streams it through the existing `_meshRunner` path. Tag the produced
       `Message.participantId = X.id` and persist the speaker snapshot fields on
       the message at creation time.
    3. **Single-round:** iterate enabled participants once in `order`.
    4. **Multi-round:** loop the order up to `maxRounds`, exposing a round counter
       and a soft **stop** button. Stop should halt after the current streaming
       participant finishes; the existing cancel action remains the hard abort
       for the active stream. **Continue** clears the stop flag and resumes from
       the saved cursor until `maxRounds` is reached. User interjection cancels
       the remaining scheduled turns and starts a fresh discussion pass from the
       new user message.
  - **Isolate "who speaks next" behind one function**
    `nextSpeaker(context) -> participant?` returning round-robin order for MVP, so
    the Phase-2 auto-moderator or a coding driver/reviewer policy drops in by
    swapping that function with **no call-site churn** (mirrors the
    `RouteContext -> ResolvedEndpoint` shape in memory
    `caverno-model-routing-roadmap`).
  - **`ChatNotifier` delegates** to the coordinator only when
    `conversation.participants` is non-empty. Do not fold this into the existing
    single-LLM tool loop; the default 1:1 path must stay byte-for-byte unchanged.
  - **Preserve existing request preparation behavior.** Participant-specific
    message transforms must still pass through the existing system-prompt,
    temporal context, memory context, prompt-compaction, session-log, and
    model-handoff preparation paths. Do not stream raw coordinator messages in a
    way that bypasses `_prepareMessagesForLLM`-equivalent behavior.
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
  `participantId == null`). Speaker snapshot fields are nullable too. No migration
  step required.

## Future Coding Pair Programming

Do not build this in LL28, but preserve the extension path.

- **Target experience:** In a coding conversation, the roster can become a
  pair-programming crew: `Driver` implements, `Navigator` reviews direction,
  `Reviewer` critiques the diff, and `Verifier` interprets analyzer/test output.
- **Permission model:** Only the active driver should be able to request file
  edits or privileged tools. Navigator/reviewer/verifier participants should be
  read-only advisory participants at first, producing attributed comments or
  suggested next steps. Any later write-capable participant must still pass
  through `codingApprovalMode`, `ToolApprovalGate`, checkpoints, and the existing
  coding tool execution path.
- **Shared evidence:** Coding turns should reuse participant attribution, but the
  request view must also include coding-specific evidence such as current plan
  artifacts, diffs, diagnostics, validation output, and checkpoints. Treat those
  evidence packets as inputs to participant turns rather than plain chat text
  whenever the existing coding flow already has structured data.
- **Worktree bridge:** LL13 worktree agents are the natural future execution path
  for write-capable or parallel coding participants. Keep the LL28 substrate
  compatible with a later policy where one participant reviews in the main
  transcript while another works in an isolated worktree.
- **UX bridge:** The same roster and bubble attribution can surface coding
  participants, but coding-mode UI should default to concise attributed review
  notes and collapsible internal turns instead of making every verifier or
  tool-analysis turn as prominent as a normal chat reply.

## Similar-Pattern Search

Before finishing, confirm no parallel/duplicate path exists.

- **Search terms:** `ToolApprovalMode`, `chatApprovalMode`, `_meshRunner`,
  `_runSecondaryCompletion`, `namedEndpoints`, `MeshEndpointRouter`,
  `participantId`, `participantDisplayName`, `roleSystemPrompt`,
  `codingApprovalMode`, `WorkspaceMode.coding`, `SubagentExecutionService`,
  `WorktreeAgentTask`.
- **Files / modules to inspect:** `chat_notifier_mesh_routing.dart`,
  `mesh_endpoint_router.dart`, `tool_approval_gate.dart`, `tool_approval_cache.dart`,
  `app_settings.dart` (approval-mode + endpoint precedents), `message.dart`,
  `conversation.dart`, `chat_state.dart`, `message_bubble.dart`,
  `chat_notifier_subagent_handlers.dart`, `subagent_execution_service.dart`,
  `worktree_agent_task.dart`.
- **Follow-up tasks to watch for:** any place that assumes exactly one assistant
  speaker per conversation (rendering, memory extraction, session logging) may
  need a `participantId`-aware branch.

## Acceptance Criteria

- **Required behavior:**
  - Inviting PC2 with a role materializes the primary assistant in the roster if
    needed, then posting a prompt yields **round-robin** replies from each enabled
    member, each bubble attributed to the right participant.
  - Single-round returns the floor to the user after one pass; multi-round loops
    up to `maxRounds` and honors **stop / continue** using the soft-stop semantics
    above.
  - Participants + `ParticipantTurnConfig` persist on the `Conversation`;
    `participantId` and speaker snapshot fields persist on messages.
  - Renaming, disabling, or hiding a participant does not make historic message
    bubbles lose their displayed speaker name, role, or color.
- **Edge cases:** zero participants == today's single-LLM behavior (no regression);
  one participant == effectively the classic flow with a name; duplicate-role
  labels allowed.
- **Failure paths:** **PC2 unreachable** → `MeshEndpointRouter` demotes to primary
  and the turn still completes (graceful single-model); a mid-discussion endpoint
  drop does not fail the whole turn.
- **Accessibility / localization / platform:** en + ja strings for all new UI;
  works on the supported desktop + mobile targets; respects dark mode.
- **Substrate compatibility:** reusable domain/data code uses participant-turn
  vocabulary rather than discussion-only vocabulary, and there is no chat-only
  assumption that would block a later coding-mode participant policy.

## Verification

Use the smallest command set that proves the change.

```bash
tool/codex_verify.sh
```

For focused tests (coordinator behavior):

```bash
tool/codex_verify.sh --test test/features/chat/participant_turn_coordinator_test.dart
```

- **Unit:** test `ParticipantTurnCoordinator` with a fake completion boundary —
  primary participant normalization, attribution rendering, speaker snapshots,
  round-robin order, single vs multi-round, and soft stop / continue cursor
  behavior.
- **Adapter:** test the participant completion runner boundary with fake mesh
  routing so PC2-down demotion still completes through the existing fallback path.
- **Live (manual):** register PC2 as a mesh endpoint, invite it with a role, send
  a brainstorm prompt, confirm PC1 + PC2 both reply correctly attributed; pull PC2
  offline and confirm graceful single-model fallback. For flutter_tester reaching
  a LAN IP, tunnel via loopback (memory `caverno-lan-canary-local-network-privacy`).
- `flutter analyze` and `flutter test` clean; regenerated Freezed files committed.

## Handoff Notes

- **Summary:** MVP = participant model + roles, round-robin, single/multi-round
  toggle, sequential streaming, attributed bubbles, roster + invite UI, tools off
  by default. The reusable substrate is participant turn coordination:
  `ParticipantTurnCoordinator` owns planning, normalization, and transcript
  transforms; a thin `ParticipantCompletionRunner` boundary owns streaming and
  mesh fallback. The substrate (mesh router/runner, approval gate/cache, system
  prompt builder, NamedEndpoint settings) already exists and should be reused, not
  rebuilt.
- **Scope discipline:** keep this to one focused review pass. If per-participant
  tool loops, coding-driver behavior, or worktree execution grow large, split
  them into follow-up tasks behind the existing approval modes.
- **Risks / follow-ups:** turn latency (slowest member bounds the round);
  same-family local models are correlated (diversify for real ensemble value);
  KV-cache loss on per-turn endpoint switches. Phase 2 (auto-moderator,
  convergence heuristics, parallel/MoA aggregation) is the bridge to **LL27** —
  design `nextSpeaker` so it slots in cleanly.
