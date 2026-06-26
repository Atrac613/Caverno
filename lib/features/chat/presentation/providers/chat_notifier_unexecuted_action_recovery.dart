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

  ToolResultInfo? _buildUnverifiedReadOnlyInspectionClaimToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final candidate = candidateResponse.trim();
    if (!_looksLikeCompletedReadOnlyInspectionClaim(candidate) ||
        _hasSuccessfulReadOnlyInspectionResult(toolResults)) {
      return null;
    }

    return ToolResultInfo(
      id: 'unverified_read_only_inspection_claim_${DateTime.now().microsecondsSinceEpoch}',
      name: 'read_file',
      arguments: {
        'reason':
            'The assistant claimed local file or project state was inspected, but no successful read-only inspection tool result is available for that claim.',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'unverified_read_only_inspection_claim',
        'error':
            'The local file or project state claim is unverified. No successful read_file, inspect_file, list_directory, find_files, search_files, or read-only local_execute_command result is available for the claimed inspection.',
        'claimedResponse': _clipForDiagnostic(candidate),
      }),
    );
  }

  /// Test-only seam for characterizing the unverified-read-only-inspection
  /// guard deterministically (does a given claim + tool-result set fire it?).
  @visibleForTesting
  ToolResultInfo? buildUnverifiedReadOnlyInspectionClaimToolResultForTest({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    return _buildUnverifiedReadOnlyInspectionClaimToolResult(
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
  }

  /// Test-only seam: does the response read as a completed read-only inspection
  /// claim (the first half of the guard trigger)?
  @visibleForTesting
  bool looksLikeCompletedReadOnlyInspectionClaimForTest(String content) {
    return _looksLikeCompletedReadOnlyInspectionClaim(content);
  }

  /// Test-only seam: do the tool results count as a successful read-only
  /// inspection (the second half — a `false` here is what makes the guard fire)?
  @visibleForTesting
  bool hasSuccessfulReadOnlyInspectionResultForTest(
    List<ToolResultInfo> toolResults,
  ) {
    return _hasSuccessfulReadOnlyInspectionResult(toolResults);
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

  bool _hasSuccessfulReadOnlyInspectionResult(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults.any((toolResult) {
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (const {
        'read_file',
        'inspect_file',
        'list_directory',
        'find_files',
        'search_files',
      }.contains(normalizedName)) {
        return _toolResultLooksSuccessfulForFinalAnswer(toolResult.result);
      }
      // Any successful command execution (local/git/ssh/run_tests) is real
      // system interaction that backs a project/repo-state inspection claim.
      // Previously only `local_execute_command` was accepted here, so a claim
      // verified via `git_execute_command` (a read-only repo inspection, proven
      // by the regression test) was wrongly flagged as unverified. Use the
      // canonical command-tool set so the inspection whitelist no longer drifts
      // from `_isCommandExecutionTool`. `process_*` carry no successful exit
      // code, so they fall through naturally.
      if (_isCommandExecutionTool(normalizedName)) {
        return _toolResultHasSuccessfulExit(toolResult);
      }
      return false;
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

  bool _looksLikeCompletedReadOnlyInspectionClaim(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.length > 1800) {
      return false;
    }
    final normalized = trimmed.toLowerCase();
    if (_containsAny(normalized, const [
          'not found',
          'not exist',
          'does not exist',
          'do not exist',
          'not checked',
          'not inspected',
          'not verified',
          'unverified',
          'not executed',
          'could not verify',
        ]) ||
        _containsAnyCodeUnitSequence(trimmed, const [
          [0x672a, 0x691c, 0x8a3c],
          [0x672a, 0x78ba, 0x8a8d],
          [0x672a, 0x5b9f, 0x884c],
          [0x898b, 0x3064, 0x304b, 0x308a, 0x307e, 0x305b, 0x3093],
        ])) {
      return false;
    }

    return _hasReadOnlyInspectionTargetMarker(normalized, trimmed) &&
        _hasCompletedReadOnlyInspectionMarker(normalized, trimmed);
  }

  bool _hasReadOnlyInspectionTargetMarker(String normalized, String original) {
    final hasEnglishTarget = _containsAny(normalized, const [
      'file',
      'directory',
      'folder',
      'path',
      'project',
      'workspace',
      'source',
      'repo',
      'repository',
      'pubspec',
      '.dart',
      '.yaml',
      '.yml',
      '.json',
      '.jsonl',
      '.md',
      '.plist',
      '/',
      '\\',
      '`',
    ]);
    if (hasEnglishTarget) {
      return true;
    }
    return _containsAnyCodeUnitSequence(original, const [
      [0x30d5, 0x30a1, 0x30a4, 0x30eb],
      [0x30c7, 0x30a3, 0x30ec, 0x30af, 0x30c8, 0x30ea],
      [0x30d5, 0x30a9, 0x30eb, 0x30c0],
      [0x30d1, 0x30b9],
      [0x30d7, 0x30ed, 0x30b8, 0x30a7, 0x30af, 0x30c8],
      [0x30ea, 0x30dd, 0x30b8, 0x30c8, 0x30ea],
      [0x5b58, 0x5728],
      [0x5185, 0x5bb9],
    ]);
  }

  bool _hasCompletedReadOnlyInspectionMarker(
    String normalized,
    String original,
  ) {
    final hasEnglishClaim = _containsAny(normalized, const [
      'confirmed',
      'verified',
      'found',
      'exists',
      'exist',
      'is present',
      'are present',
      'i checked',
      'i inspected',
      'i read',
      'the file contains',
      'the directory contains',
      'the path exists',
    ]);
    if (hasEnglishClaim) {
      return true;
    }
    return _containsAnyCodeUnitSequence(original, const [
      [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3057, 0x305f],
      [0x691c, 0x8a3c, 0x3057, 0x307e, 0x3057, 0x305f],
      [0x8abf, 0x3079, 0x307e, 0x3057, 0x305f],
      [0x8aad, 0x307f, 0x307e, 0x3057, 0x305f],
      [0x898b, 0x3064, 0x3051, 0x307e, 0x3057, 0x305f],
      [0x5b58, 0x5728, 0x3059, 0x308b],
      [0x542b, 0x307e, 0x308c, 0x3066, 0x3044, 0x307e, 0x3059],
    ]);
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
