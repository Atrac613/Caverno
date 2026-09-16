import 'dart:async';

import '../../domain/entities/chat_turn_owner.dart';

/// Ends a turn's response stream from outside the loop reading it.
///
/// [TurnStreamBindingRegistry] can only cancel a stream consumed through
/// `listen`, and the tool-aware paths consume theirs with `await for`, which
/// holds no subscription. Those loops check the interaction generation inside
/// the loop body, so they can only notice a cancellation when a chunk arrives.
/// A stream that has gone silent -- the exact condition the stop button exists
/// for -- never delivers one.
///
/// Session c138c465 measured the cost: generation 10 was cancelled at 12:17:11
/// and its `streamChatCompletionWithTools` request kept generating until
/// 12:49:31, a 36.7-minute orphan whose output was discarded and whose
/// TimeoutException was then logged into a later turn's window, where it looked
/// like that turn had failed.
///
/// One signal per turn, so aborting one thread's turn cannot end another's.
final class TurnAbortSignals {
  final Map<ChatTurnOwner, Completer<void>> _signals =
      <ChatTurnOwner, Completer<void>>{};

  /// The future [owner]'s streams end on, created on first use.
  Future<void> signalFor(ChatTurnOwner owner) =>
      (_signals[owner] ??= Completer<void>()).future;

  /// Null for an unregistered one-shot request (plan drafting, warm-up), which
  /// ends on its own and has nothing for the stop button to reach.
  Future<void>? signalForOrNull(ChatTurnOwner? owner) =>
      owner == null ? null : signalFor(owner);

  bool isAborted(ChatTurnOwner owner) => _signals[owner]?.isCompleted ?? false;

  /// Ends every stream [owner] is reading. Idempotent.
  void abort(ChatTurnOwner owner) {
    final signal = _signals[owner];
    if (signal == null || signal.isCompleted) return;
    signal.complete();
  }

  /// For the paths that end every turn at once: disposal and clearing the
  /// conversation.
  void abortAll() {
    for (final signal in _signals.values) {
      if (!signal.isCompleted) signal.complete();
    }
  }

  /// Retires [owner]'s signal once its turn is over, so a later turn for the
  /// same owner does not inherit an already-aborted one.
  void release(ChatTurnOwner owner) => _signals.remove(owner);

  int get trackedCount => _signals.length;
}

/// Carries a turn's abort future to the datasource that issues its requests.
///
/// Zone-scoped because the abort belongs to the turn, not to any one request,
/// and the turn already runs its request sites inside a zone for the session
/// log and its generation.
///
/// The datasource must read [current] *synchronously*, where it builds the
/// request. A response stream is listened to lazily and so runs outside the
/// zone that created it, which is the same trap that once cost the session log
/// its role attribution.
final class TurnAbortScope {
  TurnAbortScope._();

  static final Object _key = Object();

  static T runWith<T>(Future<void>? abort, T Function() body) =>
      abort == null ? body() : runZoned(body, zoneValues: {_key: abort});

  static Future<void>? get current {
    final value = Zone.current[_key];
    return value is Future<void> ? value : null;
  }
}

/// Ends [source] as soon as [abort] completes, cancelling [source] on the way
/// out so the request underneath it is torn down rather than left generating.
///
/// Applied to the *inner* provider event stream rather than to the stream the
/// turn reads, which matters twice over: it is the inner subscription whose
/// cancellation closes the HTTP connection, and the turn's own `await for`
/// keeps the delivery ordering its state machine was built around. Wrapping
/// the outer stream instead moved the first chunk one hop earlier and left a
/// cancelled turn's raw `<tool_call>` bubble in the transcript.
///
/// Ending the inner stream lets the datasource's generator finish normally, so
/// it still resolves its completion future with whatever had accumulated and
/// the turn is never left awaiting a completer that cannot resolve.
Stream<T> endOnAbort<T>(Stream<T> source, Future<void> abort) {
  final controller = StreamController<T>();
  StreamSubscription<T>? subscription;
  var closing = false;

  Future<void> close() async {
    if (closing) return;
    closing = true;
    final pending = subscription;
    subscription = null;
    // Cancel before closing: the close is what releases the `await for`, and
    // returning to the caller while the upstream request is still open is the
    // leak this function exists to prevent.
    if (pending != null) await pending.cancel();
    if (!controller.isClosed) await controller.close();
  }

  controller.onListen = () {
    subscription = source.listen(
      controller.add,
      onError: controller.addError,
      onDone: () => unawaited(close()),
    );
    abort.then<void>(
      (_) => unawaited(close()),
      onError: (Object _, StackTrace _) => unawaited(close()),
    );
  };
  controller.onCancel = close;
  controller.onPause = () => subscription?.pause();
  controller.onResume = () => subscription?.resume();
  return controller.stream;
}
