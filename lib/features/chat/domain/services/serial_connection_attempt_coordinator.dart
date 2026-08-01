import '../entities/chat_turn_owner.dart';
import 'serial_connection_tool_contract.dart';

// ChatNotifier decomposition collaborator: serial-connection-attempt-coordinator

/// Immutable identity for one exact serial open operation.
final class SerialConnectionAttemptIdentity {
  SerialConnectionAttemptIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String portName,
    required this.options,
  }) : toolCallId = _requiredValue(toolCallId, 'toolCallId'),
       toolName = _requiredValue(toolName, 'toolName'),
       portName = _requiredValue(portName, 'portName');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String portName;
  final SerialConnectionOptions options;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SerialConnectionAttemptIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.portName == portName &&
            other.options == options;
  }

  @override
  int get hashCode {
    return Object.hash(owner, toolCallId, toolName, portName, options);
  }

  static String _requiredValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, '$name must not be empty.');
    }
    return normalized;
  }
}

/// Registry-local, non-forgeable token for one per-port attempt lease.
final class SerialConnectionAttemptToken {
  const SerialConnectionAttemptToken._(this.epoch);

  final int epoch;
}

/// Exclusive lease held from before open until commit or rollback completes.
final class SerialConnectionAttemptLease {
  const SerialConnectionAttemptLease._({
    required this.identity,
    required this.token,
  });

  final SerialConnectionAttemptIdentity identity;
  final SerialConnectionAttemptToken token;
}

enum SerialConnectionAttemptAcquisitionKind { acquired, busy, ownerRetired }

final class SerialConnectionAttemptAcquisition {
  const SerialConnectionAttemptAcquisition.acquired(
    SerialConnectionAttemptLease this.lease,
  ) : kind = SerialConnectionAttemptAcquisitionKind.acquired;

  const SerialConnectionAttemptAcquisition.busy()
    : kind = SerialConnectionAttemptAcquisitionKind.busy,
      lease = null;

  const SerialConnectionAttemptAcquisition.ownerRetired()
    : kind = SerialConnectionAttemptAcquisitionKind.ownerRetired,
      lease = null;

  final SerialConnectionAttemptAcquisitionKind kind;
  final SerialConnectionAttemptLease? lease;
}

enum SerialConnectionBeginOpenKind { begun, ownerRetired, rejected }

/// Exact evidence that this attempt created one observable serial session.
final class SerialConnectionOpenedReceipt {
  const SerialConnectionOpenedReceipt._({
    required this.identity,
    required this.token,
    required this.sessionFingerprint,
  });

  final SerialConnectionAttemptIdentity identity;
  final SerialConnectionAttemptToken token;
  final String sessionFingerprint;
}

enum SerialConnectionMarkOpenedKind {
  openedCurrent,
  rollbackRequired,
  rejected,
}

final class SerialConnectionMarkOpenedResult {
  const SerialConnectionMarkOpenedResult._(this.kind, this.receipt);

  const SerialConnectionMarkOpenedResult.openedCurrent(
    SerialConnectionOpenedReceipt receipt,
  ) : this._(SerialConnectionMarkOpenedKind.openedCurrent, receipt);

  const SerialConnectionMarkOpenedResult.rollbackRequired(
    SerialConnectionOpenedReceipt receipt,
  ) : this._(SerialConnectionMarkOpenedKind.rollbackRequired, receipt);

  const SerialConnectionMarkOpenedResult.rejected()
    : this._(SerialConnectionMarkOpenedKind.rejected, null);

  final SerialConnectionMarkOpenedKind kind;
  final SerialConnectionOpenedReceipt? receipt;
}

enum SerialConnectionCommitKind { committed, rollbackRequired, rejected }

/// Non-forgeable authorization for one exact rollback attempt.
final class SerialConnectionRollbackPermit {
  const SerialConnectionRollbackPermit._({
    required this.receipt,
    required this.epoch,
  });

  final SerialConnectionOpenedReceipt receipt;
  final int epoch;
}

enum SerialConnectionRollbackBeginKind {
  begun,
  ownerCurrent,
  sessionMismatch,
  rejected,
}

final class SerialConnectionRollbackBeginResult {
  const SerialConnectionRollbackBeginResult._(this.kind, this.permit);

  const SerialConnectionRollbackBeginResult.begun(
    SerialConnectionRollbackPermit permit,
  ) : this._(SerialConnectionRollbackBeginKind.begun, permit);

  const SerialConnectionRollbackBeginResult.ownerCurrent()
    : this._(SerialConnectionRollbackBeginKind.ownerCurrent, null);

  const SerialConnectionRollbackBeginResult.sessionMismatch()
    : this._(SerialConnectionRollbackBeginKind.sessionMismatch, null);

  const SerialConnectionRollbackBeginResult.rejected()
    : this._(SerialConnectionRollbackBeginKind.rejected, null);

  final SerialConnectionRollbackBeginKind kind;
  final SerialConnectionRollbackPermit? permit;
}

enum SerialConnectionRollbackFinishKind { released, retryRequired, rejected }

/// Immutable work retained when one or more owners become terminal.
final class SerialConnectionRetirementResult {
  SerialConnectionRetirementResult({
    required Iterable<SerialConnectionAttemptLease> opensInFlight,
    required Iterable<SerialConnectionOpenedReceipt> rollbackRequired,
  }) : opensInFlight = List<SerialConnectionAttemptLease>.unmodifiable(
         opensInFlight,
       ),
       rollbackRequired = List<SerialConnectionOpenedReceipt>.unmodifiable(
         rollbackRequired,
       );

  final List<SerialConnectionAttemptLease> opensInFlight;
  final List<SerialConnectionOpenedReceipt> rollbackRequired;

  bool get isEmpty => opensInFlight.isEmpty && rollbackRequired.isEmpty;
}

/// Coordinates serial open attempts without owning any transport or UI object.
final class SerialConnectionAttemptCoordinator {
  final Map<String, _SerialConnectionAttemptState> _attemptsByPort = {};
  final Set<ChatTurnOwner> _knownOwners = {};
  final Set<ChatTurnOwner> _retiredOwners = {};
  int _lastAttemptEpoch = 0;
  int _lastRollbackEpoch = 0;

  /// Exact opened attempts that still require conditional cleanup.
  List<SerialConnectionOpenedReceipt> get pendingCleanupReceipts {
    return List<SerialConnectionOpenedReceipt>.unmodifiable(
      _attemptsByPort.values
          .where(
            (state) =>
                state.phase == _SerialConnectionAttemptPhase.opened ||
                state.phase == _SerialConnectionAttemptPhase.rollingBack,
          )
          .map((state) => state.receipt!),
    );
  }

  /// Retired launches whose effect must be reconciled before the port is free.
  List<SerialConnectionAttemptLease> get pendingEffectLeases {
    return List<SerialConnectionAttemptLease>.unmodifiable(
      _attemptsByPort.values
          .where(
            (state) =>
                state.phase == _SerialConnectionAttemptPhase.opening &&
                _retiredOwners.contains(state.identity.owner),
          )
          .map((state) => state.lease),
    );
  }

  /// Acquires an exclusive lease for [identity]'s exact port.
  SerialConnectionAttemptAcquisition acquire(
    SerialConnectionAttemptIdentity identity,
  ) {
    if (_retiredOwners.contains(identity.owner)) {
      return const SerialConnectionAttemptAcquisition.ownerRetired();
    }
    if (_attemptsByPort.containsKey(identity.portName)) {
      return const SerialConnectionAttemptAcquisition.busy();
    }

    final token = SerialConnectionAttemptToken._(++_lastAttemptEpoch);
    final lease = SerialConnectionAttemptLease._(
      identity: identity,
      token: token,
    );
    _knownOwners.add(identity.owner);
    _attemptsByPort[identity.portName] = _SerialConnectionAttemptState(
      lease: lease,
    );
    return SerialConnectionAttemptAcquisition.acquired(lease);
  }

  /// Converts a reservation into permission to launch the transport open.
  SerialConnectionBeginOpenKind beginOpen(
    SerialConnectionAttemptIdentity identity,
    SerialConnectionAttemptToken token,
  ) {
    final state = _stateFor(identity, token);
    if (state == null) {
      return _retiredOwners.contains(identity.owner)
          ? SerialConnectionBeginOpenKind.ownerRetired
          : SerialConnectionBeginOpenKind.rejected;
    }
    if (state.phase != _SerialConnectionAttemptPhase.reserved) {
      return SerialConnectionBeginOpenKind.rejected;
    }
    if (_retiredOwners.contains(identity.owner)) {
      _remove(state);
      return SerialConnectionBeginOpenKind.ownerRetired;
    }
    state.phase = _SerialConnectionAttemptPhase.opening;
    return SerialConnectionBeginOpenKind.begun;
  }

  /// Records that the leased open created the observed serial session.
  SerialConnectionMarkOpenedResult markOpened(
    SerialConnectionAttemptIdentity identity,
    SerialConnectionAttemptToken token, {
    required String sessionFingerprint,
  }) {
    final state = _stateFor(identity, token);
    if (state == null || state.phase != _SerialConnectionAttemptPhase.opening) {
      return const SerialConnectionMarkOpenedResult.rejected();
    }
    final fingerprint = _requiredFingerprint(sessionFingerprint);
    final receipt = SerialConnectionOpenedReceipt._(
      identity: identity,
      token: token,
      sessionFingerprint: fingerprint,
    );
    state.receipt = receipt;
    state.phase = _SerialConnectionAttemptPhase.opened;
    return _retiredOwners.contains(identity.owner)
        ? SerialConnectionMarkOpenedResult.rollbackRequired(receipt)
        : SerialConnectionMarkOpenedResult.openedCurrent(receipt);
  }

  /// Commits a current owner's successful open and releases its lease.
  SerialConnectionCommitKind finishCurrent(
    SerialConnectionOpenedReceipt receipt,
  ) {
    final state = _stateForReceipt(receipt);
    if (state == null || state.phase != _SerialConnectionAttemptPhase.opened) {
      return SerialConnectionCommitKind.rejected;
    }
    if (_retiredOwners.contains(receipt.identity.owner) ||
        state.rollbackRequired) {
      return SerialConnectionCommitKind.rollbackRequired;
    }
    _remove(state);
    return SerialConnectionCommitKind.committed;
  }

  /// Marks only [receipt]'s exact opened session for compensating rollback.
  bool requireRollback(SerialConnectionOpenedReceipt receipt) {
    final state = _stateForReceipt(receipt);
    if (state == null || state.phase != _SerialConnectionAttemptPhase.opened) {
      return false;
    }
    state.rollbackRequired = true;
    return true;
  }

  /// Begins rollback only for the exact retired attempt and observed session.
  SerialConnectionRollbackBeginResult beginRollback(
    SerialConnectionOpenedReceipt receipt, {
    required String observedSessionFingerprint,
  }) {
    final state = _stateForReceipt(receipt);
    if (state == null || state.phase != _SerialConnectionAttemptPhase.opened) {
      return const SerialConnectionRollbackBeginResult.rejected();
    }
    if (!_retiredOwners.contains(receipt.identity.owner) &&
        !state.rollbackRequired) {
      return const SerialConnectionRollbackBeginResult.ownerCurrent();
    }
    if (_requiredFingerprint(observedSessionFingerprint) !=
        receipt.sessionFingerprint) {
      return const SerialConnectionRollbackBeginResult.sessionMismatch();
    }

    final permit = SerialConnectionRollbackPermit._(
      receipt: receipt,
      epoch: ++_lastRollbackEpoch,
    );
    state.rollback = permit;
    state.phase = _SerialConnectionAttemptPhase.rollingBack;
    return SerialConnectionRollbackBeginResult.begun(permit);
  }

  /// Completes one exact rollback, retaining the lease when it must be retried.
  SerialConnectionRollbackFinishKind finishRollback(
    SerialConnectionRollbackPermit permit, {
    required bool succeeded,
  }) {
    final state = _stateForReceipt(permit.receipt);
    if (state == null || !identical(state.rollback, permit)) {
      return SerialConnectionRollbackFinishKind.rejected;
    }
    if (!succeeded) {
      state.rollback = null;
      state.phase = _SerialConnectionAttemptPhase.opened;
      return SerialConnectionRollbackFinishKind.retryRequired;
    }
    _remove(state);
    return SerialConnectionRollbackFinishKind.released;
  }

  /// Releases an opening lease after the adapter proves no session was created.
  bool releaseNoEffect(
    SerialConnectionAttemptIdentity identity,
    SerialConnectionAttemptToken token,
  ) {
    final state = _stateFor(identity, token);
    if (state == null ||
        (state.phase != _SerialConnectionAttemptPhase.reserved &&
            state.phase != _SerialConnectionAttemptPhase.opening)) {
      return false;
    }
    _remove(state);
    return true;
  }

  /// Retires [owner], removing reservations and retaining launched work.
  SerialConnectionRetirementResult clearOwner(ChatTurnOwner owner) {
    _knownOwners.add(owner);
    _retiredOwners.add(owner);
    return _retireAttempts((state) => state.identity.owner == owner);
  }

  /// Retires every observed owner, removing only unlaunched reservations.
  SerialConnectionRetirementResult clearAll() {
    _retiredOwners.addAll(_knownOwners);
    return _retireAttempts((_) => true);
  }

  SerialConnectionRetirementResult _retireAttempts(
    bool Function(_SerialConnectionAttemptState state) selects,
  ) {
    final opensInFlight = <SerialConnectionAttemptLease>[];
    final rollbackRequired = <SerialConnectionOpenedReceipt>[];
    for (final state in _attemptsByPort.values.toList()) {
      if (!selects(state)) continue;
      switch (state.phase) {
        case _SerialConnectionAttemptPhase.reserved:
          _remove(state);
          break;
        case _SerialConnectionAttemptPhase.opening:
          opensInFlight.add(state.lease);
          break;
        case _SerialConnectionAttemptPhase.opened:
        case _SerialConnectionAttemptPhase.rollingBack:
          rollbackRequired.add(state.receipt!);
          break;
      }
    }
    return SerialConnectionRetirementResult(
      opensInFlight: opensInFlight,
      rollbackRequired: rollbackRequired,
    );
  }

  _SerialConnectionAttemptState? _stateFor(
    SerialConnectionAttemptIdentity identity,
    SerialConnectionAttemptToken token,
  ) {
    final state = _attemptsByPort[identity.portName];
    return state != null &&
            state.identity == identity &&
            identical(state.token, token)
        ? state
        : null;
  }

  _SerialConnectionAttemptState? _stateForReceipt(
    SerialConnectionOpenedReceipt receipt,
  ) {
    final state = _stateFor(receipt.identity, receipt.token);
    return state != null && identical(state.receipt, receipt) ? state : null;
  }

  void _remove(_SerialConnectionAttemptState state) {
    if (identical(_attemptsByPort[state.identity.portName], state)) {
      _attemptsByPort.remove(state.identity.portName);
    }
  }

  String _requiredFingerprint(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'sessionFingerprint',
        'sessionFingerprint must not be empty.',
      );
    }
    return normalized;
  }
}

enum _SerialConnectionAttemptPhase { reserved, opening, opened, rollingBack }

final class _SerialConnectionAttemptState {
  _SerialConnectionAttemptState({required this.lease});

  final SerialConnectionAttemptLease lease;
  _SerialConnectionAttemptPhase phase = _SerialConnectionAttemptPhase.reserved;
  SerialConnectionOpenedReceipt? receipt;
  SerialConnectionRollbackPermit? rollback;
  bool rollbackRequired = false;

  SerialConnectionAttemptIdentity get identity => lease.identity;
  SerialConnectionAttemptToken get token => lease.token;
}
