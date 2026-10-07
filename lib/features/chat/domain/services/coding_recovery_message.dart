import 'dart:convert';

import '../entities/message.dart';
import '../entities/tool_call_info.dart';
import 'coding_continuation_recovery_policy.dart';

/// Composes the requested recovery prompt and any protocol correction.
abstract final class CodingRecoveryMessage {
  static Message message(
    String feedbackId,
    String candidate,
    String code,
    List<ToolResultInfo> results, {
    String? forcedPrompt,
    Map<String, dynamic>? correction,
  }) => Message(
    id: '${code}_recovery_$feedbackId',
    role: MessageRole.user,
    timestamp: DateTime.now(),
    content: content(
      candidate,
      code,
      results,
      forcedPrompt: forcedPrompt,
      correction: correction,
    ),
  );
  static String content(
    String candidate,
    String code,
    List<ToolResultInfo> results, {
    String? forcedPrompt,
    Map<String, dynamic>? correction,
  }) => [
    forcedPrompt ??
        const CodingContinuationRecoveryPolicy()
            .buildCodingContinuationRecoveryPrompt(
              candidate,
              recoveryCode: code,
              executedToolResults: results,
            ),
    if (correction != null) jsonEncode(correction),
  ].join('\n');
}
