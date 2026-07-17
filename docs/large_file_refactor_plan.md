# Large File Refactor Plan

This plan tracks high-leverage refactors for Caverno files that are large enough
to slow review, increase merge risk, or make Codex tasks harder to scope. Treat
each slice as a behavior-preserving move unless the task explicitly says
otherwise.

## Current Inventory

The live inventory below was refreshed on 2026-07-17 with `wc -l`. Refresh it
again before starting a new refactor branch.

| File | Lines | Primary concern |
|------|------:|-----------------|
| `lib/features/chat/presentation/providers/chat_notifier.dart` | 9468 | Chat orchestration, tool loops, memory, workflows, persistence |
| `lib/features/chat/presentation/pages/chat_page.dart` | 2609 | Chat screen layout, drawers, modals, input wiring, plan UI |
| `lib/features/chat/presentation/coordinators/plan_review_action_coordinator.dart` | 198 | Plan review edit, cancel, approval, projection, and task selection |
| `lib/features/chat/presentation/coordinators/workflow_editor_action_coordinator.dart` | 88 | Workflow editor save, clear, and proposal persistence |
| `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart` | 2442 | Saved-workflow execution, recovery, evidence, and auto-continuation |
| `lib/features/chat/presentation/widgets/workflow/workflow_editor_sheet.dart` | 218 | Legacy workflow metadata editor presentation and normalization |
| `lib/features/chat/data/datasources/mcp_tool_service.dart` | 1202 | Tool registry, public execution facade, remaining built-in adapters |
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
| `lib/features/settings/presentation/pages/computer_use_settings_page.dart` | 1725 | Computer Use settings coordination, diagnostics, and remaining panels |
| `lib/features/settings/presentation/widgets/computer_use_action_gate_plan.dart` | 203 | Immutable Computer Use action-gate presentation |
| `lib/features/settings/presentation/widgets/computer_use_ipc_runtime_summary.dart` | 582 | Immutable Computer Use IPC diagnostics presentation |
| `lib/features/settings/presentation/widgets/computer_use_live_smoke_summary.dart` | 302 | Immutable Computer Use live-smoke presentation |
| `lib/features/settings/presentation/widgets/computer_use_persistence_summary.dart` | 124 | Immutable Computer Use helper-persistence presentation |
| `lib/features/settings/presentation/widgets/computer_use_permission_trust_panel.dart` | 318 | Computer Use permission flow and recovery guidance presentation |
| `lib/features/settings/presentation/widgets/computer_use_verification_summary.dart` | 107 | Immutable Computer Use onboarding-verification presentation |
| `lib/features/settings/presentation/widgets/computer_use_xpc_timing_summary.dart` | 176 | Immutable Computer Use XPC timing presentation |
| `lib/features/settings/presentation/pages/computer_use_debug_page.dart` | 2864 | Debug UI, diagnostics rendering, action controls |
| `lib/features/chat/data/datasources/network_tools.dart` | 2578 | Network discovery, scanning, and command handling |
| `test/features/chat/presentation/providers/chat_notifier_test.dart` | 18648 | Broad chat orchestration regression coverage |

The primary files understate the effective library size because Dart `part`
files share private state and compile as one library. Current aggregate sizes
are 23,005 lines for the ChatNotifier library, 9,986 for the ChatPage library,
1,294 for the McpToolService library, and 33,189 for the ChatNotifier test
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

Next application-boundary slice:

- Characterize ChatPage task proposal, task editor, and task-menu ownership,
  then define the smallest coherent Tranche 3 task-action extraction. Keep
  workflow quick actions outside that slice.

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

Later tranche roadmap:

1. Tranche 3 remaining: characterize task proposal, task editor, and task-menu
   ownership, then extract the smallest coherent task-action boundary. Keep
   workflow quick actions separate.
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

Next slice:

- Refresh the live oversized-file inventory before selecting another
  application boundary. Prefer the explicit ChatPage Tranche 3 plan-review and
  approval action boundary when the recheck confirms its ownership and tests.

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

Next slice:

- The Computer Use settings summary sequence plus ChatPage plan-review and
  workflow-editor action slices are complete. Continue ChatPage Tranche 3 by
  characterizing task proposal, task editor, and task-menu ownership before
  selecting the next reviewable task-action boundary.

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
