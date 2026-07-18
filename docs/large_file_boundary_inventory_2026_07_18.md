# Large-File Boundary Inventory — 2026-07-18

Status: complete on `feature/large-file-boundary-inventory-refresh` after the
Computer Use permission-action slice landed on local `main` as `79b05c00`.

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
  `tool/codex_verify.sh --coverage --no-codegen` run for the permission-action
  slice. Coverage percentages use executable lines from `coverage/lcov.info`,
  not physical-line counts.
- Ownership source: every existing worktree from
  `git worktree list --porcelain`, conservatively compared with local `main`.
  A listed overlap does not prove that a worktree is still active, but it is a
  conflict signal that must be resolved before editing that boundary.

The full gate passed analysis, 3,833 root tests, and 13 internal-package tests
at 74.43% line coverage (52,927/71,105).

## Same-Library Aggregates

| Root library | Primary lines | Declared parts | Aggregate lines |
|---|---:|---:|---:|
| `lib/features/chat/presentation/providers/chat_notifier.dart` | 9,468 | 43 | 23,005 |
| `lib/features/chat/presentation/pages/chat_page.dart` | 2,133 | 12 | 8,945 |
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
| `lib/features/chat/presentation/pages/chat_page.dart` | 2,133 |
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
| `lib/features/chat/data/datasources/chat_remote_datasource.dart` | 1,244 |
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
aggregate and production counterpart both have multiple conservative ownership
conflicts. Do not split only the test root while production ownership remains
unsettled.

## Active-Worktree Ownership Audit

The Computer Use debug page and its product test have no remaining overlapping
active worktree after the checklist and action-group branches landed. This
proves the ownership conflict that blocked the sequence is resolved.

Conservative overlaps remain on these large boundaries:

- `chat_notifier.dart`: ten worktree branches, including discovery, notifier
  refactor, goal/tool-loop recovery, live-convergence, Plan Mode stability, and
  roadmap worktrees. One LL23 worktree is dirty.
- `chat_page.dart`: four worktree branches: notifier refactor, LL13 registry,
  investigation playbook, and LL19 recording.
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
| 1 | `network_tools.dart` | 1,996 | 41.60% | clear | Characterize route, interface, and path-MTU delegation as the next fresh slice. |
| 2 | `routine_detail_view.dart` | 1,407 | 34.90% | clear | Recheck presentation-state coupling after the network slice. |
| 3 | `workflow_task_run_coordinator.dart` | 2,442 | 60.94% | clear | Require a lifecycle and recovery contract before another split; it is a recent high-risk boundary. |
| 4 | `model_remote_datasource.dart` | 1,813 | 80.08% | clear | Defer behind lower-coverage, more cohesive candidates. |
| 5 | `computer_use_debug_page.dart` | 1,910 | 94.36% | clear | Pause after the completed extraction sequence; remaining code is orchestration-heavy. |
| 6 | `computer_use_settings_page.dart` | 1,725 | 95.22% | clear | Pause after Phase 4 summary extractions; coverage and separation are already strong. |

`network_tools.dart` is the next target because it combines a clear ownership
state, a still-large physical boundary, the lowest coverage among the top
unowned production candidates except `routine_detail_view.dart`, and an
existing internal seam. HTTP, neighbor, and socket concerns are already
delegated. Route lookup, interface inspection, and path-MTU measurement share
platform process injection, route/interface models, and fallback data, so they
form the next coherent behavior-preserving characterization target.

Do not begin that extraction until a new task document freezes supported
platforms, process commands, address-family behavior, fallback precedence,
JSON shapes, injected runners, and focused tests.

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
