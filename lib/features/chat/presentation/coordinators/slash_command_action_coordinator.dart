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

final class WorktreeAgentCommandArgs {
  const WorktreeAgentCommandArgs({
    required this.prompt,
    this.verificationCommand = '',
    this.hasVerificationMarker = false,
    this.runAfterQueue = false,
  });

  final String prompt;
  final String verificationCommand;
  final bool hasVerificationMarker;
  final bool runAfterQueue;
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
       _enqueueWorktreeAgent = enqueueWorktreeAgent,
       _startReadyWorktreeAgents = startReadyWorktreeAgents,
       _text = text;

  final ConversationsNotifier _conversationsNotifier;
  final void Function() _clearMessages;
  final void Function() _cancelStreaming;
  final void Function() _dismissPlanProposal;
  final Future<void> Function(AssistantMode mode) _updateAssistantMode;
  final void Function() _leaveDashboard;
  final Future<void> Function(List<SlashCommandDefinition> commands) _showHelp;
  final GoalSlashCommandHandler _handleGoal;
  final FeedbackSlashCommandHandler _submitFeedback;
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
        return _modeChangedResult('settings.assistant_general');
      case SlashCommandAction.coding:
        await _selectAssistantMode(
          AssistantMode.coding,
          commandContext: commandContext,
        );
        return _modeChangedResult('settings.assistant_coding');
      case SlashCommandAction.plan:
        if (!commandContext.isCodingWorkspace ||
            commandContext.currentConversation == null) {
          return SlashCommandExecutionResult.keepInput(
            feedbackMessage: _text('chat.slash_plan_unavailable'),
          );
        }
        await _conversationsNotifier.enterPlanningSession();
        return SlashCommandExecutionResult(
          feedbackMessage: _text('chat.slash_plan_started'),
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

  SlashCommandExecutionResult _modeChangedResult(String modeKey) {
    return SlashCommandExecutionResult(
      feedbackMessage: _text(
        'chat.slash_mode_changed',
        namedArgs: {'mode': _text(modeKey)},
      ),
    );
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
    try {
      final result = await _enqueueWorktreeAgent(
        WorktreeAgentTaskLaunchRequest(
          title: worktreeAgentTaskTitle(agentArgs.prompt),
          prompt: agentArgs.prompt,
          codingProjectId: activeProject.id,
          projectRootPath: activeProject.normalizedRootPath,
          verificationCommand: agentArgs.verificationCommand,
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

WorktreeAgentCommandArgs parseWorktreeAgentCommandArgs(String args) {
  final trimmed = args.trim();
  final match = RegExp(r'(^|\s)--verify(?:\s+|$)').firstMatch(trimmed);
  final verifyMarkerStart = match == null
      ? trimmed.length
      : match.start + (match.group(1)?.length ?? 0);
  final prefix = trimmed.substring(0, verifyMarkerStart).trim();
  final runMarker = RegExp(r'(^|\s)--run(?=\s|$)');
  final runAfterQueue = runMarker.hasMatch(prefix);
  final prompt = prefix.replaceFirst(runMarker, ' ').trim();
  if (match == null) {
    return WorktreeAgentCommandArgs(
      prompt: prompt,
      runAfterQueue: runAfterQueue,
    );
  }
  return WorktreeAgentCommandArgs(
    prompt: prompt,
    verificationCommand: trimmed.substring(match.end).trim(),
    hasVerificationMarker: true,
    runAfterQueue: runAfterQueue,
  );
}

String worktreeAgentTaskTitle(String prompt) {
  final firstLine = prompt
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => 'Worktree agent');
  const maxTitleLength = 80;
  if (firstLine.length <= maxTitleLength) {
    return firstLine;
  }
  return '${firstLine.substring(0, maxTitleLength - 3).trimRight()}...';
}
