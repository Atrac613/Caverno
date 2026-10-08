import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/production_release/production_release_execution_identity.dart';
import '../../domain/services/tool_call_execution_policy.dart';
import '../../domain/services/tool_failure_classifier.dart';
import 'turn_tool_result_ledger.dart';

/// Records only command calls that reached execution, with their exact
/// resolved identity for production-release recovery.
final class TurnCommandExecutionRecorder {
  const TurnCommandExecutionRecorder();

  static const _executionPolicy = ToolCallExecutionPolicy();
  static const _failureClassifier = ToolFailureClassifier();
  static const _releaseIdentity = ProductionReleaseExecutionIdentity();

  void record({
    required TurnToolResultLedger ledger,
    required ChatTurnOwner owner,
    required ToolResultInfo toolResult,
    required McpToolResult sourceResult,
    required ProductionReleaseArgumentResolver resolveArguments,
  }) {
    if (!_executionPolicy.isCommandExecutionTool(toolResult.name) ||
        _failureClassifier.declaredOrigin(sourceResult) != null) {
      return;
    }
    final command = _executionPolicy.toolCommandArgument(toolResult.arguments);
    if (command == null || command.trim().isEmpty) return;
    final toolCall = ToolCallInfo(
      id: toolResult.id,
      name: toolResult.name,
      arguments: toolResult.arguments,
    );
    ledger
      ..recordCommand(owner, command)
      ..recordCommandExecutionIdentity(
        owner,
        _releaseIdentity.forToolCall(
          toolCall,
          resolvedArguments: resolveArguments(toolCall),
        ),
      );
  }
}
