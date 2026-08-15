import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../domain/entities/tool_call_info.dart';

/// Recovers tool calls a model wrote into its message content instead of
/// emitting through the provider's tool-call channel.
///
/// Models fall back to prose for different reasons -- a template that never
/// learned the channel, a request the model treats as explanatory -- and they
/// use different spellings: `<tool_call>` / `<tool_use>` tags, a bare
/// `call: name{...}`, or the raw call object. Recovering them keeps a turn
/// moving instead of showing the user a JSON blob where an action belongs.
final class ChatCompletionEmbeddedToolCallParser {
  const ChatCompletionEmbeddedToolCallParser();

  /// Calls written in one of the tagged forms, or null when there are none.
  ///
  /// The tags are explicit enough to act on unconditionally; see
  /// [parseAdvertised] for the form that is not.
  List<ToolCallInfo>? parseTagged(String content) =>
      _toToolCallInfo(ContentParser.extractCompletedToolCalls(content));

  /// Calls recovered from [content] whose names all appear in
  /// [advertisedTools], or null when nothing qualifies.
  ///
  /// The advertised-name check is what makes recovering an untagged call
  /// object safe: a printed object only runs when the same request offered
  /// that exact tool. One unadvertised name rejects the whole batch rather
  /// than running the part that happens to match.
  List<ToolCallInfo>? parseAdvertised(
    String content,
    List<Map<String, dynamic>>? advertisedTools,
  ) {
    if (advertisedTools == null || advertisedTools.isEmpty) {
      return null;
    }
    final advertisedNames = advertisedTools
        .map((tool) => tool['function'])
        .whereType<Map<String, dynamic>>()
        .map((function) => function['name'])
        .whereType<String>()
        .toSet();
    final calls =
        parseTagged(content) ??
        _toToolCallInfo(ContentParser.extractFunctionObjectToolCalls(content));
    if (calls == null ||
        calls.any((call) => !advertisedNames.contains(call.name))) {
      return null;
    }
    return calls;
  }

  static List<ToolCallInfo>? _toToolCallInfo(List<ToolCallData> toolCalls) {
    if (toolCalls.isEmpty) {
      return null;
    }
    return toolCalls
        .map(
          (toolCall) => ToolCallInfo(
            id: toolCall.occurrenceId ?? 'raw_${toolCall.name}',
            name: toolCall.name,
            arguments: toolCall.arguments,
          ),
        )
        .toList(growable: false);
  }
}
