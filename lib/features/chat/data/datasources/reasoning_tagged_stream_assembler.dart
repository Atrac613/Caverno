import 'package:openai_dart/openai_dart.dart';

/// Turns a provider's streamed deltas into the `<think>`-tagged text the app
/// renders, and accumulates the same text for the completed response.
///
/// Every streaming entry point needs this and none of them may differ: the tag
/// pair is opened and closed by *this* state machine, so a provider that sends
/// reasoning in `reasoning_content` (DeepSeek, vLLM, OpenRouter) reads the same
/// on screen as one that inlines it. Tags are batched with the adjacent text
/// rather than emitted alone, because a chunk carrying a bare `<think>` renders
/// as literal text for the moment before the next chunk arrives.
final class ReasoningTaggedStreamAssembler {
  ReasoningTaggedStreamAssembler(this._response);

  /// Everything the caller will treat as the assistant's response, tags
  /// included.
  final StringBuffer _response;

  final StringBuffer _reasoning = StringBuffer();

  bool _isInReasoning = false;

  /// Reasoning text alone, or null when none streamed. The accumulated
  /// response content leaves it out, so a caller that must know whether the
  /// model reasoned reads it here.
  String? get reasoning => _reasoning.isEmpty ? null : _reasoning.toString();

  /// Chunks to yield for one streamed [delta], in order.
  Iterable<String> consume(ChatDelta? delta) sync* {
    if (delta == null) return;
    final reasoning = delta.reasoningContent ?? delta.reasoning;
    final content = delta.content;

    if (reasoning != null && reasoning.isNotEmpty) {
      _reasoning.write(reasoning);
      if (!_isInReasoning) {
        _isInReasoning = true;
        _response.write('<think>$reasoning');
        yield '<think>$reasoning';
      } else {
        _response.write(reasoning);
        yield reasoning;
      }
    }

    if (content != null && content.isNotEmpty) {
      if (_isInReasoning) {
        _isInReasoning = false;
        _response.write('</think>$content');
        yield '</think>$content';
      } else {
        _response.write(content);
        yield content;
      }
    }
  }

  /// Closing tag for a stream that ended while still inside reasoning, or null
  /// when nothing is open.
  String? close() {
    if (!_isInReasoning) return null;
    _isInReasoning = false;
    _response.write('</think>');
    return '</think>';
  }
}
