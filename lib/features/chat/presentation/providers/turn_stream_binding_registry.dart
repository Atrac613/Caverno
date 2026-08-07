import 'dart:async';

import '../../domain/entities/chat_turn_owner.dart';

/// The response stream a turn is consuming, bound to the turn consuming it.
///
/// This exists because a bare subscription field answered a question it could
/// not answer. Held loose, a subscription outlives the stream that set it --
/// nothing clears one that ended on its own -- so "a subscription exists" meant
/// neither "this turn is streaming" nor "that stream is this turn's". Mid-turn
/// steering asked it both, and got a leftover subscription that made it restart
/// a turn busy running a tool, and a concurrent thread's live one that it
/// cancelled out from under its owner.
///
/// Only one stream is consumed through a subscription at a time, so this holds
/// a single binding rather than a map. What it adds is the owner, and the rule
/// that a release must name it.
final class TurnStreamBindingRegistry {
  StreamSubscription<String>? _subscription;
  ChatTurnOwner? _owner;

  /// Consumes [stream] on behalf of [owner], releasing the binding when the
  /// stream ends by any route.
  ///
  /// Binding and releasing are one call because separating them is what caused
  /// the bug above: three listen sites bound, and none of them released.
  StreamSubscription<String> listen(
    ChatTurnOwner owner,
    Stream<String> stream, {
    required void Function(String chunk) onChunk,
    required void Function(Object error, StackTrace stackTrace) onError,
    required void Function() onDone,
  }) {
    _subscription = stream.listen(
      onChunk,
      onError: (Object error, StackTrace stackTrace) {
        release(owner);
        onError(error, stackTrace);
      },
      onDone: () {
        release(owner);
        onDone();
      },
      cancelOnError: true,
    );
    _owner = owner;
    return _subscription!;
  }

  /// Whether [owner] is the turn currently consuming a stream.
  bool isStreaming(ChatTurnOwner owner) =>
      _subscription != null && _owner == owner;

  /// The subscription [owner] is consuming, or null when it is not streaming.
  StreamSubscription<String>? subscriptionFor(ChatTurnOwner owner) =>
      isStreaming(owner) ? _subscription : null;

  /// Drops the binding when [owner] still holds it.
  ///
  /// Owner-keyed rather than unconditional: another turn may already have bound
  /// its own stream, and one stream finishing must not clear that one.
  void release(ChatTurnOwner owner) {
    if (_owner != owner) return;
    _subscription = null;
    _owner = null;
  }

  /// Ends whatever stream is bound, whoever owns it.
  ///
  /// For the paths that end every turn at once: disposal, clearing the
  /// conversation, cancellation.
  void cancelAll() {
    _subscription?.cancel();
    _subscription = null;
    _owner = null;
  }
}
