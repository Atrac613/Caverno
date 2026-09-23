import '../entities/tool_call_info.dart';
import 'production_release_canonical_arguments.dart';
import 'tool_call_execution_policy.dart';

typedef ProductionReleaseArgumentResolver =
    Map<String, dynamic> Function(ToolCallInfo toolCall);

/// Canonical identities for approval and duplicate-dispatch evidence.
final class ProductionReleaseExecutionIdentity {
  const ProductionReleaseExecutionIdentity();

  static const _executionPolicy = ToolCallExecutionPolicy();

  String forToolCall(
    ToolCallInfo toolCall, {
    Map<String, dynamic>? resolvedArguments,
  }) {
    final arguments = productionReleaseCanonicalArguments(
      toolCall,
      resolvedArguments ?? toolCall.arguments,
    );
    return _executionPolicy.toolCallDedupKey(
      toolCall.name,
      arguments,
      excludeNonSemanticKeys: true,
    );
  }

  String forDispatch(
    ToolCallInfo toolCall, {
    required ProductionReleaseArgumentResolver resolveArguments,
  }) {
    final arguments = <String, dynamic>{...resolveArguments(toolCall)};
    final command = _executionPolicy.toolCommandArgument(arguments);
    if (command != null) arguments['command'] = normalizeCommand(command);
    return forToolCall(toolCall, resolvedArguments: arguments);
  }

  /// Loose command comparison retained only for legacy evidence without a
  /// complete execution identity and duplicate dispatch spellings.
  String normalizeCommand(String command) =>
      command.replaceAll(RegExp(r'\s+'), ' ').trim();
}
