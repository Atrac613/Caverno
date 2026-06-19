#!/usr/bin/env bash
#
# LL13 regression gate for parallel worktree-agent orchestration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/codex_verify.sh" \
  --no-codegen \
  --test test/features/chat/domain/services/worktree_agent_assignment_planner_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_git_reservation_probe_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_git_worktree_preparer_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_task_registry_notifier_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_task_launcher_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_task_starter_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_task_scheduler_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_task_executor_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_task_orchestrator_test.dart \
  --test test/features/chat/presentation/providers/worktree_agent_verification_runner_test.dart \
  --test test/features/chat/presentation/widgets/worktree_agent_task_banner_test.dart \
  --test test/features/chat/presentation/pages/chat_page_slash_commands_test.dart
