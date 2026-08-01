import 'dart:async';

import '../../data/datasources/chat_datasource.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/message.dart';

/// Owns terminal response metadata and timing for exact chat turn owners.
///
/// A turn may start another response after consuming or discarding the prior
/// one, which is required by participant conversations. Disposing an owner
/// permanently rejects late callbacks from that generation.
final class ResponseMetadataRegistry {
  final Map<ChatTurnOwner, _ResponseMetadataState> _states =
      <ChatTurnOwner, _ResponseMetadataState>{};
  final Map<String, int> _disposedGenerationWatermarks = <String, int>{};

  int get length => _states.length;
  bool get isEmpty => _states.isEmpty;
  Set<ChatTurnOwner> get owners =>
      Set<ChatTurnOwner>.unmodifiable(_states.keys);

  bool contains(ChatTurnOwner owner) => _states.containsKey(owner);

  bool start(ChatTurnOwner owner) {
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration <= disposedThrough ||
        _states.containsKey(owner)) {
      return false;
    }
    _states[owner] = _ResponseMetadataState();
    return true;
  }

  bool capture(ChatTurnOwner owner, ChatCompletionTerminalMetadata metadata) {
    final state = _states[owner];
    if (state == null) return false;
    state.metadata = metadata;
    return true;
  }

  bool captureResult(ChatTurnOwner owner, ChatCompletionResult result) =>
      capture(owner, terminalMetadataFor(result));

  Future<ChatCompletionTerminalMetadata> terminalFor(
    Future<ChatCompletionResult> completion,
  ) {
    final terminal = completion.then(terminalMetadataFor);
    unawaited(
      terminal.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return terminal;
  }

  static ChatCompletionTerminalMetadata terminalMetadataFor(
    ChatCompletionResult result,
  ) => ChatCompletionTerminalMetadata(
    finishReason: result.finishReason,
    usage: result.usage,
  );

  ChatCompletionTerminalMetadata? metadataFor(ChatTurnOwner owner) =>
      _states[owner]?.metadata;

  String? finishReasonFor(ChatTurnOwner owner) =>
      metadataFor(owner)?.finishReason;

  MessageResponseMetrics? consume(ChatTurnOwner owner) {
    final state = _states.remove(owner);
    if (state == null) return null;
    state.timer.stop();
    final metadata = state.metadata;
    return MessageResponseMetrics(
      promptTokens: metadata?.usage.promptTokens ?? 0,
      completionTokens: metadata?.usage.completionTokens ?? 0,
      totalTokens: metadata?.usage.totalTokens ?? 0,
      elapsedMilliseconds: state.timer.elapsedMilliseconds,
      finishReason: metadata?.finishReason,
    );
  }

  bool discard(ChatTurnOwner owner) {
    final state = _states.remove(owner);
    if (state == null) return false;
    state.timer.stop();
    return true;
  }

  bool dispose(ChatTurnOwner owner) {
    discard(owner);
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration > disposedThrough) {
      _disposedGenerationWatermarks[owner.conversationId] =
          owner.interactionGeneration;
      return true;
    }
    return false;
  }
}

final class _ResponseMetadataState {
  _ResponseMetadataState() : timer = Stopwatch()..start();

  final Stopwatch timer;
  ChatCompletionTerminalMetadata? metadata;
}
