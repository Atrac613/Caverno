import 'dart:convert';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../entities/tool_call_info.dart';
import 'final_answer_claim_detector.dart';
import 'immutable_json_snapshot.dart';
import 'tool_loop_exit_reason.dart';
import 'turn_finalization_recovery_policy.dart';

// ChatNotifier decomposition collaborator: unexecuted-final-answer-tool-request-policy

ToolResultInfo _freezeToolResult(ToolResultInfo result) {
  return ToolResultInfo(
    id: result.id,
    name: result.name,
    arguments: ImmutableJsonSnapshot.freezeMap(result.arguments),
    result: result.result,
  );
}

final class UnexecutedFinalAnswerToolRequestInput {
  UnexecutedFinalAnswerToolRequestInput({
    required this.content,
    required List<ToolResultInfo> existingToolResults,
    required this.hasTimedOutCommandResult,
    required this.hasFailedCommandValidation,
    required this.hasUnexecutedCommandActionResult,
    required this.hasUnexecutedFileSideEffectResult,
    required this.hasSuccessfulFileMutationEvidence,
    required this.hasSuccessfulCommandExecutionEvidence,
  }) : existingToolResults = List<ToolResultInfo>.unmodifiable(
         existingToolResults.map(_freezeToolResult),
       );

  final String content;
  final List<ToolResultInfo> existingToolResults;
  final bool hasTimedOutCommandResult;
  final bool hasFailedCommandValidation;
  final bool hasUnexecutedCommandActionResult;
  final bool hasUnexecutedFileSideEffectResult;
  final bool hasSuccessfulFileMutationEvidence;
  final bool hasSuccessfulCommandExecutionEvidence;
}

final class UnexecutedFinalAnswerToolRequestAnalysis {
  UnexecutedFinalAnswerToolRequestAnalysis({
    required List<ToolResultInfo> newToolResults,
    required this.appendNotice,
    required this.noticeText,
    required this.exitReason,
    required this.transformId,
  }) : newToolResults = List<ToolResultInfo>.unmodifiable(
         newToolResults.map(_freezeToolResult),
       );

  final List<ToolResultInfo> newToolResults;
  final bool appendNotice;
  final String noticeText;
  final ToolLoopExitReason? exitReason;
  final String? transformId;
}

final class UnexecutedFinalAnswerToolRequestPolicy {
  const UnexecutedFinalAnswerToolRequestPolicy();

  static const notice =
      'I could not execute the additional tool request above in this final-answer step. '
      'Treat it as unexecuted; ask me to continue with a narrower follow-up '
      'if the missing action still matters.';
  static const transformId = 'unexecuted_tool_request_notice';
  static const _claimDetector = FinalAnswerClaimDetector();
  static const _turnFinalizationRecovery = TurnFinalizationRecoveryPolicy();

  UnexecutedFinalAnswerToolRequestAnalysis analyze(
    UnexecutedFinalAnswerToolRequestInput input,
  ) {
    final newToolResults = _buildNewToolResults(input);
    final allToolResults = <ToolResultInfo>[
      ...input.existingToolResults,
      ...newToolResults,
    ];
    final appendNotice =
        !input.content.contains(notice) &&
        looksLikeUnexecutedToolRequest(input.content) &&
        !_shouldSkipNoticeForToolResults(input, allToolResults: allToolResults);
    final recordedAny = newToolResults.isNotEmpty;
    return UnexecutedFinalAnswerToolRequestAnalysis(
      newToolResults: newToolResults,
      appendNotice: appendNotice,
      noticeText: notice,
      exitReason: recordedAny ? ToolLoopExitReason.unexecutedToolRequest : null,
      transformId: recordedAny
          ? UnexecutedFinalAnswerToolRequestPolicy.transformId
          : null,
    );
  }

  bool looksLikeUnexecutedToolRequest(String content) {
    if (looksLikeStructuredToolRequest(content)) {
      return true;
    }
    final trimmed = content.trim();
    return looksLikePlanOnlyFinalToolAnswer(trimmed) ||
        _claimDetector.looksLikeUnsupportedCommandExecutionAction(trimmed) ||
        _claimDetector.looksLikeFutureFileSideEffectAction(trimmed);
  }

  bool looksLikeStructuredToolRequest(String content) {
    if (ContentParser.extractCompletedToolCalls(content).isNotEmpty) {
      return true;
    }
    if (looksLikeBracketedToolRequest(content)) {
      return true;
    }

    final fencedJsonBlocks = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).allMatches(content);
    for (final block in fencedJsonBlocks) {
      final snippet = block.group(1);
      if (snippet != null && _jsonLooksLikeCommandProposal(snippet)) {
        return true;
      }
    }

    final trimmed = content.trim();
    return (trimmed.startsWith('[') || trimmed.startsWith('{')) &&
        _jsonLooksLikeCommandProposal(trimmed);
  }

  bool looksLikeBracketedToolRequest(String content) {
    return bracketedToolRequestName(content) != null;
  }

  String? bracketedToolRequestName(String content) {
    final match = RegExp(
      r'\[Tool:\s*([A-Za-z_][\w.-]*)\]\s*(?:\r?\n)+\s*Arguments:\s*(?:\{|\[)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(content);
    return match?.group(1);
  }

  bool looksLikePlanOnlyFinalToolAnswer(String content) {
    return _claimDetector.looksLikePlanOnlyFinalToolAnswer(content);
  }

  List<ToolResultInfo> _buildNewToolResults(
    UnexecutedFinalAnswerToolRequestInput input,
  ) {
    final toolCalls = ContentParser.extractCompletedToolCalls(input.content);
    if (toolCalls.isEmpty) {
      return const [];
    }

    final recordedResults = <ToolResultInfo>[...input.existingToolResults];
    final newToolResults = <ToolResultInfo>[];
    for (final toolCall in toolCalls) {
      final signature = jsonEncode({
        'name': toolCall.name,
        'arguments': toolCall.arguments,
      });
      final alreadyRecorded = recordedResults.any((result) {
        final decoded = _tryDecodeMap(result.result);
        return decoded?['reason'] == 'final_answer_tool_request' &&
            decoded?['signature'] == signature;
      });
      if (alreadyRecorded) {
        continue;
      }
      final toolResult = ToolResultInfo(
        id: 'unexecuted_final_answer_${toolCall.occurrenceId ?? toolCall.name}',
        name: toolCall.name,
        arguments: toolCall.arguments,
        result: jsonEncode({
          'ok': false,
          'code': 'tool_call_not_executed',
          'reason': 'final_answer_tool_request',
          'tool_name': toolCall.name,
          'signature': signature,
          'error':
              'The final-answer response requested a tool, but final-answer streaming does not execute tools directly.',
          'required_action':
              'Retry this tool through the normal tool-aware continuation.',
        }),
      );
      newToolResults.add(toolResult);
      recordedResults.add(toolResult);
    }
    return newToolResults;
  }

  bool _shouldSkipNoticeForToolResults(
    UnexecutedFinalAnswerToolRequestInput input, {
    required List<ToolResultInfo> allToolResults,
  }) {
    if (allToolResults.isEmpty ||
        input.hasTimedOutCommandResult ||
        input.hasFailedCommandValidation ||
        input.hasUnexecutedCommandActionResult ||
        input.hasUnexecutedFileSideEffectResult ||
        (!input.hasSuccessfulFileMutationEvidence &&
            !input.hasSuccessfulCommandExecutionEvidence)) {
      return false;
    }

    final candidate = FinalAnswerClaimDetector.claimCandidate(input.content);
    if (candidate.isEmpty ||
        looksLikeStructuredToolRequest(candidate) ||
        looksLikePlanOnlyFinalToolAnswer(candidate) ||
        _claimDetector.looksLikeFutureCommandExecutionAction(candidate) ||
        _claimDetector.looksLikeFutureFileSideEffectAction(candidate) ||
        _turnFinalizationRecovery.looksLikeCodingFutureAction(candidate)) {
      return false;
    }

    return _claimDetector.looksLikeCompletedCommandExecutionClaim(candidate) ||
        _turnFinalizationRecovery.looksLikeCompletedCodingFinalAnswer(
          candidate,
        );
  }

  bool _jsonLooksLikeCommandProposal(String snippet) {
    try {
      return _jsonValueLooksLikeCommandProposal(jsonDecode(snippet));
    } on FormatException {
      return false;
    }
  }

  bool _jsonValueLooksLikeCommandProposal(Object? value) {
    if (value is List && value.isNotEmpty) {
      final mapItems = value.whereType<Map<Object?, Object?>>().toList();
      return mapItems.length == value.length &&
          mapItems.any(_jsonMapLooksLikeCommandProposal);
    }
    if (value is Map<Object?, Object?>) {
      return _jsonMapLooksLikeCommandProposal(value);
    }
    return false;
  }

  bool _jsonMapLooksLikeCommandProposal(Map<Object?, Object?> value) {
    final keys = value.keys
        .whereType<String>()
        .map((key) => key.toLowerCase())
        .toSet();
    if (keys.contains('command')) {
      return !keys.contains('exit_code') &&
          !keys.contains('stdout') &&
          !keys.contains('stderr');
    }
    if (!keys.contains('name') || !keys.contains('arguments')) {
      return false;
    }

    String? name;
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String && key.toLowerCase() == 'name') {
        name = entry.value?.toString().toLowerCase();
        break;
      }
    }
    return name == 'local_execute_command' ||
        name == 'run_tests' ||
        name == 'git_execute_command' ||
        name == 'ssh_execute_command';
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
