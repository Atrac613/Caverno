import '../../domain/entities/chat_turn_owner.dart';

// ChatNotifier decomposition collaborator: turn-release-scope
/// The releases one turn owes, held by the turn instead of by its destructor.
///
/// A turn's teardown was a hand-written list of eleven owner-scoped steps in
/// `_terminalizeRuntimeTurn`, followed by ten more generation-scoped ones in
/// `_clearActiveResponseForGeneration`. Nothing asserted that any step ran, and
/// a missed one leaks state into the next turn: the stranded active-response
/// registration fixed in `e59fe248` was exactly that, and the model sat under a
/// spinner until restart.
///
/// This does not move where the state lives — the registries stay
/// notifier-wide, because they serve concurrent turns and are keyed by owner
/// for that reason. It moves who is responsible for releasing it. A turn
/// registers what it owes at start and the scope discharges it once, in order,
/// and can say afterwards what it discharged.
final class TurnReleaseScope {
  TurnReleaseScope({required this.owner});

  final ChatTurnOwner owner;
  final List<_TurnRelease> _releases = <_TurnRelease>[];
  final List<String> _discharged = <String>[];
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Names in registration order, for asserting the list did not silently
  /// shrink.
  List<String> get registeredNames =>
      List<String>.unmodifiable(_releases.map((release) => release.name));

  /// Names actually discharged, populated by [dispose].
  List<String> get dischargedNames => List<String>.unmodifiable(_discharged);

  /// Registers one release. Registering after disposal is a programming error
  /// rather than a silent no-op, because it means a turn acquired something
  /// after its own teardown.
  void register(String name, void Function() release) {
    if (_disposed) {
      throw StateError(
        'TurnReleaseScope for ${owner.conversationId}/'
        'gen-${owner.interactionGeneration} registered "$name" after disposal',
      );
    }
    _releases.add(_TurnRelease(name, release));
  }

  /// Runs every registered release once, in registration order.
  ///
  /// Synchronous by design. The teardown it replaces ran its steps inline and
  /// deferred only the ones it explicitly wrapped, so callers downstream of
  /// teardown observe released state immediately. Awaiting here would move
  /// every release to a microtask and break that; the characterization test
  /// caught exactly that when this started out async.
  ///
  /// One failing release must not strand the rest: teardown is the path that
  /// runs when something has already gone wrong. Failures are collected and
  /// thrown as a group after everything else has had its turn.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final failures = <Object>[];
    for (final release in _releases) {
      try {
        release.run();
        _discharged.add(release.name);
      } on Object catch (error) {
        failures.add(error);
      }
    }
    if (failures.isNotEmpty) {
      throw TurnReleaseFailure(owner: owner, failures: failures);
    }
  }
}

/// Raised when one or more releases threw. The rest still ran.
final class TurnReleaseFailure implements Exception {
  const TurnReleaseFailure({required this.owner, required this.failures});

  final ChatTurnOwner owner;
  final List<Object> failures;

  @override
  String toString() =>
      'TurnReleaseFailure(${owner.conversationId}/'
      'gen-${owner.interactionGeneration}, ${failures.length} failed)';
}

final class _TurnRelease {
  const _TurnRelease(this.name, this._release);

  final String name;
  final void Function() _release;

  void run() => _release();
}
