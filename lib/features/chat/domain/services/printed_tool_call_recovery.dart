import 'package:caverno_content_protocol/caverno_content_protocol.dart';

/// Recovers tool calls a model printed as a raw object in its message content
/// instead of emitting them through the provider's tool-call channel.
///
/// Unlike a `<tool_call>` tag, a bare object carries no marker of intent, so
/// the only thing separating a request from prose is whether the turn actually
/// offered that tool. The check is all-or-nothing: one name the turn never
/// advertised rejects the batch rather than running the part that matched.
///
/// The non-streaming path applies the same rule inside the response
/// normalizer. Both exist so a model behaves the same whether or not its
/// answer streamed.
class PrintedToolCallRecovery {
  const PrintedToolCallRecovery();

  /// Calls to act on in [content]: the tagged forms when present, otherwise
  /// whatever [recover] allows. Tags win because they state the model's intent
  /// and need no permission to be believed.
  List<ToolCallData> extract({
    required String content,
    required Set<String>? advertisedToolNames,
  }) {
    final tagged = ContentParser.extractCompletedToolCalls(content);
    return tagged.isNotEmpty
        ? tagged
        : recover(content: content, advertisedToolNames: advertisedToolNames);
  }

  List<ToolCallData> recover({
    required String content,
    required Set<String>? advertisedToolNames,
  }) {
    final advertised = advertisedToolNames;
    if (advertised == null || advertised.isEmpty) {
      return const <ToolCallData>[];
    }
    final calls = ContentParser.extractFunctionObjectToolCalls(content);
    if (calls.isEmpty || calls.any((call) => !advertised.contains(call.name))) {
      return const <ToolCallData>[];
    }
    return calls;
  }
}
