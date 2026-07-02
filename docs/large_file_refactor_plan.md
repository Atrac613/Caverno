# Large File Refactor Plan

This plan tracks high-leverage refactors for Caverno files that are large enough
to slow review, increase merge risk, or make Codex tasks harder to scope. Treat
each slice as a behavior-preserving move unless the task explicitly says
otherwise.

## Current Inventory

The live inventory below was refreshed on 2026-07-02 with `wc -l`. Refresh it
again before starting a new refactor branch.

| File | Lines | Primary concern |
|------|------:|-----------------|
| `lib/features/chat/presentation/providers/chat_notifier.dart` | 9607 | Chat orchestration, tool loops, memory, workflows, persistence |
| `lib/features/chat/presentation/pages/chat_page.dart` | 5217 | Chat screen layout, drawers, modals, input wiring, plan UI |
| `lib/features/chat/data/datasources/mcp_tool_service.dart` | 5260 | Tool registry, MCP execution, built-in tool adapters |
| `lib/features/settings/presentation/pages/computer_use_settings_page.dart` | 3270 | Computer Use settings layout and validation |
| `lib/features/settings/presentation/pages/computer_use_debug_page.dart` | 2864 | Debug UI, diagnostics rendering, action controls |
| `lib/features/chat/data/datasources/network_tools.dart` | 2578 | Network discovery, scanning, and command handling |
| `test/features/chat/presentation/providers/chat_notifier_test.dart` | 18637 | Broad chat orchestration regression coverage |

## Refactor Rules

- Start with a plan that names the target concern, destination file, risk, and
  focused tests.
- Move one concern per PR. Avoid mixing extraction with behavior changes.
- Preserve public provider names and widget contracts until tests cover the new
  boundary.
- Add or move tests in the same slice so coverage follows the extracted logic.
- Run a similar-pattern search after each extraction to find repeated helper
  code or stale imports.
- Use `tool/codex_verify.sh --coverage` when the slice changes behavior around
  tool execution, Plan Mode, persistence, approval, or recovery.

## Phase 1: ChatNotifier Decomposition

Goal: reduce `chat_notifier.dart` by extracting pure or low-state services while
keeping provider wiring stable.

Candidate slices:

1. Extract tool-loop request preparation and result prompt construction.
   - Destination: `lib/features/chat/domain/services/` or existing tool-result
     prompt services when the logic already fits there.
   - Tests: chat notifier tool tests plus focused service tests.
2. Extract conversation persistence and title update helpers.
   - Destination: presentation provider helper or domain service, depending on
     whether Riverpod state is required.
   - Tests: conversations notifier tests and chat notifier persistence paths.
3. Extract memory extraction orchestration around assistant responses.
   - Destination: session memory or memory draft service boundary.
   - Tests: session memory and chat notifier memory-related cases.
4. Extract workflow proposal, approval, and recovery coordination.
   - Destination: existing conversation plan execution services where possible.
   - Tests: Plan Mode proposal, guardrail, and execution coordinator tests.

Tranche 1 status (2026-07-02):

- `PlanningResearchCollector` plus `chat_notifier_planning_research.dart`
  extracted task-research context assembly.
- `proposal_parsing_text_utils.dart`, `WorkflowProposalParser`, and
  `TaskProposalParser` moved proposal text parsing out of the notifier.
- `ProposalOptionExtraction` plus
  `chat_notifier_proposal_option_extraction.dart` moved planning-decision option
  parsing behind a focused boundary.
- `FinalAnswerClaimDetector` moved unexecuted-action claim detection out of the
  notifier and into reusable command guardrail, terminal-response, and recovery
  paths.
- `ActiveResponseRegistry` moved generation-keyed active-response conversation
  and message tracking out of the notifier.
- The `chat_notifier.dart` ratchet budget is now 9607 lines and should continue
  shrinking as each follow-up slice lands.

Next follow-up candidates:

- Tool-loop request preparation and result-prompt construction.
- Conversation persistence and title update helpers.
- Assistant-response memory extraction orchestration.
- Workflow approval and recovery coordination after the parser boundaries have
  settled.

Exit criteria:

- The notifier remains the orchestration shell.
- Extracted services have focused tests.
- Existing Plan Mode smoke and chat notifier tests still pass.

## Phase 2: ChatPage Decomposition

Goal: make the main page readable by moving stable UI sections into widgets and
builders with narrow inputs.

Candidate slices:

1. Extract drawer and conversation list wiring.
2. Extract settings and debug modal launch helpers.
3. Extract plan timeline and review-sheet host sections only when they are not
   already covered by dedicated plan widgets.
4. Extract message list affordances that do not own page-level state.

Tranche 1 status (2026-07-02):

- Approval listener registration moved to
  `lib/features/chat/presentation/pages/chat_page_approval_listeners.dart`.
- SSH, Git, local command, Computer Use, file operation, participant tool, BLE,
  and serial approval sheets moved to standalone widgets under
  `lib/features/chat/presentation/widgets/approval/`:
  `ssh_connect_approval_sheet.dart`, `ssh_command_approval_sheet.dart`,
  `git_command_approval_sheet.dart`, `local_command_approval_sheet.dart`,
  `computer_use_action_approval_sheet.dart`,
  `file_operation_approval_sheet.dart`,
  `participant_tool_approval_sheet.dart`,
  `ble_connect_approval_sheet.dart`, and `serial_open_approval_sheet.dart`.
- Workflow status label/color helpers moved to
  `lib/features/chat/presentation/widgets/workflow_status_presentation.dart`
  behind page-side delegates.
- Desktop image drag/drop handling moved to
  `lib/features/chat/presentation/widgets/chat_image_drop_target.dart`; the page
  still owns dropped attachment identity.
- Focused widget/unit coverage now exists for the new approval sheets, workflow
  status presentation helpers, and image drop target.
- Measured main-file reduction: `chat_page.dart` went from 8296 lines at tranche
  start to 5217 lines after the tranche, a reduction of 3079 lines.

Later tranche roadmap:

1. Tranche 2: workflow task run coordinator. Extract `_runWorkflowTask`,
   `_runWorkflowTaskValidation`, `_continueToNextPendingTaskIfNeeded`, the eight
   `_maybeRecoverFrom*` heuristics,
   `_maybePromoteCompletionFromValidationToolResults`, and the
   `_captureExecutionProgress*` pair into a presentation-layer coordinator class
   that holds notifier handles plus an `isMounted` callback. Precondition: add
   characterization tests first because recovery heuristics are currently pinned
   only indirectly.
2. Tranche 3: plan review and approval actions. Extract `_editPlanInChat`,
   `_cancelPlanReview`, `_approveCurrentPlanAndStart`, workflow editor handlers,
   and task-menu handlers.
3. Tranche 4: slash command handler, pinned by
   `test/features/chat/presentation/pages/chat_page_slash_commands_test.dart`.
4. Tranche 5: `build()` scaffold decomposition plus right-sidebar layout helpers
   (`_buildRightSidebarPanel` and `_wrapWithRightSidebar`), following the
   existing `chat_page_*_builders.dart` idiom.

Exit criteria:

- The page keeps navigation and top-level state ownership.
- Extracted widgets have widget tests where they encode logic or state display.
- Layout remains visually unchanged.

## Phase 3: MCP Tool Service Decomposition

Goal: separate tool discovery, built-in tool adapters, MCP transport, and result
normalization.

Candidate slices:

1. Move built-in filesystem, network, Git, and shell tool adapters behind
   small registries.
2. Extract MCP server connection and trust-state handling.
3. Extract result normalization and error envelope creation.
4. Keep public tool names and JSON shapes stable.

Exit criteria:

- Tool names, arguments, and result envelopes remain compatible.
- Existing MCP tool service tests pass without broad fixture rewrites.
- New adapters can be tested without constructing the entire service.

## Phase 4: Settings And Debug UI

Goal: reduce large settings/debug pages after the core chat and tool surfaces
are stable.

Candidate slices:

1. Extract Computer Use permission and trust panels.
2. Extract diagnostics sections with pure view models.
3. Extract repeated form fields and validation display helpers.

Exit criteria:

- Settings copy and validation behavior stay unchanged.
- Focused widget tests cover extracted panels.

## Verification Matrix

Use focused tests first, then broaden according to risk.

| Refactor area | Focused checks | Broader checks |
|---------------|----------------|----------------|
| ChatNotifier | `test/features/chat/presentation/providers/chat_notifier_test.dart` | `tool/codex_verify.sh --coverage` |
| Plan Mode workflow | `test/features/chat/presentation/providers/chat_notifier_workflow_proposal_test.dart` | Plan Mode deterministic smoke |
| ChatPage UI | page or widget tests for touched widgets | screenshot integration test when layout changes |
| MCP tools | `test/features/chat/data/datasources/mcp_tool_service_test.dart` | live canary only when model/tool-loop behavior changes |
| Network tools | `test/features/chat/data/datasources/network_tools_test.dart` | platform-specific smoke where available |

## Tracking

When starting a slice, add the task to the roadmap or issue tracker with:

- target file and destination boundary
- expected line-count reduction
- tests to move or add
- similar-pattern search terms
- rollback plan if the extraction creates behavior drift
