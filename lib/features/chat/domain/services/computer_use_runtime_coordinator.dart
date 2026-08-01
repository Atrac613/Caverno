import '../entities/chat_turn_owner.dart';
import 'computer_use_operation_identity.dart';

export 'computer_use_operation_identity.dart';

// ChatNotifier decomposition collaborator: computer-use-runtime-coordinator
final class ComputerUseArmingGrant {
  const ComputerUseArmingGrant._(
    this.identity,
    this.runtimeRevision,
    this.runtimeEpoch,
    this.expiresAt,
  );
  final ComputerUseOperationIdentity identity;
  final int runtimeRevision, runtimeEpoch;
  final DateTime expiresAt;
}

final class ComputerUseRuntimePermit {
  const ComputerUseRuntimePermit._(
    this.identity,
    this.runtimeRevision,
    this.runtimeEpoch,
    this.expiresAt,
  );
  final ComputerUseOperationIdentity identity;
  final int runtimeRevision, runtimeEpoch;
  final DateTime expiresAt;
}

final class ComputerUseRuntimeLeaseToken {
  const ComputerUseRuntimeLeaseToken._(this._issuer, this._sequence);
  final Object _issuer;
  final int _sequence;
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ComputerUseRuntimeLeaseToken &&
            identical(other._issuer, _issuer) &&
            other._sequence == _sequence;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(_issuer), _sequence);
  @override
  String toString() => 'ComputerUseRuntimeLeaseToken(<opaque>)';
}

final class ComputerUseRuntimeLease {
  const ComputerUseRuntimeLease._(
    this.identity,
    this.runtimeRevision,
    this.runtimeEpoch,
    this.token,
  );
  final ComputerUseOperationIdentity identity;
  final int runtimeRevision, runtimeEpoch;
  final ComputerUseRuntimeLeaseToken token;
}

enum ComputerUseArmingDisposition {
  granted,
  notArmed,
  expired,
  ownerTerminated,
  globallyTerminated,
}

final class ComputerUseArmingResult {
  const ComputerUseArmingResult(this.disposition, {this.grant});
  final ComputerUseArmingDisposition disposition;
  final ComputerUseArmingGrant? grant;
}

ComputerUseArmingResult _arming(
  ComputerUseArmingDisposition disposition, [
  ComputerUseArmingGrant? grant,
]) => ComputerUseArmingResult(disposition, grant: grant);

enum ComputerUseGrantConsumeDisposition {
  consumed,
  noGrant,
  identityMismatch,
  revisionMismatch,
  expired,
  replayed,
  revoked,
  superseded,
  runtimeInvalidated,
  ownerTerminated,
  globallyTerminated,
}

final class ComputerUseGrantConsumeResult {
  const ComputerUseGrantConsumeResult(this.disposition, {this.permit});
  final ComputerUseGrantConsumeDisposition disposition;
  final ComputerUseRuntimePermit? permit;
}

ComputerUseGrantConsumeResult _consumption(
  ComputerUseGrantConsumeDisposition disposition, [
  ComputerUseRuntimePermit? permit,
]) => ComputerUseGrantConsumeResult(disposition, permit: permit);

enum ComputerUseLeaseAcquisitionDisposition {
  acquired,
  noPermit,
  identityMismatch,
  revisionMismatch,
  busy,
  replayed,
  expired,
  runtimeInvalidated,
  ownerTerminated,
  globallyTerminated,
}

final class ComputerUseLeaseAcquisitionResult {
  const ComputerUseLeaseAcquisitionResult(this.disposition, {this.lease});
  final ComputerUseLeaseAcquisitionDisposition disposition;
  final ComputerUseRuntimeLease? lease;
}

ComputerUseLeaseAcquisitionResult _acquisition(
  ComputerUseLeaseAcquisitionDisposition disposition, [
  ComputerUseRuntimeLease? lease,
]) => ComputerUseLeaseAcquisitionResult(disposition, lease: lease);

enum ComputerUseLeaseReleaseDisposition {
  released,
  alreadyReleased,
  noActiveLease,
  staleToken,
  invalidationPending,
}

enum ComputerUseRuntimeInvalidationCause { helperRestart, emergencyStop }

enum ComputerUseRuntimeInvalidationDisposition {
  invalidated,
  globallyTerminated,
}

final class ComputerUseRuntimeInvalidationResult {
  const ComputerUseRuntimeInvalidationResult(
    this.disposition,
    this.cause,
    this.previousEpoch,
    this.runtimeEpoch,
    this.invalidatedLease,
  );
  final ComputerUseRuntimeInvalidationDisposition disposition;
  final ComputerUseRuntimeInvalidationCause cause;
  final int previousEpoch, runtimeEpoch;
  final ComputerUseRuntimeLease? invalidatedLease;
}

enum ComputerUseTerminalClearDisposition {
  cleared,
  alreadyCleared,
  globallyTerminated,
}

final class ComputerUseTerminalClearResult {
  const ComputerUseTerminalClearResult(this.disposition, this.invalidatedLease);
  final ComputerUseTerminalClearDisposition disposition;
  final ComputerUseRuntimeLease? invalidatedLease;
}

enum _GrantState { armed, consumed, expired, revoked, superseded }

enum _PermitState { ready, acquired, expired }

typedef _GrantScope = ({ComputerUseOperationIdentity identity, int revision});

final class ComputerUseRuntimeCoordinator {
  final Object _tokenIssuer = Object();
  final Map<ComputerUseArmingGrant, _GrantState> _grantStates = {};
  final Map<_GrantScope, ComputerUseArmingGrant> _latestGrants = {};
  final Map<ComputerUseRuntimePermit, _PermitState> _permitStates = {};
  final Set<ComputerUseRuntimeLeaseToken> _settledLeaseTokens = {};
  final Set<ChatTurnOwner> _terminatedOwners = {};
  int _runtimeEpoch = 0;
  int _nextLeaseSequence = 0;
  bool _globallyTerminated = false;
  ComputerUseRuntimeLease? _activeLease;
  int get runtimeEpoch => _runtimeEpoch;
  ComputerUseRuntimeLease? get activeLease => _activeLease;
  ComputerUseArmingResult arm({
    required ComputerUseOperationIdentity identity,
    required int runtimeRevision,
    required bool armed,
    required DateTime now,
    required DateTime expiresAt,
  }) {
    if (_globallyTerminated) {
      return _arming(ComputerUseArmingDisposition.globallyTerminated);
    }
    if (_terminatedOwners.contains(identity.owner)) {
      return _arming(ComputerUseArmingDisposition.ownerTerminated);
    }
    RangeError.checkNotNegative(runtimeRevision, 'runtimeRevision');
    final scope = (identity: identity, revision: runtimeRevision);
    if (!armed) {
      final existing = _latestGrants.remove(scope);
      if (existing != null && _grantStates[existing] == _GrantState.armed) {
        _grantStates[existing] = _GrantState.revoked;
      }
      return _arming(ComputerUseArmingDisposition.notArmed);
    }
    if (!expiresAt.isAfter(now)) {
      return _arming(ComputerUseArmingDisposition.expired);
    }

    final existing = _latestGrants[scope];
    if (existing != null && _grantStates[existing] == _GrantState.armed) {
      _grantStates[existing] = _GrantState.superseded;
    }
    final grant = ComputerUseArmingGrant._(
      identity,
      runtimeRevision,
      _runtimeEpoch,
      expiresAt,
    );
    _grantStates[grant] = _GrantState.armed;
    _latestGrants[scope] = grant;
    return _arming(ComputerUseArmingDisposition.granted, grant);
  }

  ComputerUseGrantConsumeResult consumeGrant({
    required ComputerUseArmingGrant? grant,
    required ComputerUseOperationIdentity identity,
    required int runtimeRevision,
    required DateTime now,
  }) {
    if (_globallyTerminated) {
      return _consumption(
        ComputerUseGrantConsumeDisposition.globallyTerminated,
      );
    }
    if (grant == null || !_grantStates.containsKey(grant)) {
      return _consumption(ComputerUseGrantConsumeDisposition.noGrant);
    }
    if (grant.identity != identity) {
      return _consumption(ComputerUseGrantConsumeDisposition.identityMismatch);
    }
    if (_terminatedOwners.contains(identity.owner)) {
      return _consumption(ComputerUseGrantConsumeDisposition.ownerTerminated);
    }
    if (grant.runtimeRevision != runtimeRevision) {
      return _consumption(ComputerUseGrantConsumeDisposition.revisionMismatch);
    }

    final state = _grantStates[grant]!;
    if (grant.runtimeEpoch != _runtimeEpoch) {
      return _consumption(
        ComputerUseGrantConsumeDisposition.runtimeInvalidated,
      );
    }
    if (!now.isBefore(grant.expiresAt) || state == _GrantState.expired) {
      _grantStates[grant] = _GrantState.expired;
      return _consumption(ComputerUseGrantConsumeDisposition.expired);
    }
    final blockedDisposition = switch (state) {
      _GrantState.consumed => ComputerUseGrantConsumeDisposition.replayed,
      _GrantState.revoked => ComputerUseGrantConsumeDisposition.revoked,
      _GrantState.superseded => ComputerUseGrantConsumeDisposition.superseded,
      _GrantState.armed => null,
      _GrantState.expired => ComputerUseGrantConsumeDisposition.expired,
    };
    if (blockedDisposition != null) {
      return _consumption(blockedDisposition);
    }
    _grantStates[grant] = _GrantState.consumed;
    final permit = ComputerUseRuntimePermit._(
      grant.identity,
      grant.runtimeRevision,
      grant.runtimeEpoch,
      grant.expiresAt,
    );
    _permitStates[permit] = _PermitState.ready;
    return _consumption(ComputerUseGrantConsumeDisposition.consumed, permit);
  }

  ComputerUseLeaseAcquisitionResult acquireLease({
    required ComputerUseRuntimePermit? permit,
    required ComputerUseOperationIdentity identity,
    required int currentRuntimeRevision,
    required DateTime now,
  }) {
    if (_globallyTerminated) {
      return _acquisition(
        ComputerUseLeaseAcquisitionDisposition.globallyTerminated,
      );
    }
    if (permit == null || !_permitStates.containsKey(permit)) {
      return _acquisition(ComputerUseLeaseAcquisitionDisposition.noPermit);
    }
    if (permit.identity != identity) {
      return _acquisition(
        ComputerUseLeaseAcquisitionDisposition.identityMismatch,
      );
    }
    if (_terminatedOwners.contains(permit.identity.owner)) {
      return _acquisition(
        ComputerUseLeaseAcquisitionDisposition.ownerTerminated,
      );
    }
    if (permit.runtimeRevision != currentRuntimeRevision) {
      return _acquisition(
        ComputerUseLeaseAcquisitionDisposition.revisionMismatch,
      );
    }
    final state = _permitStates[permit]!;
    if (permit.runtimeEpoch != _runtimeEpoch) {
      return _acquisition(
        ComputerUseLeaseAcquisitionDisposition.runtimeInvalidated,
      );
    }
    if (!now.isBefore(permit.expiresAt) || state == _PermitState.expired) {
      _permitStates[permit] = _PermitState.expired;
      return _acquisition(ComputerUseLeaseAcquisitionDisposition.expired);
    }
    if (state == _PermitState.acquired) {
      return _acquisition(ComputerUseLeaseAcquisitionDisposition.replayed);
    }
    if (_activeLease != null) {
      return _acquisition(ComputerUseLeaseAcquisitionDisposition.busy);
    }
    _permitStates[permit] = _PermitState.acquired;
    final token = ComputerUseRuntimeLeaseToken._(
      _tokenIssuer,
      _nextLeaseSequence++,
    );
    final lease = ComputerUseRuntimeLease._(
      permit.identity,
      permit.runtimeRevision,
      permit.runtimeEpoch,
      token,
    );
    _activeLease = lease;
    return _acquisition(ComputerUseLeaseAcquisitionDisposition.acquired, lease);
  }

  bool discardPermit(ComputerUseRuntimePermit permit) {
    if (_permitStates[permit] != _PermitState.ready) return false;
    _permitStates.remove(permit);
    return true;
  }

  bool isLeaseCurrent(
    ComputerUseOperationIdentity identity,
    int runtimeRevision,
    ComputerUseRuntimeLeaseToken token,
  ) {
    final active = _activeLease;
    return active != null &&
        _isAuthorized(active) &&
        active.identity == identity &&
        active.runtimeRevision == runtimeRevision &&
        active.token == token;
  }

  ComputerUseLeaseReleaseDisposition releaseLease(
    ComputerUseRuntimeLeaseToken token,
  ) {
    final active = _activeLease;
    if (active?.token == token) {
      if (!_isAuthorized(active!)) {
        return ComputerUseLeaseReleaseDisposition.invalidationPending;
      }
      _activeLease = null;
      _settledLeaseTokens.add(token);
      return ComputerUseLeaseReleaseDisposition.released;
    }
    if (_settledLeaseTokens.contains(token)) {
      return ComputerUseLeaseReleaseDisposition.alreadyReleased;
    }
    return active == null
        ? ComputerUseLeaseReleaseDisposition.noActiveLease
        : ComputerUseLeaseReleaseDisposition.staleToken;
  }

  bool settleInvalidatedLease(ComputerUseRuntimeLease lease) {
    if (!identical(_activeLease, lease) || _isAuthorized(lease)) return false;
    _settledLeaseTokens.add(lease.token);
    _activeLease = null;
    return true;
  }

  ComputerUseRuntimeInvalidationResult helperRestarted() =>
      _invalidateRuntime(ComputerUseRuntimeInvalidationCause.helperRestart);

  ComputerUseRuntimeInvalidationResult emergencyStop() =>
      _invalidateRuntime(ComputerUseRuntimeInvalidationCause.emergencyStop);

  ComputerUseTerminalClearResult clearOwner(ChatTurnOwner owner) {
    if (_globallyTerminated) {
      return ComputerUseTerminalClearResult(
        ComputerUseTerminalClearDisposition.globallyTerminated,
        _invalidatedActiveLease(owner: owner),
      );
    }
    if (!_terminatedOwners.add(owner)) {
      return ComputerUseTerminalClearResult(
        ComputerUseTerminalClearDisposition.alreadyCleared,
        _invalidatedActiveLease(owner: owner),
      );
    }
    final invalidatedLease = _invalidatedActiveLease(owner: owner);
    return ComputerUseTerminalClearResult(
      ComputerUseTerminalClearDisposition.cleared,
      invalidatedLease,
    );
  }

  ComputerUseTerminalClearResult clearAll() {
    if (_globallyTerminated) {
      return ComputerUseTerminalClearResult(
        ComputerUseTerminalClearDisposition.alreadyCleared,
        _invalidatedActiveLease(),
      );
    }
    _globallyTerminated = true;
    final invalidatedLease = _invalidatedActiveLease();
    return ComputerUseTerminalClearResult(
      ComputerUseTerminalClearDisposition.cleared,
      invalidatedLease,
    );
  }

  ComputerUseRuntimeInvalidationResult _invalidateRuntime(
    ComputerUseRuntimeInvalidationCause cause,
  ) {
    final previousEpoch = _runtimeEpoch;
    if (_globallyTerminated) {
      return ComputerUseRuntimeInvalidationResult(
        ComputerUseRuntimeInvalidationDisposition.globallyTerminated,
        cause,
        previousEpoch,
        _runtimeEpoch,
        null,
      );
    }
    _runtimeEpoch += 1;
    final invalidatedLease = _invalidatedActiveLease();
    return ComputerUseRuntimeInvalidationResult(
      ComputerUseRuntimeInvalidationDisposition.invalidated,
      cause,
      previousEpoch,
      _runtimeEpoch,
      invalidatedLease,
    );
  }

  bool _isAuthorized(ComputerUseRuntimeLease lease) {
    return !_globallyTerminated &&
        !_terminatedOwners.contains(lease.identity.owner) &&
        lease.runtimeEpoch == _runtimeEpoch;
  }

  ComputerUseRuntimeLease? _invalidatedActiveLease({ChatTurnOwner? owner}) {
    final active = _activeLease;
    if (active == null || (owner != null && active.identity.owner != owner)) {
      return null;
    }
    return active;
  }
}
