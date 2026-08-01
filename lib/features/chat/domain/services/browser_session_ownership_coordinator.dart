import '../entities/chat_turn_owner.dart';

// ChatNotifier decomposition collaborator: browser-session-ownership-coordinator

/// Immutable identity for one browser tool operation.
///
/// The tool call ID remains part of the identity even when two operations have
/// the same owner and tool name. This prevents a late completion from one call
/// from satisfying a successor call in the same turn.
final class BrowserSessionOperationIdentity {
  BrowserSessionOperationIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _requiredValue(toolName, 'toolName');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BrowserSessionOperationIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName);

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }
    return normalized;
  }
}

/// Non-forgeable fencing token for an exclusive browser session lease.
///
/// [epoch] is monotonic within one coordinator and may be used for diagnostics.
/// Authorization always uses token identity, not the numeric epoch.
final class BrowserSessionLeaseToken {
  const BrowserSessionLeaseToken._(this.epoch);

  final int epoch;
}

/// Non-forgeable snapshot of the browser session's current lifetime.
///
/// A reset replaces this capability even when no operation had acquired a
/// lease. Numeric epochs are diagnostic only; validation uses object identity.
final class BrowserSessionEpochSnapshot {
  const BrowserSessionEpochSnapshot._(this.epoch);

  final int epoch;
}

/// Immutable snapshot of the page revision under one exact lease.
final class BrowserPageRevisionSnapshot {
  const BrowserPageRevisionSnapshot._({
    required this.operation,
    required this.sessionEpoch,
    required this.token,
    required this.revision,
  });

  final BrowserSessionOperationIdentity operation;
  final BrowserSessionEpochSnapshot sessionEpoch;
  final BrowserSessionLeaseToken token;
  final int revision;
}

/// Exclusive browser session lease acquired for one operation chain.
final class BrowserSessionLease {
  const BrowserSessionLease._({
    required this.operation,
    required this.sessionEpoch,
    required this.token,
    required this.pageRevision,
  });

  final BrowserSessionOperationIdentity operation;
  final BrowserSessionEpochSnapshot sessionEpoch;
  final BrowserSessionLeaseToken token;
  final BrowserPageRevisionSnapshot pageRevision;
}

/// Opaque receipt proving that one exact browser effect was admitted.
final class BrowserSessionEffectReceipt {
  const BrowserSessionEffectReceipt._({
    required this.operation,
    required this.sessionEpoch,
    required this.leaseToken,
    required Object effectToken,
  }) : _effectToken = effectToken;

  final BrowserSessionOperationIdentity operation;
  final BrowserSessionEpochSnapshot sessionEpoch;
  final BrowserSessionLeaseToken leaseToken;
  final Object _effectToken;
}

/// One-use authority that fences the actual browser transport callback.
final class BrowserSessionEffectPermit {
  BrowserSessionEffectPermit._({
    required BrowserSessionOwnershipCoordinator coordinator,
    required BrowserSessionLease lease,
    required Object effectToken,
  }) : _coordinator = coordinator,
       _lease = lease,
       _effectToken = effectToken;

  final BrowserSessionOwnershipCoordinator _coordinator;
  final BrowserSessionLease _lease;
  final Object _effectToken;
  BrowserSessionEffectReceipt? _receipt;

  BrowserSessionEffectReceipt? get receipt => _receipt;

  /// Invokes [effect] only after atomically consuming this exact permit.
  Future<T> runEffect<T>(Future<T> Function() effect) async {
    final receipt = _coordinator._beginEffect(this);
    _receipt = receipt;
    try {
      return await effect();
    } finally {
      _coordinator._markEffectInvocationSettled(receipt);
    }
  }
}

enum BrowserSessionLeaseAcquisitionKind {
  acquired,
  busy,
  ownerExpired,
  staleSession,
}

/// Result of trying to acquire the browser's exclusive operation chain.
final class BrowserSessionLeaseAcquisition {
  const BrowserSessionLeaseAcquisition.acquired(BrowserSessionLease this.lease)
    : kind = BrowserSessionLeaseAcquisitionKind.acquired;

  const BrowserSessionLeaseAcquisition.busy()
    : kind = BrowserSessionLeaseAcquisitionKind.busy,
      lease = null;

  const BrowserSessionLeaseAcquisition.ownerExpired()
    : kind = BrowserSessionLeaseAcquisitionKind.ownerExpired,
      lease = null;

  const BrowserSessionLeaseAcquisition.staleSession()
    : kind = BrowserSessionLeaseAcquisitionKind.staleSession,
      lease = null;

  final BrowserSessionLeaseAcquisitionKind kind;
  final BrowserSessionLease? lease;
}

/// Exact work invalidated when one browser-operation owner becomes terminal.
final class BrowserSessionOwnerClearResult {
  const BrowserSessionOwnerClearResult({
    required this.becameTerminal,
    required this.invalidatedLease,
  });

  final bool becameTerminal;
  final BrowserSessionLease? invalidatedLease;
}

/// Exact browser-session work invalidated by a lifetime reset.
final class BrowserSessionInvalidationResult {
  const BrowserSessionInvalidationResult({
    required this.previousEpoch,
    required this.currentEpoch,
    required this.invalidatedLease,
  });

  final BrowserSessionEpochSnapshot previousEpoch;
  final BrowserSessionEpochSnapshot currentEpoch;
  final BrowserSessionLease? invalidatedLease;
}

/// Owns exclusive browser operation leases and page-revision fencing.
///
/// This class performs no browser or UI work. Adapters acquire a lease before
/// beginning an asynchronous approval/execution chain and must validate the
/// exact operation and token before accepting any completion.
final class BrowserSessionOwnershipCoordinator {
  BrowserSessionLease? _activeLease;
  BrowserSessionEffectReceipt? _activeEffect;
  bool _activeEffectInvocationSettled = false;
  final Set<ChatTurnOwner> _knownOwners = {};
  final Set<ChatTurnOwner> _terminalOwners = {};
  int _lastLeaseEpoch = 0;
  int _lastSessionEpoch = 0;
  int _pageRevision = 0;
  BrowserSessionEpochSnapshot _sessionEpoch = BrowserSessionEpochSnapshot._(0);

  /// Captures the opaque lifetime required for a later lease acquisition.
  BrowserSessionEpochSnapshot captureSessionEpoch() => _sessionEpoch;

  /// Returns the exact effect that must be reconciled before a successor runs.
  BrowserSessionEffectReceipt? get pendingEffectRecovery => _activeEffect;

  /// Acquires the session, or reports why no lease can be issued.
  BrowserSessionLeaseAcquisition acquire(
    BrowserSessionOperationIdentity operation,
    BrowserSessionEpochSnapshot sessionEpoch,
  ) {
    if (!identical(sessionEpoch, _sessionEpoch)) {
      return const BrowserSessionLeaseAcquisition.staleSession();
    }
    if (_terminalOwners.contains(operation.owner)) {
      return const BrowserSessionLeaseAcquisition.ownerExpired();
    }
    if (_activeLease != null) {
      return const BrowserSessionLeaseAcquisition.busy();
    }

    final token = BrowserSessionLeaseToken._(++_lastLeaseEpoch);
    final snapshot = BrowserPageRevisionSnapshot._(
      operation: operation,
      sessionEpoch: sessionEpoch,
      token: token,
      revision: _pageRevision,
    );
    final lease = BrowserSessionLease._(
      operation: operation,
      sessionEpoch: sessionEpoch,
      token: token,
      pageRevision: snapshot,
    );
    _knownOwners.add(operation.owner);
    _activeLease = lease;
    return BrowserSessionLeaseAcquisition.acquired(lease);
  }

  /// Whether [operation] still owns the session through the exact [token].
  bool isLeaseCurrent(
    BrowserSessionOperationIdentity operation,
    BrowserSessionEpochSnapshot sessionEpoch,
    BrowserSessionLeaseToken token,
  ) {
    final active = _activeLease;
    return active != null &&
        identical(sessionEpoch, _sessionEpoch) &&
        !_terminalOwners.contains(operation.owner) &&
        active.operation == operation &&
        identical(active.sessionEpoch, sessionEpoch) &&
        identical(active.token, token);
  }

  /// Captures the current page revision when the exact lease is still active.
  BrowserPageRevisionSnapshot? capturePageRevision(
    BrowserSessionOperationIdentity operation,
    BrowserSessionEpochSnapshot sessionEpoch,
    BrowserSessionLeaseToken token,
  ) {
    if (!isLeaseCurrent(operation, sessionEpoch, token)) return null;
    return BrowserPageRevisionSnapshot._(
      operation: operation,
      sessionEpoch: sessionEpoch,
      token: token,
      revision: _pageRevision,
    );
  }

  /// Validates that a snapshot belongs to the exact active lease and page.
  bool isPageRevisionCurrent(
    BrowserSessionOperationIdentity operation,
    BrowserSessionEpochSnapshot sessionEpoch,
    BrowserSessionLeaseToken token,
    BrowserPageRevisionSnapshot snapshot,
  ) {
    return isLeaseCurrent(operation, sessionEpoch, token) &&
        snapshot.operation == operation &&
        identical(snapshot.sessionEpoch, sessionEpoch) &&
        identical(snapshot.token, token) &&
        snapshot.revision == _pageRevision;
  }

  /// Mints a one-use permit for the exact active browser lease.
  BrowserSessionEffectPermit? authorizeEffect(BrowserSessionLease lease) {
    if (!identical(_activeLease, lease) ||
        !isLeaseCurrent(lease.operation, lease.sessionEpoch, lease.token) ||
        _activeEffect != null) {
      return null;
    }
    return BrowserSessionEffectPermit._(
      coordinator: this,
      lease: lease,
      effectToken: Object(),
    );
  }

  /// Accepts only the exact, settled transport completion for [lease].
  bool acceptEffect(
    BrowserSessionLease lease,
    BrowserSessionEffectPermit permit,
  ) {
    final receipt = permit.receipt;
    if (receipt == null ||
        !identical(_activeLease, lease) ||
        !_matchesActiveEffect(receipt) ||
        !_activeEffectInvocationSettled ||
        !isLeaseCurrent(lease.operation, lease.sessionEpoch, lease.token)) {
      return false;
    }
    _activeEffect = null;
    _activeEffectInvocationSettled = false;
    _pageRevision += 1;
    return true;
  }

  /// Releases a settled uncertain effect after exact external reconciliation.
  bool clearEffectRecovery(BrowserSessionEffectReceipt receipt) {
    if (!_matchesActiveEffect(receipt) || !_activeEffectInvocationSettled) {
      return false;
    }
    final active = _activeLease;
    if (active == null ||
        active.operation != receipt.operation ||
        !identical(active.sessionEpoch, receipt.sessionEpoch) ||
        !identical(active.token, receipt.leaseToken)) {
      return false;
    }
    _activeEffect = null;
    _activeEffectInvocationSettled = false;
    _activeLease = null;
    _pageRevision += 1;
    return true;
  }

  /// Invalidates prior page snapshots and returns the successor snapshot.
  ///
  /// A stale completion cannot change the successor's revision because both the
  /// exact operation and the non-forgeable token must still own the lease.
  BrowserPageRevisionSnapshot? advancePageRevision(
    BrowserSessionOperationIdentity operation,
    BrowserSessionEpochSnapshot sessionEpoch,
    BrowserSessionLeaseToken token,
  ) {
    if (!isLeaseCurrent(operation, sessionEpoch, token)) return null;
    _pageRevision += 1;
    return capturePageRevision(operation, sessionEpoch, token);
  }

  /// Invalidates snapshots after a page change from the exact browser session.
  bool invalidatePageRevisionGlobally(
    BrowserSessionEpochSnapshot sessionEpoch,
  ) {
    if (!identical(sessionEpoch, _sessionEpoch)) return false;
    _pageRevision += 1;
    return true;
  }

  /// Releases only the lease identified by [operation] and exact [token].
  bool release(
    BrowserSessionOperationIdentity operation,
    BrowserSessionEpochSnapshot sessionEpoch,
    BrowserSessionLeaseToken token,
  ) {
    if (!isLeaseCurrent(operation, sessionEpoch, token)) return false;
    if (_activeEffect != null) return false;
    _activeLease = null;
    return true;
  }

  /// Settles one exact lease only after retirement invalidated its authority.
  bool settleInvalidatedLease(BrowserSessionLease lease) {
    final active = _activeLease;
    if (!identical(active, lease)) return false;
    final invalidated =
        !identical(lease.sessionEpoch, _sessionEpoch) ||
        _terminalOwners.contains(lease.operation.owner);
    if (!invalidated || _activeEffect != null) return false;
    _activeLease = null;
    return true;
  }

  /// Marks [owner] terminal and revokes any lease held by that owner.
  ///
  /// A terminal owner cannot acquire another lease from this coordinator.
  BrowserSessionOwnerClearResult clearOwner(ChatTurnOwner owner) {
    _knownOwners.add(owner);
    final becameTerminal = _terminalOwners.add(owner);
    final active = _activeLease;
    final invalidatedLease = active?.operation.owner == owner ? active : null;
    if (invalidatedLease != null) {
      _pageRevision += 1;
    }
    return BrowserSessionOwnerClearResult(
      becameTerminal: becameTerminal,
      invalidatedLease: invalidatedLease,
    );
  }

  /// Terminalizes every owner observed so far and invalidates the session.
  ///
  /// A previously unseen owner, including a later interaction generation, may
  /// still acquire the reset session using a newly captured session epoch.
  BrowserSessionInvalidationResult clearAll() => invalidateSession();

  /// Advances the session epoch and revokes every lease from the prior session.
  BrowserSessionInvalidationResult invalidateSession() {
    final previousEpoch = _sessionEpoch;
    _terminalOwners.addAll(_knownOwners);
    final invalidatedLease = _activeLease;
    if (invalidatedLease != null) {
      _terminalOwners.add(invalidatedLease.operation.owner);
    }
    _pageRevision += 1;
    _sessionEpoch = BrowserSessionEpochSnapshot._(++_lastSessionEpoch);
    return BrowserSessionInvalidationResult(
      previousEpoch: previousEpoch,
      currentEpoch: _sessionEpoch,
      invalidatedLease: invalidatedLease,
    );
  }

  BrowserSessionEffectReceipt _beginEffect(BrowserSessionEffectPermit permit) {
    final lease = permit._lease;
    if (!identical(permit._coordinator, this) ||
        permit._receipt != null ||
        !identical(_activeLease, lease) ||
        _activeEffect != null ||
        !isLeaseCurrent(lease.operation, lease.sessionEpoch, lease.token)) {
      throw StateError('Browser effect permit is no longer current.');
    }
    final receipt = BrowserSessionEffectReceipt._(
      operation: lease.operation,
      sessionEpoch: lease.sessionEpoch,
      leaseToken: lease.token,
      effectToken: permit._effectToken,
    );
    _activeEffect = receipt;
    _activeEffectInvocationSettled = false;
    return receipt;
  }

  void _markEffectInvocationSettled(BrowserSessionEffectReceipt receipt) {
    if (_matchesActiveEffect(receipt)) {
      _activeEffectInvocationSettled = true;
    }
  }

  bool _matchesActiveEffect(BrowserSessionEffectReceipt receipt) {
    final active = _activeEffect;
    return active != null &&
        active.operation == receipt.operation &&
        identical(active.sessionEpoch, receipt.sessionEpoch) &&
        identical(active.leaseToken, receipt.leaseToken) &&
        identical(active._effectToken, receipt._effectToken);
  }
}
