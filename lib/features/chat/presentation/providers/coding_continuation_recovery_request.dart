import '../../data/datasources/chat_datasource.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/coding/coding_continuation_recovery_policy.dart';
import '../../domain/services/coding/coding_recovery_message.dart';
import '../../domain/services/coding/coding_recovery_protocol.dart';
import '../../domain/services/project_verification_repair_policy.dart';
import '../../domain/services/reasoning_only_stop.dart';
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

/// Requests bounded recovery without dispatching protocol violations.
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
    final repair = recoveryCode == ProjectVerificationRepairPolicy.recoveryCode;
    final structuredStep = recoveryCode == 'structured_project_subtask';
    const policy = CodingContinuationRecoveryPolicy();
    Map<String, dynamic>? violation;
    ChatCompletionResult? rejected;
    for (var attempt = 0; attempt < (structured || repair ? 2 : 1); attempt++) {
      if (!isCurrent()) return null;
      // Include execution evidence that may have fallen out of the prompt tail.
      final feedback = const StructuredTaskStatusEvidence().attachTo(
        policy.buildCodingContinuationRecoveryToolResult(
          id: '${recoveryCode}_${DateTime.now().microsecondsSinceEpoch}_$attempt',
          candidateResponse: candidateResponse,
          recoveryCode: recoveryCode,
        ),
        structured || structuredStep || repair ? executedResults : const [],
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
            CodingRecoveryMessage.message(
              feedback.id,
              candidateResponse,
              recoveryCode,
              executedResults,
              forcedPrompt: forcedPrompt,
              correction: correction,
            ),
          ],
        ),
      );
      if (!isCurrent()) return null;
      if (!structured && !repair) return response;
      final calls = response.toolCalls ?? [];
      if (CodingRecoveryProtocol.accepts(calls, tools, repair: repair)) {
        return response;
      }
      rejected = response;
      violation = CodingRecoveryProtocol.violation(
        calls,
        tools,
        repair: repair,
      );
    }
    return ChatCompletionResult(
      content: rejected!.content,
      finishReason: 'stop',
      usage: rejected.usage,
    );
  }
}
