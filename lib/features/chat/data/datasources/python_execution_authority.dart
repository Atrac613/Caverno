import '../../domain/entities/chat_turn_owner.dart';

/// Opaque proof that one exact Python execution crossed the effect boundary.
final class PythonExecutionRecoveryReceipt<I> {
  const PythonExecutionRecoveryReceipt._({
    required this.identity,
    required Object token,
  }) : _token = token;

  final I identity;
  final Object _token;
}

/// Raised when a reserved Python execution loses authority before launch.
final class PythonExecutionEffectPermitExpired implements Exception {
  const PythonExecutionEffectPermitExpired();

  @override
  String toString() => 'Python execution effect permit expired before launch.';
}

/// A one-use capability that must wrap the actual Python process effect.
final class PythonExecutionEffectPermit<I> {
  PythonExecutionEffectPermit._({
    required PythonExecutionAuthority<I> authority,
    required this.identity,
    required Object token,
  }) : _authority = authority,
       _token = token;

  final PythonExecutionAuthority<I> _authority;
  final I identity;
  final Object _token;
  PythonExecutionRecoveryReceipt<I>? _receipt;

  PythonExecutionRecoveryReceipt<I>? get receipt => _receipt;

  /// Revalidates lifecycle ownership immediately before invoking [effect].
  Future<T> runEffect<T>(Future<T> Function() effect) async {
    final receipt = _authority._begin(this);
    _receipt = receipt;
    try {
      return await effect();
    } finally {
      _authority._markInvocationSettled(receipt);
    }
  }
}

enum PythonExecutionReservationDisposition { reserved, busy, ownerExpired }

final class PythonExecutionReservation<I> {
  const PythonExecutionReservation._(this.disposition, this.permit);

  const PythonExecutionReservation.reserved(
    PythonExecutionEffectPermit<I> permit,
  ) : this._(PythonExecutionReservationDisposition.reserved, permit);

  const PythonExecutionReservation.busy()
    : this._(PythonExecutionReservationDisposition.busy, null);

  const PythonExecutionReservation.ownerExpired()
    : this._(PythonExecutionReservationDisposition.ownerExpired, null);

  final PythonExecutionReservationDisposition disposition;
  final PythonExecutionEffectPermit<I>? permit;
}

final class _PythonExecutionRecord<I> {
  _PythonExecutionRecord({
    required this.owner,
    required this.identity,
    required this.token,
    required this.ownerIsCurrent,
  });

  final ChatTurnOwner owner;
  final I identity;
  final Object token;
  final bool Function() ownerIsCurrent;
  PythonExecutionRecoveryReceipt<I>? receipt;
  bool invocationSettled = false;
  bool executionAcknowledged = false;
  bool cleanupAcknowledged = false;
  bool releasePrepared = false;
  bool recoveryRequired = false;
}

/// Serializes Python effects and retains ambiguous executions for recovery.
///
/// One stable instance must outlive individual tool handler calls. The permit
/// is consumed at the raw launch boundary, while the record remains fenced
/// through staging cleanup and the final result-cache acknowledgement.
final class PythonExecutionAuthority<I> {
  _PythonExecutionRecord<I>? _active;
  final Set<ChatTurnOwner> _knownOwners = {};
  final Set<ChatTurnOwner> _terminalOwners = {};

  PythonExecutionRecoveryReceipt<I>? get pendingRecovery {
    final record = _active;
    return record?.recoveryRequired == true ? record!.receipt : null;
  }

  PythonExecutionReservation<I> reserve({
    required ChatTurnOwner owner,
    required I identity,
    required bool Function() ownerIsCurrent,
  }) {
    if (_terminalOwners.contains(owner)) {
      return const PythonExecutionReservation.ownerExpired();
    }
    if (_active != null) {
      return const PythonExecutionReservation.busy();
    }
    final token = Object();
    _active = _PythonExecutionRecord<I>(
      owner: owner,
      identity: identity,
      token: token,
      ownerIsCurrent: ownerIsCurrent,
    );
    _knownOwners.add(owner);
    return PythonExecutionReservation.reserved(
      PythonExecutionEffectPermit<I>._(
        authority: this,
        identity: identity,
        token: token,
      ),
    );
  }

  bool acknowledgeExecution(PythonExecutionEffectPermit<I> permit) {
    final record = _matchingRecord(permit);
    final receipt = permit.receipt;
    if (record == null ||
        receipt == null ||
        !_matchesReceipt(record, receipt) ||
        !record.invocationSettled ||
        record.recoveryRequired) {
      return false;
    }
    record.executionAcknowledged = true;
    return true;
  }

  bool acknowledgeCleanup(PythonExecutionEffectPermit<I> permit) {
    final record = _matchingRecord(permit);
    if (record == null ||
        !record.executionAcknowledged ||
        record.recoveryRequired) {
      return false;
    }
    record.cleanupAcknowledged = true;
    return true;
  }

  /// Freezes exact preconditions before a final cache acknowledgement.
  bool prepareRelease(PythonExecutionEffectPermit<I> permit) {
    final record = _matchingRecord(permit);
    if (record == null ||
        !record.invocationSettled ||
        !record.executionAcknowledged ||
        !record.cleanupAcknowledged ||
        record.recoveryRequired ||
        _terminalOwners.contains(record.owner) ||
        !_safeOwnerCheck(record.ownerIsCurrent)) {
      return false;
    }
    record.releasePrepared = true;
    return true;
  }

  /// Releases only the exact record that passed [prepareRelease].
  bool release(PythonExecutionEffectPermit<I> permit) {
    final record = _matchingRecord(permit);
    if (record == null ||
        !record.releasePrepared ||
        record.recoveryRequired ||
        _terminalOwners.contains(record.owner) ||
        !_safeOwnerCheck(record.ownerIsCurrent)) {
      return false;
    }
    _active = null;
    return true;
  }

  bool abandonBeforeEffect(PythonExecutionEffectPermit<I> permit) {
    final record = _matchingRecord(permit);
    if (record == null || record.receipt != null) return false;
    _active = null;
    return true;
  }

  PythonExecutionRecoveryReceipt<I>? retainRecovery(
    PythonExecutionEffectPermit<I> permit,
  ) {
    final record = _matchingRecord(permit);
    if (record == null) return null;
    final hadReceipt = record.receipt != null;
    final receipt =
        record.receipt ??
        PythonExecutionRecoveryReceipt<I>._(
          identity: record.identity,
          token: record.token,
        );
    record
      ..receipt = receipt
      ..releasePrepared = false
      ..recoveryRequired = true;
    if (!hadReceipt) {
      record.invocationSettled = true;
    }
    permit._receipt = receipt;
    return receipt;
  }

  /// Clears a receipt after read-only reconciliation confirms its identity.
  bool reconcileRecovery({
    required PythonExecutionRecoveryReceipt<I> receipt,
    required I observedIdentity,
  }) {
    final record = _active;
    if (record == null ||
        record.identity != observedIdentity ||
        !_matchesReceipt(record, receipt) ||
        !record.recoveryRequired ||
        !record.invocationSettled) {
      return false;
    }
    _active = null;
    return true;
  }

  /// Explicitly clears one exact opaque recovery receipt.
  bool clearRecovery(PythonExecutionRecoveryReceipt<I> receipt) {
    final record = _active;
    if (record == null ||
        !_matchesReceipt(record, receipt) ||
        !record.recoveryRequired ||
        !record.invocationSettled) {
      return false;
    }
    _active = null;
    return true;
  }

  PythonExecutionRecoveryReceipt<I>? clearOwner(ChatTurnOwner owner) {
    _terminalOwners.add(owner);
    final record = _active;
    if (record?.owner != owner) return null;
    final receipt = record!.receipt;
    if (receipt == null) {
      return null;
    }
    record
      ..releasePrepared = false
      ..recoveryRequired = true;
    return receipt;
  }

  PythonExecutionRecoveryReceipt<I>? clearAll() {
    _terminalOwners.addAll(_knownOwners);
    final record = _active;
    if (record == null) return null;
    final receipt = record.receipt;
    if (receipt == null) {
      return null;
    }
    record
      ..releasePrepared = false
      ..recoveryRequired = true;
    return receipt;
  }

  PythonExecutionRecoveryReceipt<I> _begin(
    PythonExecutionEffectPermit<I> permit,
  ) {
    final record = _matchingRecord(permit);
    if (record == null ||
        record.receipt != null ||
        _terminalOwners.contains(record.owner) ||
        !_safeOwnerCheck(record.ownerIsCurrent)) {
      throw const PythonExecutionEffectPermitExpired();
    }
    final receipt = PythonExecutionRecoveryReceipt<I>._(
      identity: record.identity,
      token: record.token,
    );
    record.receipt = receipt;
    return receipt;
  }

  void _markInvocationSettled(PythonExecutionRecoveryReceipt<I> receipt) {
    final record = _active;
    if (record != null && _matchesReceipt(record, receipt)) {
      record.invocationSettled = true;
    }
  }

  _PythonExecutionRecord<I>? _matchingRecord(
    PythonExecutionEffectPermit<I> permit,
  ) {
    final record = _active;
    return record != null &&
            identical(permit._authority, this) &&
            record.identity == permit.identity &&
            identical(record.token, permit._token)
        ? record
        : null;
  }

  bool _matchesReceipt(
    _PythonExecutionRecord<I> record,
    PythonExecutionRecoveryReceipt<I> receipt,
  ) {
    return record.identity == receipt.identity &&
        identical(record.token, receipt._token) &&
        identical(record.receipt, receipt);
  }

  bool _safeOwnerCheck(bool Function() ownerIsCurrent) {
    try {
      return ownerIsCurrent();
    } catch (_) {
      return false;
    }
  }
}
