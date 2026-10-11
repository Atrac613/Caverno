import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../entities/message.dart';

/// Parses unfinished calls while the caller retains owner-bound acceptance.
final class IncompleteContentToolRecoveryPlan {
  const IncompleteContentToolRecoveryPlan._({
    required this.recoveredToolCalls,
    required this.logMessage,
    this.pendingResult,
  });

  final List<ToolCallData> recoveredToolCalls;
  final String logMessage;
  final String? pendingResult;

  static IncompleteContentToolRecoveryPlan? assess(
    Message? message, {
    required bool Function(ToolCallData call) acceptCall,
  }) {
    if (message == null ||
        message.role != MessageRole.assistant ||
        !ContentParser.hasIncompleteToolCall(message.content)) {
      return null;
    }
    final recovered = ContentParser.extractRecoverableIncompleteToolCalls(
      message.content,
    ).where(acceptCall).toList();
    if (recovered.isEmpty) {
      return IncompleteContentToolRecoveryPlan._(
        recoveredToolCalls: recovered,
        logMessage:
            '[ContentTool] Incomplete tool call could not be parsed; requesting continuation recovery',
        pendingResult:
            '[Incomplete assistant tool call]\n'
            'The assistant emitted an unfinished tool call tag. Reissue the needed '
            'tool call as one complete <tool_use>...</tool_use> tag, or finish with '
            'a concise text answer if no more tools are needed. Do not write '
            '<tool_result> tags yourself.',
      );
    }
    return IncompleteContentToolRecoveryPlan._(
      recoveredToolCalls: recovered,
      logMessage:
          '[ContentTool] Recovering incomplete tool_call(s): ${recovered.length}',
    );
  }
}
