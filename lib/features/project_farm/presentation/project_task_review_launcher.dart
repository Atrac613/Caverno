import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/domain/entities/conversation_workflow.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../application/project_task_review_turn_runner.dart';
import '../application/project_task_review_workflow.dart';
import '../application/project_task_step_turn_runner.dart';
import '../data/project_git_status_reader.dart';
import 'providers/project_task_progress_provider.dart';
import 'providers/roadmap_snapshot_providers.dart';

/// Starts the automatic workflow for a dashboard-started roadmap task when its
/// thread is first opened, and reports the outcome.
///
/// Lives outside `ChatPage` so the page only forwards the selection; the page
/// library has no size budget left for the wiring.
final class ProjectTaskReviewLauncher {
  ProjectTaskReviewLauncher({
    ProjectGitStatusReader gitReader = const ProjectGitStatusReader(),
  }) : _gitReader = gitReader;

  final ProjectGitStatusReader _gitReader;
  final Set<String> _running = <String>{};

  Future<void> start({
    required WidgetRef ref,
    required String conversationId,
    required String languageCode,
    required bool Function() isMounted,
    required void Function(String message) showMessage,
  }) async {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .conversationForId(conversationId);
    if (conversation?.goal?.projectTaskAutoReview != true ||
        conversation!.messages.isNotEmpty ||
        !_running.add(conversationId)) {
      return;
    }
    try {
      if (!ref.read(settingsNotifierProvider).hasCodeReviewRoute) {
        showMessage('chat.slash_review_not_configured'.tr());
        return;
      }
      final projectRoot = ref
          .read(codingProjectsNotifierProvider)
          .findById(conversation.projectId)
          ?.rootPath
          .trim();
      final notifier = ref.read(chatNotifierProvider.notifier);
      Conversation? readTask() => ref
          .read(conversationsNotifierProvider)
          .conversationForId(conversationId);
      bool selected() =>
          isMounted() &&
          ref.read(conversationsNotifierProvider).currentConversationId ==
              conversationId &&
          notifier.conversationId == conversationId;
      bool waiting() =>
          notifier.isConversationBusy(conversationId) ||
          notifier.isConversationAwaitingApproval(conversationId) ||
          ref
                  .read(chatNotifierProvider)
                  .pendingAskUserQuestion
                  ?.conversationId ==
              conversationId;
      final runner = ProjectTaskReviewTurnRunner(
        readConversation: readTask,
        isSelected: selected,
        isWaitingForUser: waiting,
        reactivate: () => ref
            .read(conversationsNotifierProvider.notifier)
            .markCurrentGoalStatus(status: ConversationGoalStatus.active),
        sendTurn: (prompt, {required codeReview}) => notifier.sendMessage(
          prompt,
          languageCode: languageCode,
          bypassPlanMode: true,
          codeReview: codeReview,
          projectTaskImplementation: !codeReview,
        ),
        waitForCompletion: notifier.waitForTurnCompletion,
      );
      ProjectTaskStepTurnRunner step(
        bool Function(ConversationGoal goal) admits,
      ) => ProjectTaskStepTurnRunner(
        readConversation: readTask,
        isSelected: selected,
        isWaitingForUser: waiting,
        admits: admits,
        sendTurn: (prompt) => notifier.sendMessage(
          prompt,
          languageCode: languageCode,
          bypassPlanMode: true,
        ),
        waitForCompletion: notifier.waitForTurnCompletion,
      );
      final conversations = ref.read(conversationsNotifierProvider.notifier);
      final workflow = ProjectTaskReviewWorkflow(
        conversationId: conversationId,
        readConversation: readTask,
        isSelected: selected,
        isWaitingForUser: waiting,
        send: runner.send,
        commit: step(ProjectTaskStepTurnRunner.completedGoal).send,
        sendStep: step(ProjectTaskStepTurnRunner.activeGoal).send,
        // The subtasks become the thread's execution tasks, so the Plan Mode
        // progress rows and the execution snapshot in the prompt show them.
        // They are saved without a plan review by user decision (2026-10-01)
        // and carry no validation command, so nothing the model wrote runs
        // unapproved.
        decompose: (objective) async {
          final subtasks = await ref
              .read(projectTaskDecomposerProvider)
              .decompose(objective, languageCode: languageCode);
          if (subtasks.isNotEmpty) {
            await conversations.updateCurrentWorkflow(
              conversationId: conversationId,
              workflowStage: ConversationWorkflowStage.implement,
              workflowSpec: ConversationWorkflowSpec(
                goal: objective,
                tasks: subtasks,
              ),
            );
          }
          return subtasks;
        },
        markSubtaskDone: (taskId) {
          final now = DateTime.now();
          return conversations.updateCurrentExecutionTaskProgress(
            conversationId: conversationId,
            taskId: taskId,
            status: ConversationWorkflowTaskStatus.completed,
            lastRunAt: now,
            eventType: ConversationExecutionTaskEventType.completed,
            eventTimestamp: now,
          );
        },
        onProgress: (progress) => ref
            .read(projectTaskProgressProvider.notifier)
            .report(conversationId, progress),
        readGitState: (paths) async =>
            projectRoot == null || projectRoot.isEmpty
            ? null
            : _gitReader.readTaskState(projectRoot, paths),
      );
      final result = await workflow.run();
      if (!isMounted() || !selected()) return;
      showMessage(switch (result) {
        ProjectTaskReviewResult.committed =>
          'chat.project_task_review_committed'.tr(),
        ProjectTaskReviewResult.findingsRemain =>
          'chat.project_task_review_findings'.tr(),
        ProjectTaskReviewResult.stopped =>
          'chat.project_task_review_stopped'.tr(),
      });
    } catch (error) {
      if (isMounted()) {
        showMessage(
          'chat.project_task_review_error'.tr(
            namedArgs: {'error': error.toString()},
          ),
        );
      }
    } finally {
      _running.remove(conversationId);
    }
  }
}
