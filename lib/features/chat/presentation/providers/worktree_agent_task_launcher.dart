import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/worktree_agent_task.dart';
import '../../domain/services/worktree_agent_assignment_planner.dart';
import 'coding_projects_notifier.dart';
import 'worktree_agent_git_reservation_probe.dart';
import 'worktree_agent_task_registry_notifier.dart';

class WorktreeAgentTaskLaunchRequest {
  const WorktreeAgentTaskLaunchRequest({
    required this.title,
    required this.prompt,
    this.codingProjectId = '',
    this.projectRootPath = '',
    this.baseBranch = 'main',
    this.branchPrefix = WorktreeAgentAssignmentPlanner.defaultBranchPrefix,
    this.worktreeRootPath = '',
    this.checkpointLineageId = '',
    this.endpointId = '',
    this.verificationCommand = '',
    this.existingBranchNames = const <String>[],
    this.existingWorktreePaths = const <String>[],
  });

  final String title;
  final String prompt;
  final String codingProjectId;
  final String projectRootPath;
  final String baseBranch;
  final String branchPrefix;
  final String worktreeRootPath;
  final String checkpointLineageId;
  final String endpointId;
  final String verificationCommand;
  final Iterable<String> existingBranchNames;
  final Iterable<String> existingWorktreePaths;
}

class WorktreeAgentTaskLaunchResult {
  const WorktreeAgentTaskLaunchResult({required this.plan, required this.task});

  final WorktreeAgentAssignmentPlan plan;
  final WorktreeAgentTask task;
}

final worktreeAgentAssignmentPlannerProvider =
    Provider<WorktreeAgentAssignmentPlanner>((ref) {
      return const WorktreeAgentAssignmentPlanner();
    });

final worktreeAgentTaskLauncherProvider = Provider<WorktreeAgentTaskLauncher>((
  ref,
) {
  return WorktreeAgentTaskLauncher(ref);
});

class WorktreeAgentTaskLauncher {
  const WorktreeAgentTaskLauncher(this._ref);

  final Ref _ref;

  Future<WorktreeAgentTaskLaunchResult> enqueue(
    WorktreeAgentTaskLaunchRequest request,
  ) async {
    final projectState = _ref.read(codingProjectsNotifierProvider);
    final project = _resolveProject(request, projectState);
    final projectRootPath = _resolveProjectRootPath(request, project);
    if (projectRootPath.isEmpty) {
      throw StateError(
        'A coding project root path is required to launch a worktree agent task.',
      );
    }

    final registryState = _ref.read(worktreeAgentTaskRegistryNotifierProvider);
    final gitReservations = await _ref
        .read(worktreeAgentGitReservationProbeProvider)
        .load(projectRootPath);
    if (gitReservations.hasError) {
      throw StateError(
        gitReservations.errorMessage ??
            'Could not read git worktree reservations.',
      );
    }

    final settings = _ref.read(settingsNotifierProvider);
    final endpointId = _resolveEndpointId(
      request: request,
      settings: settings,
      registryState: registryState,
    );
    final codingProjectId = request.codingProjectId.trim().isEmpty
        ? (project?.id ?? '')
        : request.codingProjectId.trim();

    final planner = _ref.read(worktreeAgentAssignmentPlannerProvider);
    final plan = planner.plan(
      title: request.title,
      prompt: request.prompt,
      projectRootPath: projectRootPath,
      existingTasks: registryState.tasks,
      codingProjectId: codingProjectId,
      baseBranch: request.baseBranch,
      branchPrefix: request.branchPrefix,
      worktreeRootPath: request.worktreeRootPath,
      checkpointLineageId: request.checkpointLineageId,
      endpointId: endpointId,
      verificationCommand: request.verificationCommand,
      existingBranchNames: [
        ...gitReservations.branchNames,
        ...request.existingBranchNames,
      ],
      existingWorktreePaths: [
        ...gitReservations.worktreePaths,
        ...request.existingWorktreePaths,
      ],
    );

    final task = await _ref
        .read(worktreeAgentTaskRegistryNotifierProvider.notifier)
        .registerAssignment(plan);
    return WorktreeAgentTaskLaunchResult(plan: plan, task: task);
  }

  CodingProject? _resolveProject(
    WorktreeAgentTaskLaunchRequest request,
    CodingProjectsState state,
  ) {
    final requestedProjectId = request.codingProjectId.trim();
    final explicitRootPath = request.projectRootPath.trim();
    if (requestedProjectId.isNotEmpty) {
      final project = state.findById(requestedProjectId);
      if (project != null || explicitRootPath.isNotEmpty) {
        return project;
      }

      throw StateError('Coding project $requestedProjectId was not found.');
    }

    if (explicitRootPath.isNotEmpty) {
      return _findProjectByRootPath(explicitRootPath, state);
    }

    return state.selectedProject;
  }

  CodingProject? _findProjectByRootPath(
    String rootPath,
    CodingProjectsState state,
  ) {
    final normalizedRootPath = rootPath.trim();
    for (final project in state.projects) {
      if (project.normalizedRootPath == normalizedRootPath) {
        return project;
      }
    }
    return null;
  }

  String _resolveProjectRootPath(
    WorktreeAgentTaskLaunchRequest request,
    CodingProject? project,
  ) {
    final explicitRootPath = request.projectRootPath.trim();
    if (explicitRootPath.isNotEmpty) {
      return explicitRootPath;
    }
    return project?.normalizedRootPath ?? '';
  }

  String _resolveEndpointId({
    required WorktreeAgentTaskLaunchRequest request,
    required AppSettings settings,
    required WorktreeAgentTaskRegistryState registryState,
  }) {
    final explicitEndpointId = request.endpointId.trim();
    if (explicitEndpointId.isNotEmpty) {
      return explicitEndpointId;
    }

    final candidates = _endpointCandidates(settings);
    if (candidates.isEmpty) {
      return '';
    }

    final activeCounts = _activeEndpointCounts(registryState.tasks);
    var selected = candidates.first;
    var selectedCount = activeCounts[_endpointKey(selected)] ?? 0;
    for (final candidate in candidates.skip(1)) {
      final candidateCount = activeCounts[_endpointKey(candidate)] ?? 0;
      if (candidateCount < selectedCount) {
        selected = candidate;
        selectedCount = candidateCount;
      }
    }
    return selected;
  }

  List<String> _endpointCandidates(AppSettings settings) {
    final candidates = <String>[];
    final enabledEndpointIds = settings.enabledNamedEndpoints
        .map((endpoint) => endpoint.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    void addCandidate(String endpointId) {
      final normalized = endpointId.trim();
      if (normalized.isEmpty || candidates.contains(normalized)) {
        return;
      }
      candidates.add(normalized);
    }

    final preferredEndpointId = settings.subagentEndpointId.trim();
    if (enabledEndpointIds.isEmpty) {
      addCandidate(preferredEndpointId);
      return candidates;
    }

    if (enabledEndpointIds.contains(preferredEndpointId)) {
      addCandidate(preferredEndpointId);
    }
    for (final endpointId in enabledEndpointIds) {
      addCandidate(endpointId);
    }
    return candidates;
  }

  Map<String, int> _activeEndpointCounts(List<WorktreeAgentTask> tasks) {
    final counts = <String, int>{};
    for (final task in tasks) {
      if (task.isTerminal) continue;
      final endpointKey = _endpointKey(task.endpointId);
      counts[endpointKey] = (counts[endpointKey] ?? 0) + 1;
    }
    return counts;
  }

  String _endpointKey(String endpointId) {
    final normalized = endpointId.trim();
    return normalized.isEmpty ? 'primary' : normalized;
  }
}
