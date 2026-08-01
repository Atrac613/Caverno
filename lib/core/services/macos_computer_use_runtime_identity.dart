/// Why the live Computer Use runtime identity changed.
enum MacosComputerUseRuntimeInvalidationCause {
  helperLaunch,
  helperRestart,
  helperTermination,
  emergencyStop,
}

/// Whether the captured helper identity may currently start an action.
enum MacosComputerUseRuntimeAvailability { available, transitioning, stopped }

/// Immutable identity of the helper runtime that may execute an action.
final class MacosComputerUseRuntimeIdentity {
  MacosComputerUseRuntimeIdentity({
    required String sessionId,
    required this.revision,
  }) : sessionId = _requiredValue(sessionId, 'sessionId') {
    RangeError.checkNotNegative(revision, 'revision');
  }

  final String sessionId;
  final int revision;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MacosComputerUseRuntimeIdentity &&
            other.sessionId == sessionId &&
            other.revision == revision;
  }

  @override
  int get hashCode => Object.hash(sessionId, revision);

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }
    return normalized;
  }
}

/// One synchronous runtime invalidation notification.
final class MacosComputerUseRuntimeInvalidation {
  const MacosComputerUseRuntimeInvalidation({
    required this.cause,
    required this.previous,
    required this.current,
  });

  final MacosComputerUseRuntimeInvalidationCause cause;
  final MacosComputerUseRuntimeIdentity previous;
  final MacosComputerUseRuntimeIdentity current;

  bool get rotatedSession => previous.sessionId != current.sessionId;
}

/// Atomic view of the helper identity and its launch availability.
final class MacosComputerUseRuntimeSnapshot {
  const MacosComputerUseRuntimeSnapshot({
    required this.identity,
    required this.availability,
  });

  final MacosComputerUseRuntimeIdentity identity;
  final MacosComputerUseRuntimeAvailability availability;

  bool get canStartAction =>
      availability == MacosComputerUseRuntimeAvailability.available;
}

/// Opaque ownership token for one helper lifecycle transition.
final class MacosComputerUseRuntimeTransition {
  const MacosComputerUseRuntimeTransition._({
    required int sequence,
    required this.invalidation,
  }) : _sequence = sequence;

  final int _sequence;
  final MacosComputerUseRuntimeInvalidation invalidation;
}

typedef MacosComputerUseRuntimeInvalidationListener =
    void Function(MacosComputerUseRuntimeInvalidation invalidation);

/// Synchronous process-local authority for helper session and revision state.
///
/// The same instance must be shared by the native service lifecycle and every
/// runtime adapter that can start a Computer Use side effect.
final class MacosComputerUseRuntimeIdentityProvider {
  MacosComputerUseRuntimeIdentityProvider({
    String? initialSessionId,
    int initialRevision = 0,
    String Function()? sessionIdFactory,
  }) : _sessionIdFactory = sessionIdFactory ?? _defaultSessionId {
    RangeError.checkNotNegative(initialRevision, 'initialRevision');
    _identity = MacosComputerUseRuntimeIdentity(
      sessionId: initialSessionId ?? _sessionIdFactory(),
      revision: initialRevision,
    );
  }

  static int _nextSessionSequence = 0;

  final String Function() _sessionIdFactory;
  final Map<int, MacosComputerUseRuntimeInvalidationListener> _listeners = {};
  late MacosComputerUseRuntimeIdentity _identity;
  MacosComputerUseRuntimeAvailability _availability =
      MacosComputerUseRuntimeAvailability.available;
  int _nextListenerId = 0;
  int _nextTransitionSequence = 0;
  int? _activeTransitionSequence;

  MacosComputerUseRuntimeIdentity capture() => _identity;

  MacosComputerUseRuntimeIdentity? captureAvailable() {
    return _availability == MacosComputerUseRuntimeAvailability.available
        ? _identity
        : null;
  }

  MacosComputerUseRuntimeSnapshot captureSnapshot() {
    return MacosComputerUseRuntimeSnapshot(
      identity: _identity,
      availability: _availability,
    );
  }

  void Function() addInvalidationListener(
    MacosComputerUseRuntimeInvalidationListener listener,
  ) {
    final listenerId = _nextListenerId++;
    _listeners[listenerId] = listener;
    var attached = true;
    return () {
      if (!attached) return;
      attached = false;
      _listeners.remove(listenerId);
    };
  }

  MacosComputerUseRuntimeInvalidation helperRestarted() {
    final transition = beginHelperRestart();
    finishTransition(transition, helperAvailable: true);
    return transition.invalidation;
  }

  MacosComputerUseRuntimeInvalidation emergencyStop() {
    final transition = beginEmergencyStop();
    finishTransition(transition, helperAvailable: true);
    return transition.invalidation;
  }

  MacosComputerUseRuntimeTransition beginHelperLaunch() {
    return _beginTransition(
      MacosComputerUseRuntimeInvalidationCause.helperLaunch,
      rotateSession: true,
    );
  }

  MacosComputerUseRuntimeTransition beginHelperRestart() {
    return _beginTransition(
      MacosComputerUseRuntimeInvalidationCause.helperRestart,
      rotateSession: true,
    );
  }

  MacosComputerUseRuntimeTransition beginHelperTermination() {
    return _beginTransition(
      MacosComputerUseRuntimeInvalidationCause.helperTermination,
      rotateSession: true,
    );
  }

  MacosComputerUseRuntimeTransition beginEmergencyStop() {
    return _beginTransition(
      MacosComputerUseRuntimeInvalidationCause.emergencyStop,
      rotateSession: false,
    );
  }

  /// Settles only the latest transition so stale completions cannot reopen it.
  bool finishTransition(
    MacosComputerUseRuntimeTransition transition, {
    required bool helperAvailable,
  }) {
    if (_activeTransitionSequence != transition._sequence) {
      return false;
    }
    _activeTransitionSequence = null;
    _availability = helperAvailable
        ? MacosComputerUseRuntimeAvailability.available
        : MacosComputerUseRuntimeAvailability.stopped;
    return true;
  }

  MacosComputerUseRuntimeTransition _beginTransition(
    MacosComputerUseRuntimeInvalidationCause cause, {
    required bool rotateSession,
  }) {
    final previous = _identity;
    final revision = previous.revision + 1;
    var sessionId = previous.sessionId;
    if (rotateSession) {
      sessionId = _sessionIdFactory().trim();
      if (sessionId.isEmpty) {
        throw StateError(
          'The Computer Use runtime session factory returned an empty ID.',
        );
      }
      if (sessionId == previous.sessionId) {
        sessionId = '$sessionId-$revision';
      }
    }
    final current = MacosComputerUseRuntimeIdentity(
      sessionId: sessionId,
      revision: revision,
    );
    _identity = current;
    _availability = MacosComputerUseRuntimeAvailability.transitioning;
    final transitionSequence = _nextTransitionSequence++;
    _activeTransitionSequence = transitionSequence;
    final invalidation = MacosComputerUseRuntimeInvalidation(
      cause: cause,
      previous: previous,
      current: current,
    );
    for (final listener in List<MacosComputerUseRuntimeInvalidationListener>.of(
      _listeners.values,
    )) {
      try {
        listener(invalidation);
      } catch (_) {
        // Runtime fencing must not prevent the native recovery action.
      }
    }
    return MacosComputerUseRuntimeTransition._(
      sequence: transitionSequence,
      invalidation: invalidation,
    );
  }

  static String _defaultSessionId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final sequence = _nextSessionSequence++;
    return 'computer-use-runtime-$timestamp-$sequence';
  }
}
