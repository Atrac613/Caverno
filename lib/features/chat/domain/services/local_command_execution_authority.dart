import '../entities/chat_turn_owner.dart';
import 'local_command_tool_contract.dart';

/// Opaque proof that one exact local-command effect was admitted.
final class LocalCommandEffectReceipt {
  const LocalCommandEffectReceipt._({
    required this.identity,
    required Object token,
  }) : _token = token;

  final LocalCommandOperationIdentity identity;
  final Object _token;
}

/// Raised when a reserved command loses authority before its actual launch.
final class LocalCommandEffectPermitExpired implements Exception {
  const LocalCommandEffectPermitExpired();

  @override
  String toString() => 'Local command effect permit expired before launch.';
}

/// One-use capability that must wrap the actual process launch callback.
final class LocalCommandEffectPermit {
  LocalCommandEffectPermit._({
    required LocalCommandExecutionAuthority authority,
    required this.identity,
    required Object token,
    required bool Function() ownerIsCurrent,
  }) : _authority = authority,
       _token = token,
       _ownerIsCurrent = ownerIsCurrent;

  final LocalCommandExecutionAuthority _authority;
  final LocalCommandOperationIdentity identity;
  final Object _token;
  final bool Function() _ownerIsCurrent;
  LocalCommandEffectReceipt? _receipt;

  LocalCommandEffectReceipt? get receipt => _receipt;

  /// Consumes this permit immediately before invoking [effect].
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

enum LocalCommandReservationDisposition { reserved, busy, ownerExpired }

final class LocalCommandReservation {
  const LocalCommandReservation._(this.disposition, this.permit);

  const LocalCommandReservation.reserved(LocalCommandEffectPermit permit)
    : this._(LocalCommandReservationDisposition.reserved, permit);

  const LocalCommandReservation.busy()
    : this._(LocalCommandReservationDisposition.busy, null);

  const LocalCommandReservation.ownerExpired()
    : this._(LocalCommandReservationDisposition.ownerExpired, null);

  final LocalCommandReservationDisposition disposition;
  final LocalCommandEffectPermit? permit;
}

final class _LocalCommandRecord {
  _LocalCommandRecord({
    required this.identity,
    required this.token,
    required this.ownerIsCurrent,
  });

  final LocalCommandOperationIdentity identity;
  final Object token;
  final bool Function() ownerIsCurrent;
  LocalCommandEffectReceipt? receipt;
  bool invocationSettled = false;
}

/// Serializes actual command launches and retains uncertain effects.
///
/// The coordinator is intentionally stateful and must outlive individual tool
/// handler calls. Retirement invalidates a delayed permit before it can launch.
final class LocalCommandExecutionAuthority {
  _LocalCommandRecord? _active;
  final Set<ChatTurnOwner> _knownOwners = {};
  final Set<ChatTurnOwner> _terminalOwners = {};

  LocalCommandEffectReceipt? get pendingRecovery => _active?.receipt;

  LocalCommandReservation reserve(
    LocalCommandOperationIdentity identity, {
    required bool Function() ownerIsCurrent,
  }) {
    if (_terminalOwners.contains(identity.owner)) {
      return const LocalCommandReservation.ownerExpired();
    }
    if (_active != null) {
      return const LocalCommandReservation.busy();
    }
    final token = Object();
    final record = _LocalCommandRecord(
      identity: identity,
      token: token,
      ownerIsCurrent: ownerIsCurrent,
    );
    _knownOwners.add(identity.owner);
    _active = record;
    return LocalCommandReservation.reserved(
      LocalCommandEffectPermit._(
        authority: this,
        identity: identity,
        token: token,
        ownerIsCurrent: ownerIsCurrent,
      ),
    );
  }

  bool prepareSettlement(LocalCommandEffectPermit permit) {
    final record = _matchingRecord(permit);
    final receipt = permit.receipt;
    return record != null &&
        receipt != null &&
        _matchesReceipt(record, receipt) &&
        record.invocationSettled &&
        !_terminalOwners.contains(record.identity.owner) &&
        _safeOwnerCheck(record.ownerIsCurrent);
  }

  bool accept(LocalCommandEffectPermit permit) {
    final record = _matchingRecord(permit);
    if (record == null ||
        !prepareSettlement(permit) ||
        permit.receipt == null ||
        !_matchesReceipt(record, permit.receipt!)) {
      return false;
    }
    _active = null;
    return true;
  }

  bool abandonBeforeEffect(LocalCommandEffectPermit permit) {
    final record = _matchingRecord(permit);
    if (record == null || record.receipt != null) return false;
    _active = null;
    return true;
  }

  bool clearEffectRecovery(LocalCommandEffectReceipt receipt) {
    final record = _active;
    if (record == null ||
        !_matchesReceipt(record, receipt) ||
        !record.invocationSettled) {
      return false;
    }
    _active = null;
    return true;
  }

  LocalCommandEffectReceipt? retainUncertainDispatch(
    LocalCommandEffectPermit permit,
  ) {
    final record = _matchingRecord(permit);
    if (record == null) return null;
    final existing = record.receipt;
    if (existing != null) return existing;
    final receipt = LocalCommandEffectReceipt._(
      identity: record.identity,
      token: record.token,
    );
    record
      ..receipt = receipt
      ..invocationSettled = true;
    permit._receipt = receipt;
    return receipt;
  }

  LocalCommandEffectReceipt? clearOwner(ChatTurnOwner owner) {
    _terminalOwners.add(owner);
    final record = _active;
    if (record?.identity.owner != owner) return null;
    if (record!.receipt == null) {
      _active = null;
      return null;
    }
    return record.receipt;
  }

  LocalCommandEffectReceipt? clearAll() {
    _terminalOwners.addAll(_knownOwners);
    final record = _active;
    if (record == null) return null;
    if (record.receipt == null) {
      _active = null;
      return null;
    }
    return record.receipt;
  }

  LocalCommandEffectReceipt _begin(LocalCommandEffectPermit permit) {
    final record = _matchingRecord(permit);
    if (record == null ||
        record.receipt != null ||
        _terminalOwners.contains(record.identity.owner) ||
        !_safeOwnerCheck(permit._ownerIsCurrent)) {
      if (record != null && record.receipt == null) {
        _active = null;
      }
      throw const LocalCommandEffectPermitExpired();
    }
    final receipt = LocalCommandEffectReceipt._(
      identity: record.identity,
      token: record.token,
    );
    record.receipt = receipt;
    return receipt;
  }

  void _markInvocationSettled(LocalCommandEffectReceipt receipt) {
    final record = _active;
    if (record != null && _matchesReceipt(record, receipt)) {
      record.invocationSettled = true;
    }
  }

  _LocalCommandRecord? _matchingRecord(LocalCommandEffectPermit permit) {
    final record = _active;
    return record != null &&
            identical(permit._authority, this) &&
            record.identity == permit.identity &&
            identical(record.token, permit._token)
        ? record
        : null;
  }

  bool _matchesReceipt(
    _LocalCommandRecord record,
    LocalCommandEffectReceipt receipt,
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
