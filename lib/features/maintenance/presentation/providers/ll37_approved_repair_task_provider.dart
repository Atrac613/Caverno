import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/repositories/worktree_agent_task_repository.dart';
import '../../../chat/domain/entities/worktree_agent_task.dart';
import '../../../chat/presentation/providers/worktree_agent_task_launcher.dart';
import '../../domain/services/ll37_approved_repair_task_adapter.dart';

typedef Ll37ApprovedRepairTaskEnqueue =
    Future<WorktreeAgentTask> Function(Ll37ApprovedRepairTaskSpec spec);

WorktreeAgentTaskLaunchRequest ll37ApprovedRepairTaskLaunchRequest(
  Ll37ApprovedRepairTaskSpec spec,
) => WorktreeAgentTaskLaunchRequest(
  title: spec.title,
  prompt: spec.prompt,
  codingProjectId: spec.codingProjectId,
  baseBranch: spec.baseBranch,
  assignmentId: spec.assignmentId,
  branchPrefix: spec.branchPrefix,
  checkpointLineageId: spec.checkpointLineageId,
  endpointId: spec.endpointId,
  verificationCommand: spec.verificationCommand,
  objectiveAcceptanceCriteria: spec.objectiveAcceptanceCriteria,
);

/// Reads LL13 history without starting registry recovery or changing tasks.
final ll37ApprovedRepairTaskSourceProvider =
    Provider<List<WorktreeAgentTask> Function()>((ref) {
      return () => ref.read(worktreeAgentTaskRepositoryProvider).loadAll();
    });

/// Crosses into the existing LL13 queue only after the UI confirms approval.
final ll37ApprovedRepairTaskEnqueueProvider =
    Provider<Ll37ApprovedRepairTaskEnqueue>((ref) {
      return (spec) async {
        final result = await ref
            .read(worktreeAgentTaskLauncherProvider)
            .enqueue(ll37ApprovedRepairTaskLaunchRequest(spec));
        return result.task;
      };
    });
