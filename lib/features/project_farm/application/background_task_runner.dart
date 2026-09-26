import '../../chat/domain/entities/coding_project.dart';
import '../../chat/domain/entities/worktree_agent_task.dart';
import '../domain/entities/project_farm_policy.dart';
import '../domain/entities/project_proposal.dart';
import '../domain/entities/roadmap_snapshot.dart';
import 'project_task_starter.dart';

/// Why Run in background is unavailable for a project right now.
enum BackgroundRunBlocker {
  /// The user has not allowed any verification command (invariant 2).
  noPolicy,

  /// No verified task to run.
  noTask,

  /// The orchestrator did not propose this task as `unattended`.
  needsHuman,

  /// A background task for this project has not finished (one per project).
  busy,
}

/// Null when [item] may run in the background; otherwise the first reason it
/// may not. Every condition is mechanical: the policy is the user's, the
/// proposal must name this very item, and the label is only one gate of four.
BackgroundRunBlocker? backgroundRunBlocker({
  required ProjectFarmPolicy? policy,
  required ProjectProposal? proposal,
  required RoadmapItemSnapshot? item,
  required Iterable<WorktreeAgentTask> projectTasks,
}) {
  if (policy == null || !policy.allowsBackgroundWork) {
    return BackgroundRunBlocker.noPolicy;
  }
  if (item == null || !item.verified) return BackgroundRunBlocker.noTask;
  if (proposal == null ||
      proposal.error != null ||
      proposal.taskId != item.id ||
      proposal.automatability != 'unattended') {
    return BackgroundRunBlocker.needsHuman;
  }
  if (projectTasks.any((task) => !task.isTerminal)) {
    return BackgroundRunBlocker.busy;
  }
  return null;
}

/// The instruction a worktree agent receives. The goal cites its roadmap line,
/// and the agent is told its limits so it does not promise what it cannot do.
String backgroundTaskPrompt(RoadmapItemSnapshot item, String roadmapPath) =>
    '${projectTaskObjective(item, roadmapPath)}\n\n'
    'Complete this roadmap task in the current worktree with the smallest '
    'change that does it. You can read and edit files only; a declared '
    'verification command runs after you finish. Do not merge, push, or edit '
    'the roadmap to mark the task done: the user reviews your branch.';

/// Enqueues [item] on the LL13 worktree route and starts the scheduler.
///
/// Rechecks the policy at the last moment, so a command the policy does not
/// allow is refused here even if a caller skipped the dialog.
Future<WorktreeAgentTask> runProjectTaskInBackground({
  required Future<WorktreeAgentTask> Function({
    required String title,
    required String prompt,
    required String codingProjectId,
    required String projectRootPath,
    required String verificationCommand,
    required List<String> acceptanceCriteria,
  })
  enqueue,
  required void Function(String projectRootPath) startReady,
  required CodingProject project,
  required ProjectFarmPolicy policy,
  required RoadmapItemSnapshot item,
  required String roadmapPath,
  required String verificationCommand,
}) async {
  if (policy.projectId != project.id || !policy.allows(verificationCommand)) {
    throw StateError(
      'The verification command is not allowed by this project\'s policy.',
    );
  }
  final task = await enqueue(
    title: [item.id, item.title].where((part) => part.isNotEmpty).join(': '),
    prompt: backgroundTaskPrompt(item, roadmapPath),
    codingProjectId: project.id,
    projectRootPath: project.rootPath,
    verificationCommand: normalizePolicyCommand(verificationCommand),
    acceptanceCriteria: [
      'The roadmap task is done as stated: "${item.quote.trim()}"',
      'The verification command exits 0.',
    ],
  );
  startReady(project.rootPath);
  return task;
}
