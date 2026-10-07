import 'package:openai_dart/openai_dart.dart';

import '../../domain/entities/tool_call_info.dart';
import 'strict_tool_choice_policy.dart';

/// Maps Caverno's tool definition maps onto the SDK's request fields.
abstract final class ChatRequestToolDeclarations {
  /// Build a list of [Tool] objects from the tool definition maps.
  static List<Tool>? tools(List<Map<String, dynamic>>? tools) {
    if (tools == null) return null;
    return tools.map((t) {
      final function = t['function'] as Map<String, dynamic>;
      return Tool.function(
        name: function['name'] as String,
        description: function['description'] as String?,
        parameters: function['parameters'] as Map<String, dynamic>?,
        strict: function['strict'] == true,
      );
    }).toList();
  }

  /// Forces an opening control request or an explicit status elicitation.
  ///
  /// Tool-result follow-ups stay model-directed. Forcing `update_goal` again
  /// after its result would require another call and trap a restricted goal
  /// turn that should be allowed to finish in text.
  static ToolChoice? toolChoice(
    List<Map<String, dynamic>>? tools, {
    List<ToolResultInfo>? toolResults,
  }) {
    if (toolResults != null &&
        !StrictToolChoicePolicy.isStatusRecovery(toolResults)) {
      return null;
    }
    final functionName = StrictToolChoicePolicy.forcedFunctionName(tools);
    return functionName == null ? null : ToolChoice.function(functionName);
  }
}
