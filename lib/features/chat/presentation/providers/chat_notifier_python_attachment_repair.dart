// Same-library extension on [ChatNotifier]: recovery for skipped Python
// attachment analysis and Python attachment path failures (re-prompt builders
// and their detectors). Pure relocation from chat_notifier.dart (F5), no
// behavior change.
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
    if (!_shouldRepairSkippedPythonAttachmentAnalysis(
      candidateResponse: candidateResponse,
      toolResults: executedToolResults,
      tools: tools,
      interactionGeneration: interactionGeneration,
    )) {
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
          content: _buildSkippedPythonAttachmentAnalysisRepairPrompt(),
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

  bool _shouldRepairSkippedPythonAttachmentAnalysis({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) {
    if (candidateResponse.trim().isEmpty) {
      return false;
    }
    if (_settings.disabledBuiltInToolsSet.contains('run_python_script')) {
      return false;
    }
    if (_latestPythonInputMessage() == null) {
      return false;
    }
    final availableToolNames =
        ToolDefinitionSearchService.toolNamesFromDefinitions(tools).toSet();
    if (!availableToolNames.contains('run_python_script')) {
      return false;
    }
    if (_hasRunPythonScriptToolResult(toolResults)) {
      return false;
    }
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    return _looksLikePythonAttachmentAnalysisRequest(latestUserContent);
  }

  bool _hasRunPythonScriptToolResult(List<ToolResultInfo> toolResults) {
    return toolResults.any(
      (toolResult) =>
          toolResult.name.trim().toLowerCase() == 'run_python_script',
    );
  }

  bool _looksLikePythonAttachmentAnalysisRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final mentionsPythonTool = _containsAny(normalized, const [
      'run_python_script',
      'python',
    ]);
    final mentionsAnalysis = _containsAny(normalized, const [
      'metadata',
      'exif',
      'analyze',
      'analyse',
      'analysis',
      'inspect',
      'parse',
    ]);
    return mentionsPythonTool &&
        (mentionsAnalysis || _containsCjkAnalysisMarker(text));
  }

  bool _containsCjkAnalysisMarker(String value) {
    final analysisMarkers = [
      String.fromCharCodes([0x30e1, 0x30bf, 0x30c7, 0x30fc, 0x30bf]),
      String.fromCharCodes([0x89e3, 0x6790]),
      String.fromCharCodes([0x753b, 0x50cf]),
      String.fromCharCodes([0x5199, 0x771f]),
      String.fromCharCodes([0x6dfb, 0x4ed8]),
    ];
    return analysisMarkers.any(value.contains);
  }

  String _buildSkippedPythonAttachmentAnalysisRepairPrompt() {
    return [
      'The latest user request requires run_python_script to inspect an attached file.',
      'A file is already staged for run_python_script as caverno.inputs[0].',
      'Do not answer in prose that analysis will happen, and do not claim the attachment is missing.',
      'Call run_python_script now with a complete Python script in the code argument.',
      'The script should read caverno.inputs[0], print concise metadata findings, and use only the standard library plus piexif when useful.',
      'For image metadata, start with `path = caverno.inputs[0].path` and `piexif.load(path)`.',
      'When naming EXIF tags, use `piexif.TAGS[ifd][tag].get(\'name\', str(tag))`; TAGS entries are maps.',
    ].join('\n');
  }

  Future<ChatCompletionResult?> _requestPythonAttachmentPathFailureRepair({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) async {
    if (!_shouldRepairPythonAttachmentPathFailure(
      candidateResponse: candidateResponse,
      toolResults: executedToolResults,
      tools: tools,
      interactionGeneration: interactionGeneration,
    )) {
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
          content: _buildPythonAttachmentPathFailureRepairPrompt(),
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

  bool _shouldRepairPythonAttachmentPathFailure({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) {
    if (candidateResponse.trim().isEmpty) {
      return false;
    }
    if (_settings.disabledBuiltInToolsSet.contains('run_python_script')) {
      return false;
    }
    if (_latestPythonInputMessage() == null) {
      return false;
    }
    final availableToolNames =
        ToolDefinitionSearchService.toolNamesFromDefinitions(tools).toSet();
    if (!availableToolNames.contains('run_python_script')) {
      return false;
    }
    if (!_hasRunPythonScriptPathFailure(toolResults)) {
      return false;
    }
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    return _looksLikePythonAttachmentAnalysisRequest(latestUserContent);
  }

  bool _hasRunPythonScriptPathFailure(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      if (toolResult.name.trim().toLowerCase() != 'run_python_script') {
        return false;
      }
      final normalized = toolResult.result.toLowerCase();
      return _containsAny(normalized, const [
        'filenotfounderror',
        'no such file or directory',
        'file not found',
      ]);
    });
  }

  String _buildPythonAttachmentPathFailureRepairPrompt() {
    return [
      'The previous run_python_script call failed because it opened a guessed file path such as test.jpg.',
      'The latest user request still has an attached file staged for run_python_script as caverno.inputs[0].',
      'Do not ask the user to reattach the file or provide a path.',
      'Call run_python_script again with a complete Python script that reads caverno.inputs[0].path or caverno.inputs[0].read_bytes().',
      'Do not open literal paths such as test.jpg, attachment_0.jpg, or any guessed relative path.',
      'For image metadata, prefer `path = caverno.inputs[0].path` followed by `piexif.load(path)`.',
      'When naming EXIF tags, use `piexif.TAGS[ifd][tag].get(\'name\', str(tag))`; TAGS entries are maps.',
      'Print concise metadata findings from the staged attachment.',
    ].join('\n');
  }
}
