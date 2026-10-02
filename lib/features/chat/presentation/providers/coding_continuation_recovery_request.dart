import 'dart:convert';

import '../../data/datasources/chat_datasource.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/coding_continuation_recovery_policy.dart';
import '../../domain/services/reasoning_only_stop.dart';
import '../../domain/services/status_recovery_verification.dart';
import '../../domain/services/structured_task_status_evidence.dart';

typedef RecoveryCompletionCreator =
    Future<ChatCompletionResult> Function({
      required String logLabel,
      required int interactionGeneration,
      required List<Message> Function(bool) buildMessages,
      required List<ToolResultInfo> toolResults,
      required String? assistantContent,
      required List<Map<String, dynamic>> tools,
    });

/// Requests control status without dispatching a model's protocol violations.
abstract final class CodingContinuationRecoveryRequest {
  static Future<ChatCompletionResult?> run({
    required String candidateResponse,
    required String recoveryCode,
    required String? forcedPrompt,
    required int generation,
    required List<Map<String, dynamic>> tools,
    required List<ToolResultInfo> executedResults,
    required List<Message> Function(bool) buildBaseMessages,
    required List<ToolResultInfo> Function(ToolResultInfo) carryResults,
    required RecoveryCompletionCreator create,
    required bool Function() isCurrent,
  }) async {
    final structured = recoveryCode == 'structured_coding_task_status';
    final structuredStep = recoveryCode == 'structured_project_subtask';
    const policy = CodingContinuationRecoveryPolicy();
    Map<String, dynamic>? violation;
    ChatCompletionResult? rejected;
    for (var attempt = 0; attempt < (structured ? 2 : 1); attempt++) {
      if (!isCurrent()) return null;
      // The carried tail can omit the very writes and verification a status
      // report is judged on (session 1d76c878), so the request states them.
      final feedback = const StructuredTaskStatusEvidence().attachTo(
        policy.buildCodingContinuationRecoveryToolResult(
          id: '${recoveryCode}_${DateTime.now().microsecondsSinceEpoch}_$attempt',
          candidateResponse: candidateResponse,
          recoveryCode: recoveryCode,
        ),
        structured || structuredStep ? executedResults : const [],
      );
      final correctiveFeedback = violation == null
          ? feedback
          : policy.withProtocolCorrection(feedback, violation);
      final correction = violation;
      final response = await ReasoningOnlyStop.send(
        recoveryCode,
        () => create(
          logLabel: policy.recoveryLogLabel(recoveryCode),
          interactionGeneration: generation,
          tools: tools,
          assistantContent: candidateResponse.isEmpty
              ? null
              : candidateResponse,
          toolResults: carryResults(correctiveFeedback),
          buildMessages: (forceCompaction) => [
            ...buildBaseMessages(forceCompaction),
            Message(
              id: '${recoveryCode}_recovery_${feedback.id}',
              role: MessageRole.user,
              timestamp: DateTime.now(),
              content: [
                forcedPrompt ??
                    policy.buildCodingContinuationRecoveryPrompt(
                      candidateResponse,
                      recoveryCode: recoveryCode,
                      executedToolResults: executedResults,
                    ),
                if (correction != null) jsonEncode(correction),
              ].join('\n'),
            ),
          ],
        ),
      );
      if (!isCurrent()) return null;
      if (!structured) return response;
      final calls = response.toolCalls ?? [];
      const verification = StatusRecoveryVerification();
      if (verification.accepts(calls, tools)) return response;
      rejected = response;
      violation = verification.violation(calls, tools);
    }
    return ChatCompletionResult(
      content: rejected!.content,
      finishReason: 'stop',
      usage: rejected.usage,
    );
  }
}
