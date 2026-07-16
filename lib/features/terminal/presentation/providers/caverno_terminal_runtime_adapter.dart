import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../chat/presentation/providers/caverno_execution_runtime_provider.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/chat_state.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../application/caverno_cli_arguments.dart';
import '../../application/caverno_cli_contract.dart';
import '../../application/caverno_cli_runtime_configuration.dart';
import '../../application/caverno_cli_runtime_port.dart';
import '../../application/caverno_cli_tool_policy.dart';

final class CavernoTerminalRuntimeAdapter implements CavernoCliRuntimePort {
  CavernoTerminalRuntimeAdapter({
    required this.container,
    Map<String, String>? environment,
  }) : environment = environment ?? Platform.environment;

  final ProviderContainer container;
  final Map<String, String> environment;
  CavernoExecutionRuntime? _resolvedRuntime;
  ChatNotifier? _resolvedChatNotifier;

  CavernoExecutionRuntime get _runtime {
    final resolved = _resolvedRuntime;
    if (resolved != null) {
      return resolved;
    }
    final created = container.read(cavernoExecutionRuntimeProvider);
    _resolvedRuntime = created;
    return created;
  }

  ChatNotifier get _chatNotifier {
    final resolved = _resolvedChatNotifier;
    if (resolved != null) {
      return resolved;
    }
    final created = container.read(chatNotifierProvider.notifier);
    _resolvedChatNotifier = created;
    return created;
  }

  ChatState get _chatState {
    _chatNotifier;
    return container.read(chatNotifierProvider);
  }

  @override
  Stream<CavernoRuntimeEvent> get events => _runtime.events;

  @override
  Future<void> prepare(CavernoCliInvocation invocation) async {
    final command = invocation.command;
    final isResume =
        invocation.action == CavernoCliInvocationAction.conversationResume;
    if (command == null && !isResume) {
      throw const CavernoCliFailure(
        code: 'command_required',
        message: 'A runnable CLI command is required.',
        exitCode: CavernoCliExitCode.usage,
      );
    }

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    final resumedConversation = isResume
        ? await _prepareResumedConversation(invocation, conversations)
        : null;

    final currentSettings = container.read(settingsNotifierProvider);
    final runtimeConfiguration = resolveCavernoCliRuntimeConfiguration(
      invocation: invocation,
      environment: environment,
      persistedSettings: currentSettings,
    );
    _validateEndpoint(runtimeConfiguration.baseUrl);
    if (runtimeConfiguration.model.isEmpty) {
      throw const CavernoCliFailure(
        code: 'model_required',
        message: 'The effective model is empty.',
        exitCode: CavernoCliExitCode.input,
      );
    }

    final assistantMode = resumedConversation == null
        ? switch (command!) {
            CavernoCliCommand.chat => AssistantMode.general,
            CavernoCliCommand.coding => AssistantMode.coding,
            CavernoCliCommand.plan => AssistantMode.plan,
          }
        : _assistantModeForConversation(resumedConversation);
    container
        .read(settingsNotifierProvider.notifier)
        .applyTransientRuntimeOverrides(
          assistantMode: assistantMode,
          baseUrl: runtimeConfiguration.baseUrl,
          model: runtimeConfiguration.model,
          apiKey: runtimeConfiguration.apiKey,
          disabledBuiltInTools: <String>{...cavernoCliDisabledToolNames},
        );

    if (resumedConversation != null) {
      return;
    }
    if (command == CavernoCliCommand.chat) {
      conversations.activateWorkspace(workspaceMode: WorkspaceMode.chat);
      return;
    }

    final projectPath = await _canonicalProjectPath(invocation.projectPath!);
    final project = await container
        .read(codingProjectsNotifierProvider.notifier)
        .ensureTerminalProject(projectPath);
    conversations.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
    );
    if (command == CavernoCliCommand.plan) {
      await conversations.enterPlanningSession();
    } else {
      await conversations.exitPlanningSession();
    }
  }

  Future<Conversation> _prepareResumedConversation(
    CavernoCliInvocation invocation,
    ConversationsNotifier conversations,
  ) async {
    final conversationId = invocation.conversationId?.trim() ?? '';
    final conversation = container
        .read(conversationsNotifierProvider)
        .conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      throw CavernoCliFailure(
        code: 'conversation_not_found',
        message: 'Conversation not found: $conversationId',
        exitCode: CavernoCliExitCode.input,
      );
    }
    if (!conversation.workspaceMode.usesConversations) {
      throw CavernoCliFailure(
        code: 'conversation_not_resumable',
        message: 'Conversation $conversationId cannot be resumed.',
        exitCode: CavernoCliExitCode.input,
      );
    }

    if (conversation.workspaceMode == WorkspaceMode.coding) {
      final projectId = conversation.normalizedProjectId;
      final projectsState = container.read(codingProjectsNotifierProvider);
      final project = projectsState.findById(projectId);
      if (project == null || project.normalizedRootPath.isEmpty) {
        throw CavernoCliFailure(
          code: 'conversation_project_unavailable',
          message:
              'The saved coding project for conversation $conversationId is unavailable.',
          exitCode: CavernoCliExitCode.input,
        );
      }
      await _requireSavedDirectory(
        project.normalizedRootPath,
        code: 'conversation_project_unavailable',
        label: 'project',
        conversationId: conversationId,
      );
      final worktreePath = conversation.normalizedWorktreePath;
      if (worktreePath.isNotEmpty) {
        await _requireSavedDirectory(
          worktreePath,
          code: 'conversation_worktree_unavailable',
          label: 'worktree',
          conversationId: conversationId,
        );
      }
      final projects = container.read(codingProjectsNotifierProvider.notifier);
      if (!await projects.ensureProjectAccess(project.id)) {
        throw CavernoCliFailure(
          code: 'conversation_project_access_denied',
          message:
              'Access to the saved coding project for conversation $conversationId could not be restored.',
          exitCode: CavernoCliExitCode.input,
        );
      }
      projects.selectProject(project.id);
    }

    conversations.selectConversation(conversation.id);
    return conversation;
  }

  AssistantMode _assistantModeForConversation(Conversation conversation) {
    if (conversation.workspaceMode != WorkspaceMode.coding) {
      return AssistantMode.general;
    }
    return conversation.isPlanningSession
        ? AssistantMode.plan
        : AssistantMode.coding;
  }

  Future<void> _requireSavedDirectory(
    String value, {
    required String code,
    required String label,
    required String conversationId,
  }) async {
    final normalized = value.trim();
    if (!Directory(normalized).isAbsolute ||
        !await Directory(normalized).exists()) {
      throw CavernoCliFailure(
        code: code,
        message:
            'The saved $label for conversation $conversationId is unavailable: $normalized',
        exitCode: CavernoCliExitCode.input,
      );
    }
  }

  @override
  Future<void> start({
    required CavernoCliInvocation invocation,
    required String prompt,
  }) {
    return _chatNotifier.sendMessage(prompt, languageCode: 'en');
  }

  @override
  Future<void> resolveApproval({
    required String id,
    required bool approved,
  }) async {
    final state = _chatState;
    final notifier = _chatNotifier;
    if (state.pendingLocalCommand?.id == id) {
      notifier.resolveLocalCommand(
        id: id,
        approval: LocalCommandApproval(approved: approved),
      );
    } else if (state.pendingGitCommand?.id == id) {
      notifier.resolveGitCommand(id: id, approved: approved);
    } else if (state.pendingFileOperation?.id == id) {
      notifier.resolveFileOperation(id: id, approved: approved);
    } else if (state.pendingBrowserAction?.id == id) {
      notifier.resolveBrowserAction(id: id, approved: approved);
    } else if (state.pendingSshCommand?.id == id) {
      notifier.resolveSshCommand(id: id, approved: approved);
    } else if (state.pendingBleConnect?.id == id) {
      notifier.resolveBleConnect(id: id, approved: approved);
    } else if (state.pendingSerialOpen?.id == id) {
      notifier.resolveSerialOpen(id: id, approved: approved);
    } else if (state.pendingParticipantToolApproval?.id == id) {
      notifier.resolveParticipantToolApproval(id: id, approved: approved);
    } else if (state.pendingComputerUseAction?.id == id) {
      notifier.resolveComputerUseAction(id: id, approved: false, armed: false);
    } else if (state.pendingSshConnect?.id == id) {
      notifier.resolveSshConnect(id: id);
    }
  }

  @override
  Future<void> resolveQuestion({required String id, String? answer}) async {
    final state = _chatState;
    final notifier = _chatNotifier;
    final pendingQuestion = state.pendingAskUserQuestion;
    if (pendingQuestion?.id == id) {
      notifier.resolveAskUserQuestion(
        id: id,
        answer: _askUserQuestionAnswer(pendingQuestion!, answer),
      );
      return;
    }

    final pendingDecision = state.pendingWorkflowDecision;
    if (pendingDecision?.id == id) {
      notifier.resolveWorkflowDecision(
        id: id,
        answer: _workflowDecisionAnswer(pendingDecision!, answer),
      );
    }
  }

  @override
  Future<void> terminate({
    required String code,
    required String message,
    required int exitCode,
  }) async {
    _chatNotifier.cancelStreaming();
    _runtime.terminateActiveTurns(
      code: code,
      message: message,
      exitCode: exitCode,
    );
  }

  @override
  Future<void> cancel() {
    return terminate(
      code: 'cancelled',
      message: 'Execution was cancelled by the user.',
      exitCode: CavernoCliExitCode.cancelled,
    );
  }

  @override
  Future<void> close() async {
    await _resolvedChatNotifier?.flushPendingPersistence();
    await _resolvedRuntime?.close();
  }

  void _validateEndpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw CavernoCliFailure(
        code: 'invalid_base_url',
        message: 'The effective base URL is invalid: $value',
        exitCode: CavernoCliExitCode.input,
      );
    }
  }

  Future<String> _canonicalProjectPath(String value) async {
    final directory = Directory(value).absolute;
    if (!await directory.exists()) {
      throw CavernoCliFailure(
        code: 'project_not_found',
        message: 'Project directory does not exist: $value',
        exitCode: CavernoCliExitCode.input,
      );
    }
    try {
      return await directory.resolveSymbolicLinks();
    } on FileSystemException {
      return directory.path;
    }
  }

  AskUserQuestionAnswer? _askUserQuestionAnswer(
    PendingAskUserQuestion pending,
    String? rawAnswer,
  ) {
    final normalized = rawAnswer?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    final selected = <AskUserQuestionSelection>[];
    final unmatched = <String>[];
    final tokens = pending.allowMultiple
        ? normalized.split(',').map((token) => token.trim())
        : <String>[normalized];
    for (final token in tokens.where((value) => value.isNotEmpty)) {
      final option = _findQuestionOption(pending.options, token);
      if (option == null) {
        unmatched.add(token);
      } else if (!selected.any((selection) => selection.id == option.id)) {
        selected.add(
          AskUserQuestionSelection(
            id: option.id,
            label: option.label,
            description: option.description,
            preview: option.preview,
          ),
        );
      }
    }
    final otherText = pending.allowOther ? unmatched.join(', ') : '';
    final answer = AskUserQuestionAnswer(
      question: pending.question,
      selectedOptions: selected,
      otherText: otherText,
    );
    return answer.hasAnswer ? answer : null;
  }

  AskUserQuestionOption? _findQuestionOption(
    List<AskUserQuestionOption> options,
    String token,
  ) {
    final index = int.tryParse(token);
    if (index != null && index > 0 && index <= options.length) {
      return options[index - 1];
    }
    final normalized = token.toLowerCase();
    return options
        .where(
          (option) =>
              option.id.toLowerCase() == normalized ||
              option.label.toLowerCase() == normalized,
        )
        .firstOrNull;
  }

  WorkflowPlanningDecisionAnswer? _workflowDecisionAnswer(
    PendingWorkflowDecision pending,
    String? rawAnswer,
  ) {
    final token = rawAnswer?.trim() ?? '';
    if (token.isEmpty) {
      return null;
    }
    final options = pending.decision.options;
    final index = int.tryParse(token);
    final option = index != null && index > 0 && index <= options.length
        ? options[index - 1]
        : options
              .where(
                (item) =>
                    item.id.toLowerCase() == token.toLowerCase() ||
                    item.label.toLowerCase() == token.toLowerCase(),
              )
              .firstOrNull;
    if (option == null) {
      return null;
    }
    return WorkflowPlanningDecisionAnswer(
      decisionId: pending.decision.id,
      question: pending.decision.question,
      optionId: option.id,
      optionLabel: option.label,
    );
  }
}
