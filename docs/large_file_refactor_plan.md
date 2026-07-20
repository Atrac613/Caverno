# Large File Refactor Plan

This plan tracks high-leverage refactors for Caverno files that are large enough
to slow review, increase merge risk, or make Codex tasks harder to scope. Treat
each slice as a behavior-preserving move unless the task explicitly says
otherwise.

## Current Inventory

The live tracked-boundary inventory below was refreshed on 2026-07-18 with
`wc -l`. The complete non-generated 1,000-line production scan, test scan,
coverage ranking, same-library aggregates, and active-worktree ownership audit
are recorded in `docs/large_file_boundary_inventory_2026_07_18.md`. On
2026-07-19, the user confirmed that the listed auxiliary worktrees are inactive
and must not block refactor selection; the audit remains historical context.

| File | Lines | Primary concern |
|------|------:|-----------------|
| `lib/features/chat/presentation/providers/chat_notifier.dart` | 9468 | Chat orchestration, tool loops, memory, workflows, persistence |
| `lib/features/chat/presentation/pages/chat_page.dart` | 2045 | Chat provider composition, dashboard and sidebar state, modals, input wiring, and plan UI |
| `lib/features/chat/presentation/coordinators/chat_page_workspace_navigation_coordinator.dart` | 127 | Workspace, project, conversation, and assistant-mode routing |
| `lib/features/chat/presentation/coordinators/slash_command_action_coordinator.dart` | 364 | Slash command loading policy, action dispatch, mode changes, conversation actions, and worktree queueing |
| `lib/features/chat/presentation/coordinators/goal_slash_command_coordinator.dart` | 243 | Goal slash lifecycle, status summaries, budgets, and auto-continuation state |
| `lib/features/chat/presentation/coordinators/feedback_slash_command_coordinator.dart` | 95 | Feedback slash preconditions, session-log resolution, submission, and failures |
| `lib/features/chat/presentation/slash_commands/slash_command_catalog.dart` | 100 | Built-in/custom command catalog and prompt-template resolution |
| `lib/features/chat/presentation/widgets/slash_command_help_sheet.dart` | 42 | Slash command help presentation |
| `lib/features/chat/presentation/widgets/chat_page_scaffold.dart` | 87 | Compact and persistent ChatPage scaffold composition |
| `lib/features/chat/presentation/widgets/chat_right_sidebar.dart` | 114 | Controlled right-sidebar tabs, widths, and split-pane layout |
| `lib/features/chat/presentation/widgets/file_workspace_viewer_sheet.dart` | 1559 | File workspace state, file loading, path containment, and compatible diff-row rendering |
| `lib/features/chat/presentation/widgets/file_workspace_diff_parser.dart` | 97 | Pure unified-diff row classification and line-number tracking |
| `lib/features/chat/presentation/coordinators/plan_review_action_coordinator.dart` | 198 | Plan review edit, cancel, approval, projection, and task selection |
| `lib/features/chat/presentation/coordinators/workflow_editor_action_coordinator.dart` | 88 | Workflow editor save, clear, and proposal persistence |
| `lib/features/chat/presentation/coordinators/workflow_task_action_coordinator.dart` | 258 | Workflow task proposal, editor, menu routing, and status persistence |
| `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart` | 2380 | Saved-workflow execution, typed recovery dispatch, evidence, side effects, and recursion |
| `lib/features/chat/domain/services/workflow_task_run_lifecycle_policy.dart` | 56 | Pure auto-continuation selection and terminal-status classification |
| `lib/features/chat/domain/services/workflow_task_turn_route_policy.dart` | 43 | Pure typed recovery order and post-recovery gates |
| `lib/features/chat/domain/services/workflow_tool_result_failure_detector.dart` | 54 | Pure structured, command-output, and raw-text tool failure classification |
| `lib/features/chat/presentation/widgets/workflow/workflow_editor_sheet.dart` | 218 | Legacy workflow metadata editor presentation and normalization |
| `lib/features/chat/presentation/widgets/workflow/workflow_task_editor_sheet.dart` | 209 | Legacy workflow task editor presentation and normalization |
| `lib/features/chat/data/datasources/mcp_tool_service.dart` | 1202 | Tool registry, public execution facade, remaining built-in adapters |
| `lib/features/chat/data/datasources/chat_remote_datasource.dart` | 1164 | OpenAI-compatible request transport, streaming, retries, telemetry, and tool-result follow-ups |
| `lib/features/chat/data/datasources/chat_completion_response_normalizer.dart` | 183 | Pure reasoning, tool-call, finish-reason, and raw parse-failure normalization |
| `lib/features/chat/data/datasources/filesystem_tools.dart` | 1282 | Path resolution, file inspection and mutation, snapshots, and compatible diff delegates |
| `lib/features/chat/data/datasources/filesystem_diff_builder.dart` | 213 | Pure unified-diff construction, hunk rendering, fallback copy, and preview truncation |
| `lib/features/chat/data/datasources/remote_mcp_connection_manager.dart` | 317 | Remote MCP connection state, trust resolution, and invocation |
| `lib/features/chat/data/datasources/remote_mcp_tool_name_policy.dart` | 120 | Deterministic remote names, reserved-prefix neutralization, and collision retries |
| `lib/features/chat/data/datasources/built_in_network_tool_handler.dart` | 978 | Built-in network definitions, validation, and operation dispatch |
| `lib/features/chat/data/datasources/built_in_filesystem_tool_handler.dart` | 622 | Built-in filesystem definitions, execution, and rollback checkpoints |
| `lib/features/chat/data/datasources/built_in_local_command_tool_handler.dart` | 581 | Built-in local command and background-process tool routing |
| `lib/features/chat/data/datasources/built_in_ble_tool_handler.dart` | 360 | Built-in BLE definitions, normalization, execution, and result formatting |
| `lib/features/chat/data/datasources/built_in_browser_tool_handler.dart` | 395 | Built-in browser definitions, argument normalization, and approved service dispatch |
| `lib/features/chat/data/datasources/built_in_computer_use_tool_handler.dart` | 714 | Built-in Computer Use definitions, argument normalization, and post-approval service dispatch |
| `lib/features/chat/data/datasources/built_in_wifi_tool_handler.dart` | 65 | Built-in WiFi definitions, availability, dispatch, and result normalization |
| `lib/features/chat/data/datasources/built_in_lan_scan_tool_handler.dart` | 77 | Built-in LAN definitions, argument normalization, dispatch, and result handling |
| `lib/features/chat/data/datasources/built_in_serial_tool_handler.dart` | 141 | Built-in serial definitions, direct dispatch, and compatible result handling |
| `lib/features/chat/data/datasources/built_in_ssh_tool_handler.dart` | 183 | Built-in SSH definitions, post-approval command dispatch, and disconnect handling |
| `lib/features/chat/data/datasources/mcp_tool_result_normalizer.dart` | 126 | Compatible direct, JSON, command, and structured-error result construction |
| `lib/features/settings/data/model_remote_datasource.dart` | 1710 | Provider discovery, response parsing, lifecycle HTTP actions, catalog merging, and compatible metadata delegates |
| `lib/features/settings/data/model_metadata_parser.dart` | 120 | Pure model ID normalization and context-window metadata parsing |
| `lib/features/settings/presentation/pages/computer_use_settings_page.dart` | 1725 | Computer Use settings coordination, diagnostics, and remaining panels |
| `lib/features/settings/presentation/widgets/computer_use_action_gate_plan.dart` | 203 | Immutable Computer Use action-gate presentation |
| `lib/features/settings/presentation/widgets/computer_use_ipc_runtime_summary.dart` | 582 | Immutable Computer Use IPC diagnostics presentation |
| `lib/features/settings/presentation/widgets/computer_use_live_smoke_summary.dart` | 302 | Immutable Computer Use live-smoke presentation |
| `lib/features/settings/presentation/widgets/computer_use_persistence_summary.dart` | 124 | Immutable Computer Use helper-persistence presentation |
| `lib/features/settings/presentation/widgets/computer_use_permission_trust_panel.dart` | 318 | Computer Use permission flow and recovery guidance presentation |
| `lib/features/settings/presentation/widgets/computer_use_verification_summary.dart` | 107 | Immutable Computer Use onboarding-verification presentation |
| `lib/features/settings/presentation/widgets/computer_use_xpc_timing_summary.dart` | 176 | Immutable Computer Use XPC timing presentation |
| `lib/features/settings/presentation/pages/computer_use_debug_page.dart` | 1910 | Permission, runtime, diagnostics, and smoke coordination |
| `lib/features/settings/presentation/widgets/computer_use_debug_audio_card.dart` | 99 | Immutable System Audio state and action presentation |
| `lib/features/settings/presentation/widgets/computer_use_debug_display_screenshot_card.dart` | 81 | Immutable display capture and preview presentation |
| `lib/features/settings/presentation/widgets/computer_use_debug_input_card.dart` | 133 | Immutable input arming, target, field, and action presentation |
| `lib/features/settings/presentation/widgets/computer_use_debug_window_targeting_card.dart` | 163 | Immutable window actions, selection, bounds, and preview presentation |
| `lib/features/settings/presentation/widgets/computer_use_debug_diagnostics_cards.dart` | 149 | Immutable diagnostics actions, copied audit presentation, export feedback, and native result display |
| `lib/features/settings/presentation/widgets/computer_use_debug_image_preview.dart` | 153 | Screenshot decoding, zoom presentation, and source-coordinate selection |
| `lib/features/settings/presentation/widgets/computer_use_debug_onboarding_card.dart` | 94 | Typed onboarding progress, steps, and XPC readiness presentation |
| `lib/features/settings/presentation/widgets/computer_use_debug_permission_actions.dart` | 119 | Immutable ordered helper and permission action presentation |
| `lib/features/settings/presentation/widgets/computer_use_debug_permission_checklist.dart` | 94 | Typed ready, warning, and unknown permission-guidance presentation |
| `lib/features/settings/presentation/widgets/computer_use_debug_status_primitives.dart` | 424 | Debug headings, helper boundary, status rows, arming, and coordinate presentation |
| `lib/features/routines/presentation/pages/routine_detail_view.dart` | 948 | Routine provider coordination, mutations, summary, and plan presentation |
| `lib/features/routines/presentation/widgets/routine_run_history_section.dart` | 525 | Immutable run cards, metadata, transcript, and error presentation |
| `lib/core/services/lan_scan_service.dart` | 843 | LAN scan planning, probes, link-layer discovery, and result caching |
| `lib/core/services/lan_ip_network.dart` | 199 | Pure IPv4 and IPv6 CIDR value object and address ordering |
| `lib/features/chat/data/datasources/network_tools.dart` | 968 | Remaining DNS, mDNS, ping, and traceroute handling plus compatible network delegates |
| `lib/features/chat/data/datasources/network_address_utils.dart` | 34 | Pure IP normalization and deterministic address ordering |
| `lib/features/chat/data/datasources/network_http_tools.dart` | 287 | HTTP status and method execution behind an injectable client factory |
| `lib/features/chat/data/datasources/network_neighbor_tools.dart` | 266 | ARP and NDP execution, parsing, filtering, and ordering behind an injectable process runner |
| `lib/features/chat/data/datasources/network_route_tools.dart` | 1128 | Route, interface, and path-MTU diagnostics behind injectable platform IO |
| `lib/features/chat/data/datasources/network_socket_tools.dart` | 204 | Port, TLS certificate, and WHOIS execution behind injectable connectors |
| `lib/features/chat/data/datasources/network_tool_dependencies.dart` | 10 | Shared process-runner and address-lookup dependency contracts |
| `test/features/chat/presentation/providers/chat_notifier_test.dart` | 18648 | Broad chat orchestration regression coverage |

The primary files understate the effective library size because Dart `part`
files share private state and compile as one library. Current aggregate sizes
are 23,005 lines for the ChatNotifier library, 8,857 for the ChatPage library,
1,294 for the McpToolService library, and 33,189 for the ChatNotifier test
library. Ratchets must cover both the primary file and its aggregate library.

The 2026-07-18 re-inventory selected the `network_tools.dart` route, interface,
and path-MTU cluster, followed by the routine run-history, LAN IP network,
filesystem diff, model metadata, file workspace diff-row, workflow tool
failure, and workflow lifecycle boundaries. All eight slices are now complete.
They were squash-integrated into `main` as `f80132bf`. The network facade fell
from 1,996 to 968 physical lines; the independently testable route service is
1,128 lines at 93.88%
coverage, and combined executable coverage for those two files is 65.10%. The
routine detail page fell from 1,407 to 948 lines, while its independent 525-line
run-history widget reached 96.17% coverage. The LAN scan service fell from
1,038 to 843 lines, while its pure 199-line CIDR value object reached 97.87%
coverage. The filesystem service fell from 1,476 to 1,282 lines, while its pure
213-line diff builder reached 99.06% coverage. The model datasource fell from
1,813 to 1,710 lines, while its pure 120-line metadata parser reached 97.14%
coverage. The file workspace viewer fell from 1,634 to 1,559 lines, while its
pure 97-line diff-row parser reached 96.97% coverage. ChatNotifier, ChatPage,
and MessageInput are no longer deferred by worktree ownership. Their current
root-file coverage is 83.15%, 54.26%, and 65.62% respectively. The ChatPage
state contract and workspace-navigation extraction are now complete; its
127-line coordinator reached 100.00% coverage. The ChatRemoteDataSource response
normalizer is also complete: its 183-line pure boundary reached 100.00%, while
the datasource fell from 1,244 to 1,164 lines. A narrow MessageInput contract is
next. ChatNotifier still requires a narrowly scoped concern despite its size.
The workflow run coordinator fell from 2,442 to 2,392 lines across two slices.
Its pure 54-line failure detector reached 95.65% coverage, and its pure 56-line
lifecycle policy reached 100.00% coverage. A separate route-and-evidence
contract now freezes assistant-evidence precedence, bounded edit-mismatch
recovery, hidden-send liveness, continuation limits, and terminal stopping. It
also fixed matching edit-recovery reads being misclassified as task completion
when target metadata was absent. The coordinator remains at its 2,392-line
contract baseline. The follow-up typed route-policy slice extracted the exact
seven-route order and post-recovery gates into a 43-line pure service at
100.00% coverage (3/3). The coordinator shrank to 2,380 lines and reached
62.17% coverage (470/756) while retaining every side effect. The final slice
gate passed analysis, 3,913 root tests, and 13 internal-package tests at 75.01%
line coverage (53,400/71,190). The recently reduced Computer Use pages remain
paused because their coverage is above 94% and their remaining code is
orchestration-heavy, not because of worktree ownership.

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

## Phase 0: Package Boundary Foundation

Goal: use packages to enforce stable reusable boundaries, not to relocate
application composition or hide large files.

Dependency direction:

```text
Caverno Flutter application
  -> internal pure-Dart packages
  -> external Dart packages
```

Internal packages must never import `package:caverno`, Flutter, Riverpod,
storage plugins, or platform plugins. The first package is
`caverno_execution_runtime`, containing the shared runtime event, ports,
execution engine, and failure classifier used by GUI and terminal frontends.
File-backed ownership leases, persistence, Riverpod adapters, and frontend
composition remain in the application.

Follow-up package candidates require a stable second consumer and an acyclic
dependency graph. `ChatNotifier`, `ChatPage`, `McpToolService`, and settings or
debug pages remain application composition and must be decomposed in place.

Exit criteria:

- Package boundaries are checked by an architecture test.
- Repository verification resolves, analyzes, and tests every internal package.
- The root application depends on packages in one direction only.
- Runtime event schemas and frontend behavior remain unchanged.

Foundation status (2026-07-16):

- `packages/caverno_execution_runtime` now owns the shared event, ports,
  execution engine, and failure classifier behind one public library.
- The package has no Flutter, Riverpod, storage, platform, or root Caverno
  dependency. IO ownership and application composition remain in the root app.
- `test/quality/package_boundary_test.dart` rejects legacy imports, platform
  dependencies, root-package imports, and relative paths that escape the
  package.
- `tool/codex_verify.sh` discovers internal packages and runs dependency
  resolution, analysis, and tests for each package before root focused tests.
- The package passed 13 tests; the focused root integration gate passed 32
  tests; root and package analysis reported no findings.

Foundation follow-up:

- The previously planned ChatPage build-scaffold and right-sidebar boundary is
  complete under Phase 2 Tranche 5. Do not create another package until a
  stable second consumer and an acyclic dependency direction are demonstrated.

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
- The `chat_notifier.dart` ratchet budget is now 9468 lines and should continue
  shrinking as each follow-up slice lands.

Deferred follow-up candidates:

- Conversation persistence and title update helpers, plus assistant-response
  memory extraction orchestration, remain valid characterization candidates.
- Tool-loop request preparation, result-prompt construction, and workflow
  coordination now span several extracted services and active worktrees.
  Re-characterize their current ownership before treating the older candidate
  wording as an implementation task.
- `chat_notifier.dart` remains deferred while its active worktree overlaps are
  unresolved.

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

Tranche 2 status (2026-07-16):

- Product-path characterization covers bounded non-execution recovery,
  successful auto-continuation, failed-task stopping, and direct plus
  auto-continued Python runtime dependency recovery.
- A missing Python runtime recovery guard was fixed before extraction so a
  successful recovery cannot fall through to assistant-evidence or tool-less
  processing.
- `WorkflowTaskRunCoordinator` now owns task execution, saved validation,
  auto-continuation, recovery, completion promotion, and evidence capture
  without importing Flutter, localization, or Riverpod directly.
- Direct coordinator tests cover successful and failed saved validation,
  bounded continuation, blocked and incomplete stopping, and page-unmount
  liveness using the production validation inference path.
- Measured main-file reduction: `chat_page.dart` fell from 5,168 lines to 2,738
  lines. Its same-library aggregate fell from 12,774 to 10,344 lines, and the
  independent coordinator is budgeted at 2,442 lines.

Tranche 3 plan-review action status (2026-07-17):

- Product-path characterization now pins approved-plan editing, pending-edit
  cancellation, invalid approval rejection, and the existing successful
  approval-to-execution path.
- `PlanReviewActionCoordinator` owns planning entry, cancellation artifact
  restoration or clearing, approval validation and persistence, workflow
  projection fallback, page-liveness decisions, and next-task selection without
  importing Flutter, localization, or Riverpod directly.
- ChatPage retains composer state, post-frame scrolling, localized SnackBars,
  the generic execution prompt, and the existing workflow task runner behind
  thin delegates.
- `chat_page.dart` fell from 2,738 to 2,632 lines, its same-library aggregate
  fell from 10,344 to 10,230 lines, and the independent coordinator is
  ratcheted at 198 lines.
- The focused verifier passed 47 root tests plus 13 internal-package tests. The
  full repository gate passed the complete root suite plus 13 package tests at
  73.27% line coverage; the coordinator reached 88.89% coverage.

Tranche 3 workflow-editor action status (2026-07-17):

- `WorkflowEditorSheet` now owns the legacy workflow metadata modal, explicit
  initial-value precedence, field normalization, task retention, and typed save
  or clear submissions.
- `WorkflowEditorActionCoordinator` owns workflow save, empty-spec clearing,
  ordered workflow-and-plan clearing, and workflow proposal application while
  retaining current tasks and dismissing only after persistence.
- ChatPage retains plan-document blocking, modal launch, mounted-context checks,
  localization, and notifications. Task proposal, quick action, task editor,
  and task-menu paths remain unchanged.
- `chat_page.dart` fell from 2,632 to 2,609 lines, its same-library aggregate
  fell from 10,230 to 9,986 lines, the coordinator is ratcheted at 88 lines,
  and the widget is ratcheted at 218 lines.
- The focused verifier passed 44 root tests plus 13 internal-package tests. The
  full repository gate passed the complete root suite plus 13 package tests at
  73.43% line coverage; coordinator and widget coverage reached 100.00% and
  97.06%, respectively.

Tranche 3 task-action status (2026-07-17):

- `WorkflowTaskEditorSheet` now owns the legacy task modal, task field seeding,
  status selection, input normalization, and typed save or delete submissions.
- `WorkflowTaskActionCoordinator` owns task proposal application, editor CRUD,
  menu-action routing, and the distinct legacy task-list or approved-plan
  execution-progress persistence paths.
- ChatPage retains plan-document guards, modal launch, blocker dialogs, scoped
  replanning, mounted-context checks, localization, and notifications. Workflow
  quick actions remain page-owned because they send execution prompts after
  persistence.
- `chat_page.dart` fell from 2,609 to 2,506 lines, its same-library aggregate
  fell from 9,986 to 9,654 lines, the coordinator is ratcheted at 258 lines,
  and the widget is ratcheted at 209 lines.
- The focused verifier passed 51 root tests plus 13 internal-package tests. The
  full repository gate passed 3,680 root tests plus 13 package tests at 73.98%
  line coverage; coordinator and widget coverage each reached 100.00%.

Tranche 4 slash-command status (2026-07-17):

- `SlashCommandActionCoordinator` owns loading policy and every top-level slash
  action, including mode changes, conversation actions, planning, delegation,
  worktree queueing, and prompt expansion.
- `GoalSlashCommandCoordinator` and `FeedbackSlashCommandCoordinator` own their
  complete persistence and failure contracts without Riverpod reads or page
  state. The catalog and help body are independently importable and tested.
- ChatPage retains provider composition, modal launch, localization, the shared
  goal editor, language selection, dashboard state, and the normal composer
  worktree launcher behind thin callbacks.
- `chat_page.dart` fell from 2,506 to 2,271 lines and its same-library aggregate
  fell from 9,654 to 9,085 lines. All five extracted boundaries have exact
  line-count ratchets.
- The focused verifier passed 128 root tests plus 13 internal-package tests. The
  full repository gate passed 3,745 root tests plus 13 package tests at 74.11%
  line coverage. Extracted-boundary coverage ranges from 93.33% to 100.00%.

Tranche 5 build-scaffold status (2026-07-17):

- `ChatRightSidebarPanel` owns the controlled Companion and Files tabs, exact
  width calculation, surface and divider presentation, and mounted indexed
  bodies. `ChatRightSidebarLayout` owns the shared conversation and routine
  split-pane contract.
- `ChatPageScaffold` owns compact AppBar, temporary drawer, optional FAB, task
  banner, and persistent drawer/header composition using already-built child
  widgets. It imports no Riverpod, localization, or ChatPage-private types.
- ChatPage retains responsive visibility decisions, provider composition,
  localization, tab state, companion and viewer construction, browser-pane
  wrapping, navigation, and mobile keyboard dismissal.
- `chat_page.dart` fell from 2,271 to 2,133 lines and its same-library aggregate
  fell from 9,085 to 8,945 lines. The two independent widgets are ratcheted at
  87 and 114 lines.
- The focused verifier passed 58 root tests plus 13 internal-package tests. The
  full repository gate passed 3,754 root tests plus 13 package tests at 74.11%
  line coverage; both extracted widgets reached 100.00% coverage.

Workspace-navigation follow-up status (2026-07-19):

- `ChatPageWorkspaceNavigationCoordinator` owns Chat, Coding, and Routines
  workspace activation, coding-project selection, drawer conversation routing,
  and assistant-mode synchronization behind the completed product-path state
  contract.
- ChatPage retains Riverpod composition, dashboard visibility, sidebar and
  Files-tab state, workflow, approval, composer, localization, and modal state.
- `chat_page.dart` fell from 2,133 to 2,045 lines and its same-library aggregate
  fell from 8,945 to 8,857 lines. The independent coordinator is ratcheted at
  127 lines.
- The focused verifier passed 92 root tests plus 13 internal-package tests. The
  full repository gate passed 3,927 root tests plus 13 package tests at 75.19%
  line coverage (53,527/71,192). The coordinator reached 100.00% coverage
  (40/40); the page reached 54.26% (420/774), and their combined coverage is
  56.51% (460/814).

Phase 2 follow-up:

- The planned ChatPage sequence through Tranche 5 is complete and the phase
  exit criteria below are met. Refresh the oversized-file inventory before
  selecting another application boundary. Treat any later message-list or
  composer extraction as a new lifecycle-characterization task.

Exit criteria:

- The page keeps provider composition and top-level UI state ownership; the
  coordinator owns only workspace navigation transitions.
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

Network handler status (2026-07-16):

- `BuiltInNetworkToolHandler` now owns the 21 ordered network definitions,
  validation, argument normalization, error envelopes, and production
  delegation to `NetworkTools`.
- An injected operation runner keeps handler tests deterministic and avoids
  live socket, process, DNS, or mDNS access.
- Characterization preserves disabled-definition/direct-execution behavior,
  reserved-name collision handling, exact schema order, numeric clamps, HTTP
  arguments, and negative-network-fact success results.
- `mcp_tool_service.dart` fell from 5,269 to 4,096 lines, and its same-library
  aggregate fell from 5,612 to 4,439 lines. The independent handler is
  ratcheted at 978 lines.
- The focused verifier passed 74 root tests plus 13 internal-package tests.
  The full repository gate passed 3,432 root tests at 72.16% line coverage;
  the new handler reached 72.22% line coverage without live network access.

Filesystem handler status (2026-07-17):

- `BuiltInFilesystemToolHandler` owns the five inspection definitions, four
  mutation definitions, validation, argument normalization, execution,
  mutation snapshots, and rollback checkpoint lifecycle.
- Characterization preserves the exact definition placement around dependency
  grounding and LSP, platform gating, disabled direct execution, all nine
  remote-collision reservations, legacy result-envelope asymmetry, and
  first-snapshot turn rollback behavior.
- `mcp_tool_service.dart` fell from 4,096 to 3,621 lines, and its same-library
  aggregate fell from 4,439 to 3,910 lines. The independent handler is
  ratcheted at 622 lines.
- The focused verifier passed 97 root tests plus 13 internal-package tests.
  The full repository gate passed 3,445 root tests at 72.27% line coverage;
  the new handler reached 99.20% line coverage using deterministic runners and
  isolated temporary directories.

Local command handler status (2026-07-17):

- `BuiltInLocalCommandToolHandler` owns the eight ordered local command,
  background-process, and `run_tests` definitions, validation, argument
  normalization, direct execution, unavailable-provider results, process-list
  aggregation, and the exact approval sentinel.
- Characterization preserves desktop and process-capability gates,
  disabled-definition direct execution, all eight remote-collision
  reservations, Git-write rejection, truthy background coercion, mixed job-ID
  filtering, and the legacy result-envelope asymmetry.
- `mcp_tool_service.dart` fell from 3,621 to 3,076 lines, and its same-library
  aggregate fell from 3,910 to 3,365 lines. The independent handler is
  ratcheted at 587 lines.
- The focused verifier passed 108 root tests plus 13 internal-package tests.
  The full repository gate passed 3,468 root tests at 72.35% line coverage;
  the new handler reached 99.48% line coverage using deterministic providers.

Remote MCP connection manager status (2026-07-17):

- `RemoteMcpConnectionManager` owns connection state, override and trust
  resolution, remote tool caching, exposed-name aliases, client bindings, and
  invocation routing behind injected transport factories.
- Characterization preserves source precedence, pending trust-review access,
  blocked and invalid filtering, desktop stdio gating, partial and total
  failure states, configured order, 64-character aliases, original-name
  forwarding, and virtual `McpToolService.refresh()` dispatch.
- `McpToolService` remains the public facade, retains SearXNG fallback and
  provider-owned transport lifetimes, and fell from 3,076 to 2,945 lines. Its
  same-library aggregate fell from 3,365 to 3,037 lines; the independent manager
  is ratcheted at 397 lines.
- The focused verifier passed 125 root tests plus 13 internal-package tests.
  The full repository gate passed 3,487 root tests plus 13 internal-package
  tests at 72.11% line coverage; the new manager reached 90.40% coverage using
  deterministic fake clients.

Remote MCP reserved-name collision status (2026-07-17):

- `spawn_subagent`, `get_subagent_result`, and `save_skill` now remain
  unconditionally reserved, so same-named remote tools receive aliases instead
  of being intercepted by Caverno's exact built-in dispatch.
- Regression coverage preserves available, disabled, and unavailable built-in
  cases, unique OpenAI definitions, original remote names, and unchanged
  argument forwarding. `McpToolService` remains at 2,945 lines and its
  same-library aggregate remains at 3,037 lines.
- The focused verifier passed 90 root tests plus 13 internal-package tests. The
  full repository gate passed 3,489 root tests plus 13 internal-package tests at
  72.12% line coverage; an independent review reported no findings.
- Similar-pattern review found a separate prefix-dispatch bug: namespaced remote
  `browser_*` and `computer_*` aliases retain prefixes consumed by built-in
  dispatch and remain unreachable.

Remote MCP prefix-collision routing status (2026-07-17):

- Remote names matching `browser_` or `computer_`, including mixed-case and
  arbitrary names, now receive deterministic neutral `mcp__` aliases before
  they reach built-in prefix dispatch or policy classifiers.
- `RemoteMcpToolNamePolicy` owns exact reservations, case-insensitive prefix
  reservations, server-key generation, 64-character truncation, and ordered
  collision retries. Original names, schemas, source metadata, clients, and
  arguments remain unchanged in bindings and invocation.
- `McpToolService` fell from 2,945 to 2,929 lines, its same-library aggregate
  fell from 3,037 to 3,021 lines, and `RemoteMcpConnectionManager` fell from
  397 to 319 lines. The new policy is ratcheted at 120 lines.
- The focused verifier passed 104 root tests plus 13 internal-package tests.
  The full repository gate passed 3,494 root tests plus 13 internal-package
  tests at 72.13% line coverage. The policy reached 100.00% coverage and an
  independent static review reported no findings.
- Similar-pattern inspection found that generic remote MCP results are not
  consistently marked as MCP-derived in taint recording and generic MCP tools
  retain an existing Plan Mode/read-only capability-policy gap.

Remote MCP provenance and planning-policy status (2026-07-17):

- Successful and failed remote calls now carry transient external-MCP
  provenance that is excluded from serialized `McpToolResult` JSON.
- Main and participant tool paths record taint from the actual execution result,
  so remote-controlled success and error content is untrusted while local
  pre-dispatch denials remain local.
- Exact live binding lookup lets Plan Mode reject capability-unknown external
  MCP tools before invocation. Ordinary and Routine trusted-MCP execution remain
  unchanged.
- `McpToolService` fell from 2,929 to 2,924 lines and its same-library aggregate
  fell from 3,021 to 3,016 lines. `RemoteMcpConnectionManager` remains at 319
  lines and `ChatNotifier` remains at 9,468 lines.
- The focused verifier passed 109 root tests plus 13 internal-package tests. The
  full repository gate passed 3,500 root tests plus 13 internal-package tests at
  72.15% line coverage; the new taint recorder reached 100.00% coverage.

MCP tool result normalization status (2026-07-17):

- `McpToolResultNormalizer` now owns compatible direct success and failure
  results, ordered structured failure encoding, the existing `ok` payload
  interpretation, and command failure classification.
- `McpToolService`, local command envelopes, worktree session finishing, and
  remote invocation use the boundary. Legacy payload-success asymmetry, exact
  result bytes, error messages, and external provenance remain unchanged.
- `McpToolService` fell from 2,924 to 2,869 lines and its same-library aggregate
  fell from 3,016 to 2,961 lines. The local command handler fell from 587 to 581
  lines, the remote manager from 319 to 317 lines, and the normalizer is
  ratcheted at 126 lines.
- The focused verifier passed 115 root tests plus 13 internal-package tests. The
  full repository gate passed 3,506 root tests plus 13 internal-package tests at
  72.18% line coverage; the normalizer reached 100.00% coverage.

BLE handler status (2026-07-17):

- `BuiltInBleToolHandler` now owns the 16 ordered BLE definitions, availability,
  argument normalization, execution, output formatting, byte decoding, and
  compatible success and failure envelopes while reusing `BleTools` schemas.
- Characterization preserves definition placement after SSH and before WiFi,
  unavailable and disabled behavior, unconditional remote-name reservation,
  scan clamps, exact text and JSON results, all central and peripheral calls,
  value encodings, notification formatting, and service exception conversion.
- ChatNotifier remains the only approved `ble_connect` path; direct execution
  retains the existing internal-error result, and tests use a deterministic
  service subclass without initializing Bluetooth platform managers.
- `McpToolService` fell from 2,869 to 2,522 lines and its same-library aggregate
  fell from 2,961 to 2,614 lines. The independent handler is ratcheted at 360
  lines.
- The focused verifier passed 99 root tests plus 13 internal-package tests. The
  full repository gate passed 3,521 root tests plus 13 internal-package tests at
  72.98% line coverage; the handler reached 99.41% coverage and `BleTools`
  reached 99.29% without real hardware access.

WiFi handler status (2026-07-17):

- `BuiltInWifiToolHandler` now owns the three ordered WiFi definitions,
  availability, exact argument forwarding, execution, and compatible success
  and failure envelopes while reusing `WifiTools` schemas.
- Characterization preserves definition placement after BLE and before LAN,
  unavailable and disabled behavior, unconditional remote-name reservation,
  optional `sort_by` forwarding, and the legacy behavior that JSON error
  payloads remain successful tool envelopes.
- `McpToolService` fell from 2,522 to 2,483 lines and its same-library aggregate
  fell from 2,614 to 2,575 lines. The independent handler is ratcheted at 65
  lines.
- The focused verifier passed 97 root tests plus 13 internal-package tests. The
  full repository gate passed 3,529 root tests plus 13 internal-package tests at
  72.71% line coverage; the handler reached 95.45% coverage and `WifiTools`
  reached 94.44% without platform permissions or real hardware access.

LAN scan handler status (2026-07-17):

- `BuiltInLanScanToolHandler` now owns the two ordered LAN definitions,
  availability, argument normalization, execution, and compatible success and
  failure envelopes while reusing `LanScanTools` schemas.
- Characterization preserves placement after WiFi and before serial,
  unavailable and disabled behavior, unconditional remote-name reservation,
  subnet and address-family trimming, numeric timeout and port conversion,
  port ordering, cached-result sorting, and exact payload bytes.
- `McpToolService` fell from 2,483 to 2,438 lines and its same-library aggregate
  fell from 2,575 to 2,530 lines. The independent handler is ratcheted at 77
  lines.
- The focused verifier passed 103 root tests plus 13 internal-package tests.
  The full repository gate passed 3,539 root tests plus 13 internal-package
  tests at 72.84% line coverage; the handler reached 96.43% coverage and
  `LanScanTools` reached 95.45% without interfaces, probes, ARP/NDP, or mDNS.

Serial handler status (2026-07-17):

- `BuiltInSerialToolHandler` now owns the six ordered serial definitions,
  platform-aware exposure, direct argument normalization, five direct service
  calls, compatible result envelopes, and the direct `serial_open` denial
  while reusing `SerialPortTools` schemas.
- Characterization preserves placement after LAN and before Computer Use,
  unsupported-platform exposure, unavailable and disabled behavior,
  unconditional remote-name reservation, trimming and numeric conversions,
  defaults, delimiter and field forwarding, exact payload bytes, and legacy
  JSON-error success envelopes.
- ChatNotifier remains the only approved `serial_open` path. Tests use a
  deterministic `SerialPortService` subclass and never enumerate or operate
  real serial hardware.
- `McpToolService` fell from 2,438 to 2,353 lines and its same-library aggregate
  fell from 2,530 to 2,445 lines. The independent handler is ratcheted at 141
  lines.
- The focused verifier passed 124 root tests plus 13 internal-package tests.
  The full repository gate passed 3,551 root tests plus 13 internal-package
  tests at 72.90% line coverage; the handler reached 98.18% coverage and
  `SerialPortTools` reached 98.44% without native inventory or hardware access.

SSH handler status (2026-07-17):

- `BuiltInSshToolHandler` now owns the three ordered SSH definitions,
  availability, direct connect denial, approved command trimming and
  execution, disconnect execution, and compatible result envelopes.
- Characterization preserves placement after Git and before BLE, unavailable
  and disabled behavior, unconditional remote-name reservation, exact
  inactive-session guidance, command output formatting, idempotent disconnect,
  and service exception conversion.
- ChatNotifier remains the only connection path and the owner of per-command
  approval and result caching. Tests use a deterministic `SshService` subclass
  and never open sockets, authenticate, or read credentials.
- `McpToolService` fell from 2,353 to 2,191 lines and its same-library aggregate
  fell from 2,445 to 2,283 lines. The independent handler is ratcheted at 183
  lines.
- The focused verifier passed 118 root tests plus 13 internal-package tests.
  The full repository gate passed 3,563 root tests plus 13 internal-package
  tests at 72.95% line coverage; the handler reached 98.33% coverage without
  network access.

Browser handler status (2026-07-17):

- `BuiltInBrowserToolHandler` now owns all 12 ordered browser definitions,
  availability, complete prefix routing, argument normalization, service
  dispatch, and compatible JSON result normalization.
- Characterization preserves global placement after Computer Use, disabled
  direct routing, exact and prefix collision reservation, selector trimming,
  numeric and string ref conversion, defaults, exact result bytes, unknown
  prefix errors, and service exception propagation.
- ChatNotifier still owns sensitive fill, click, submit, JavaScript, and save
  approval, reviewer redaction, pending UI state, and save-target previews.
  Tests use a deterministic service subclass and do not mount a webview,
  access the network, evaluate JavaScript, or write browser save files.
- `McpToolService` fell from 2,191 to 1,861 lines and its same-library aggregate
  fell from 2,283 to 1,953 lines. The handler is ratcheted at 395 lines.
- The focused verifier passed 143 root tests plus 13 internal-package tests.
  The full repository gate passed 3,578 root tests plus 13 internal-package
  tests at 73.47% line coverage; the handler reached 100.00% coverage.

Computer Use handler status (2026-07-17):

- `BuiltInComputerUseToolHandler` now owns all 19 ordered Computer Use
  definitions, availability, complete prefix routing, argument compatibility,
  post-approval native service dispatch, and compatible JSON result
  normalization.
- Characterization preserves placement after serial and before browser,
  disabled direct routing, exact and prefix collision reservation, permission
  defaults and the legacy `screenCapture` alias, System Settings defaults,
  argument-free audio stop, exact result bytes, unknown-prefix results, and
  service exception propagation.
- ChatNotifier and `ChatToolDispatcher` still own policy classification,
  planning restrictions, target safety, action-time confirmation, approval
  caching, smoke arming, audit, result redaction, emergency stop, and
  post-action observation. Tests use a deterministic service subclass and
  perform no real desktop actions.
- `McpToolService` fell from 1,861 to 1,202 lines and its same-library aggregate
  fell from 1,953 to 1,294 lines. The handler is ratcheted at 714 lines.
- The focused verifier passed 154 root tests plus 13 internal-package tests.
  The full repository gate passed 3,589 root tests plus 13 internal-package
  tests at 73.15% line coverage; the handler reached 100.00% coverage.

Phase 3 follow-up:

- The previously named ChatPage Tranche 3 plan-review boundary is complete.
  The MCP decomposition sequence is also complete; the remaining 1,202-line
  facade stays deferred while an older notifier-refactor worktree overlaps it.
  Re-rank it only after that ownership signal is resolved.

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

Permission and trust panel status (2026-07-17):

- `ComputerUsePermissionTrustPanel` now owns the ordered permission flow and
  recovery guidance behind derived grant flags, a loading flag, a typed
  recovery summary, and three explicit callbacks.
- Characterization preserves row-specific Accessibility and Screen Recording
  actions, independent rechecks, loading disablement, completed-row display,
  conditional recovery details, exact copy, and presentation order.
- The settings page remains the only owner of permission requests, System
  Settings navigation, helper lifecycle, audit, diagnostics, app lifecycle,
  and refresh state. Direct widget tests perform no platform action.
- `computer_use_settings_page.dart` fell from 3,270 to 2,995 lines. The
  independent panel is ratcheted at 318 lines.
- The focused verifier passed 53 root tests plus 13 internal-package tests.
  The full repository gate passed 3,595 root tests plus 13 internal-package
  tests at 73.16% line coverage; the panel reached 100.00% coverage.

Action gate plan status (2026-07-17):

- `ComputerUseActionGatePlan` now owns the exact eight-row action plan behind
  an immutable view model that copies status, next-action, and positive-state
  decisions without retaining mutable runtime maps.
- Characterization preserves helper launch and IPC states, permission rows,
  row order, missing-status and next-action fallbacks, pre-smoke instructions,
  live-smoke details, unsupported audio, armed unsafe actions, icons, spacing,
  and copy.
- The settings page remains the only owner of runtime maps, live-smoke state,
  permission state, helper and IPC lifecycle, diagnostics, refresh behavior,
  and platform operations. Direct widget tests perform no platform action.
- `computer_use_settings_page.dart` fell from 2,995 to 2,816 lines. The
  independent action-gate widget is ratcheted at 203 lines.
- The focused verifier passed 55 root tests plus 13 internal-package tests.
  The full repository gate passed 3,602 root tests plus 13 internal-package
  tests at 73.50% line coverage; the widget reached 100.00% coverage.

IPC runtime summary status (2026-07-17):

- `ComputerUseIpcRuntimeSummary` now owns the complete ordered IPC diagnostics
  presentation behind an immutable view model that copies heading and chip
  values without retaining mutable runtime maps or lists.
- Characterization preserves all 81 optional and required diagnostic rows,
  their order, missing scalar interpolation, nested-map type checks, list
  stringification, first-seen deduplication, path shortening, fallback status,
  icons, wrapping, spacing, and copy.
- The settings page remains the only owner of runtime-map assembly, refresh
  state, helper and XPC lifecycle, permissions, smoke state, diagnostics, and
  platform operations. Direct widget tests perform no platform action.
- `computer_use_settings_page.dart` fell from 2,816 to 2,189 lines. The
  independent IPC runtime summary is ratcheted at 582 lines.
- The focused verifier passed 57 root tests plus 13 internal-package tests.
  The full repository gate passed 3,609 root tests plus 13 internal-package
  tests at 73.50% line coverage; the widget reached 100.00% coverage.

Live-smoke summary status (2026-07-17):

- `ComputerUseLiveSmokeSummary` now owns live-smoke envelope normalization and
  ordered presentation behind an immutable view model that copies headings,
  status rows, and detail lines without retaining mutable maps or lists.
- Characterization preserves nested report and outer path precedence, the two
  required and ten optional status rows, unsupported-audio success semantics,
  blocker category and detail ordering, malformed nested values, capture
  failure fallbacks, and helper-path shortening.
- The settings page remains the only owner of the report envelope, refresh
  state, smoke execution, diagnostics generation, helper and XPC lifecycle,
  permissions, and platform operations. Direct widget tests perform no native
  Computer Use action.
- `computer_use_settings_page.dart` fell from 2,189 to 1,927 lines. The
  independent live-smoke summary is ratcheted at 302 lines.
- The focused verifier passed 58 root tests plus 13 internal-package tests.
  The full repository gate passed 3,616 root tests plus 13 internal-package
  tests at 73.51% line coverage; the widget reached 100.00% coverage.

XPC timing summary status (2026-07-17):

- `ComputerUseXpcTimingSummary` now owns ordered XPC timing presentation behind
  an immutable view model that copies the heading and information rows without
  retaining the derived timing map.
- Characterization preserves required status and gate rows, all fifteen
  conditional rows, scalar type checks, false-boolean labels, fallback status,
  row order, icons, wrapping, spacing, and copy.
- The settings page remains the only owner of timing-report construction, the
  `missing_preferred_attempt` visibility decision, refresh state, helper and
  XPC lifecycle, diagnostics, and platform operations. Direct widget tests
  perform no platform action.
- `computer_use_settings_page.dart` fell from 1,927 to 1,811 lines. The
  independent XPC timing summary is ratcheted at 176 lines.
- The focused verifier passed 59 root tests plus 13 internal-package tests.
  The full repository gate passed 3,623 root tests plus 13 internal-package
  tests at 73.52% line coverage; the widget reached 100.00% coverage.

Helper persistence summary status (2026-07-17):

- `ComputerUsePersistenceSummary` now owns helper-persistence normalization and
  presentation behind an immutable view model that copies the heading, two
  status rows, and active-work detail without retaining source or nested maps.
- Characterization preserves timestamp fallback and empty-string handling,
  exact-true active-work filtering, map insertion order and key
  stringification, verification presence and success semantics, chip order,
  icons, wrapping, spacing, and copy.
- The settings page remains the only owner of persistence lookup precedence
  and visibility, refresh state, helper lifecycle, diagnostics generation, and
  platform operations. Direct widget tests perform no platform action.
- `computer_use_settings_page.dart` fell from 1,811 to 1,759 lines. The
  independent helper persistence summary is ratcheted at 124 lines.
- The focused verifier passed 60 root tests plus 13 internal-package tests.
  The full repository gate passed 3,630 root tests plus 13 internal-package
  tests at 73.52% line coverage; the widget reached 100.00% coverage.

Onboarding verification summary status (2026-07-17):

- `ComputerUseVerificationSummary` now owns onboarding-verification
  normalization and presentation behind an immutable view model that copies
  the heading, step-section presence, and ordered status rows without retaining
  source maps, the nested list, or step maps.
- Characterization preserves summary and generated-time precedence, direct
  interpolation of non-null values, the distinction between missing and empty
  step lists, map-only filtering, list order, labels, status fallbacks,
  exact-true success, icons, wrapping, spacing, and copy.
- The settings page remains the only owner of verification lookup precedence
  and visibility, refresh state, permission recovery, helper lifecycle,
  diagnostics generation, and platform operations. Direct widget tests perform
  no platform action.
- `computer_use_settings_page.dart` fell from 1,759 to 1,725 lines. The
  independent onboarding verification summary is ratcheted at 107 lines.
- The focused verifier passed 62 root tests plus 13 internal-package tests.
  The full repository gate passed 3,638 root tests plus 13 internal-package
  tests at 73.53% line coverage; the widget reached 100.00% coverage.

Debug image preview status (2026-07-17):

- `ComputerUseDebugImagePreview` now owns base64 decoding, image presentation,
  zoom-controller lifecycle, active styling, and viewport-to-source coordinate
  conversion behind immutable snapshot and point values.
- The debug page retains native screenshot-result parsing, target selection,
  coordinate text controllers, diagnostics, service calls, and command
  dispatch. Direct widget tests perform no native Computer Use actions.
- `computer_use_debug_page.dart` fell from 2,864 to 2,721 lines. The independent
  preview boundary is ratcheted at 153 lines.
- The focused verifier passed 69 root tests plus 13 internal-package tests. The
  full repository gate passed 3,760 root tests plus 13 package tests at 74.11%
  line coverage; the preview reached 100.00% coverage.

Debug status primitives status (2026-07-17):

- Nine Computer Use-specific widgets now own section titles, helper-boundary
  details, onboarding progress and rows, informational notes, tri-state
  permission and status rows, arming switches, and coordinate-target labels.
- The debug page retains card composition, providers, service calls, state,
  result mapping, permission operations, helper lifecycle, screenshots, input,
  audio, and diagnostics. Direct widget tests perform no native actions.
- `computer_use_debug_page.dart` fell from 2,721 to 2,322 lines. The independent
  status-primitives boundary is ratcheted at 424 lines.
- The focused verifier passed 71 root tests plus 13 internal-package tests. The
  full repository gate passed 3,767 root tests plus 13 package tests at 74.12%
  line coverage; the new boundary reached 100.00% coverage.

Debug onboarding card status (2026-07-17):

- `ComputerUseDebugOnboardingCard` owns checklist progress, ordered typed step
  presentation, first-incomplete guidance, and XPC ready or blocker notes. Its
  view model copies step and blocker iterables into unmodifiable snapshots.
- The debug page retains checklist-state calculation, diagnostic map output,
  XPC protocol translation, providers, services, and native operations. Direct
  widget tests perform no native actions.
- `computer_use_debug_page.dart` fell from 2,322 to 2,275 lines. The independent
  onboarding boundary is ratcheted at 94 lines.
- The focused verifier passed 69 root tests plus 13 internal-package tests. The
  full repository gate passed 3,771 root tests plus 13 package tests at 74.13%
  line coverage; the onboarding boundary reached 100.00% coverage.

Network HTTP tools status (2026-07-18):

- `NetworkHttpTools` now owns HTTP status plus GET, HEAD, DELETE, POST, PUT, and
  PATCH execution behind an injectable `HttpClient` factory.
- Exact request controls, headers, content-type precedence, redirects, response
  envelopes, UTF-8 and base64 body handling, truncation, and cleanup are pinned
  by in-memory transport tests that open no socket.
- `NetworkTools` retains unchanged static delegates. The extracted boundary is
  ratcheted at 287 lines and reached 98.88% line coverage.

Network socket tools status (2026-07-18):

- `NetworkSocketTools` now owns TCP port checks, TLS certificate inspection,
  and WHOIS execution behind injected plain and secure socket connectors and a
  deterministic clock.
- Tests pin success and failure payloads, certificate metadata and validity,
  registry selection, query normalization, referral fallback, timeouts,
  cleanup, and truncation without opening real sockets.
- `network_tools.dart` fell from 2,578 to 2,269 lines across both network
  slices. The socket boundary is ratcheted at 204 lines and reached 93.65% line
  coverage. The full gate passed 3,787 root tests plus 13 package tests at
  74.30% line coverage.

Network neighbor tools status (2026-07-18):

- `NetworkNeighborTools` now owns macOS and Linux ARP and NDP command
  selection, execution, parsing, filtering, and ordering behind injected
  platform and process-runner boundaries.
- Shared pure IP normalization and numeric ordering moved to
  `network_address_utils.dart` so route, interface, mDNS, and neighbor results
  keep one comparison contract.
- Direct tests pin macOS and Linux parsing, invalid and unsupported inputs,
  command failures, filtering, ordering, and the IPv6-only compatibility
  wrapper without executing a real process.
- `network_tools.dart` fell from 2,269 to 1,996 lines. The neighbor and address
  boundaries are ratcheted at 266 and 34 lines and reached 98.10% and 88.89%
  line coverage. The final root gate passed analysis and 3,794 tests at 73.99%
  line coverage; the internal-package gate remains green at 13 tests.

Network route tools status (2026-07-18):

- `NetworkRouteTools` now owns route lookup, interface inspection, and path-MTU
  measurement behind injected platform, process-runner, and address-lookup
  boundaries.
- Direct tests pin macOS and Linux command selection and parsing, unsupported
  platform errors, address-family validation and lookup recovery, interface
  filtering, Linux tracepath alternatives, and both interface-MTU fallbacks
  without executing real route or interface commands.
- `NetworkTools` retains unchanged static signatures and re-exports the shared
  process-runner and address-lookup typedefs for source compatibility. DNS,
  mDNS, ping, and traceroute behavior remains in the facade.
- `network_tools.dart` fell from 1,996 to 968 lines. The route service and
  dependency contracts are ratcheted at 1,128 and 10 lines. The service reached
  93.88% coverage (414/441), while combined coverage for the facade and route
  service reached 65.10% (485/745).
- The focused verifier passed 91 root tests plus 13 internal-package tests. The
  full repository gate passed analysis, 3,849 root tests, and 13 package tests
  at 74.67% line coverage (53,110/71,124).
- The preserved macOS `ifconfig` parser does not capture a scoped IPv6 address
  when its zone identifier contains non-hexadecimal letters. Treat any fix as
  a separate behavior-change task with explicit compatibility tests.

Debug diagnostics cards status (2026-07-18):

- `ComputerUseDebugDiagnosticsCard` now owns manual-smoke safety copy, ordered
  diagnostic actions, a defensively copied redacted audit snapshot, and the
  optional export-path row. `ComputerUseDebugResultCard` owns the last action
  and selectable monospace native result.
- The debug page retains the busy flag, audit-log access, callbacks, diagnostic
  serialization, clipboard and export operations, smoke execution, state, and
  every native Computer Use action.
- Direct tests pin source-copy isolation, immutable snapshots, action order and
  busy gating, callback dispatch, the five-entry audit limit, export-path
  visibility, exact copy, selection, and result typography.
- `computer_use_debug_page.dart` fell from 2,275 to 2,198 lines. The new
  boundary is ratcheted at 149 lines and reached 100.00% line coverage. The
  full gate passed analysis, 3,798 root tests, and 13 package tests at 74.00%
  line coverage.

Debug audio card status (2026-07-18):

- `ComputerUseDebugAudioCard` now owns the System Audio arming switch,
  recording status, and ordered start and stop actions behind an immutable
  view model and explicit callbacks.
- The debug page retains recording service calls, arming reset, result
  handling, smoke completion, and diagnostic state. Direct widget tests execute
  no native desktop action.
- Direct and product-path tests pin eligibility, copy, icons, colors, callback
  dispatch, failed-start disarming, successful start and stop service calls,
  and recording state.
- `computer_use_debug_page.dart` fell from 2,198 to 2,145 lines. The new
  boundary is ratcheted at 99 lines and reached 100.00% line coverage. The full
  gate passed analysis, 3,803 root tests, and 13 package tests at 74.00% line
  coverage.

Debug display screenshot card status (2026-07-18):

- `ComputerUseDebugDisplayScreenshotCard` now owns the max-width field,
  capture action, and optional display preview behind an immutable view model,
  the page-owned text controller, and explicit callbacks.
- The debug page retains max-width normalization, service execution, result
  decoding, snapshot and coordinate-target state, and selected-point mutation.
  Direct widget tests execute no native desktop action.
- Direct and product-path tests pin busy-only capture eligibility, copy, icons,
  preview keys and active state, callback dispatch, all invalid-width fallback
  cases, display selection, and source dimensions passed to input actions.
- `computer_use_debug_page.dart` fell from 2,145 to 2,114 lines. The new
  boundary is ratcheted at 81 lines and reached 100.00% line coverage. The full
  gate passed analysis, 3,811 root tests, and 13 package tests at 74.37% line
  coverage.

Debug input card status (2026-07-18):

- `ComputerUseDebugInputCard` now owns input arming, target-summary, field, and
  ordered move, click, and type presentation behind an immutable view model,
  page-owned controllers, and explicit callbacks.
- The debug page retains coordinate and text validation, source dimensions,
  window IDs, service execution, snackbars, smoke completion, and post-attempt
  disarming. Direct widget tests execute no native desktop action.
- Direct and product-path tests pin the busy, armed, and target eligibility
  matrix, controller reuse, editable busy fields, callback order, blank-text
  rejection, original-text forwarding, disarming, and display and window
  coordinate arguments.
- `computer_use_debug_page.dart` fell from 2,114 to 2,037 lines. The new
  boundary is ratcheted at 133 lines and reached 100.00% line coverage. The
  full gate passed analysis, 3,818 root tests, and 13 package tests at 74.39%
  line coverage.

Debug window-targeting card status (2026-07-18):

- `ComputerUseDebugWindowTargetingCard` now owns ordered window actions,
  selection, formatted bounds, and optional preview presentation behind
  immutable display items, a defensive view model, and explicit callbacks.
- The debug page retains raw response maps, compatible ID parsing, formatted
  item construction, selection and preview cleanup, service execution, result
  decoding, and coordinate state. Direct widget tests execute no native
  desktop action.
- Direct and product-path tests pin immutable snapshots, empty, selected, and
  busy eligibility, action order, dropdown behavior, list, focus, and capture
  arguments, preview activation and cleanup, repeated selection, and window
  source dimensions passed to input actions.
- `computer_use_debug_page.dart` fell from 2,037 to 1,991 lines. The new
  boundary is ratcheted at 163 lines and reached 100.00% line coverage. The
  full gate passed analysis, 3,824 root tests, and 13 package tests at 74.41%
  line coverage.

Debug permission-checklist status (2026-07-18):

- `ComputerUseDebugPermissionChecklist` now owns the exact title, subtitle,
  icon, theme color, border, and spacing presentation for typed ready,
  warning, and unknown states.
- The debug page retains setup evaluation, raw permission and helper state,
  backend-specific guidance generation, service execution, and System
  Settings actions. Direct widget tests execute no native desktop action.
- Direct and product-path tests pin status derivation, all three icon and color
  mappings, decoration and text styles, exact warning guidance, and page-owned
  setup-to-presentation mapping.
- `computer_use_debug_page.dart` fell from 1,991 to 1,950 lines. The new
  boundary is ratcheted at 94 lines and reached 100.00% line coverage. The full
  gate passed analysis, 3,829 root tests, and 13 package tests at 74.42% line
  coverage.

Debug permission-actions status (2026-07-18):

- `ComputerUseDebugPermissionActions` now owns the exact nine-action order,
  labels, icons, keys, tonal-button presentation, wrapping, and busy-state
  eligibility behind an immutable view model and explicit callbacks.
- The debug page retains helper launch and restart sequences, ping and stop
  result storage, permission refresh and split requests, System Settings
  navigation, service execution, and all state mutation. Direct widget tests
  execute no native desktop action.
- Direct and product-path tests pin all labels, icons, keys, order, spacing,
  idle callback dispatch, busy disablement, helper lifecycle calls, targeted
  settings sections, and split permission request arguments.
- `computer_use_debug_page.dart` fell from 1,950 to 1,910 lines. The new
  boundary is ratcheted at 119 lines and reached 100.00% line coverage. The
  full gate passed analysis, 3,833 root tests, and 13 package tests at 74.43%
  line coverage.

Chat response-normalization status (2026-07-19):

- `ChatCompletionResponseNormalizer` owns reasoning composition, native call
  conversion, advertised embedded-call promotion, finish-reason selection, and
  raw parse-failure recovery without HTTP, mutable state, or UI dependencies.
- `ChatRemoteDataSource` retains request construction, HTTP and streaming
  transport, reasoning retries, stream accumulation, usage telemetry,
  tool-result formatting, images, and diagnostic logging.
- `chat_remote_datasource.dart` fell from 1,244 to 1,164 lines. The independent
  normalizer is ratcheted at 183 lines.
- The focused verifier passed 109 root tests plus 13 internal-package tests. The
  full gate passed analysis, 3,944 root tests, and 13 package tests at 75.19%
  line coverage (53,557/71,231). The normalizer reached 100.00% coverage
  (60/60), the datasource reached 52.81% (263/498), and their combined coverage
  is 57.89% (323/558).

MessageInput slash suggestion state status (2026-07-20):

- `MessageInputSlashSuggestionState` owns slash-command suggestion refresh,
  selected-index clamping, next and previous wrapping, tapped index selection,
  dismiss state, and completed-command suppression without widget, controller,
  localization, or command-handler dependencies.
- `MessageInput` retains text controller mutation, key-event routing,
  localized feedback, command execution, attachment handling, input history,
  worktree session sending, voice recording, and coding-goal controls.
- `message_input.dart` fell from 2,374 to 2,332 lines. The independent state
  helper is ratcheted at 131 lines.
- The focused verifier passed analysis, 31 root tests, and 13
  internal-package tests.

Next slice:

- The planned network route, routine run-history, LAN IP network, filesystem
  diff, model metadata, file workspace diff-row, and peer debug action-card
  slices are complete. The workflow tool failure detector and lifecycle policy
  are also complete. Do not widen those stacks into unrelated DNS, mDNS, ping,
  traceroute, routine mutation, scheduling, probe, file I/O, path containment,
  edit validation, provider HTTP, model lifecycle, or native action changes.
  The complete stack is integrated into `main` as `f80132bf`.
- The planned permission action group is complete, and the 2026-07-18 full
  inventory refresh is recorded in
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- The integrated-main production and ownership ranking is refreshed in
  `docs/large_file_boundary_inventory_2026_07_18.md`. The recovery route and
  evidence contract and pure typed route-policy extraction are complete. The
  policy selects only from already-derived evidence and owns no prompt,
  progress mutation, page state, retry body, or recursion.
- Auxiliary worktree overlap is no longer a selection blocker. The ChatPage
  state contract and workspace-navigation extraction are complete. The move
  reduced `chat_page.dart` from 2,133 to 2,045 lines and its same-library
  aggregate from 8,945 to 8,857 lines. The coordinator reached 100.00% coverage
  (40/40), and the full gate passed analysis, 3,927 root tests, and 13 package
  tests at 75.19% line coverage (53,527/71,192).
- The ChatRemoteDataSource response-normalization extraction is complete. Keep
  its remaining request-building and streaming transformations separate from
  ChatPage, tool-loop, and workflow recovery changes.
- MessageInput remains the next newly unblocked candidate at 2,332 lines and
  65.62% coverage. Slash suggestion state is complete; re-characterize one
  remaining composer action contract before moving more code.
  ChatNotifier is also eligible, but its 83.15% root-file coverage and 23,005-
  line same-library aggregate require a smaller named concern and aggregate
  ratchet before any move. Do not split only the notifier test root.
- Do not widen `ChatPageWorkspaceNavigationCoordinator` into dashboard,
  sidebar, Files-tab, workflow, approval, composer, or persistence state.
- Keep `routine_detail_view.dart` and
  `lan_scan_service.dart` paused now that both are below 1,000 lines; their
  remaining concerns are more tightly coupled to page-owned provider state or
  platform IO. Re-rank `filesystem_tools.dart` and
  `model_remote_datasource.dart` before another extraction even though both
  remain above 1,000 lines. Re-rank `file_workspace_viewer_sheet.dart` before
  separating file loading, path containment, or layout concerns. Keep
  `workflow_task_run_coordinator.dart` side-effect ownership unchanged. The
  completed contract and route policy now freeze recovery ordering, liveness,
  retry limits, progress-evidence semantics, terminal states, continuation
  depth, and compatible next-task selection.
- Keep the Computer Use debug and settings pages paused at 94.36% and 95.22%
  coverage. Their remaining orchestration-heavy code, rather than worktree
  ownership, makes another extraction lower leverage.

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
