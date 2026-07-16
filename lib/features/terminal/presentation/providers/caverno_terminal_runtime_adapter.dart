import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../chat/application/runtime/caverno_execution_runtime.dart';
import '../../../chat/application/runtime/caverno_runtime_event.dart';
import '../../../chat/presentation/providers/caverno_execution_runtime_provider.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/chat_state.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../application/caverno_cli_arguments.dart';
import '../../application/caverno_cli_contract.dart';
import '../../application/caverno_cli_runtime_port.dart';

final class CavernoTerminalRuntimeAdapter implements CavernoCliRuntimePort {
  CavernoTerminalRuntimeAdapter({
    required this.container,
    Map<String, String>? environment,
  }) : environment = environment ?? Platform.environment;

  final ProviderContainer container;
  final Map<String, String> environment;

  CavernoExecutionRuntime get _runtime =>
      container.read(cavernoExecutionRuntimeProvider);

  @override
  Stream<CavernoRuntimeEvent> get events => _runtime.events;

  @override
  Future<void> prepare(CavernoCliInvocation invocation) async {
    final command = invocation.command;
    if (command == null) {
      throw const CavernoCliFailure(
        code: 'command_required',
        message: 'A runnable CLI command is required.',
        exitCode: CavernoCliExitCode.usage,
      );
    }

    final currentSettings = container.read(settingsNotifierProvider);
    final baseUrl = _firstNonEmpty(<String?>[
      invocation.baseUrl,
      environment['CAVERNO_LLM_BASE_URL'],
      currentSettings.baseUrl,
    ]);
    final model = _firstNonEmpty(<String?>[
      invocation.model,
      environment['CAVERNO_LLM_MODEL'],
      currentSettings.model,
    ]);
    final apiKey = _firstNonEmpty(<String?>[
      invocation.apiKey,
      environment['CAVERNO_LLM_API_KEY'],
      currentSettings.apiKey,
    ]);
    _validateEndpoint(baseUrl);
    if (model.isEmpty) {
      throw const CavernoCliFailure(
        code: 'model_required',
        message: 'The effective model is empty.',
        exitCode: CavernoCliExitCode.input,
      );
    }

    final assistantMode = switch (command) {
      CavernoCliCommand.chat => AssistantMode.general,
      CavernoCliCommand.coding => AssistantMode.coding,
      CavernoCliCommand.plan => AssistantMode.plan,
    };
    container
        .read(settingsNotifierProvider.notifier)
        .applyTransientRuntimeOverrides(
          assistantMode: assistantMode,
          baseUrl: baseUrl,
          model: model,
          apiKey: apiKey,
          disabledBuiltInTools: MacosComputerUseToolPolicy.allToolNames,
        );

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    if (command == CavernoCliCommand.chat) {
      conversations.activateWorkspace(workspaceMode: WorkspaceMode.chat);
      return;
    }

    final projectPath = await _canonicalProjectPath(invocation.projectPath!);
    final project = container
        .read(codingProjectsNotifierProvider.notifier)
        .useTransientProject(projectPath);
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

  @override
  Future<void> start({
    required CavernoCliInvocation invocation,
    required String prompt,
  }) {
    return container
        .read(chatNotifierProvider.notifier)
        .sendMessage(prompt, languageCode: 'en');
  }

  @override
  Future<void> resolveApproval({
    required String id,
    required bool approved,
  }) async {
    final state = container.read(chatNotifierProvider);
    final notifier = container.read(chatNotifierProvider.notifier);
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
    final state = container.read(chatNotifierProvider);
    final notifier = container.read(chatNotifierProvider.notifier);
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
    container.read(chatNotifierProvider.notifier).cancelStreaming();
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
    await container
        .read(chatNotifierProvider.notifier)
        .flushPendingPersistence();
    await _runtime.close();
  }

  String _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      final value = candidate?.trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
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
