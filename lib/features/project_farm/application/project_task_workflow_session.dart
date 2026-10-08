import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../core/types/workspace_mode.dart';
import '../../chat/data/datasources/llm_session_log_store.dart';
import '../../chat/data/datasources/session_logging_chat_datasource.dart';
import '../../chat/data/repositories/conversation_listing_codec.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/domain/entities/conversation_plan_artifact.dart';
import '../../chat/domain/entities/conversation_workflow.dart';
import '../../chat/domain/entities/turn_diff.dart';
import '../../chat/domain/services/conversation_plan_document_builder.dart';
import '../../chat/domain/services/project_task_review_verdict.dart';
import '../../chat/domain/services/project_task_terminal_status.dart';
import '../../chat/presentation/providers/chat_notifier.dart';
import '../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../chat/presentation/providers/conversations_notifier.dart';
import '../../settings/presentation/providers/settings_notifier.dart';
import '../data/project_git_status_reader.dart';
import '../data/project_task_commit_reader.dart';
import '../domain/entities/project_task_commit_scope.dart';
import '../presentation/providers/project_task_progress_provider.dart';
import '../presentation/providers/roadmap_snapshot_providers.dart';
import 'project_task_commit_turn_evidence.dart';
import 'project_task_inheritance.dart';
import 'project_task_review_turn_runner.dart';
import 'project_task_review_workflow.dart';
import 'project_task_step_turn_runner.dart';

/// Reads a provider; satisfied by both `WidgetRef.read` and
/// `ProviderContainer.read`, so the GUI and the terminal share one session.
typedef ProjectTaskProviderRead = T Function<T>(ProviderListenable<T> provider);

/// How a [ProjectTaskWorkflowSession.run] call ended. The caller decides how,
/// and whether, to tell the user.
sealed class ProjectTaskWorkflowOutcome {
  const ProjectTaskWorkflowOutcome();
}

/// The thread is not an unstarted auto-review task, or a run already owns it.
final class ProjectTaskWorkflowSkipped extends ProjectTaskWorkflowOutcome {
  const ProjectTaskWorkflowSkipped();
}

/// No code-review route is configured, so the review phase cannot run.
final class ProjectTaskWorkflowUnavailable extends ProjectTaskWorkflowOutcome {
  const ProjectTaskWorkflowUnavailable();
}

final class ProjectTaskWorkflowFinished extends ProjectTaskWorkflowOutcome {
  const ProjectTaskWorkflowFinished(this.result, {required this.stillSelected});

  final ProjectTaskReviewResult result;

  /// Whether the task thread was still the active one when the run ended.
  final bool stillSelected;
}

final class ProjectTaskWorkflowFailed extends ProjectTaskWorkflowOutcome {
  const ProjectTaskWorkflowFailed(this.error);

  final Object error;
}

/// Composes and runs the automatic decompose, implement, review and commit
/// workflow for a roadmap task thread.
///
/// Frontend-neutral: it reads providers through [ProjectTaskProviderRead] and
/// reports a [ProjectTaskWorkflowOutcome] instead of showing messages, so the
/// chat page and a headless farm command drive the same workflow.
final class ProjectTaskWorkflowSession {
  ProjectTaskWorkflowSession({
    ProjectGitStatusReader gitReader = const ProjectGitStatusReader(),
  }) : _gitReader = gitReader;

  final ProjectGitStatusReader _gitReader;
  final Set<String> _running = <String>{};

  /// Runs the workflow for [conversationId]. [isActive] reports whether the
  /// frontend that started the run is still present; the workflow pauses its
  /// turns while the thread is not selected in an active frontend.
  /// [onDecision] receives each workflow decision as it is logged.
  /// With [resume], a thread whose earlier run stopped continues from where
  /// its saved state shows it stopped instead of starting fresh.
  Future<ProjectTaskWorkflowOutcome> run({
    required ProjectTaskProviderRead read,
    required String conversationId,
    required String languageCode,
    required bool Function() isActive,
    void Function(Map<String, Object?> decision)? onDecision,
    bool resume = false,
  }) async {
    final conversation = read(
      conversationsNotifierProvider,
    ).conversationForId(conversationId);
    if (conversation?.goal?.projectTaskAutoReview != true ||
        conversation!.messages.isEmpty == resume ||
        !_running.add(conversationId)) {
      return const ProjectTaskWorkflowSkipped();
    }
    try {
      if (!read(settingsNotifierProvider).hasCodeReviewRoute) {
        return const ProjectTaskWorkflowUnavailable();
      }
      final projectRoot = read(
        codingProjectsNotifierProvider,
      ).findById(conversation.projectId)?.rootPath.trim();
      final notifier = read(chatNotifierProvider.notifier);
      Conversation? readTask() =>
          read(conversationsNotifierProvider).conversationForId(conversationId);
      bool selected() =>
          isActive() &&
          read(conversationsNotifierProvider).currentConversationId ==
              conversationId &&
          notifier.conversationId == conversationId;
      bool waiting() =>
          notifier.isConversationBusy(conversationId) ||
          notifier.isConversationAwaitingApproval(conversationId) ||
          read(chatNotifierProvider).pendingAskUserQuestion?.conversationId ==
              conversationId;
      ProjectTaskReviewVerdict? reviewVerdict;
      final runner = ProjectTaskReviewTurnRunner(
        readConversation: readTask,
        isSelected: selected,
        isWaitingForUser: waiting,
        reactivate: () => read(
          conversationsNotifierProvider.notifier,
        ).markCurrentGoalStatus(status: ConversationGoalStatus.active),
        sendTurn: (prompt, {required codeReview}) {
          if (codeReview) reviewVerdict = null;
          return notifier.sendMessage(
            prompt,
            languageCode: languageCode,
            bypassPlanMode: true,
            purpose: codeReview
                ? PrimaryTurnPurpose.codeReview
                : PrimaryTurnPurpose.projectTaskImplementation,
          );
        },
        waitForCompletion: (owner) async {
          await notifier.waitForTurnCompletion(owner);
          reviewVerdict = notifier.takeProjectTaskReviewVerdict(owner);
        },
      );
      ProjectTaskCommitTurnEvidence? commitTurnEvidence;
      ProjectTaskTerminalStatus? subtaskStatus;
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
          if (purpose == PrimaryTurnPurpose.projectTaskStep) {
            subtaskStatus = notifier.takeProjectTaskSubtaskStatus(owner);
          }
          if (commitScope != null) {
            commitTurnEvidence = notifier.takeProjectTaskCommitTurnEvidence(
              owner,
            );
          }
        },
      );
      final conversations = read(conversationsNotifierProvider.notifier);
      final inherited = projectRoot == null || projectRoot.isEmpty
          ? const <TurnDiffFile>[]
          : await inheritedTaskFiles(
              task: conversation,
              conversations: read(conversationsNotifierProvider).conversations,
              load: (run) async {
                if (!ConversationListingCodec.isListingStub(run.messages)) {
                  return run;
                }
                await conversations.refreshConversationForExecution(run.id);
                return read(
                      conversationsNotifierProvider,
                    ).conversationForId(run.id) ??
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
        readReviewVerdict: () => reviewVerdict,
        readVerificationContext: () =>
            notifier.projectTaskVerificationContext(conversationId),
        projectRoot: projectRoot,
        readCommitSnapshot: const ProjectTaskCommitReader().read,
        onDecision: (decision) {
          final state = read(chatNotifierProvider);
          final observed = <String, Object?>{
            ...decision,
            'selected': selected(),
            'busy': notifier.isConversationBusy(conversationId),
            'awaitingApproval': notifier.isConversationAwaitingApproval(
              conversationId,
            ),
            'pendingQuestion':
                state.pendingAskUserQuestion?.conversationId == conversationId,
          };
          onDecision?.call(observed);
          final settings = read(settingsNotifierProvider);
          if (!LlmSessionLogStore.isEnabled(
                settingsEnabled: settings.enableLlmSessionLogs,
              ) ||
              settings.demoMode) {
            return;
          }
          final owner = readTask();
          unawaited(
            read(llmSessionLogStoreProvider).recordProjectTaskDecision(
              context: LlmSessionLogContext(
                workspaceMode: owner?.workspaceMode ?? WorkspaceMode.coding,
                sessionId: conversationId,
                conversationId: conversationId,
                phase: 'project_task_workflow',
              ),
              decision: observed,
              at: DateTime.now(),
            ),
          );
        },
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
        readSubtaskStatus: () => subtaskStatus,
        sendStep: (prompt) {
          subtaskStatus = null;
          return step(
            ProjectTaskStepTurnRunner.activeGoal,
            reactivate: () => conversations.markCurrentGoalStatus(
              status: ConversationGoalStatus.active,
            ),
          ).send(prompt);
        },
        // The subtasks become the thread's execution tasks, so the Plan Mode
        // progress rows and the execution snapshot in the prompt show them.
        // They are saved without a plan review by user decision (2026-10-01)
        // and carry no validation command, so nothing the model wrote runs
        // unapproved. The outline document is written first and labelled as
        // unreviewed: otherwise saving the workflow backfills one recorded as
        // an approved plan, and the prompt presents it as one.
        decompose: (objective) async {
          final subtasks = await read(
            projectTaskDecomposerProvider,
          ).decompose(objective, languageCode: languageCode);
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
        onProgress: (progress) => read(
          projectTaskProgressProvider.notifier,
        ).report(conversationId, progress),
        readGitState: (paths) async =>
            projectRoot == null || projectRoot.isEmpty
            ? null
            : _gitReader.readTaskState(projectRoot, paths),
        readTaskPatch: (paths) async =>
            projectRoot == null || projectRoot.isEmpty
            ? null
            : _gitReader.readTaskPatch(projectRoot, paths),
      );
      final result = resume ? await workflow.resume() : await workflow.run();
      return ProjectTaskWorkflowFinished(result, stillSelected: selected());
    } catch (error) {
      final settings = read(settingsNotifierProvider);
      if (LlmSessionLogStore.isEnabled(
            settingsEnabled: settings.enableLlmSessionLogs,
          ) &&
          !settings.demoMode) {
        await read(llmSessionLogStoreProvider).recordProjectTaskDecision(
          context: LlmSessionLogContext(
            workspaceMode: conversation.workspaceMode,
            sessionId: conversationId,
            conversationId: conversationId,
            phase: 'project_task_workflow',
          ),
          decision: {
            'phase': 'workflow',
            'decision': 'stopped',
            'reason': 'workflow_exception',
          },
          at: DateTime.now(),
        );
      }
      return ProjectTaskWorkflowFailed(error);
    } finally {
      _running.remove(conversationId);
    }
  }
}
