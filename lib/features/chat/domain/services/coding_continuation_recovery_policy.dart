import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';
import 'structured_coding_execution_deferral_detector.dart';
import 'tool_call_execution_policy.dart';
import 'tool_definition_search_service.dart';

// ChatNotifier decomposition collaborator: coding-continuation-recovery-policy

final class CodingContinuationRecoveryInput {
  CodingContinuationRecoveryInput({
    required this.candidateResponse,
    required List<Map<String, dynamic>> toolDefinitions,
    required this.owningTurnLatestUserText,
    required this.requireContinuationRequest,
    required this.isCodingWorkspaceOrMode,
    required this.hasPendingAutoContinueWorkflow,
    required this.saveSkillCompletedInGeneration,
    required this.acceptsTerminalToolRoleBlockerResponse,
    required this.bracketedToolRequestName,
  }) : toolDefinitions = List<Map<String, dynamic>>.unmodifiable(
         toolDefinitions.map(ImmutableJsonSnapshot.freezeMap),
       );

  final String candidateResponse;
  final List<Map<String, dynamic>> toolDefinitions;
  final String owningTurnLatestUserText;
  final bool requireContinuationRequest;
  final bool isCodingWorkspaceOrMode;
  final bool hasPendingAutoContinueWorkflow;
  final bool saveSkillCompletedInGeneration;
  final bool acceptsTerminalToolRoleBlockerResponse;
  final String? bracketedToolRequestName;
}

final class CodingContinuationRecoveryPolicy {
  const CodingContinuationRecoveryPolicy();

  static const _executionPolicy = ToolCallExecutionPolicy();
  static const _structuredDeferralDetector =
      StructuredCodingExecutionDeferralDetector();

  String? recoveryCode(CodingContinuationRecoveryInput input) {
    final candidate = input.candidateResponse.trim();
    if (candidate.isEmpty) {
      return null;
    }
    if (!input.isCodingWorkspaceOrMode) {
      return null;
    }
    if (!hasCodingContinuationRecoveryTools(input.toolDefinitions)) {
      return null;
    }
    if (input.saveSkillCompletedInGeneration) {
      return null;
    }

    final hasStructuredExecutionDeferral = _structuredDeferralDetector.matches(
      candidate,
    );
    final hasPendingStructuredExecutionDeferral =
        hasStructuredExecutionDeferral && input.hasPendingAutoContinueWorkflow;
    if (hasStructuredExecutionDeferral &&
        !hasPendingStructuredExecutionDeferral) {
      return null;
    }
    if (input.requireContinuationRequest &&
        !looksLikeContinuationOnlyUserRequest(input.owningTurnLatestUserText) &&
        !hasPendingStructuredExecutionDeferral) {
      return null;
    }
    if (input.acceptsTerminalToolRoleBlockerResponse) {
      return null;
    }

    final bracketedToolName = input.bracketedToolRequestName;
    if (bracketedToolName != null &&
        isCodingContinuationRecoveryToolName(bracketedToolName)) {
      return 'bracketed_coding_tool_request';
    }
    if (looksLikeProseOnlyCodingContinuation(candidate) ||
        hasPendingStructuredExecutionDeferral) {
      return 'prose_only_coding_continuation';
    }
    return null;
  }

  bool hasCodingContinuationRecoveryTools(
    List<Map<String, dynamic>> toolDefinitions,
  ) {
    final toolNames = ToolDefinitionSearchService.toolNamesFromDefinitions(
      toolDefinitions,
    ).map((toolName) => toolName.trim().toLowerCase()).toSet();
    return toolNames.any(isCodingContinuationRecoveryToolName);
  }

  bool isCodingContinuationRecoveryToolName(String toolName) {
    return const {
      'read_file',
      'list_directory',
      'search_files',
      'resolve_installed_dependency',
      'write_file',
      'edit_file',
      'delete_file',
      'local_execute_command',
      'git_execute_command',
      'run_tests',
      'run_python_script',
    }.contains(toolName.trim().toLowerCase());
  }

  bool looksLikeContinuationOnlyUserRequest(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final cleaned = normalized
        .replaceAll(RegExp(r'^[\s.!?]+'), '')
        .replaceAll(RegExp(r'[\s.!?]+$'), '');
    if (const {
      'continue',
      'go on',
      'keep going',
      'proceed',
      'resume',
      'next',
      'next step',
    }.contains(cleaned)) {
      return true;
    }
    if (cleaned.startsWith('automatic goal continuation ')) {
      return true;
    }
    return _containsAnyCodeUnitSequence(text, const [
      [0x7d9a, 0x3051, 0x3066],
      [0x7d9a, 0x304d],
      [0x9032, 0x3081, 0x3066],
    ]);
  }

  bool looksLikeProseOnlyCodingContinuation(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final hasFencedCode = trimmed.contains('```');
    if (trimmed.length > 1600 && (!hasFencedCode || trimmed.length > 12000)) {
      return false;
    }
    final normalized = trimmed.toLowerCase();
    if (_containsAny(normalized, const [
      'cannot',
      'can not',
      "can't",
      'unable',
      'blocked',
      'need your',
      'please provide',
      'not enough information',
    ])) {
      return false;
    }

    final hasEnglishTarget = _containsAny(normalized, const [
      'code',
      'source',
      'file',
      'project',
      'dart',
      'python',
      'script',
      'logic',
      'entrypoint',
      'implementation',
      'pubspec',
      'error',
      'diagnostic',
      'analyzer',
      'test failure',
    ]);
    final hasEnglishAction = _containsAny(normalized, const [
      'i will inspect',
      'i will check',
      'i will read',
      'i will port',
      'i will implement',
      'i will update',
      'i will edit',
      'i will modify',
      'i will write',
      'i will create',
      'i will fix',
      'i will resolve',
      "i'll inspect",
      "i'll check",
      "i'll read",
      "i'll port",
      "i'll implement",
      "i'll update",
      "i'll edit",
      "i'll modify",
      "i'll write",
      "i'll create",
      "i'll fix",
      "i'll resolve",
      'i am going to inspect',
      'i am going to check',
      'i am going to read',
      'i am going to port',
      'i am going to implement',
      'i am going to update',
      'i am going to edit',
      'i am going to modify',
      'i am going to write',
      'i am going to create',
      'i am going to fix',
      'i am going to resolve',
      'next i will',
      'now i will',
    ]);
    final hasCjkTarget = _containsAnyCodeUnitSequence(text, const [
      [0x30b3, 0x30fc, 0x30c9],
      [0x30bd, 0x30fc, 0x30b9],
      [0x30d5, 0x30a1, 0x30a4, 0x30eb],
      [0x30d7, 0x30ed, 0x30b8, 0x30a7, 0x30af, 0x30c8],
      [0x30b9, 0x30af, 0x30ea, 0x30d7, 0x30c8],
      [0x30ed, 0x30b8, 0x30c3, 0x30af],
      [0x65e2, 0x5b58],
      [0x30a8, 0x30e9, 0x30fc],
      [0x8a3a, 0x65ad],
    ]);
    final hasCjkAction = _containsAnyCodeUnitSequence(text, const [
      [0x78ba, 0x8a8d, 0x3057],
      [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059],
      [0x8abf, 0x67fb, 0x3057, 0x307e, 0x3059],
      [0x8aad, 0x307f, 0x307e, 0x3059],
      [0x30dd, 0x30fc, 0x30c6, 0x30a3, 0x30f3, 0x30b0, 0x3057, 0x307e, 0x3059],
      [0x79fb, 0x690d, 0x3057, 0x307e, 0x3059],
      [0x5b9f, 0x88c5, 0x3057, 0x307e, 0x3059],
      [0x66f4, 0x65b0, 0x3057, 0x307e, 0x3059],
      [0x7de8, 0x96c6, 0x3057, 0x307e, 0x3059],
      [0x4f5c, 0x6210, 0x3057, 0x307e, 0x3059],
      [0x66f8, 0x304d, 0x307e, 0x3059],
      [0x4fee, 0x6b63, 0x3057, 0x307e, 0x3059],
    ]);
    return (hasEnglishTarget || hasCjkTarget) &&
        (hasEnglishAction || hasCjkAction);
  }

  ToolResultInfo buildCodingContinuationRecoveryToolResult({
    required String id,
    required String candidateResponse,
    required String recoveryCode,
  }) {
    return ToolResultInfo(
      id: id,
      name: 'coding_continuation_recovery',
      arguments: {'reason': recoveryReason(recoveryCode)},
      result: jsonEncode({
        'ok': false,
        'code': recoveryCode,
        'error': recoveryError(recoveryCode),
        'claimedResponse': _clipForDiagnostic(candidateResponse),
        'requiredAction': recoveryRequiredAction(recoveryCode),
      }),
    );
  }

  String buildCodingContinuationRecoveryPrompt(
    String candidateResponse, {
    required String recoveryCode,
    List<ToolResultInfo> executedToolResults = const [],
  }) {
    final partialProgressNotice = recoveryPartialProgressNotice(
      executedToolResults,
    );
    if (partialProgressNotice != null) {
      return [
        recoveryPromptLead(recoveryCode),
        partialProgressNotice,
        'Do not restart the task or re-run commands that already completed successfully.',
        'Use the available tools now to investigate and resolve only the unresolved failure above, then report the final status.',
        'Do not restate the plan and do not answer with future-tense prose.',
        'Previous response: ${_clipForDiagnostic(candidateResponse)}',
      ].join('\n');
    }
    return [
      recoveryPromptLead(recoveryCode),
      'Treat that response as unexecuted.',
      'Use the available tools now to perform the next concrete coding step.',
      'Prefer read_file, list_directory, or search_files before editing when the target file has not been inspected.',
      'Do not restate the plan and do not answer with future-tense prose.',
      'Previous response: ${_clipForDiagnostic(candidateResponse)}',
    ].join('\n');
  }

  String? recoveryPartialProgressNotice(
    List<ToolResultInfo> executedToolResults,
  ) {
    if (executedToolResults.isEmpty) {
      return null;
    }
    final hasTimeout = executedToolResults.any(
      _executionPolicy.toolResultTimedOut,
    );
    final hasFailedExit = _toolResultsContainFailedCommandValidation(
      executedToolResults,
    );
    if (!hasTimeout && !hasFailedExit) {
      return null;
    }
    final problems = <String>[
      if (hasTimeout) 'a command timed out before completing',
      if (hasFailedExit) 'a command exited with a non-zero status',
    ];
    final progressClause =
        executedToolResults.any(_executionPolicy.toolResultHasSuccessfulExit)
        ? 'Some commands in this turn already completed successfully, but '
        : 'In this turn, ';
    return '$progressClause${problems.join(' and ')}.';
  }

  String recoveryLogLabel(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'length-truncated pending action recovery';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'bracketed coding tool request recovery';
    }
    return 'prose-only coding continuation recovery';
  }

  String recoveryReason(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'The assistant reached the output-token limit while trusted tool evidence still showed incomplete executable coding work.';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'The assistant returned a bracketed coding tool request in final-answer text instead of issuing an executable tool call.';
    }
    return 'The assistant returned coding continuation prose instead of using an available coding tool.';
  }

  String recoveryError(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'The assistant reached the output-token limit before issuing the next executable coding action.';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'The assistant response contained a bracketed coding tool request, but no executable tool call was issued.';
    }
    return 'The assistant response described a future coding action, but no tool call was issued.';
  }

  String recoveryRequiredAction(String recoveryCode) {
    if (recoveryCode == 'length_truncated_pending_action') {
      return 'Issue exactly one available tool call that advances the incomplete work.';
    }
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'Issue the requested coding tool call now. Do not describe bracketed tool blocks as already executed.';
    }
    return 'Use an available file, command, or test tool now. Do not restate the plan.';
  }

  String recoveryPromptLead(String recoveryCode) {
    if (recoveryCode == 'bracketed_coding_tool_request') {
      return 'The previous assistant response contained a bracketed coding tool request in final-answer text, but no tool call was issued.';
    }
    return 'The previous assistant response was a coding continuation, but no tool call was issued.';
  }

  bool _toolResultsContainFailedCommandValidation(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults.any((toolResult) {
      if (!_executionPolicy.isCommandExecutionTool(toolResult.name)) {
        return false;
      }
      final normalizedResult = toolResult.result.toLowerCase();
      return RegExp(
            r'"exit_code"\s*:\s*(?!0\b)-?\d+',
          ).hasMatch(normalizedResult) ||
          RegExp(r'exit_code:\s*(?!0\b)-?\d+').hasMatch(normalizedResult);
    });
  }

  String _clipForDiagnostic(String value, {int maxLength = 240}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) {
    return sequences.any(
      (sequence) => _containsCodeUnitSequence(text, sequence),
    );
  }

  bool _containsCodeUnitSequence(String text, List<int> sequence) {
    if (sequence.isEmpty || sequence.length > text.length) {
      return false;
    }
    for (var start = 0; start <= text.length - sequence.length; start += 1) {
      var matches = true;
      for (var offset = 0; offset < sequence.length; offset += 1) {
        if (text.codeUnitAt(start + offset) != sequence[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return true;
      }
    }
    return false;
  }
}
