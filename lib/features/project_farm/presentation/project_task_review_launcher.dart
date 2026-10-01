import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../application/project_task_commit_turn_runner.dart';
import '../application/project_task_review_turn_runner.dart';
import '../application/project_task_review_workflow.dart';
import '../data/project_git_status_reader.dart';

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
      final workflow = ProjectTaskReviewWorkflow(
        conversationId: conversationId,
        readConversation: readTask,
        isSelected: selected,
        isWaitingForUser: waiting,
        send: runner.send,
        commit: ProjectTaskCommitTurnRunner(
          readConversation: readTask,
          isSelected: selected,
          isWaitingForUser: waiting,
          sendTurn: (prompt) => notifier.sendMessage(
            prompt,
            languageCode: languageCode,
            bypassPlanMode: true,
          ),
          waitForCompletion: notifier.waitForTurnCompletion,
        ).send,
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
