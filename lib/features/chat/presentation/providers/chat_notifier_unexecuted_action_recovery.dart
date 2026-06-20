// Same-library extension on [ChatNotifier]: detection and synthetic tool
// results for actions the model described but did not execute (skipped browser
// action, unexecuted file side-effect / command), plus the request detectors.
// Pure relocation from chat_notifier.dart (F5), no behavior change.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierUnexecutedActionRecovery on ChatNotifier {
  ToolResultInfo? _buildUnexecutedSkippedBrowserActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required int interactionGeneration,
  }) {
    if (!_hasRecoveredBrowserSnapshot(batchToolResults)) {
      return null;
    }
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    if (!_looksLikeBrowserActionRequest(latestUserContent)) {
      return null;
    }
    final missingToolName = _browserActionToolNameForText(latestUserContent);
    return ToolResultInfo(
      id: 'unexecuted_browser_action_${DateTime.now().microsecondsSinceEpoch}',
      name: missingToolName,
      arguments: {
        'reason':
            'The model returned prose after a recovered browser_snapshot instead of issuing the required browser action tool call.',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'unexecuted_browser_action',
        'error':
            'The requested browser action was not executed. A recovered browser_snapshot ran, but no follow-up browser action tool call was issued.',
        'claimedResponse': _clipForDiagnostic(candidateResponse),
      }),
    );
  }

  ToolResultInfo? _buildUnexecutedFileSideEffectToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) {
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    if (!_looksLikeFileSideEffectRequest(latestUserContent) ||
        _hasSuccessfulFileSideEffectResult(toolResults)) {
      return null;
    }

    final missingToolName = _fileSideEffectToolNameForResults(toolResults);
    return ToolResultInfo(
      id: 'unexecuted_file_save_${DateTime.now().microsecondsSinceEpoch}',
      name: missingToolName,
      arguments: {
        'reason':
            'The latest user request required a file save or file mutation, but no successful file-operation tool result is available.',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'unexecuted_file_save',
        'error':
            'The requested file save or file mutation was not executed. No successful browser_save_data, write_file, edit_file, rollback_last_file_change, or explicit file-operation tool result is available.',
        'missing_tool': missingToolName,
        'claimedResponse': _clipForDiagnostic(candidateResponse),
      }),
    );
  }

  ToolResultInfo? _buildUnexecutedCommandActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) {
    final candidate = candidateResponse.trim();
    final looksLikeFutureAction = _looksLikeFutureCommandExecutionAction(
      candidate,
    );
    final looksLikeCompletionClaim = _looksLikeCompletedCommandExecutionClaim(
      candidate,
    );
    if (!looksLikeFutureAction && !looksLikeCompletionClaim) {
      return null;
    }
    if (!looksLikeFutureAction &&
        _hasSuccessfulCommandExecutionResult(toolResults)) {
      return null;
    }

    return ToolResultInfo(
      id: 'unexecuted_command_action_${DateTime.now().microsecondsSinceEpoch}',
      name: 'local_execute_command',
      arguments: {
        'reason':
            'The assistant said it would run a local command, but no matching successful command-execution tool result is available for the claimed action.',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'unexecuted_command_action',
        'error':
            'The requested command was not executed. No matching successful local_execute_command, process_start, process_status, process_wait, run_tests, git_execute_command, or ssh_execute_command tool result is available for the claimed action.',
        'claimedResponse': _clipForDiagnostic(candidate),
      }),
    );
  }

  bool _looksLikeFileSideEffectRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (_containsAny(normalized, const [
      'save',
      'save as',
      'download',
      'export',
      'write file',
      'write a file',
      'write to file',
      'create file',
      'create a file',
      'make file',
      'make a file',
      'as markdown',
      'markdown file',
      'to markdown',
      'file name',
      'filename',
      'local file',
    ])) {
      return true;
    }
    return _containsAnyCodeUnitSequence(text, const [
      [0x4fdd, 0x5b58],
      [0x4f5c, 0x6210],
      [0x66f8, 0x304d, 0x8fbc],
      [0x30c0, 0x30a6, 0x30f3, 0x30ed, 0x30fc, 0x30c9],
    ]);
  }

  bool _hasSuccessfulFileSideEffectResult(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (normalizedName == 'browser_save_data') {
        return _toolResultLooksSuccessfulForFinalAnswer(toolResult.result);
      }
      return _isFileMutationToolName(normalizedName) &&
          _isSuccessfulFileMutationToolResult(toolResult);
    });
  }

  String _fileSideEffectToolNameForResults(List<ToolResultInfo> toolResults) {
    final sawBrowserContext = toolResults.any(
      (toolResult) =>
          toolResult.name.trim().toLowerCase().startsWith('browser_'),
    );
    return sawBrowserContext ? 'browser_save_data' : 'write_file';
  }

  String _clipForDiagnostic(String value, {int maxLength = 240}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  Set<String> _browserToolNamesFromDefinitions(
    List<Map<String, dynamic>> toolDefinitions,
  ) {
    return ToolDefinitionSearchService.toolNamesFromDefinitions(
      toolDefinitions,
    ).where((toolName) => toolName.startsWith('browser_')).toSet();
  }

  bool _looksLikeBrowserActionRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (_containsAny(normalized, const [
      'click',
      'press',
      'tap',
      'open',
      'navigate',
      'go to',
      'follow',
      'type',
      'fill',
      'input',
      'enter',
      'submit',
      'search',
    ])) {
      return true;
    }
    return _containsBrowserActionCodeUnitMarker(text);
  }

  bool _containsBrowserActionCodeUnitMarker(String text) {
    const markers = [
      [0x30af, 0x30ea, 0x30c3, 0x30af],
      [0x30bf, 0x30c3, 0x30d7],
      [0x62bc],
      [0x958b, 0x304f],
      [0x958b, 0x3044, 0x3066],
      [0x958b, 0x3051],
      [0x958b, 0x304d],
      [0x9077, 0x79fb],
      [0x79fb, 0x52d5],
      [0x5165, 0x529b],
      [0x9001, 0x4fe1],
      [0x691c, 0x7d22],
    ];
    return markers.any((marker) => _containsCodeUnitSequence(text, marker));
  }

  String _browserActionToolNameForText(String text) {
    final normalized = text.trim().toLowerCase();
    if (_containsAny(normalized, const ['click', 'press', 'tap', 'follow']) ||
        _containsAnyCodeUnitSequence(text, const [
          [0x30af, 0x30ea, 0x30c3, 0x30af],
          [0x30bf, 0x30c3, 0x30d7],
          [0x62bc],
        ])) {
      return 'browser_click';
    }
    if (_containsAny(normalized, const ['type', 'fill', 'input', 'enter']) ||
        _containsAnyCodeUnitSequence(text, const [
          [0x5165, 0x529b],
        ])) {
      return 'browser_fill';
    }
    if (_containsAny(normalized, const ['submit', 'search']) ||
        _containsAnyCodeUnitSequence(text, const [
          [0x9001, 0x4fe1],
          [0x691c, 0x7d22],
        ])) {
      return 'browser_submit';
    }
    if (_containsAny(normalized, const ['open', 'navigate', 'go to']) ||
        _containsAnyCodeUnitSequence(text, const [
          [0x958b, 0x304f],
          [0x958b, 0x3044, 0x3066],
          [0x958b, 0x3051],
          [0x958b, 0x304d],
          [0x9077, 0x79fb],
          [0x79fb, 0x52d5],
        ])) {
      return 'browser_open';
    }
    return 'browser_click';
  }
}
