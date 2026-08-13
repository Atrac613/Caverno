import 'dart:async';

import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import '../providers/conversations_notifier.dart';
import '../providers/worktree_agent_task_launcher.dart';
import '../providers/worktree_agent_task_orchestrator.dart';
import '../slash_commands/slash_command.dart';
import '../slash_commands/slash_command_catalog.dart';
import '../slash_commands/slash_command_prompt_template.dart';
import '../slash_commands/worktree_agent_command_args.dart';
import 'slash_command_result_builders.dart';

export '../slash_commands/worktree_agent_command_args.dart'
    show worktreeAgentTaskTitle;

typedef GoalSlashCommandHandler =
    Future<SlashCommandExecutionResult> Function(
      Conversation conversation,
      String args, {
      required bool sendObjectiveAsInitialPrompt,
    });

typedef FeedbackSlashCommandHandler =
    Future<SlashCommandExecutionResult> Function(
      Conversation? conversation,
      String feedbackText,
    );

final class SlashCommandActionContext {
  const SlashCommandActionContext({
    required this.isLoading,
    required this.isCodingWorkspace,
    required this.activeProject,
    required this.currentConversation,
    required this.conversationsState,
    required this.customPromptTemplates,
  });

  final bool isLoading;
  final bool isCodingWorkspace;
  final CodingProject? activeProject;
  final Conversation? currentConversation;
  final ConversationsState conversationsState;
  final List<SlashCommandPromptTemplate> customPromptTemplates;
}

final class SlashCommandActionCoordinator {
  SlashCommandActionCoordinator({
    required ConversationsNotifier conversationsNotifier,
    required void Function() clearMessages,
    required void Function() cancelStreaming,
    required void Function() dismissPlanProposal,
    required Future<void> Function(AssistantMode mode) updateAssistantMode,
    required void Function() leaveDashboard,
    required Future<void> Function(List<SlashCommandDefinition> commands)
    showHelp,
    required GoalSlashCommandHandler handleGoal,
    required FeedbackSlashCommandHandler submitFeedback,
    required ProReasoningSlashCommandHandler startProReasoning,
    required Future<WorktreeAgentTaskLaunchResult> Function(
      WorktreeAgentTaskLaunchRequest request,
    )
    enqueueWorktreeAgent,
    required Future<void> Function(WorktreeAgentTaskRunRequest request)
    startReadyWorktreeAgents,
    required SlashCommandTextResolver text,
  }) : _conversationsNotifier = conversationsNotifier,
       _clearMessages = clearMessages,
       _cancelStreaming = cancelStreaming,
       _dismissPlanProposal = dismissPlanProposal,
       _updateAssistantMode = updateAssistantMode,
       _leaveDashboard = leaveDashboard,
       _showHelp = showHelp,
       _handleGoal = handleGoal,
       _submitFeedback = submitFeedback,
       _startProReasoning = startProReasoning,
       _enqueueWorktreeAgent = enqueueWorktreeAgent,
       _startReadyWorktreeAgents = startReadyWorktreeAgents,
       _text = text;

  final ConversationsNotifier _conversationsNotifier;
  final void Function() _clearMessages, _cancelStreaming;
  final void Function() _dismissPlanProposal, _leaveDashboard;
  final Future<void> Function(AssistantMode mode) _updateAssistantMode;
  final Future<void> Function(List<SlashCommandDefinition> commands) _showHelp;
  final GoalSlashCommandHandler _handleGoal;
  final FeedbackSlashCommandHandler _submitFeedback;
  final ProReasoningSlashCommandHandler _startProReasoning;
  final Future<WorktreeAgentTaskLaunchResult> Function(
    WorktreeAgentTaskLaunchRequest request,
  )
  _enqueueWorktreeAgent;
  final Future<void> Function(WorktreeAgentTaskRunRequest request)
  _startReadyWorktreeAgents;
  final SlashCommandTextResolver _text;

  Future<SlashCommandExecutionResult> handle(
    SlashCommandInvocation invocation, {
    required SlashCommandActionContext commandContext,
  }) async {
    if (commandContext.isLoading &&
        !invocation.definition.enabledWhileLoading) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text('chat.slash_blocked_while_loading'),
      );
    }

    switch (invocation.definition.action) {
      case SlashCommandAction.help:
        await _showHelp(
          buildSlashCommandCatalog(
            text: _text,
            customPromptTemplates: commandContext.customPromptTemplates,
          ),
        );
        return SlashCommandExecutionResult.handled;
      case SlashCommandAction.newConversation:
        _leaveDashboard();
        if (commandContext.isCodingWorkspace &&
            commandContext.activeProject != null) {
          _conversationsNotifier.startDraftConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: commandContext.activeProject!.id,
          );
        } else {
          _conversationsNotifier.createNewConversation(
            workspaceMode:
                commandContext.conversationsState.activeWorkspaceMode,
            projectId: commandContext.activeProject?.id,
          );
        }
        return SlashCommandExecutionResult(
          feedbackMessage: _text(
            commandContext.isCodingWorkspace
                ? 'chat.slash_new_thread_started'
                : 'chat.slash_new_conversation_started',
          ),
        );
      case SlashCommandAction.clear:
        _clearMessages();
        await _conversationsNotifier.updateCurrentConversation(
          const <Message>[],
        );
        return SlashCommandExecutionResult(
          feedbackMessage: _text('chat.slash_cleared'),
        );
      case SlashCommandAction.general:
        await _selectAssistantMode(
          AssistantMode.general,
          commandContext: commandContext,
        );
        return buildSlashModeChangedResult(_text, 'settings.assistant_general');
      case SlashCommandAction.coding:
        await _selectAssistantMode(
          AssistantMode.coding,
          commandContext: commandContext,
        );
        return buildSlashModeChangedResult(_text, 'settings.assistant_coding');
      case SlashCommandAction.plan:
        // enterPlanningSession starts the conversation on a brand-new thread.
        if (!commandContext.isCodingWorkspace) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: _text('chat.slash_plan_unavailable'),
          );
        }
        await _conversationsNotifier.enterPlanningSession();
        return SlashCommandExecutionResult(
          feedbackMessage: _text('chat.slash_plan_started'),
        );
      case SlashCommandAction.pro:
        return buildProReasoningSlashCommandResult(
          isCodingWorkspace: commandContext.isCodingWorkspace,
          args: invocation.args,
          startProReasoning: _startProReasoning,
          text: _text,
        );
      case SlashCommandAction.goal:
        var goalConversation = commandContext.currentConversation;
        final shouldStartGoalPrompt = goalConversation == null;
        if (goalConversation == null && commandContext.isCodingWorkspace) {
          goalConversation = _conversationsNotifier.ensureCurrentConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId:
                commandContext.activeProject?.id ??
                commandContext.conversationsState.activeProjectId,
          );
        }
        if (!commandContext.isCodingWorkspace || goalConversation == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: _text('chat.slash_goal_unavailable'),
          );
        }
        return _handleGoal(
          goalConversation,
          invocation.args,
          sendObjectiveAsInitialPrompt: shouldStartGoalPrompt,
        );
      case SlashCommandAction.cancel:
        if (!commandContext.isLoading) {
          return SlashCommandExecutionResult(
            feedbackMessage: _text('chat.slash_cancel_idle'),
          );
        }
        _cancelStreaming();
        return SlashCommandExecutionResult(
          feedbackMessage: _text('chat.slash_cancelled'),
        );
      case SlashCommandAction.feedback:
        return _submitFeedback(
          commandContext.currentConversation,
          invocation.args,
        );
      case SlashCommandAction.worktreeAgent:
        return _handleWorktreeAgent(
          invocation.args,
          commandContext: commandContext,
        );
      case SlashCommandAction.review:
      case SlashCommandAction.fix:
      case SlashCommandAction.explain:
      case SlashCommandAction.test:
      case SlashCommandAction.promptTemplate:
        final template = resolveSlashCommandPromptTemplate(
          invocation,
          commandContext.customPromptTemplates,
        );
        if (template == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: _text('message.slash_command_failed'),
          );
        }
        return SlashCommandExecutionResult.sendPrompt(
          template.expand(
            args: invocation.args,
            commandName: invocation.commandName,
          ),
        );
    }
  }

  Future<void> _selectAssistantMode(
    AssistantMode mode, {
    required SlashCommandActionContext commandContext,
  }) async {
    if (commandContext.currentConversation?.isPlanningSession ?? false) {
      await _conversationsNotifier.exitPlanningSession();
      _dismissPlanProposal();
    }
    await _updateAssistantMode(mode);
  }

  Future<SlashCommandExecutionResult> _handleWorktreeAgent(
    String args, {
    required SlashCommandActionContext commandContext,
  }) async {
    final activeProject = commandContext.activeProject;
    if (!commandContext.isCodingWorkspace || activeProject == null) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text('chat.slash_agent_unavailable'),
      );
    }
    final agentArgs = parseWorktreeAgentCommandArgs(args);
    if (agentArgs.prompt.isEmpty) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text('chat.slash_agent_prompt_required'),
      );
    }
    if (agentArgs.hasVerificationMarker &&
        agentArgs.verificationCommand.isEmpty) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text('chat.slash_agent_verify_required'),
      );
    }
    if (agentArgs.hasAcceptanceMarker &&
        agentArgs.objectiveAcceptanceCriteria.isEmpty) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text('chat.slash_agent_acceptance_required'),
      );
    }
    if (agentArgs.hasAcceptanceMarker &&
        agentArgs.verificationCommand.isEmpty) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text('chat.slash_agent_acceptance_verify_required'),
      );
    }
    try {
      final result = await _enqueueWorktreeAgent(
        WorktreeAgentTaskLaunchRequest(
          title: worktreeAgentTaskTitle(agentArgs.prompt),
          prompt: agentArgs.prompt,
          codingProjectId: activeProject.id,
          projectRootPath: activeProject.normalizedRootPath,
          verificationCommand: agentArgs.verificationCommand,
          objectiveAcceptanceCriteria: agentArgs.objectiveAcceptanceCriteria,
        ),
      );
      if (agentArgs.runAfterQueue) {
        unawaited(
          _startReadyWorktreeAgents(
            WorktreeAgentTaskRunRequest(
              fallbackProjectRootPath: activeProject.normalizedRootPath,
            ),
          ),
        );
        return SlashCommandExecutionResult(
          feedbackMessage: _text(
            'chat.slash_agent_queued_and_started',
            namedArgs: {'branch': result.task.branchName},
          ),
        );
      }
      return SlashCommandExecutionResult(
        feedbackMessage: _text(
          'chat.slash_agent_queued',
          namedArgs: {'branch': result.task.branchName},
        ),
      );
    } catch (error) {
      return SlashCommandExecutionResult.keepInput(
        feedbackMessage: _text(
          'chat.slash_agent_failed',
          namedArgs: {'error': '$error'},
        ),
      );
    }
  }
}
