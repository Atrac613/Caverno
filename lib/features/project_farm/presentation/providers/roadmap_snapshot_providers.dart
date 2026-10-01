import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/workspace_mode.dart';
import '../../../chat/data/datasources/chat_datasource.dart';
import '../../../chat/domain/entities/chat_turn_owner.dart';
import '../../../chat/domain/entities/coding_project.dart';
import '../../../chat/domain/entities/message.dart';
import '../../../chat/domain/entities/worktree_agent_task.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../../chat/presentation/providers/turn_thread_scope.dart';
import '../../../chat/presentation/providers/worktree_agent_task_launcher.dart';
import '../../../chat/presentation/providers/worktree_agent_task_orchestrator.dart';
import '../../../chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../application/background_task_runner.dart';
import '../../application/farm_unattended_runner.dart';
import '../../application/project_proposal_service.dart';
import '../../application/project_task_decomposer.dart';
import '../../application/project_task_starter.dart';
import '../../application/roadmap_snapshot_service.dart';
import '../../application/workspace_control_tools.dart';
import '../../data/roadmap_snapshot_repository.dart';
import '../../domain/entities/project_farm_policy.dart';
import '../../domain/entities/roadmap_snapshot.dart';
import '../../domain/next_step_proposal_contract.dart';
import '../../domain/roadmap_next_task_extractor.dart';

final roadmapSnapshotRepositoryProvider =
    Provider<RoadmapSnapshotRepositoryApi>(
      (ref) => RoadmapSnapshotRepository(ref.watch(sharedPreferencesProvider)),
    );

final roadmapSnapshotServiceProvider = Provider<RoadmapSnapshotService>((ref) {
  return RoadmapSnapshotService(
    repository: ref.watch(roadmapSnapshotRepositoryProvider),
    ensureAccess: (projectId) => ref
        .read(codingProjectsNotifierProvider.notifier)
        .ensureProjectAccess(projectId),
    readFile: _readFileIfPresent,
    // Resolved per refresh so a settings change reaches the next extraction.
    extractor: () => RoadmapNextTaskExtractor(
      complete: structuredRoadmapCompletion(
        ref.read(chatRemoteDataSourceProvider),
        model: ref.read(settingsNotifierProvider).effectiveModel,
      ),
    ),
    model: () => ref.read(settingsNotifierProvider).effectiveModel,
  );
});

Future<String?> _readFileIfPresent(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsString();
}

/// Splits a dashboard-started task into subtasks with the primary model.
final projectTaskDecomposerProvider = Provider<ProjectTaskDecomposer>((ref) {
  return ProjectTaskDecomposer(
    complete: structuredRoadmapCompletion(
      ref.read(chatRemoteDataSourceProvider),
      model: ref.read(settingsNotifierProvider).effectiveModel,
    ),
  );
});

/// Adapts the app's structured-output datasource to the extractor's port.
///
/// Uses the primary datasource with its own model, like the run-log analyser:
/// a role-pinned endpoint with an empty model would otherwise be sent the
/// primary model's name.
RoadmapCompletionPort structuredRoadmapCompletion(
  ChatDataSource dataSource, {
  required String model,
}) {
  return ({
    required String system,
    required String user,
    required String schemaName,
    required Map<String, dynamic> schema,
    required int maxTokens,
  }) async {
    if (dataSource is! StructuredOutputChatDataSource) {
      throw StateError(
        'The configured endpoint does not support structured output.',
      );
    }
    final source = dataSource as StructuredOutputChatDataSource;
    final now = DateTime.now();
    final result = await source.createStructuredChatCompletion(
      messages: [
        Message(
          id: 'roadmap-$schemaName-system',
          role: MessageRole.system,
          content: system,
          timestamp: now,
        ),
        Message(
          id: 'roadmap-$schemaName-user',
          role: MessageRole.user,
          content: user,
          timestamp: now,
        ),
      ],
      responseFormat: StructuredOutputRequest.jsonSchema(
        name: schemaName,
        schema: schema,
      ),
      model: model,
      temperature: 0,
      maxTokens: maxTokens,
    );
    return RoadmapCompletion(
      content: result.content,
      finishReason: result.finishReason,
    );
  };
}

/// The FARM2 read-only control-plane tools, offered to the model through
/// `McpToolService`. Every dependency is read at call time: this provider sits
/// under `mcpToolServiceProvider`, which the chat notifier itself depends on.
final workspaceControlToolsProvider = Provider<WorkspaceControlTools>((ref) {
  return WorkspaceControlTools(
    projects: () => ref.read(codingProjectsNotifierProvider).projects,
    conversations: () => ref.read(conversationsNotifierProvider).conversations,
    snapshotFor: (projectId) =>
        ref.read(roadmapSnapshotServiceProvider).cachedSnapshot(projectId),
    isBusy: (id) =>
        ref.read(chatNotifierProvider.notifier).isConversationBusy(id),
    needsApproval: (id) => ref
        .read(chatNotifierProvider.notifier)
        .isConversationAwaitingApproval(id),
    callerConversationId: () => TurnThread.currentId,
    startTask: ({required project, required item, required roadmapPath}) async {
      final callerId = TurnThread.currentId;
      final generation = TurnGeneration.current;
      if (callerId == null || generation == null) return null;
      final objective = projectTaskObjective(item, roadmapPath);
      // Fresh approval every time, never cached: starting work in another
      // thread is the user's call (docs/project_farm_roadmap.md, invariant 1).
      final approved = await ref
          .read(chatNotifierProvider.notifier)
          .requestFileOperation(
            owner: ChatTurnOwner(
              conversationId: callerId,
              interactionGeneration: generation,
            ),
            operation: 'Start Project Task',
            path: project.rootPath,
            preview: objective,
            reason:
                'Creates a coding thread in ${project.name} with this '
                'goal. Nothing is sent until you open it.',
          );
      if (!approved) return null;
      return startProjectTask(
        conversations: ref.read(conversationsNotifierProvider.notifier),
        projectId: project.id,
        item: item,
        roadmapPath: roadmapPath,
      );
    },
  );
});

/// FARM3 suggest mode: the orchestrator's next-step proposal per project.
final projectProposalServiceProvider = Provider<ProjectProposalService>((ref) {
  return ProjectProposalService(
    repository: ref.watch(roadmapSnapshotRepositoryProvider),
    complete: () => structuredRoadmapCompletion(
      ref.read(chatRemoteDataSourceProvider),
      model: ref.read(settingsNotifierProvider).effectiveModel,
    ),
    model: () => ref.read(settingsNotifierProvider).effectiveModel,
  );
});

/// FARM4 slice 4b: runs a task on the unchanged LL13 worktree route.
Future<WorktreeAgentTask> runProjectTaskInBackgroundFromRef(
  WidgetRef ref, {
  required CodingProject project,
  required ProjectFarmPolicy policy,
  required RoadmapItemSnapshot item,
  required String roadmapPath,
  required String verificationCommand,
}) => runProjectTaskInBackground(
  enqueue:
      ({
        required title,
        required prompt,
        required codingProjectId,
        required projectRootPath,
        required verificationCommand,
        required acceptanceCriteria,
      }) async =>
          (await ref
                  .read(worktreeAgentTaskLauncherProvider)
                  .enqueue(
                    WorktreeAgentTaskLaunchRequest(
                      title: title,
                      prompt: prompt,
                      codingProjectId: codingProjectId,
                      projectRootPath: projectRootPath,
                      verificationCommand: verificationCommand,
                      objectiveAcceptanceCriteria: acceptanceCriteria,
                    ),
                  ))
              .task,
  // Fire and forget, like the slash command and the Anabasis route: the run
  // outlives the page that started it.
  startReady: (projectRootPath) => unawaited(
    ref
        .read(worktreeAgentTaskOrchestratorProvider)
        .startAndExecuteReady(
          WorktreeAgentTaskRunRequest(fallbackProjectRootPath: projectRootPath),
        ),
  ),
  project: project,
  policy: policy,
  item: item,
  roadmapPath: roadmapPath,
  verificationCommand: verificationCommand,
);

/// Thread states for a proposal: titles, run state, and goals, no transcripts.
List<ProposalThread> proposalThreadsFor(Ref ref, String projectId) {
  final chat = ref.read(chatNotifierProvider.notifier);
  return [
    for (final thread in ref.read(conversationsNotifierProvider).conversations)
      if (thread.workspaceMode == WorkspaceMode.coding &&
          thread.normalizedProjectId == projectId)
        ProposalThread(
          title: thread.title,
          state: chat.isConversationAwaitingApproval(thread.id)
              ? 'needs_approval'
              : chat.isConversationBusy(thread.id)
              ? 'running'
              : 'idle',
          goal: thread.goal?.objective.split('\n').first,
          goalStatus: thread.goal?.status.name,
        ),
  ];
}

/// FARM5: the idle-maintenance pass that advances opted-in projects.
final farmUnattendedRunnerProvider = Provider<FarmUnattendedRunner>((ref) {
  return FarmUnattendedRunner(
    repository: ref.watch(roadmapSnapshotRepositoryProvider),
    projects: () => ref.read(codingProjectsNotifierProvider).projects,
    refreshSnapshot: (project) => ref
        .read(roadmapSnapshotServiceProvider)
        .refresh(projectId: project.id, projectRoot: project.rootPath),
    refreshProposal: (project, snapshot) => ref
        .read(projectProposalServiceProvider)
        .refresh(
          project: project,
          snapshot: snapshot,
          threads: proposalThreadsFor(ref, project.id),
        ),
    tasks: () => ref.read(worktreeAgentTaskRegistryNotifierProvider).tasks,
    enqueue:
        ({
          required title,
          required prompt,
          required codingProjectId,
          required projectRootPath,
          required verificationCommand,
          required acceptanceCriteria,
        }) async =>
            (await ref
                    .read(worktreeAgentTaskLauncherProvider)
                    .enqueue(
                      WorktreeAgentTaskLaunchRequest(
                        title: title,
                        prompt: prompt,
                        codingProjectId: codingProjectId,
                        projectRootPath: projectRootPath,
                        verificationCommand: verificationCommand,
                        objectiveAcceptanceCriteria: acceptanceCriteria,
                      ),
                    ))
                .task,
    startReady: (projectRootPath) => unawaited(
      ref
          .read(worktreeAgentTaskOrchestratorProvider)
          .startAndExecuteReady(
            WorktreeAgentTaskRunRequest(
              fallbackProjectRootPath: projectRootPath,
            ),
          ),
    ),
  );
});
