# Large File Refactor Plan

This plan tracks high-leverage refactors for Caverno files that are large enough
to slow review, increase merge risk, or make Codex tasks harder to scope. Treat
each slice as a behavior-preserving move unless the task explicitly says
otherwise.

## Current Inventory

The live inventory below was refreshed on 2026-07-16 with `wc -l`. Refresh it
again before starting a new refactor branch.

| File | Lines | Primary concern |
|------|------:|-----------------|
| `lib/features/chat/presentation/providers/chat_notifier.dart` | 9468 | Chat orchestration, tool loops, memory, workflows, persistence |
| `lib/features/chat/presentation/pages/chat_page.dart` | 2738 | Chat screen layout, drawers, modals, input wiring, plan UI |
| `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart` | 2442 | Saved-workflow execution, recovery, evidence, and auto-continuation |
| `lib/features/chat/data/datasources/mcp_tool_service.dart` | 4096 | Tool registry, MCP execution, remaining built-in adapters |
| `lib/features/chat/data/datasources/built_in_network_tool_handler.dart` | 978 | Built-in network definitions, validation, and operation dispatch |
| `lib/features/settings/presentation/pages/computer_use_settings_page.dart` | 3270 | Computer Use settings layout and validation |
| `lib/features/settings/presentation/pages/computer_use_debug_page.dart` | 2864 | Debug UI, diagnostics rendering, action controls |
| `lib/features/chat/data/datasources/network_tools.dart` | 2578 | Network discovery, scanning, and command handling |
| `test/features/chat/presentation/providers/chat_notifier_test.dart` | 18648 | Broad chat orchestration regression coverage |

The primary files understate the effective library size because Dart `part`
files share private state and compile as one library. Current aggregate sizes
are 23,005 lines for the ChatNotifier library, 10,344 for the ChatPage library,
4,439 for the McpToolService library, and 33,189 for the ChatNotifier test
library. Ratchets must cover both the primary file and its aggregate library.

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

Next slice:

- Extract the built-in MCP filesystem tool family behind an independently
  testable application-internal handler, including rollback checkpoint
  ownership and the existing delete-file part.

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

Later tranche roadmap:

1. Tranche 3: plan review and approval actions. Extract `_editPlanInChat`,
   `_cancelPlanReview`, `_approveCurrentPlanAndStart`, workflow editor handlers,
   and task-menu handlers.
2. Tranche 4: slash command handler, pinned by
   `test/features/chat/presentation/pages/chat_page_slash_commands_test.dart`.
3. Tranche 5: `build()` scaffold decomposition plus right-sidebar layout helpers
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

Next slice:

- Extract filesystem definitions and routing into
  `BuiltInFilesystemToolHandler`. Include `list_directory`, `read_file`,
  `inspect_file`, `write_file`, `edit_file`, `delete_file`,
  `rollback_last_file_change`, `find_files`, and `search_files` while
  preserving platform gating, direct execution, collision handling, and
  checkpoint lifecycle behavior.

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
