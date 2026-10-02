import 'dart:convert';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../entities/tool_call_info.dart';
import 'coding_continuation_recovery_input.dart';
import 'coding_continuation_recovery_prompt_builder.dart';
import 'reasoning_only_stop.dart';
import 'structured_coding_execution_deferral_detector.dart';
import 'tool_definition_search_service.dart';

export 'coding_continuation_recovery_input.dart';

// ChatNotifier decomposition collaborator: coding-continuation-recovery-policy

typedef _RecoveryText = ({
  String label,
  String reason,
  String error,
  String action,
  String? lead,
});

final class CodingContinuationRecoveryPolicy {
  const CodingContinuationRecoveryPolicy();

  static const _structuredDeferralDetector =
      StructuredCodingExecutionDeferralDetector();

  String? recoveryCode(CodingContinuationRecoveryInput input) {
    if (!input.isCodingWorkspaceOrMode ||
        !hasCodingContinuationRecoveryTools(input.toolDefinitions)) {
      return null;
    }
    // Mechanical, so it applies to project-task turns too; once per turn.
    if (!input.reasoningOnlyRecoveryUsed &&
        const ReasoningOnlyStop().matches(input.candidateResponse)) {
      return ReasoningOnlyStop.recoveryCode;
    }
    final candidate = ContentParser.stripModelHistoryArtifacts(
      input.candidateResponse,
    );
    if (candidate.isEmpty || input.isProjectTaskTurn) {
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
    final trimmed = ContentParser.stripModelHistoryArtifacts(text);
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
    final hasCjkTarget = _containsAnyCodeUnitSequence(trimmed, const [
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
    // Future and volitional forms only, like the English list: the bare stem
    // for "check" also matched "checked" and "please check", which sent a
    // finished release report back to work (session 4ceebb57, 19c593b74).
    final hasCjkAction = _containsAnyCodeUnitSequence(trimmed, const [
      [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059],
      [0x78ba, 0x8a8d, 0x3057, 0x3066, 0x3044, 0x304d, 0x307e, 0x3059],
      [0x78ba, 0x8a8d, 0x3057, 0x3066, 0x307f, 0x307e, 0x3059],
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

  bool looksLikeUnexecutedDelegation(String content) {
    final visible = ContentParser.stripModelHistoryArtifacts(content);
    if (visible.length > 12000) return false;
    return visible.split('\n').any((line) {
      final plain = line.trim().replaceAll('*', '').trim();
      if (RegExp(r'(?:委任|委譲)します[。.!！]*$').hasMatch(plain)) {
        return true;
      }
      return RegExp(
        r"\b(?:I will|I'll|Let me) delegate\b",
        caseSensitive: false,
      ).hasMatch(plain);
    });
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

  /// [feedback] restated after a rejected status response, naming the
  /// violation and the only accepted call.
  ToolResultInfo withProtocolCorrection(
    ToolResultInfo feedback,
    Map<String, dynamic> violation,
  ) => feedback.withResult(
    jsonEncode({
      ...jsonDecode(feedback.result) as Map<String, dynamic>,
      'protocol_violation': violation,
      'requiredAction':
          'The rejected calls were not executed. Call only '
          'update_goal once with completed as a JSON boolean.',
    }),
  );

  String buildCodingContinuationRecoveryPrompt(
    String candidateResponse, {
    required String recoveryCode,
    List<ToolResultInfo> executedToolResults = const [],
  }) => const CodingContinuationRecoveryPromptBuilder().build(
    responsePreview: _clipForDiagnostic(candidateResponse),
    lead: recoveryPromptLead(recoveryCode),
    recoveryCode: recoveryCode,
    executedToolResults: executedToolResults,
  );

  String? recoveryPartialProgressNotice(List<ToolResultInfo> results) =>
      const CodingContinuationRecoveryPromptBuilder().partialProgressNotice(
        results,
      );

  /// Wording per recovery code. An unknown code reads as prose continuation,
  /// and a code without its own lead uses the prose lead.
  static const _texts = <String, _RecoveryText>{
    'structured_project_subtask': (
      label: 'structured project subtask recovery',
      reason: 'The intermediate project subtask has unresolved requirements.',
      error: 'The subtask completion marker or execution evidence is missing.',
      action:
          'Resolve the subtask requirements without completing the parent goal.',
      lead: null,
    ),
    'structured_coding_task_status': (
      label: 'structured coding task status recovery',
      reason:
          'The project task has no terminal structured goal acknowledgement.',
      error: 'The project task needs a structured goal status report.',
      action:
          'Call update_goal with a JSON boolean completed value, using the captured execution evidence.',
      lead: null,
    ),
    'unexecuted_delegation': (
      label: 'unexecuted delegation recovery',
      reason:
          'The parent promised delegation without a spawn_subagent tool result.',
      error: 'Delegation was described but spawn_subagent was not called.',
      action:
          'Call spawn_subagent now, or state that delegation did not occur.',
      lead:
          'The previous answer promised delegation, but no spawn_subagent call was executed. Call spawn_subagent now if the task is ready; otherwise state the blocker and that delegation did not occur.',
    ),
    'length_truncated_pending_action': (
      label: 'length-truncated pending action recovery',
      reason:
          'The assistant reached the output-token limit while trusted tool evidence still showed incomplete executable coding work.',
      error:
          'The assistant reached the output-token limit before issuing the next executable coding action.',
      action:
          'Issue exactly one available tool call that advances the incomplete work.',
      lead: null,
    ),
    'bracketed_coding_tool_request': (
      label: 'bracketed coding tool request recovery',
      reason:
          'The assistant returned a bracketed coding tool request in final-answer text instead of issuing an executable tool call.',
      error:
          'The assistant response contained a bracketed coding tool request, but no executable tool call was issued.',
      action:
          'Issue the requested coding tool call now. Do not describe bracketed tool blocks as already executed.',
      lead:
          'The previous assistant response contained a bracketed coding tool request in final-answer text, but no tool call was issued.',
    ),
    ReasoningOnlyStop.recoveryCode: (
      label: ReasoningOnlyStop.label,
      reason: ReasoningOnlyStop.reason,
      error: ReasoningOnlyStop.reason,
      action: ReasoningOnlyStop.requiredAction,
      lead: ReasoningOnlyStop.lead,
    ),
  };

  static const _RecoveryText _proseText = (
    label: 'prose-only coding continuation recovery',
    reason:
        'The assistant returned coding continuation prose instead of using an available coding tool.',
    error:
        'The assistant response described a future coding action, but no tool call was issued.',
    action:
        'Use an available file, command, or test tool now. Do not restate the plan.',
    lead:
        'The previous assistant response was a coding continuation, but no tool call was issued.',
  );

  _RecoveryText _textFor(String code) => _texts[code] ?? _proseText;

  String recoveryLogLabel(String recoveryCode) => _textFor(recoveryCode).label;
  String recoveryReason(String recoveryCode) => _textFor(recoveryCode).reason;
  String recoveryError(String recoveryCode) => _textFor(recoveryCode).error;
  String recoveryRequiredAction(String recoveryCode) =>
      _textFor(recoveryCode).action;
  String recoveryPromptLead(String recoveryCode) =>
      _textFor(recoveryCode).lead ?? _proseText.lead!;

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

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) =>
      sequences.any(
        (units) =>
            units.isNotEmpty && text.contains(String.fromCharCodes(units)),
      );
}
