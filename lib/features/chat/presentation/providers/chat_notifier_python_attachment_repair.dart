// Same-library extension on [ChatNotifier]: orchestration adapters for skipped
// Python attachment analysis and Python attachment path failure recovery.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierPythonAttachmentRepair on ChatNotifier {
  Future<ChatCompletionResult?> _requestSkippedPythonAttachmentAnalysisRepair({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) async {
    final repairInput = _pythonAttachmentRepairInput(
      candidateResponse: candidateResponse,
      toolResults: executedToolResults,
      tools: tools,
      interactionGeneration: interactionGeneration,
    );
    if (repairInput == null ||
        !const PythonAttachmentRepairPolicy()
            .shouldRepairSkippedPythonAttachmentAnalysis(repairInput)) {
      return null;
    }

    appLog('[Tool] Requesting run_python_script repair for attached file');
    List<Message> buildRepairMessages(bool forceCompaction) {
      final messages = _prepareMessagesForLLM(
        forceCompaction: forceCompaction,
        toolDefinitionsOverride: tools,
        interactionGeneration: interactionGeneration,
      );
      messages.add(
        Message(
          id: 'python_attachment_repair_${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.user,
          content:
              PythonAttachmentRepairPolicy.buildSkippedPythonAttachmentAnalysisRepairPrompt(),
          timestamp: DateTime.now(),
        ),
      );
      return messages;
    }

    return _createToolResultCompletionWithContextRetry(
      logLabel: 'python attachment analysis repair',
      interactionGeneration: interactionGeneration,
      buildMessages: buildRepairMessages,
      toolResults: batchToolResults,
      assistantContent: candidateResponse.isNotEmpty ? candidateResponse : null,
      tools: tools,
    );
  }

  PythonAttachmentRepairInput? _pythonAttachmentRepairInput({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) {
    final ownerSnapshot = _turnOwnerSnapshotForGeneration(
      interactionGeneration,
    );
    if (ownerSnapshot == null) return null;
    final availableToolNames =
        ToolDefinitionSearchService.toolNamesFromDefinitions(tools).toSet();
    final hasPythonAttachment = ownerSnapshot.messages.any(
      (message) =>
          message.role == MessageRole.user &&
          ((message.originalImagePath?.isNotEmpty ?? false) ||
              (message.imageBase64?.isNotEmpty ?? false)),
    );
    return PythonAttachmentRepairInput(
      candidateResponse: candidateResponse,
      executedResults: toolResults,
      availableToolNames: availableToolNames,
      runPythonScriptDisabled: _settings.disabledBuiltInToolsSet.contains(
        'run_python_script',
      ),
      hasPythonAttachment: hasPythonAttachment,
      owningTurnLatestUserText: ownerSnapshot.latestUserContent,
    );
  }

  Future<ChatCompletionResult?> _requestPythonAttachmentPathFailureRepair({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) async {
    final repairInput = _pythonAttachmentRepairInput(
      candidateResponse: candidateResponse,
      toolResults: executedToolResults,
      tools: tools,
      interactionGeneration: interactionGeneration,
    );
    if (repairInput == null ||
        !const PythonAttachmentRepairPolicy()
            .shouldRepairPythonAttachmentPathFailure(repairInput)) {
      return null;
    }

    appLog('[Tool] Requesting run_python_script repair for missing file path');
    List<Message> buildRepairMessages(bool forceCompaction) {
      final messages = _prepareMessagesForLLM(
        forceCompaction: forceCompaction,
        toolDefinitionsOverride: tools,
        interactionGeneration: interactionGeneration,
      );
      messages.add(
        Message(
          id: 'python_attachment_path_repair_${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.user,
          content:
              PythonAttachmentRepairPolicy.buildPythonAttachmentPathFailureRepairPrompt(),
          timestamp: DateTime.now(),
        ),
      );
      return messages;
    }

    return _createToolResultCompletionWithContextRetry(
      logLabel: 'python attachment path repair',
      interactionGeneration: interactionGeneration,
      buildMessages: buildRepairMessages,
      toolResults: batchToolResults,
      assistantContent: candidateResponse.isNotEmpty ? candidateResponse : null,
      tools: tools,
    );
  }

  @visibleForTesting
  bool shouldRepairSkippedPythonAttachmentAnalysisForOwnerForTest({
    required String ownerConversationId,
    required List<Message> ownerMessages,
    required String candidateResponse,
    List<ToolResultInfo> executedToolResults = const <ToolResultInfo>[],
    required List<Map<String, dynamic>> tools,
  }) {
    final interactionGeneration = _beginInteractionGeneration();
    _trackActiveResponse(
      interactionGeneration,
      ownerConversationId,
      ownerMessages: ownerMessages,
    );
    try {
      final repairInput = _pythonAttachmentRepairInput(
        candidateResponse: candidateResponse,
        toolResults: executedToolResults,
        tools: tools,
        interactionGeneration: interactionGeneration,
      );
      return repairInput != null &&
          const PythonAttachmentRepairPolicy()
              .shouldRepairSkippedPythonAttachmentAnalysis(repairInput);
    } finally {
      _clearActiveResponseForGeneration(interactionGeneration);
    }
  }
}
