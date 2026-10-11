import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../entities/tool_call_info.dart';

/// Selects repeated-call feedback through an owner-bound successful-result lookup.
final class RepeatedContentToolRecoveryPlan {
  const RepeatedContentToolRecoveryPlan._({
    required this.logMessage,
    required this.replacementContent,
  });

  final String logMessage;
  final String replacementContent;

  static RepeatedContentToolRecoveryPlan? assess(
    List<ToolCallData> repeatedCalls, {
    required ToolResultInfo? Function(ToolCallData call)
    previousSuccessfulResult,
  }) {
    for (final call in repeatedCalls) {
      final previous = previousSuccessfulResult(call);
      if (previous == null) continue;
      return RepeatedContentToolRecoveryPlan._(
        logMessage:
            '[ContentTool] Repeated successful tool call suppressed for '
            '${call.name}: ${call.arguments}',
        replacementContent:
            'The ${previous.name} tool already ran with the same arguments. '
            'I will use the previous tool result instead of repeating the call.',
      );
    }
    return null;
  }
}
