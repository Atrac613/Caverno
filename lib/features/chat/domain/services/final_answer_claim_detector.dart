import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'tool_call_execution_policy.dart';
import 'tool_definition_search_service.dart';

class FinalAnswerClaimDetector {
  const FinalAnswerClaimDetector({
    this.toolCallExecutionPolicy = const ToolCallExecutionPolicy(),
  });

  final ToolCallExecutionPolicy toolCallExecutionPolicy;

  static const unexecutedFileSideEffectNotice =
      'The requested file save was not executed because no successful file-operation tool result is available. '
      'Treat any save, create, or download claim above as unverified.';

  static const unexecutedCommandActionNotice =
      'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action. '
      'Treat any run, dry-run, test, validation, or command execution claim above as unverified.';

  static const unverifiedReadOnlyInspectionNotice =
      'The local file or project state claim above is unverified because no successful read-only inspection tool result is available for that claim. '
      'Treat any file existence, file content, directory listing, or path verification claim above as unverified.';

  ToolResultInfo? buildUnexecutedSkippedBrowserActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required String latestUserContent,
  }) {
    if (!hasRecoveredBrowserSnapshot(batchToolResults)) {
      return null;
    }
    if (!looksLikeBrowserActionRequest(latestUserContent)) {
      return null;
    }
    final missingToolName = browserActionToolNameForText(latestUserContent);
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
        'claimedResponse': clipForDiagnostic(candidateResponse),
      }),
    );
  }

  ToolResultInfo? buildUnexecutedFileSideEffectToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required String latestUserContent,
  }) {
    if (!looksLikeFileSideEffectRequest(latestUserContent) ||
        hasSuccessfulFileSideEffectResult(toolResults)) {
      return null;
    }

    final missingToolName = fileSideEffectToolNameForResults(toolResults);
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
        'claimedResponse': clipForDiagnostic(candidateResponse),
      }),
    );
  }

  ToolResultInfo? buildUnexecutedCommandActionToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final candidate = candidateResponse.trim();
    final looksLikeFutureAction = looksLikeFutureCommandExecutionAction(
      candidate,
    );
    final looksLikeCompletionClaim = looksLikeCompletedCommandExecutionClaim(
      candidate,
    );
    if (!looksLikeFutureAction && !looksLikeCompletionClaim) {
      return null;
    }
    if (!looksLikeFutureAction &&
        hasSuccessfulCommandExecutionResult(toolResults)) {
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
        'claimedResponse': clipForDiagnostic(candidate),
      }),
    );
  }

  ToolResultInfo? buildUnverifiedReadOnlyInspectionClaimToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final candidate = candidateResponse.trim();
    if (!looksLikeCompletedReadOnlyInspectionClaim(candidate) ||
        hasSuccessfulReadOnlyInspectionResult(toolResults)) {
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
        'claimedResponse': clipForDiagnostic(candidate),
      }),
    );
  }

  Set<String> browserToolNamesFromDefinitions(
    List<Map<String, dynamic>> toolDefinitions,
  ) {
    return ToolDefinitionSearchService.toolNamesFromDefinitions(
      toolDefinitions,
    ).where((toolName) => toolName.startsWith('browser_')).toSet();
  }

  bool hasRecoveredBrowserSnapshot(List<ToolResultInfo> toolResults) {
    return toolResults.any(
      (toolResult) =>
          toolResult.name == 'browser_snapshot' &&
          toolResult.id.startsWith('recovered_browser_snapshot_'),
    );
  }

  bool looksLikeFileSideEffectRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (containsAny(normalized, const [
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
    return containsAnyCodeUnitSequence(text, const [
      [0x4fdd, 0x5b58],
      [0x4f5c, 0x6210],
      [0x66f8, 0x304d, 0x8fbc],
      [0x30c0, 0x30a6, 0x30f3, 0x30ed, 0x30fc, 0x30c9],
    ]);
  }

  bool hasSuccessfulFileSideEffectResult(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (normalizedName == 'browser_save_data') {
        return toolResultLooksSuccessfulForFinalAnswer(toolResult.result);
      }
      return isFileMutationToolName(normalizedName) &&
          isSuccessfulFileMutationToolResult(toolResult);
    });
  }

  bool hasSuccessfulReadOnlyInspectionResult(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (const {
        'read_file',
        'inspect_file',
        'list_directory',
        'find_files',
        'search_files',
      }.contains(normalizedName)) {
        return toolResultLooksSuccessfulForFinalAnswer(toolResult.result);
      }
      if (toolCallExecutionPolicy.isCommandExecutionTool(normalizedName)) {
        return toolCallExecutionPolicy.toolResultHasSuccessfulExit(toolResult);
      }
      return false;
    });
  }

  String fileSideEffectToolNameForResults(List<ToolResultInfo> toolResults) {
    final sawBrowserContext = toolResults.any(
      (toolResult) =>
          toolResult.name.trim().toLowerCase().startsWith('browser_'),
    );
    return sawBrowserContext ? 'browser_save_data' : 'write_file';
  }

  String clipForDiagnostic(String value, {int maxLength = 240}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  bool looksLikeCompletedReadOnlyInspectionClaim(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty || trimmed.length > 1800) {
      return false;
    }
    final normalized = trimmed.toLowerCase();
    if (containsAny(normalized, const [
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
        containsAnyCodeUnitSequence(trimmed, const [
          [0x672a, 0x691c, 0x8a3c],
          [0x672a, 0x78ba, 0x8a8d],
          [0x672a, 0x5b9f, 0x884c],
          [0x898b, 0x3064, 0x304b, 0x308a, 0x307e, 0x305b, 0x3093],
        ])) {
      return false;
    }

    return hasReadOnlyInspectionTargetMarker(normalized, trimmed) &&
        hasCompletedReadOnlyInspectionMarker(normalized, trimmed);
  }

  bool hasReadOnlyInspectionTargetMarker(String normalized, String original) {
    final hasEnglishTarget = containsAny(normalized, const [
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
    return containsAnyCodeUnitSequence(original, const [
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

  bool hasCompletedReadOnlyInspectionMarker(
    String normalized,
    String original,
  ) {
    final hasEnglishClaim = containsAny(normalized, const [
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
    return containsAnyCodeUnitSequence(original, const [
      [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3057, 0x305f],
      [0x691c, 0x8a3c, 0x3057, 0x307e, 0x3057, 0x305f],
      [0x8abf, 0x3079, 0x307e, 0x3057, 0x305f],
      [0x8aad, 0x307f, 0x307e, 0x3057, 0x305f],
      [0x898b, 0x3064, 0x3051, 0x307e, 0x3057, 0x305f],
      [0x5b58, 0x5728, 0x3059, 0x308b],
      [0x542b, 0x307e, 0x308c, 0x3066, 0x3044, 0x307e, 0x3059],
    ]);
  }

  bool looksLikeBrowserActionRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (containsAny(normalized, const [
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
    return containsBrowserActionCodeUnitMarker(text);
  }

  bool containsBrowserActionCodeUnitMarker(String text) {
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
    return markers.any((marker) => containsCodeUnitSequence(text, marker));
  }

  String browserActionToolNameForText(String text) {
    final normalized = text.trim().toLowerCase();
    if (containsAny(normalized, const ['click', 'press', 'tap', 'follow']) ||
        containsAnyCodeUnitSequence(text, const [
          [0x30af, 0x30ea, 0x30c3, 0x30af],
          [0x30bf, 0x30c3, 0x30d7],
          [0x62bc],
        ])) {
      return 'browser_click';
    }
    if (containsAny(normalized, const ['type', 'fill', 'input', 'enter']) ||
        containsAnyCodeUnitSequence(text, const [
          [0x5165, 0x529b],
        ])) {
      return 'browser_fill';
    }
    if (containsAny(normalized, const ['submit', 'search']) ||
        containsAnyCodeUnitSequence(text, const [
          [0x9001, 0x4fe1],
          [0x691c, 0x7d22],
        ])) {
      return 'browser_submit';
    }
    if (containsAny(normalized, const ['open', 'navigate', 'go to']) ||
        containsAnyCodeUnitSequence(text, const [
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

  String messageContentWithUnexecutedCommandActionNotice(
    String content, {
    String notice = unexecutedCommandActionNotice,
  }) {
    if (content.contains(notice)) {
      return content;
    }
    if (looksLikeUnsupportedCommandExecutionAction(content.trim())) {
      return notice;
    }
    return '${content.trimRight()}\n\n$notice';
  }

  String messageContentWithPrependedClaimCorrectionNotice(
    String content,
    String notice,
  ) {
    if (content.contains(notice)) {
      return content;
    }
    final trimmed = content.trimRight();
    if (trimmed.trim().isEmpty) {
      return notice;
    }
    return '$notice\n\n$trimmed';
  }

  String messageContentWithUnverifiedReadOnlyInspectionNotice(
    String content, {
    String notice = unverifiedReadOnlyInspectionNotice,
  }) {
    if (content.contains(notice)) {
      return content;
    }
    if (looksLikeCompletedReadOnlyInspectionClaim(content.trim())) {
      return notice;
    }
    return '${content.trimRight()}\n\n$notice';
  }

  bool looksLikeUnsupportedFileSideEffectClaim(
    String content, {
    required List<ToolResultInfo> toolResults,
  }) {
    if (!hasUnexecutedFileSideEffectResult(toolResults) ||
        hasSuccessfulFileSideEffectResult(toolResults)) {
      return false;
    }

    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty ||
        containsAny(normalized, const [
          'not saved',
          'not created',
          'not downloaded',
          'not executed',
          'not yet',
          'unexecuted',
          'was not',
          'were not',
          'could not save',
          'could not create',
          'could not download',
          'no file',
          'no successful file-operation',
        ]) ||
        containsAnyCodeUnitSequence(content, const [
          [0x3067, 0x304d, 0x307e, 0x305b, 0x3093],
          [0x672a, 0x5b9f, 0x884c],
        ])) {
      return false;
    }

    return containsFileMutationCompletionMarker(normalized) ||
        containsAnyCodeUnitSequence(content, const [
          [0x4fdd, 0x5b58],
          [0x4f5c, 0x6210],
          [0x5b8c, 0x4e86],
        ]);
  }

  bool hasUnexecutedFileSideEffectResult(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      try {
        final decoded = jsonDecode(toolResult.result);
        if (decoded is Map<String, dynamic>) {
          return decoded['code'] == 'unexecuted_file_save';
        }
      } catch (_) {
        return false;
      }
      return false;
    });
  }

  bool hasUnexecutedCommandActionResult(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      try {
        final decoded = jsonDecode(toolResult.result);
        if (decoded is Map<String, dynamic>) {
          return decoded['code'] == 'unexecuted_command_action';
        }
      } catch (_) {
        return false;
      }
      return false;
    });
  }

  bool hasUnverifiedReadOnlyInspectionClaimResult(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults.any((toolResult) {
      try {
        final decoded = jsonDecode(toolResult.result);
        if (decoded is Map<String, dynamic>) {
          return decoded['code'] == 'unverified_read_only_inspection_claim';
        }
      } catch (_) {
        return false;
      }
      return false;
    });
  }

  bool hasSuccessfulCommandExecutionResult(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      return toolCallExecutionPolicy.isCommandExecutionTool(toolResult.name) &&
          toolCallExecutionPolicy.toolResultHasSuccessfulExit(toolResult);
    });
  }

  bool looksLikeCommandSuccessClaim(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (containsAny(normalized, const [
      'not passed',
      'not complete',
      'not completed',
      'not successful',
      'failed',
      'failure',
      'unverified',
      'incomplete',
      'timed out and did not complete',
    ])) {
      return false;
    }
    return containsAny(normalized, const [
          'passed',
          'success',
          'successful',
          'succeeded',
          'completed',
          'complete',
          'green',
          'no issues found',
        ]) ||
        containsAnyCodeUnitSequence(content, const [
          [0x5408, 0x683c],
          [0x6210, 0x529f],
          [0x5b8c, 0x4e86],
          [0x901a, 0x904e],
          [0x30b3, 0x30df, 0x30c3, 0x30c8, 0x6e08, 0x307f],
          [0x6b63, 0x5e38, 0x306b, 0x52d5, 0x4f5c],
        ]);
  }

  bool looksLikeUnsupportedCommandExecutionAction(String content) {
    return looksLikeFutureCommandExecutionAction(content) ||
        looksLikeCompletedCommandExecutionClaim(content);
  }

  bool looksLikeFutureCommandExecutionAction(String content) {
    if (content.isEmpty || content.length > 1200) {
      return false;
    }
    if (looksLikeCommandExecutionQuestion(content)) {
      return false;
    }

    final lowerContent = content.toLowerCase();
    final hasCommandContext = containsCommandExecutionContext(content);
    final hasEnglishAction = containsAny(lowerContent, const [
      'i will run',
      'i will execute',
      "i'll run",
      "i'll execute",
      'i am going to run',
      "i'm going to run",
      'running the',
      'executing the',
      'run the command',
      'execute the command',
    ]);
    return (hasCommandContext && hasEnglishAction) ||
        containsCjkFutureCommandExecutionAction(content);
  }

  bool looksLikeCompletedCommandExecutionClaim(String content) {
    if (content.isEmpty || content.length > 1800) {
      return false;
    }
    if (looksLikeCommandExecutionQuestion(content)) {
      return false;
    }
    if (!containsCommandExecutionContext(content)) {
      return false;
    }

    final lowerContent = content.toLowerCase();
    if (containsAny(lowerContent, const [
      'not completed',
      'not successful',
      'not uploaded',
      'not released',
      'failed',
      'failure',
      'unverified',
      'not executed',
    ])) {
      return false;
    }

    return containsAny(lowerContent, const [
          'completed',
          'succeeded',
          'successful',
          'successfully',
          'uploaded',
          'exported',
          'released',
          'build passed',
          'upload succeeded',
          'release complete',
        ]) ||
        containsAnyCodeUnitSequence(content, const [
          [0x6210, 0x529f],
          [0x5b8c, 0x4e86],
          [0x6e08, 0x307f],
        ]);
  }

  bool looksLikeFutureFileSideEffectAction(String content) {
    if (content.isEmpty || content.length > 1200) {
      return false;
    }
    final lowerContent = content.toLowerCase();
    final hasEnglishFileAction =
        containsAny(lowerContent, const [
          'i will create',
          'i will write',
          'i will save',
          'i will edit',
          'i will update',
          'i will bump',
          'i will increment',
          "i'll create",
          "i'll write",
          "i'll save",
          "i'll edit",
          "i'll update",
          "i'll bump",
          "i'll increment",
        ]) &&
        containsAny(lowerContent, const [
          'file',
          'release note',
          'markdown',
          'document',
          'pubspec.yaml',
          'yaml',
          'version',
          'build number',
        ]);
    if (hasEnglishFileAction) {
      return true;
    }
    return containsCjkFutureFileSideEffectAction(content);
  }

  bool containsCommandExecutionContext(String content) {
    final lowerContent = content.toLowerCase();
    if (containsAny(lowerContent, const [
      'local command',
      'command line',
      'shell command',
      'local_execute_command',
      'run_tests',
      'git_execute_command',
      'dry run',
      'dry-run',
      'release script',
      'tool/release_',
      'flutter test',
      'flutter analyze',
      'flutter build',
      'dart test',
      'git commit',
      'git add',
      'git push',
      'xcodebuild',
      'app store connect',
      'build/ios',
      'ipa',
      'bash ',
    ])) {
      return true;
    }
    return containsAnyCodeUnitSequence(content, const [
      [0x30d3, 0x30eb, 0x30c9],
      [0x30a2, 0x30c3, 0x30d7, 0x30ed, 0x30fc, 0x30c9],
      [0x30ea, 0x30ea, 0x30fc, 0x30b9],
      [0x30d7, 0x30ed, 0x30bb, 0x30b9],
      [0x30b3, 0x30de, 0x30f3, 0x30c9],
      [0x30b3, 0x30df, 0x30c3, 0x30c8],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5],
      [0x691c, 0x8a3c],
      [0x5b9f, 0x884c],
    ]);
  }

  bool looksLikeCommandExecutionQuestion(String content) {
    final lowerContent = content.toLowerCase();
    if (containsAny(lowerContent, const [
      'should i run',
      'shall i run',
      'do you want me to run',
      'would you like me to run',
      'can i run',
      'run it?',
      'execute it?',
    ])) {
      return true;
    }
    final hasQuestionMark =
        lowerContent.contains('?') ||
        content.contains(String.fromCharCode(0xff1f));
    return hasQuestionMark &&
        containsAnyCodeUnitSequence(content, const [
          [0x5b9f, 0x884c, 0x3057, 0x307e, 0x3059, 0x304b],
          [0x30b3, 0x30df, 0x30c3, 0x30c8, 0x3057, 0x307e, 0x3059, 0x304b],
          [0x30b9, 0x30c6, 0x30fc, 0x30b8, 0x3057, 0x307e, 0x3059, 0x304b],
          [0x30d7, 0x30c3, 0x30b7, 0x30e5, 0x3057, 0x307e, 0x3059, 0x304b],
        ]);
  }

  bool containsCjkFutureCommandExecutionAction(String value) {
    final hasAction = containsAnyCodeUnitSequence(value, const [
      [0x5b9f, 0x884c, 0x3057, 0x307e, 0x3059],
      [0x8d70, 0x3089, 0x305b, 0x307e, 0x3059],
      [0x958b, 0x59cb, 0x3057, 0x307e, 0x3059],
      [0x958b, 0x59cb, 0x3057, 0x307e, 0x3057, 0x305f],
      [0x30b3, 0x30df, 0x30c3, 0x30c8, 0x3057, 0x307e, 0x3059],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8, 0x3057, 0x307e, 0x3059],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5, 0x3057, 0x307e, 0x3059],
      [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059],
      [0x691c, 0x8a3c, 0x3057, 0x307e, 0x3059],
    ]);
    if (!hasAction) {
      return false;
    }
    return containsAnyCodeUnitSequence(value, const [
      [0x30c9, 0x30e9, 0x30a4, 0x30e9, 0x30f3],
      [0x30ed, 0x30fc, 0x30ab, 0x30eb, 0x30b3, 0x30de, 0x30f3, 0x30c9],
      [0x30b3, 0x30de, 0x30f3, 0x30c9],
      [0x30b3, 0x30df, 0x30c3, 0x30c8],
      [0x30b9, 0x30c6, 0x30fc, 0x30b8],
      [0x30d7, 0x30c3, 0x30b7, 0x30e5],
      [0x691c, 0x8a3c],
      [0x30c6, 0x30b9, 0x30c8],
      [0x9759, 0x7684, 0x89e3, 0x6790],
      [0x89e3, 0x6790],
      [0x30ea, 0x30ea, 0x30fc, 0x30b9],
      [0x672c, 0x756a],
      [0x30b9, 0x30af, 0x30ea, 0x30d7, 0x30c8],
    ]);
  }

  bool containsCjkFutureActionMarker(String value, {int startIndex = 0}) {
    final markers = [
      String.fromCharCodes([0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x8abf, 0x67fb, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x8ffd, 0x8de1, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x691c, 0x8a3c, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x8abf, 0x67fb, 0x8a08, 0x753b]),
    ];
    final clampedStart = startIndex.clamp(0, value.length).toInt();
    for (final marker in markers) {
      if (value.indexOf(marker, clampedStart) >= 0) {
        return true;
      }
    }
    return false;
  }

  bool containsCjkFutureFileSideEffectAction(String value) {
    final hasFilePath = RegExp(
      r'(?:^|[\s`"(<])[\w./-]+\.(?:dart|yaml|yml|json|md|txt|swift|kt|java|js|ts|tsx|jsx|py|rs|go|rb|php|css|scss|html)(?:$|[\s`")>,.])',
      caseSensitive: false,
    ).hasMatch(value);
    final objectMarkers = [
      String.fromCharCodes([0x30d5, 0x30a1, 0x30a4, 0x30eb]),
      'pubspec.yaml',
      'version',
      String.fromCharCodes([
        0x30ea,
        0x30ea,
        0x30fc,
        0x30b9,
        0x30ce,
        0x30fc,
        0x30c8,
      ]),
      'markdown',
      'Markdown',
      String.fromCharCodes([0x30c9, 0x30ad, 0x30e5, 0x30e1, 0x30f3, 0x30c8]),
    ];
    final hasUiMutationTarget = containsAnyCodeUnitSequence(value, const [
      [0x30bb, 0x30af, 0x30b7, 0x30e7, 0x30f3],
      [0x753b, 0x9762],
      [0x8a2d, 0x5b9a],
      [0x9805, 0x76ee],
    ]);
    final actionMarkers = [
      String.fromCharCodes([0x4f5c, 0x6210, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x4fdd, 0x5b58, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x66f8, 0x304d, 0x307e, 0x3059]),
      String.fromCharCodes([0x66f8, 0x304d, 0x8fbc, 0x307f, 0x307e, 0x3059]),
      String.fromCharCodes([0x751f, 0x6210, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([
        0x30a4,
        0x30f3,
        0x30af,
        0x30ea,
        0x30e1,
        0x30f3,
        0x30c8,
        0x3057,
        0x307e,
        0x3059,
      ]),
      String.fromCharCodes([
        0x7de8,
        0x96c6,
        0x3092,
        0x884c,
        0x3044,
        0x307e,
        0x3059,
      ]),
      String.fromCharCodes([0x7de8, 0x96c6, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x5909, 0x66f4, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([
        0x975e,
        0x8868,
        0x793a,
        0x306b,
        0x3057,
        0x307e,
        0x3059,
      ]),
      String.fromCharCodes([
        0x975e,
        0x8868,
        0x793a,
        0x306b,
        0x3057,
        0x307e,
        0x3057,
        0x305f,
      ]),
      String.fromCharCodes([
        0x30e9,
        0x30c3,
        0x30d4,
        0x30f3,
        0x30b0,
        0x5b8c,
        0x4e86,
      ]),
    ];
    return (hasFilePath ||
            hasUiMutationTarget ||
            objectMarkers.any(value.contains)) &&
        actionMarkers.any(value.contains);
  }

  bool isFileMutationToolName(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'write_file':
      case 'edit_file':
      case 'delete_file':
      case 'rollback_last_file_change':
        return true;
    }
    return false;
  }

  bool isSuccessfulFileMutationToolResult(ToolResultInfo toolResult) {
    final normalized = toolResult.result.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.startsWith('error:') ||
        normalized.startsWith('auto-review denied')) {
      return false;
    }
    try {
      final decoded = jsonDecode(toolResult.result);
      if (decoded is! Map<String, dynamic>) {
        return true;
      }
      if (decoded['error'] != null) {
        return false;
      }
      final code = decoded['code']?.toString().trim().toLowerCase();
      if (code == 'permission_denied' ||
          code == 'bookmark_restore_failed' ||
          code == 'tool_execution_failed') {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  bool toolResultLooksSuccessfulForFinalAnswer(String result) {
    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('error:')) {
      return false;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<Object?, Object?>) {
        final keys = decoded.keys
            .whereType<String>()
            .map((key) => key.toLowerCase())
            .toSet();
        if (keys.contains('error')) {
          return false;
        }
        Object? codeValue;
        for (final entry in decoded.entries) {
          final key = entry.key;
          if (key is String && key.toLowerCase() == 'code') {
            codeValue = entry.value;
            break;
          }
        }
        final code = codeValue?.toString().toLowerCase();
        if (code != null &&
            (code.contains('denied') ||
                code.contains('failure') ||
                code.contains('failed') ||
                code.contains('not_executed'))) {
          return false;
        }
      }
    } on FormatException {
      return true;
    }
    return true;
  }

  bool containsFileMutationCompletionMarker(String response) {
    final normalized = response.toLowerCase();
    return containsAny(normalized, const [
      'saved',
      'wrote',
      'created',
      'updated',
      'overwrote',
      'modified',
      'file:',
      'file path',
      'bytes_written',
    ]);
  }

  bool containsAny(String value, List<String> markers) {
    return markers.any(value.contains);
  }

  bool containsAnyAtOrAfter(
    String value,
    List<String> markers,
    int startIndex,
  ) {
    final clampedStart = startIndex.clamp(0, value.length).toInt();
    for (final marker in markers) {
      if (value.indexOf(marker, clampedStart) >= 0) {
        return true;
      }
    }
    return false;
  }

  bool containsAnyCodeUnitSequence(String text, List<List<int>> sequences) {
    return sequences.any(
      (sequence) => containsCodeUnitSequence(text, sequence),
    );
  }

  bool containsCodeUnitSequence(String text, List<int> sequence) {
    if (sequence.isEmpty || text.isEmpty) {
      return false;
    }
    final units = text.codeUnits;
    if (sequence.length > units.length) {
      return false;
    }
    for (var start = 0; start <= units.length - sequence.length; start++) {
      var matched = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (units[start + offset] != sequence[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return true;
      }
    }
    return false;
  }
}
