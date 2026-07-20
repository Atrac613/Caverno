# Large-File Boundary Inventory — 2026-07-18

Status: complete. Its selected route, interface, and path-MTU slice was
implemented on `feature/network-route-tools-extraction`, followed by the
run-history slice on `feature/routine-run-history-extraction` and the LAN IP
network slice on `feature/lan-ip-network-extraction`. The filesystem diff slice
then completed on `feature/filesystem-diff-extraction`, followed by the model
metadata parser slice on `feature/model-metadata-parser-extraction` and the file
workspace diff parser slice on
`feature/file-workspace-diff-parser-extraction`, followed by the workflow tool
failure detector slice on
`feature/workflow-tool-failure-detector-extraction` and the workflow task
lifecycle policy slice on
`feature/workflow-task-run-lifecycle-policy-extraction`. The completed
31-commit stack was squash-integrated into `main` as `f80132bf`. A subsequent
route-and-evidence contract completed on
`feature/workflow-recovery-route-evidence-contract` on 2026-07-19, followed by
the typed route-policy slice on `feature/workflow-task-turn-route-policy` and
the ChatPage state-transition contract on
`feature/chat-page-state-transition-contract`. The subsequent workspace
navigation extraction completed on
`feature/chat-page-workspace-navigation-coordinator`, followed by the response
normalizer extraction on `feature/chat-response-normalizer`.

## Scope And Method

This inventory rechecks physical file size, Dart same-library aggregate size,
line coverage, and active-worktree overlap before another implementation
boundary is selected.

- Production scan: every tracked non-generated Dart file under `lib/` and
  `packages/` with at least 1,000 physical lines.
- Standalone-boundary table: excludes generated `*.g.dart` and
  `*.freezed.dart` files plus files declared with `part of`; those part files
  remain represented by their root-library aggregates.
- Test scan: standalone test files with at least 1,800 physical lines, with the
  ChatNotifier test aggregate measured separately.
- Coverage source: the successful full
  `tool/codex_verify.sh --coverage --no-codegen` run on integrated `main` at
  `f80132bf`. Coverage percentages use executable lines from
  `coverage/lcov.info`, not physical-line counts.
- Historical ownership source: every existing worktree from
  `git worktree list --porcelain`, conservatively compared with local `main`.
  The 2026-07-19 user override treats every listed auxiliary worktree as
  inactive, so overlap is advisory and no longer blocks editing or ranking.

The full gate passed analysis, 3,905 root tests, and 13 internal-package tests
at 74.98% line coverage (53,368/71,175).

The ranked coordinator, MessageInput, and ChatNotifier rows are refreshed below
from the successful 2026-07-19 route-policy branch gate. The ChatPage row uses
the later navigation extraction gate. The ChatRemoteDataSource and response
normalizer rows use the latest extraction gate, which passed 3,944 root tests
and 13 internal-package tests at 75.19% line coverage (53,557/71,231). All other
coverage values remain the integrated `main` snapshot described above.

## Same-Library Aggregates

| Root library | Primary lines | Declared parts | Aggregate lines |
|---|---:|---:|---:|
| `lib/features/chat/presentation/providers/chat_notifier.dart` | 9,468 | 43 | 23,005 |
| `lib/features/chat/presentation/pages/chat_page.dart` | 2,045 | 12 | 8,857 |
| `lib/features/chat/data/datasources/mcp_tool_service.dart` | 1,202 | 1 | 1,294 |
| `test/features/chat/presentation/providers/chat_notifier_test.dart` | 18,648 | 22 | 33,189 |

The aggregates match their current non-increasing ratchets. Moving code to a
new `part` file would not reduce these totals.

## Standalone Production Boundaries

| File | Physical lines |
|---|---:|
| `lib/features/chat/presentation/providers/chat_notifier.dart` | 9,468 |
| `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart` | 2,442 |
| `lib/features/chat/presentation/widgets/message_input.dart` | 2,374 |
| `lib/features/chat/presentation/pages/chat_page.dart` | 2,045 |
| `lib/features/chat/data/datasources/network_tools.dart` | 1,996 |
| `lib/features/settings/presentation/pages/computer_use_debug_page.dart` | 1,910 |
| `lib/features/settings/data/model_remote_datasource.dart` | 1,813 |
| `lib/features/chat/presentation/providers/conversations_notifier.dart` | 1,741 |
| `lib/features/settings/presentation/pages/computer_use_settings_page.dart` | 1,725 |
| `lib/features/settings/domain/services/live_llm_diagnostic_service.dart` | 1,711 |
| `lib/features/chat/presentation/widgets/file_workspace_viewer_sheet.dart` | 1,634 |
| `lib/features/chat/domain/services/workflow_task_proposal_quality_service.dart` | 1,634 |
| `lib/features/chat/domain/services/conversation_plan_execution_guardrails.dart` | 1,617 |
| `lib/features/chat/domain/services/tool_result_prompt_builder.dart` | 1,607 |
| `lib/features/chat/data/datasources/local_shell_tools.dart` | 1,568 |
| `lib/features/chat/data/datasources/filesystem_tools.dart` | 1,476 |
| `lib/features/routines/presentation/pages/routine_detail_view.dart` | 1,407 |
| `lib/core/services/macos_computer_use_setup.dart` | 1,400 |
| `lib/features/remote_coding/presentation/remote_coding_page.dart` | 1,392 |
| `lib/features/chat/domain/services/session_memory_service.dart` | 1,337 |
| `lib/features/chat/data/datasources/installed_dependency_grounding_service.dart` | 1,337 |
| `lib/features/chat/data/datasources/git_tools.dart` | 1,337 |
| `lib/features/chat/presentation/widgets/conversation_drawer.dart` | 1,329 |
| `lib/features/chat/data/datasources/chat_remote_datasource.dart` | 1,164 |
| `lib/core/services/macos_computer_use_service.dart` | 1,238 |
| `lib/features/chat/data/datasources/mcp_tool_service.dart` | 1,202 |
| `lib/features/settings/presentation/pages/general_settings_page.dart` | 1,189 |
| `lib/features/routines/data/routine_execution_service.dart` | 1,165 |
| `lib/features/chat/domain/services/final_answer_claim_detector.dart` | 1,125 |
| `lib/features/settings/domain/entities/app_settings.dart` | 1,123 |
| `lib/features/chat/presentation/widgets/message_bubble.dart` | 1,114 |
| `lib/features/chat/domain/services/conversation_plan_execution_coordinator.dart` | 1,074 |
| `lib/features/chat/domain/services/system_prompt_builder.dart` | 1,043 |
| `lib/core/services/lan_scan_service.dart` | 1,038 |

## Standalone Test Boundaries

| File | Physical lines |
|---|---:|
| `test/features/chat/presentation/providers/chat_notifier_test.dart` | 18,648 |
| `test/tool/run_macos_computer_use_smoke_test_test.dart` | 11,257 |
| `test/integration_support/macos_computer_use_release_readiness_test.dart` | 7,646 |
| `test/features/chat/data/datasources/mcp_tool_service_test.dart` | 4,285 |
| `test/features/chat/presentation/pages/chat_page_slash_commands_test.dart` | 1,997 |
| `test/features/routines/data/routine_execution_service_test.dart` | 1,893 |
| `test/features/chat/presentation/providers/conversations_notifier_test.dart` | 1,887 |
| `test/features/chat/domain/services/conversation_plan_execution_guardrails_test.dart` | 1,877 |

The ChatNotifier test root remains the largest test concern, but its 33,189-line
aggregate must still be reduced with its production concern and aggregate
ratchet. Do not split only the test root even though worktree overlap is no
longer a selection blocker.

## Historical Worktree Audit And Override

On 2026-07-19, the user confirmed that the auxiliary worktrees listed below are
inactive and directed that they must not block refactor selection. The paths
remain useful historical context, but the ranking now treats their overlap as
non-blocking. No worktree or branch is deleted by this decision.

The Computer Use debug page and its product test have no remaining overlapping
active worktree after the checklist and action-group branches landed. This
proves the ownership conflict that blocked the sequence is resolved.

Conservative overlaps remain on these large boundaries:

- `chat_notifier.dart`: eleven worktrees, including discovery, notifier
  refactor, goal/tool-loop recovery, live-convergence, Plan Mode stability,
  roadmap, and one detached worktree. The LL23 worktree also has an unrelated
  dirty notifier-test file.
- `chat_page.dart`: five worktrees: notifier refactor, LL13 registry,
  investigation playbook, LL19 recording, and one detached worktree.
- `message_input.dart`, `conversations_notifier.dart`,
  `workflow_task_proposal_quality_service.dart`, `local_shell_tools.dart`,
  `git_tools.dart`, `mcp_tool_service.dart`, `remote_coding_page.dart`, and
  `message_bubble.dart`: the clean `feature/chat-notifier-refactor-slices`
  worktree overlaps each boundary.
- `tool_result_prompt_builder.dart`: discovery and notifier-refactor worktrees.
- `conversation_plan_execution_guardrails.dart`: the Plan Mode stability
  worktree.
- `routine_execution_service.dart`: the tool-lifecycle diagnostics worktree.
- `final_answer_claim_detector.dart`: the notifier tranche-1 worktree.
- `app_settings.dart`: the roadmap idle worktree.
- `system_prompt_builder.dart`: discovery, notifier-refactor, and roadmap idle
  worktrees.

No active worktree overlap was found for `network_tools.dart`,
`workflow_task_run_coordinator.dart`, `computer_use_debug_page.dart`,
`model_remote_datasource.dart`, `computer_use_settings_page.dart`,
`live_llm_diagnostic_service.dart`, `file_workspace_viewer_sheet.dart`,
`filesystem_tools.dart`, `routine_detail_view.dart`,
`macos_computer_use_setup.dart`, `installed_dependency_grounding_service.dart`,
`conversation_drawer.dart`, `chat_remote_datasource.dart`,
`macos_computer_use_service.dart`, `general_settings_page.dart`,
`conversation_plan_execution_coordinator.dart`, or `lan_scan_service.dart`.

## Ranked Decision

| Rank | Boundary | Lines | Coverage | Ownership | Decision |
|---:|---|---:|---:|---|---|
| 1 | `message_input.dart` | 2,332 | 65.62% | non-blocking | Slash suggestion state extraction complete; re-characterize one remaining composer action before another move. |
| 2 | `chat_page.dart` | 2,045 | 54.26% | non-blocking | Workspace navigation extraction complete; re-characterize one remaining page-owned boundary before another move. |
| 3 | `chat_remote_datasource.dart` | 1,164 | 52.81% | clear | Response normalizer complete; re-characterize one request-building or streaming transformation before another move. |
| 4 | `installed_dependency_grounding_service.dart` | 1,337 | 67.57% | clear | Characterize ecosystem-specific resolution behind its stable JSON contract. |
| 5 | `workflow_task_run_coordinator.dart` | 2,380 | 62.17% | clear | Typed route policy complete; re-rank remaining side-effect clusters before another move. |
| 6 | `chat_notifier.dart` | 9,468 | 83.15% | non-blocking | Eligible, but select one pure concern and preserve the 23,005-line aggregate ratchet. |
| 7 | `conversation_drawer.dart` | 1,329 | 74.91% | clear | Characterize a presentational section only after widget lifecycle coverage. |
| 8 | `filesystem_tools.dart` | 1,282 | 78.98% | clear | Diff extraction complete; re-rank remaining IO and path concerns. |
| 9 | `model_remote_datasource.dart` | 1,710 | 79.36% | clear | Metadata extraction complete; re-rank provider and lifecycle concerns. |
| 10 | `file_workspace_viewer_sheet.dart` | 1,559 | 82.90% | clear | Diff-row extraction complete; re-rank IO, containment, and layout concerns. |
| 11 | `live_llm_diagnostic_service.dart` | 1,711 | 85.86% | clear | Pause while coverage is high and remaining logic is orchestration-heavy. |
| 12 | `computer_use_debug_page.dart` | 1,910 | 94.36% | clear | Pause because remaining code is high-coverage orchestration. |
| 13 | `computer_use_settings_page.dart` | 1,725 | 95.22% | clear | Pause because remaining code is high-coverage orchestration. |

Ignoring inactive worktrees changes eligibility, not extraction safety. The
typed workflow selector, ChatPage state contract, and workspace-navigation move
are complete. The extracted 127-line coordinator reached 100.00% coverage and
must remain limited to workspace, project, conversation, and assistant-mode
routing. The 183-line ChatRemoteDataSource response normalizer also reached
100.00% and must remain independent from transport and streaming state. The
131-line MessageInput slash suggestion state helper now owns suggestion
refresh, selected-index clamping, wrapping, and dismissal. Re-characterize one
remaining MessageInput composer action before another move. ChatNotifier is
eligible but ranks lower because its root coverage is already 83.15% and any
move must preserve the much larger same-library aggregate. The Computer Use
pages remain paused solely because their 94% to 95% coverage and remaining
orchestration make another extraction lower leverage.

`network_tools.dart` was selected because it combined a clear ownership state,
a still-large physical boundary, the lowest coverage among the top unowned
production candidates except `routine_detail_view.dart`, and an existing
internal seam. After that slice completed, the routine detail page's immutable
run-history presentation was the next clear, cohesive boundary. The refreshed
ranking then selected `lan_scan_service.dart` because its pure CIDR value object
was the smallest low-coverage seam with clear ownership. The next refresh kept
the lower-coverage workflow coordinator deferred because its recovery state
machine requires a larger lifecycle contract, and selected the smaller pure
diff seam in `filesystem_tools.dart` instead.

After the diff slice, the pure model metadata seam was selected ahead of the
lower-coverage workflow coordinator because it had an already characterized
37-line helper region and did not require changing recovery lifecycle state.

The next refresh selected the file workspace diff-row parser ahead of the
workflow coordinator because it was a deterministic 30-line executable region
with clear ownership and no recovery, Flutter, file IO, or path dependency.

The following refresh admitted the coordinator's shared 22-line executable
failure detector because it had no state transition, liveness, prompt, or retry
responsibility. The remaining recovery state machine stays deferred.

The next refresh admitted the coordinator's pure lifecycle rules after a
contract froze the depth boundary, refreshed-task requirement, active-before-
pending precedence, same-ID rejection, and exact terminal statuses. State
writes, liveness, prompts, result processing, retry behavior, and recursion
remained coordinator-owned. At that point, the recovery routes stayed deferred
pending the separate route-and-evidence contract recorded below.

The post-integration refresh ranks that contract as the next task because the
coordinator remains the largest clear-ownership boundary below 60% coverage,
while the contract can be completed without moving side effects. The first
implementation fallback is `chat_remote_datasource.dart`: it has the lowest
coverage among clear standalone candidates and exposes separable streaming and
response-normalization concerns. Ecosystem-specific installed-dependency
resolution is the next fallback. The remaining clear candidates either have
already completed a pure extraction or retain higher-coverage orchestration,
IO, lifecycle, containment, or layout responsibilities.

The route extraction was gated by a task document that froze supported
platforms, process commands, address-family behavior, fallback precedence,
JSON shapes, injected runners, and focused tests. The routine and LAN
extractions used the same contract-first approach for presentation behavior
and CIDR semantics respectively. The filesystem contract froze public API,
headers, hunk context, algorithm thresholds, truncation, and fallback copy.

The model metadata contract froze ID normalization, metadata source and key
precedence, numeric coercion, LM Studio selected-instance fallback, and public
datasource parsing APIs.

The file workspace contract froze row classification order, hunk counter
resets, old and new line progression, malformed input handling, trailing rows,
and existing viewer rendering.

The workflow failure contract froze structured JSON fields, command-output
guardrail delegation, raw marker order, malformed input fallback, batch
short-circuiting, and the existing 12 coordinator call sites.

The workflow lifecycle contract froze continuation depths 0 through 7, the
depth-8 stop, refreshed completed-task validation, compatible task precedence,
same-ID rejection, and completed-or-blocked terminal classification.

The workflow recovery contract then froze assistant-evidence precedence over
tool-less recovery, one read-context and one edit retry after an edit mismatch,
post-hidden-send liveness, the existing continuation ceiling, and blocked or
incomplete stopping. It also confirmed and fixed matching recovery reads being
treated as completion evidence when target metadata was absent.

## Network Slice Outcome

The selected route, interface, and path-MTU cluster is complete on
`feature/network-route-tools-extraction`.

- `network_tools.dart` fell from 1,996 to 968 physical lines and retains the
  static compatibility facade plus DNS, mDNS, ping, and traceroute concerns.
- `network_route_tools.dart` is an independent 1,128-line service with injected
  platform, process-runner, and address-lookup boundaries.
- Direct service coverage reached 93.88% (414/441). Combined executable
  coverage for the facade and extracted service rose from the original 41.60%
  snapshot to 65.10% (485/745).
- The full gate passed analysis, 3,849 root tests, and 13 internal-package tests
  at 74.67% line coverage (53,110/71,124).
- The next inventory-ranked candidate was `routine_detail_view.dart`; its
  ownership and presentation-state coupling were rechecked before extraction.

## Routine Run-History Slice Outcome

The routine run-history boundary is complete on
`feature/routine-run-history-extraction`.

- `routine_detail_view.dart` fell from 1,407 to 948 physical lines and retains
  provider coordination, mutations, summary state, and plan presentation.
- `routine_run_history_section.dart` is an independent 525-line widget with one
  immutable `Routine` input and no Riverpod or notifier dependency.
- Product-path and direct tests cover empty and populated histories, successful
  and failed records, ordering, duration boundaries, action visibility, and
  transcript and error sheets.
- The extracted widget reached 96.17% coverage (251/261). The remaining page
  reached 37.72% (175/464), up from the original 34.90% snapshot.
- The full gate passed analysis, 3,857 root tests, and 13 internal-package tests
  at 74.91% line coverage (53,293/71,147).
- Pause the page now that it is below 1,000 lines. Refresh this ranking before
  selecting another production boundary.

## LAN IP Network Slice Outcome

The LAN IP network boundary is complete on
`feature/lan-ip-network-extraction`.

- `lan_scan_service.dart` fell from 1,038 to 843 physical lines and retains
  scan planning, ping and TCP probes, port scanning, link-layer discovery, and
  result caching.
- `lan_ip_network.dart` is an independent 199-line value object for IPv4 and
  IPv6 CIDR parsing, normalization, enumeration, containment, numeric ordering,
  and scope handling. The service re-exports it for source compatibility.
- Direct tests cover normalization, invalid prefixes, IPv4 `/30`, `/31`, and
  `/32` enumeration, IPv6 `/126` enumeration, host caps, containment, address
  families, numeric ordering, invalid-address fallback, and scope stripping.
- The extracted value object reached 97.87% coverage (92/94). The remaining
  service reached 51.83% (170/328), and their combined executable coverage rose
  from the original 57.82% snapshot to 62.09% (262/422).
- The full gate passed analysis, 3,865 root tests, and 13 internal-package tests
  at 74.93% line coverage (53,311/71,147).
- Pause the service now that it is below 1,000 lines. Refresh this ranking before
  selecting another production boundary.

## Filesystem Diff Slice Outcome

The filesystem diff boundary is complete on
`feature/filesystem-diff-extraction`.

- `filesystem_tools.dart` fell from 1,476 to 1,282 physical lines and retains
  path resolution, directory and file inspection, file mutation, edit
  preconditions, snapshots, rollback, and the public diff compatibility API.
- `filesystem_diff_builder.dart` is an independent 213-line pure service for
  LCS and anchor diff construction, hunk context, unavailable-preview content,
  and line and character truncation.
- Direct and compatibility tests cover created, deleted, unchanged, small,
  separated-hunk, large, and truncated previews plus fallback proposed content.
- The extracted service reached 99.06% coverage (105/106). The remaining
  filesystem service reached 78.98% (417/528), and their combined executable
  coverage rose from the original 77.46% snapshot to 82.33% (522/634).
- The full gate passed analysis, 3,876 root tests, and 13 internal-package tests
  at 74.97% line coverage (53,344/71,151).
- Re-rank the remaining 1,282-line service before another extraction. Do not
  widen this slice into file I/O, path handling, or edit semantics.

## Model Metadata Parser Slice Outcome

The model metadata parser boundary is complete on
`feature/model-metadata-parser-extraction`.

- `model_remote_datasource.dart` fell from 1,813 to 1,710 physical lines and
  retains provider discovery, response construction, catalog merging, HTTP
  transport, lifecycle actions, and its public parsing compatibility APIs.
- `model_metadata_parser.dart` is an independent 120-line pure service for
  model ID normalization, ordered context-window metadata lookup, positive
  numeric coercion, and LM Studio loaded-instance context selection.
- Direct and compatibility tests cover root and nested precedence, numeric
  coercion, malformed values, ID normalization, selected and fallback loaded
  instances, model-level fallback, and llama.cpp slot consistency.
- The parser reached 97.14% coverage (34/35). The remaining datasource reached
  79.36% (546/688), and their combined executable coverage reached 80.22%
  (580/723), compared with the original datasource snapshot of 80.08%
  (575/718).
- The full gate passed analysis, 3,885 root tests, and 13 internal-package tests
  at 74.97% line coverage (53,349/71,156).
- Re-rank the remaining datasource before another extraction. Do not widen this
  slice into provider HTTP, catalog merge, or model lifecycle behavior.

## File Workspace Diff Parser Slice Outcome

The file workspace diff parser boundary is complete on
`feature/file-workspace-diff-parser-extraction`.

- `file_workspace_viewer_sheet.dart` fell from 1,634 to 1,559 physical lines
  and retains file loading, root containment, selection state, layout, colors,
  details, actions, and compatible parsed-row rendering.
- `file_workspace_diff_parser.dart` is an independent 97-line pure service for
  header, context, addition, and removal classification plus old and new line
  tracking across hunks.
- Direct and compatibility tests cover file headers, multiple hunks, counter
  resets, additions, removals, context, malformed hunk text, no-newline markers,
  blank rows, empty patches, trailing newlines, and rendered line numbers.
- The parser reached 96.97% coverage (32/33). The remaining viewer reached
  82.90% (514/620), and their combined executable coverage reached 83.61%
  (546/653), compared with the original viewer snapshot of 83.69% (544/650).
- The full gate passed analysis, 3,892 root tests, and 13 internal-package tests
  at 74.97% line coverage (53,351/71,159).
- Re-rank the remaining viewer before another extraction. Do not widen this
  slice into file IO, root containment, selection state, or layout behavior.

## Workflow Tool Result Failure Detector Slice Outcome

The workflow tool result failure detector boundary is complete on
`feature/workflow-tool-failure-detector-extraction`.

- `workflow_task_run_coordinator.dart` fell from 2,442 to 2,402 physical lines
  and retains recovery ordering, prompts, status mutation, liveness checks,
  completion evidence, retries, and all 12 compatible failure checks.
- `workflow_tool_result_failure_detector.dart` is an independent 54-line domain
  service for structured JSON failures, command-output anomalies, and
  case-insensitive raw failure markers.
- Direct and compatibility tests cover blank and benign results, malformed
  JSON, numeric exits, boolean flags, error fields, zero-exit output anomalies,
  every raw marker, mixed batches, recovery precedence, and liveness.
- The detector reached 95.65% coverage (22/23). The remaining coordinator
  reached 60.16% (450/748), and their combined executable coverage reached
  61.22% (472/771), compared with the original coordinator snapshot of 60.94%
  (465/763).
- The full gate passed analysis, 3,898 root tests, and 13 internal-package tests
  at 74.98% line coverage (53,359/71,167).
- The following lifecycle-policy slice satisfied the terminal-state and
  continuation contract requirement without moving recovery side effects.

## Workflow Task Run Lifecycle Policy Slice Outcome

The workflow task lifecycle policy boundary is complete on
`feature/workflow-task-run-lifecycle-policy-extraction`.

- `workflow_task_run_coordinator.dart` fell from 2,402 to 2,392 physical lines
  and retains all liveness checks, status mutation, prompts, result processing,
  recovery ordering, retry behavior, and recursion.
- `workflow_task_run_lifecycle_policy.dart` is an independent 56-line pure
  domain service for continuation depth, refreshed completed-task validation,
  compatible next-task selection, same-ID protection, and terminal statuses.
- Direct and compatibility tests cover depths 7 and 8, negative depth, missing
  and non-completed current tasks, in-progress and pending precedence, no next
  task, duplicate IDs, and every terminal and non-terminal status.
- The policy reached 100.00% coverage (12/12). The remaining coordinator
  reached 59.95% (446/744), and their combined executable coverage reached
  60.58% (458/756).
- The full gate passed analysis, 3,905 root tests, and 13 internal-package tests
  at 74.98% line coverage (53,367/71,175).
- This slice left the remaining recovery state machine paused pending the
  separate route-and-evidence contract recorded below.

## Workflow Recovery Route And Evidence Contract Outcome

The workflow recovery route and evidence contract is complete on
`feature/workflow-recovery-route-evidence-contract`.

- Direct coordinator tests freeze assistant evidence before tool-less recovery,
  one bounded edit-mismatch retry, and no progress mutation after page unmount
  during a hidden recovery send.
- Characterization found that a matching recovery `read_file` could mark a
  task without target metadata complete before the edit retry. The coordinator
  now treats that read as context evidence and preserves the bounded retry.
- Existing validation, eight-continuation, blocked-task, incomplete-task, and
  visible-send liveness coverage remains green.
- The coordinator stays within its 2,392-line ratchet and reached 61.69%
  coverage (459/744).
- The focused verifier passed analysis, 94 root tests, and 13 internal-package
  tests. The final full gate passed analysis, 3,908 root tests, and 13
  internal-package tests at 75.00% line coverage (53,384/71,175).
- This contract required the follow-up implementation task to define a pure
  typed route selector while prompts, evidence capture, liveness, progress
  writes, retries, and recursion remained coordinator-owned.

## Workflow Task Turn Route Policy Slice Outcome

The workflow task turn route policy is complete on
`feature/workflow-task-turn-route-policy`.

- `workflow_task_turn_route_policy.dart` is a 43-line pure domain service that
  owns the exact seven-route recovery order and the assistant-evidence and
  tool-less recovery gates.
- `workflow_task_run_coordinator.dart` iterates the typed routes and retains the
  exhaustive dispatcher, all recovery implementations, prompts, evidence
  capture, liveness checks, progress writes, retry bodies, and recursion.
- Direct tests freeze the route order and complete boolean gate truth tables.
  Product-path tests continue to execute every specialized recovery route.
- The policy reached 100.00% coverage (3/3). The coordinator shrank from 2,392
  to 2,380 physical lines and reached 62.17% coverage (470/756).
- The focused verifier passed analysis, 110 root tests, and 13 internal-package
  tests. The full gate passed analysis, 3,913 root tests, and 13
  internal-package tests at 75.01% line coverage (53,400/71,190).
- The following contract-only ChatPage characterization is complete.

## ChatPage State Transition Contract Outcome

The ChatPage state transition contract is complete on
`feature/chat-page-state-transition-contract`.

- Product-path widget tests freeze dashboard exits, workspace and conversation
  selection, coding-project synchronization, assistant-mode changes, and Files
  tab retention when the wide companion sidebar is hidden and reopened.
- The contract exercises only public drawer and header controls and adds no
  test-only production seam.
- Characterization found no production defect, so `chat_page.dart` remains
  2,133 physical lines with no production change.
- `chat_page.dart` coverage increased from 49.51% (402/812) to 55.91%
  (454/812). Full repository coverage reached 75.18% (53,522/71,190).
- The focused verifier passed analysis, 7 root tests, and 13 internal-package
  tests. The full gate passed analysis, 3,915 root tests, and 13
  internal-package tests.
- This contract enabled the subsequent workspace, project, conversation, and
  assistant-mode routing extraction. Dashboard visibility, sidebar visibility,
  Files-tab state, workflow, approval, and composer behavior remained
  page-owned and out of scope for that move.

## ChatPage Workspace Navigation Coordinator Outcome

The workspace navigation extraction is complete on
`feature/chat-page-workspace-navigation-coordinator`.

- `ChatPageWorkspaceNavigationCoordinator` owns workspace activation,
  coding-project selection, drawer conversation selection, dashboard exit, and
  assistant-mode synchronization through injected notifier and state callbacks.
- ChatPage retains Riverpod composition, dashboard visibility, sidebar and
  Files-tab state, workflow, approval, composer, localization, and modal state.
- `chat_page.dart` fell from 2,133 to 2,045 physical lines and its same-library
  aggregate fell from 8,945 to 8,857 lines. The coordinator is 127 lines.
- Direct tests freeze Chat, Coding, and Routines activation, first-open deferral,
  project fallback, missing conversations, normalized project selection, and
  non-General mode preservation. Existing product-path state tests remain green.
- The focused verifier passed analysis, 92 root tests, and 13 internal-package
  tests. The full gate passed analysis, 3,927 root tests, and 13 package tests at
  75.19% line coverage (53,527/71,192).
- The coordinator reached 100.00% coverage (40/40), `chat_page.dart` reached
  54.26% (420/774), and their combined executable coverage is 56.51%
  (460/814).
- This ranking selected the response-normalization contract completed below;
  the navigation coordinator remained narrow.

## Chat Completion Response Normalizer Outcome

The response-normalization extraction is complete on
`feature/chat-response-normalizer`.

- `ChatCompletionResponseNormalizer` owns reasoning composition, native call
  conversion and malformed-argument fallback, advertised embedded-call
  promotion, finish-reason selection, and raw parse-failure recovery.
- `ChatRemoteDataSource` retains request construction, HTTP and streaming
  transport, reasoning retries, stream accumulation, usage telemetry,
  tool-result and image formatting, exception propagation, and diagnostic logs.
- `chat_remote_datasource.dart` fell from 1,244 to 1,164 physical lines. The
  independent normalizer is 183 lines, and both files have non-increasing
  ratchets.
- Direct tests freeze plain and reasoning responses, native precedence,
  sanitized and malformed arguments, advertised-name filtering, incomplete
  embedded calls, channel-marker recovery, and raw-call promotion. Existing
  datasource product paths remain green.
- The focused verifier passed analysis, 109 root tests, and 13 internal-package
  tests. The full gate passed analysis, 3,944 root tests, and 13 package tests at
  75.19% line coverage (53,557/71,231).
- The normalizer reached 100.00% coverage (60/60), the datasource reached
  52.81% (263/498), and their combined executable coverage is 57.89%
  (323/558).
- The next ranked candidate is one MessageInput composer state or action
  contract. Re-characterize streaming before any later datasource extraction.

## MessageInput Slash Suggestion State Outcome

The slash suggestion state extraction is complete on
`feature/message-input-slash-suggestion-state`.

- `MessageInputSlashSuggestionState` owns suggestion refresh, selected-index
  clamping, next and previous wrapping, tapped index selection, dismiss state,
  and completed-command suppression.
- `MessageInput` retains text controller mutation, key-event routing,
  localized feedback, slash command execution, attachment handling, input
  history, worktree session sending, voice recording, and coding-goal controls.
- `message_input.dart` fell from 2,374 to 2,332 physical lines. The independent
  state helper is 131 lines, and both files have ratchets.
- Direct tests freeze enabled and attachment-guarded suggestion refresh,
  clamping, wrapping, dismiss suppression, completed-command suppression, and
  same-instance no-op refreshes. Existing MessageInput product-path widget tests
  remain green.
- The focused verifier passed analysis, 31 root tests, and 13 internal-package
  tests.
- Re-characterize one remaining MessageInput composer action before another
  extraction. Do not widen this helper into execution, history, attachments, or
  goal controls.

## Stack Integration Outcome

The eight completed extraction slices are integrated into `main` as
`f80132bf`.

- `main` was the direct ancestor of the 31-commit stack, and the squash applied
  without conflicts.
- The staged integration contained the audited 37 slice files plus the
  integration task contract; no unrelated worktree changes were included.
- The integrated full gate passed analysis, 3,905 root tests, and 13
  internal-package tests at 74.98% line coverage (53,368/71,175).
- Source branches and unrelated worktrees remain intact. The follow-up workflow
  route-and-evidence contract, typed route policy, and ChatPage state
  characterization, workspace-navigation extraction, and response-normalizer
  extraction are complete.

## Reproduction Commands

```bash
find lib packages -name '*.dart' -type f \
  ! -name '*.g.dart' ! -name '*.freezed.dart' -print0 \
  | xargs -0 wc -l | sort -nr
```

```bash
git worktree list --porcelain
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```
