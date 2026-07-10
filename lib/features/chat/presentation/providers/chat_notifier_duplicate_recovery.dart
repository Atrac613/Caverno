part of 'chat_notifier.dart';

extension ChatNotifierDuplicateRecovery on ChatNotifier {
  List<ToolResultInfo> _buildDuplicateRecoveryToolResults({
    required List<ToolCallInfo> currentToolCalls,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> fallbackToolResults,
  }) {
    final recoveryToolResults = <ToolResultInfo>[];
    for (final toolCall in currentToolCalls) {
      final matchingResult = executedToolResults.reversed
          .where(
            (toolResult) =>
                _toolExecutionKey(
                  ToolCallInfo(
                    id: toolResult.id,
                    name: toolResult.name,
                    arguments: toolResult.arguments,
                  ),
                ) ==
                _toolExecutionKey(toolCall),
          )
          .firstOrNull;
      if (matchingResult != null) {
        recoveryToolResults.add(
          ToolResultInfo(
            id: toolCall.id,
            name: toolCall.name,
            arguments: toolCall.arguments,
            result: _buildDuplicateResultReusePayload(
              matchingResult,
              currentToolCallId: toolCall.id,
            ),
          ),
        );
      }
    }
    recoveryToolResults.addAll(
      fallbackToolResults.where(
        (fallbackResult) => !currentToolCalls.any(
          (toolCall) =>
              _toolExecutionKey(
                ToolCallInfo(
                  id: fallbackResult.id,
                  name: fallbackResult.name,
                  arguments: fallbackResult.arguments,
                ),
              ) ==
              _toolExecutionKey(toolCall),
        ),
      ),
    );
    return _dedupeRecoveryToolResults(recoveryToolResults);
  }

  String _buildDuplicateResultReusePayload(
    ToolResultInfo previousResult, {
    required String currentToolCallId,
  }) {
    final decoded = _tryDecodeMap(previousResult.result);
    if (decoded != null) {
      return jsonEncode({
        ...decoded,
        'code': 'duplicate_tool_call_result_reused',
        'execution_reused': true,
        'prior_tool_call_id': previousResult.id,
        'current_tool_call_id': currentToolCallId,
      });
    }
    return jsonEncode({
      'ok': true,
      'code': 'duplicate_tool_call_result_reused',
      'execution_reused': true,
      'prior_tool_call_id': previousResult.id,
      'current_tool_call_id': currentToolCallId,
      'prior_result': previousResult.result,
    });
  }
}
