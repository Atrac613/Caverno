import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/data/repositories/conversation_listing_codec.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/domain/entities/conversation_plan_artifact.dart';
import '../../chat/domain/entities/conversation_workflow.dart';
import '../../chat/domain/entities/turn_diff.dart';
import '../../chat/domain/services/conversation_plan_document_builder.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../application/project_task_commit_turn_evidence.dart';
import '../application/project_task_inheritance.dart';
import '../application/project_task_review_turn_runner.dart';
import '../application/project_task_review_workflow.dart';
import '../application/project_task_step_turn_runner.dart';
import '../data/project_git_status_reader.dart';
import '../data/project_task_commit_reader.dart';
import '../domain/entities/project_task_commit_scope.dart';
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
          purpose: codeReview
              ? PrimaryTurnPurpose.codeReview
              : PrimaryTurnPurpose.projectTaskImplementation,
        ),
        waitForCompletion: notifier.waitForTurnCompletion,
      );
      ProjectTaskCommitTurnEvidence? commitTurnEvidence;
      ProjectTaskStepTurnRunner step(
        bool Function(ConversationGoal goal) admits, {
        Future<void> Function()? reactivate,
        PrimaryTurnPurpose purpose = PrimaryTurnPurpose.projectTaskStep,
        ProjectTaskCommitScope? commitScope,
      }) => ProjectTaskStepTurnRunner(
        readConversation: readTask,
        isSelected: selected,
        isWaitingForUser: waiting,
        admits: admits,
        reactivateCompleted: reactivate,
        sendTurn: (prompt) => commitScope == null
            ? notifier.sendMessage(
                prompt,
                languageCode: languageCode,
                bypassPlanMode: true,
                purpose: purpose,
              )
            : notifier.sendProjectTaskCommit(
                prompt,
                commitScope,
                languageCode: languageCode,
                purpose: purpose,
              ),
        waitForCompletion: (owner) async {
          await notifier.waitForTurnCompletion(owner);
          if (commitScope != null) {
            commitTurnEvidence = notifier.takeProjectTaskCommitTurnEvidence(
              owner,
            );
          }
        },
      );
      final conversations = ref.read(conversationsNotifierProvider.notifier);
      final inherited = projectRoot == null || projectRoot.isEmpty
          ? const <TurnDiffFile>[]
          : await inheritedTaskFiles(
              task: conversation,
              conversations: ref
                  .read(conversationsNotifierProvider)
                  .conversations,
              load: (run) async {
                if (!ConversationListingCodec.isListingStub(run.messages)) {
                  return run;
                }
                await conversations.refreshConversationForExecution(run.id);
                return ref
                        .read(conversationsNotifierProvider)
                        .conversationForId(run.id) ??
                    run;
              },
              isDirty: (path) async =>
                  (await _gitReader.readTaskState(projectRoot, [
                    path,
                  ]))?.dirtyPaths.isNotEmpty ==
                  true,
            );
      if (inherited.isNotEmpty) {
        // The completion gate reads this from the goal, so a turn that finds
        // the work already done is asked to verify it, not to report a
        // blocker.
        await conversations.persistRuntimeGoal(
          conversationId: conversationId,
          goal: conversation.goal!.copyWith(
            projectTaskInheritedPaths: [
              ...{for (final file in inherited) file.filePath},
            ],
            updatedAt: DateTime.now(),
          ),
        );
      }
      final workflow = ProjectTaskReviewWorkflow(
        conversationId: conversationId,
        readConversation: readTask,
        isSelected: selected,
        isWaitingForUser: waiting,
        send: runner.send,
        projectRoot: projectRoot,
        readCommitSnapshot: const ProjectTaskCommitReader().read,
        readCommitTurnEvidence: () => commitTurnEvidence,
        prepareCommit: (prompt, scope) {
          commitTurnEvidence = null;
          return step(
            ProjectTaskStepTurnRunner.completedGoal,
            purpose: PrimaryTurnPurpose.projectTaskCommitPreparation,
            commitScope: scope,
          ).send(prompt);
        },
        commit: (prompt, scope) {
          commitTurnEvidence = null;
          return step(
            ProjectTaskStepTurnRunner.completedGoal,
            purpose: PrimaryTurnPurpose.projectTaskCommit,
            commitScope: scope,
          ).send(prompt);
        },
        sendStep: step(
          ProjectTaskStepTurnRunner.activeGoal,
          reactivate: () => conversations.markCurrentGoalStatus(
            status: ConversationGoalStatus.active,
          ),
        ).send,
        // The subtasks become the thread's execution tasks, so the Plan Mode
        // progress rows and the execution snapshot in the prompt show them.
        // They are saved without a plan review by user decision (2026-10-01)
        // and carry no validation command, so nothing the model wrote runs
        // unapproved. The outline document is written first and labelled as
        // unreviewed: otherwise saving the workflow backfills one recorded as
        // an approved plan, and the prompt presents it as one.
        decompose: (objective) async {
          final subtasks = await ref
              .read(projectTaskDecomposerProvider)
              .decompose(objective, languageCode: languageCode);
          if (subtasks.isNotEmpty) {
            final spec = ConversationWorkflowSpec(
              goal: objective,
              tasks: subtasks,
            );
            await conversations.updateCurrentPlanArtifact(
              conversationId: conversationId,
              planArtifact:
                  ConversationPlanDocumentBuilder.buildApprovedArtifact(
                    workflowStage: ConversationWorkflowStage.implement,
                    workflowSpec: spec,
                    updatedAt: DateTime.now(),
                    label: ConversationPlanArtifact.unreviewedOutlineLabel,
                  ),
            );
            await conversations.updateCurrentWorkflow(
              conversationId: conversationId,
              workflowStage: ConversationWorkflowStage.implement,
              workflowSpec: spec,
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
        inheritedFiles: inherited,
        recordPriorChanges: (paths) async {
          final goal = readTask()?.goal;
          if (goal == null) return;
          final merged = {...goal.projectTaskInheritedPaths, ...paths};
          if (merged.length == goal.projectTaskInheritedPaths.length) return;
          await conversations.persistRuntimeGoal(
            conversationId: conversationId,
            goal: goal.copyWith(
              projectTaskInheritedPaths: merged.toList(),
              updatedAt: DateTime.now(),
            ),
          );
        },
        onProgress: (progress) => ref
            .read(projectTaskProgressProvider.notifier)
            .report(conversationId, progress),
        readGitState: (paths) async =>
            projectRoot == null || projectRoot.isEmpty
            ? null
            : _gitReader.readTaskState(projectRoot, paths),
        readTaskPatch: (paths) async =>
            projectRoot == null || projectRoot.isEmpty
            ? null
            : _gitReader.readTaskPatch(projectRoot, paths),
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
