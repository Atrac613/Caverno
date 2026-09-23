import '../../data/datasources/local_shell_tools.dart';
import '../entities/tool_call_info.dart';
import 'local_command_tool_contract.dart';
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
    final arguments = <String, dynamic>{
      ...(resolvedArguments ?? toolCall.arguments),
    };
    final command = arguments['command'];
    if (command is String) {
      arguments['command'] = LocalShellTools.normalizeCommand(command);
    }
    final workingDirectory = arguments['working_directory'];
    final effectiveDirectory =
        workingDirectory is String && workingDirectory.trim().isNotEmpty
        ? workingDirectory
        : arguments['cwd'];
    if (effectiveDirectory is String) {
      arguments['working_directory'] = effectiveDirectory.trim();
    }
    // The source alias adds no semantics after path resolution.
    arguments.remove('cwd');
    // process_start always runs in the background, so an omitted flag and an
    // explicit `true` are one execution. Keying on the raw argument made the
    // harness's own retry instruction (which spells `background=true`) miss
    // an approval recorded for a call that omitted it.
    arguments['background'] =
        toolCall.name.trim().toLowerCase() == 'process_start' ||
        argumentIsTruthy(arguments['background']);
    // `label` only names the background job in the UI, and the model rewords
    // it on every retry; `reason` is narration. Neither changes what runs.
    // Session 99bdd62c (2026-09-23) spent nine refused retries on an approved
    // release whose only difference was a reworded label.
    arguments
      ..remove('reason')
      ..remove('label');
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
