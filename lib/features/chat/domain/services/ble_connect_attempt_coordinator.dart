import 'dart:async';

import '../../../../core/services/ble_connection_effect_port.dart';
import '../entities/chat_turn_owner.dart';

enum BleConnectAttemptOutcomeKind { connected, ownerExpired, failed }

class BleConnectAttemptOutcome {
  const BleConnectAttemptOutcome._(
    this.kind, {
    this.error,
    this.effectUncertain = false,
    this.recoveryReceipt,
  });

  const BleConnectAttemptOutcome.connected()
    : this._(BleConnectAttemptOutcomeKind.connected);

  const BleConnectAttemptOutcome.ownerExpired()
    : this._(BleConnectAttemptOutcomeKind.ownerExpired);

  const BleConnectAttemptOutcome.failed(Object error)
    : this._(BleConnectAttemptOutcomeKind.failed, error: error);

  const BleConnectAttemptOutcome.effectUncertain({
    required Object error,
    BleConnectRecoveryReceipt? recoveryReceipt,
  }) : this._(
         BleConnectAttemptOutcomeKind.failed,
         error: error,
         effectUncertain: true,
         recoveryReceipt: recoveryReceipt,
       );

  final BleConnectAttemptOutcomeKind kind;
  final Object? error;
  final bool effectUncertain;
  final BleConnectRecoveryReceipt? recoveryReceipt;
}

enum BleConnectRecoveryReason {
  postConnectStateUnknown,
  disconnectFailed,
  postDisconnectStateUnknown,
  disconnectDidNotSettle,
  attemptOwnershipLost,
}

/// Opaque identity for one BLE connection that still needs reconciliation.
final class BleConnectRecoveryReceipt {
  const BleConnectRecoveryReceipt._({
    required this.owner,
    required this.deviceId,
    required this.reason,
    required this.error,
    required Object token,
  }) : _token = token;

  final ChatTurnOwner owner;
  final String deviceId;
  final BleConnectRecoveryReason reason;
  final Object error;
  final Object _token;
}

enum BleConnectRecoveryDisposition { reconciled, staleReceipt, effectUncertain }

final class BleConnectRecoveryOutcome {
  const BleConnectRecoveryOutcome._({
    required this.disposition,
    this.receipt,
    this.error,
  });

  const BleConnectRecoveryOutcome.reconciled()
    : this._(disposition: BleConnectRecoveryDisposition.reconciled);

  const BleConnectRecoveryOutcome.staleReceipt()
    : this._(disposition: BleConnectRecoveryDisposition.staleReceipt);

  const BleConnectRecoveryOutcome.effectUncertain({
    required BleConnectRecoveryReceipt receipt,
    required Object error,
  }) : this._(
         disposition: BleConnectRecoveryDisposition.effectUncertain,
         receipt: receipt,
         error: error,
       );

  final BleConnectRecoveryDisposition disposition;
  final BleConnectRecoveryReceipt? receipt;
  final Object? error;
}

final class BleConnectAttemptCoordinator {
  final Map<String, Future<void>> _tails = {};
  final Map<String, _BleConnectAttempt> _activeAttempts = {};
  final Map<String, BleConnectRecoveryReceipt> _pendingRecoveries = {};

  BleConnectRecoveryReceipt? pendingRecoveryForDevice(String deviceId) {
    return _pendingRecoveries[deviceId];
  }

  Future<BleConnectAttemptOutcome> connect({
    required ChatTurnOwner owner,
    required String deviceId,
    required BleConnectionEffectPort service,
    required bool Function(ChatTurnOwner owner) ownerIsCurrent,
    required void Function(Object error) onRollbackError,
  }) {
    return _serialized(deviceId, () async {
      final pendingRecovery = _pendingRecoveries[deviceId];
      if (pendingRecovery != null) {
        return BleConnectAttemptOutcome.effectUncertain(
          error: StateError(
            'BLE connection recovery is pending for $deviceId.',
          ),
          recoveryReceipt: pendingRecovery,
        );
      }

      final attempt = _BleConnectAttempt(
        owner: owner,
        token: Object(),
        deviceId: deviceId,
      );
      _activeAttempts[deviceId] = attempt;
      try {
        if (!ownerIsCurrent(owner)) {
          return const BleConnectAttemptOutcome.ownerExpired();
        }
        final _BleConnectionState connectionBeforeAttempt;
        try {
          connectionBeforeAttempt = _readConnectionState(service, deviceId);
        } catch (error) {
          return BleConnectAttemptOutcome.failed(error);
        }
        final connectionPredatedAttempt =
            connectionBeforeAttempt == _BleConnectionState.connected;
        try {
          await service.connect(deviceId);
        } catch (error) {
          if (!ownerIsCurrent(owner)) {
            return connectionPredatedAttempt
                ? const BleConnectAttemptOutcome.ownerExpired()
                : _rollbackExpiredAttempt(
                    attempt: attempt,
                    service: service,
                    onRollbackError: onRollbackError,
                  );
          }
          return _recoverCurrentOwnerThrow(
            attempt: attempt,
            service: service,
            connectionPredatedAttempt: connectionPredatedAttempt,
            connectError: error,
            onRollbackError: onRollbackError,
          );
        }
        if (!ownerIsCurrent(owner)) {
          return connectionPredatedAttempt
              ? const BleConnectAttemptOutcome.ownerExpired()
              : _rollbackExpiredAttempt(
                  attempt: attempt,
                  service: service,
                  onRollbackError: onRollbackError,
                );
        }
        return const BleConnectAttemptOutcome.connected();
      } finally {
        if (_owns(attempt)) {
          _activeAttempts.remove(deviceId);
        }
      }
    });
  }

  Future<BleConnectRecoveryOutcome> reconcileRecovery({
    required BleConnectRecoveryReceipt receipt,
    required BleConnectionEffectPort service,
    required void Function(Object error) onRollbackError,
  }) {
    return _serialized(receipt.deviceId, () async {
      if (!_matchesPending(receipt)) {
        return const BleConnectRecoveryOutcome.staleReceipt();
      }
      try {
        final state = _readConnectionState(service, receipt.deviceId);
        if (state == _BleConnectionState.disconnected) {
          _pendingRecoveries.remove(receipt.deviceId);
          return const BleConnectRecoveryOutcome.reconciled();
        }
      } catch (error) {
        final retained = _retainRecovery(
          receipt: receipt,
          reason: BleConnectRecoveryReason.postConnectStateUnknown,
          error: error,
        );
        return BleConnectRecoveryOutcome.effectUncertain(
          receipt: retained,
          error: error,
        );
      }

      final disconnectError = await _disconnect(
        receipt.deviceId,
        service,
        onRollbackError,
      );
      if (disconnectError != null) {
        final retained = _retainRecovery(
          receipt: receipt,
          reason: BleConnectRecoveryReason.disconnectFailed,
          error: disconnectError,
        );
        return BleConnectRecoveryOutcome.effectUncertain(
          receipt: retained,
          error: disconnectError,
        );
      }
      return _settleRecoveryAfterDisconnect(receipt, service);
    });
  }

  Future<bool> clearRecovery(BleConnectRecoveryReceipt receipt) {
    return _serialized(receipt.deviceId, () async {
      if (!_matchesPending(receipt)) return false;
      _pendingRecoveries.remove(receipt.deviceId);
      return true;
    });
  }

  bool _owns(_BleConnectAttempt attempt) {
    final active = _activeAttempts[attempt.deviceId];
    return active?.owner == attempt.owner &&
        identical(active?.token, attempt.token);
  }

  Future<BleConnectAttemptOutcome> _recoverCurrentOwnerThrow({
    required _BleConnectAttempt attempt,
    required BleConnectionEffectPort service,
    required bool connectionPredatedAttempt,
    required Object connectError,
    required void Function(Object error) onRollbackError,
  }) async {
    final _BleConnectionState stateAfterThrow;
    try {
      stateAfterThrow = _readConnectionState(service, attempt.deviceId);
    } catch (error) {
      final receipt = _retainAttemptRecovery(
        attempt: attempt,
        reason: BleConnectRecoveryReason.postConnectStateUnknown,
        error: error,
      );
      return BleConnectAttemptOutcome.effectUncertain(
        error: connectError,
        recoveryReceipt: receipt,
      );
    }
    if (connectionPredatedAttempt ||
        stateAfterThrow == _BleConnectionState.disconnected) {
      return BleConnectAttemptOutcome.failed(connectError);
    }
    if (!_owns(attempt)) {
      final ownershipError = StateError(
        'BLE connection attempt ownership changed before compensation.',
      );
      final receipt = _retainAttemptRecovery(
        attempt: attempt,
        reason: BleConnectRecoveryReason.attemptOwnershipLost,
        error: ownershipError,
      );
      return BleConnectAttemptOutcome.effectUncertain(
        error: connectError,
        recoveryReceipt: receipt,
      );
    }

    final disconnectError = await _disconnect(
      attempt.deviceId,
      service,
      onRollbackError,
    );
    if (disconnectError != null) {
      final receipt = _retainAttemptRecovery(
        attempt: attempt,
        reason: BleConnectRecoveryReason.disconnectFailed,
        error: disconnectError,
      );
      return BleConnectAttemptOutcome.effectUncertain(
        error: connectError,
        recoveryReceipt: receipt,
      );
    }
    final settlement = _settleAttemptAfterDisconnect(attempt, service);
    return BleConnectAttemptOutcome.effectUncertain(
      error: connectError,
      recoveryReceipt: settlement,
    );
  }

  Future<BleConnectAttemptOutcome> _rollbackExpiredAttempt({
    required _BleConnectAttempt attempt,
    required BleConnectionEffectPort service,
    required void Function(Object error) onRollbackError,
  }) async {
    if (!_owns(attempt)) {
      final ownershipError = StateError(
        'BLE connection attempt ownership changed before expired-owner '
        'compensation.',
      );
      final receipt = _retainAttemptRecovery(
        attempt: attempt,
        reason: BleConnectRecoveryReason.attemptOwnershipLost,
        error: ownershipError,
      );
      return BleConnectAttemptOutcome.effectUncertain(
        error: ownershipError,
        recoveryReceipt: receipt,
      );
    }

    final disconnectError = await _disconnect(
      attempt.deviceId,
      service,
      onRollbackError,
    );
    if (disconnectError != null) {
      final receipt = _retainAttemptRecovery(
        attempt: attempt,
        reason: BleConnectRecoveryReason.disconnectFailed,
        error: disconnectError,
      );
      return BleConnectAttemptOutcome.effectUncertain(
        error: disconnectError,
        recoveryReceipt: receipt,
      );
    }
    final receipt = _settleAttemptAfterDisconnect(attempt, service);
    if (receipt != null) {
      return BleConnectAttemptOutcome.effectUncertain(
        error: receipt.error,
        recoveryReceipt: receipt,
      );
    }
    return const BleConnectAttemptOutcome.ownerExpired();
  }

  Future<Object?> _disconnect(
    String deviceId,
    BleConnectionEffectPort service,
    void Function(Object error) onRollbackError,
  ) async {
    try {
      await service.disconnect(deviceId);
      return null;
    } catch (error) {
      try {
        onRollbackError(error);
      } catch (_) {}
      return error;
    }
  }

  BleConnectRecoveryReceipt? _settleAttemptAfterDisconnect(
    _BleConnectAttempt attempt,
    BleConnectionEffectPort service,
  ) {
    try {
      final state = _readConnectionState(service, attempt.deviceId);
      if (state == _BleConnectionState.disconnected) return null;
      return _retainAttemptRecovery(
        attempt: attempt,
        reason: BleConnectRecoveryReason.disconnectDidNotSettle,
        error: StateError(
          'BLE device ${attempt.deviceId} remained connected after rollback.',
        ),
      );
    } catch (error) {
      return _retainAttemptRecovery(
        attempt: attempt,
        reason: BleConnectRecoveryReason.postDisconnectStateUnknown,
        error: error,
      );
    }
  }

  BleConnectRecoveryOutcome _settleRecoveryAfterDisconnect(
    BleConnectRecoveryReceipt receipt,
    BleConnectionEffectPort service,
  ) {
    try {
      final state = _readConnectionState(service, receipt.deviceId);
      if (state == _BleConnectionState.disconnected) {
        _pendingRecoveries.remove(receipt.deviceId);
        return const BleConnectRecoveryOutcome.reconciled();
      }
      final error = StateError(
        'BLE device ${receipt.deviceId} remained connected after recovery.',
      );
      final retained = _retainRecovery(
        receipt: receipt,
        reason: BleConnectRecoveryReason.disconnectDidNotSettle,
        error: error,
      );
      return BleConnectRecoveryOutcome.effectUncertain(
        receipt: retained,
        error: error,
      );
    } catch (error) {
      final retained = _retainRecovery(
        receipt: receipt,
        reason: BleConnectRecoveryReason.postDisconnectStateUnknown,
        error: error,
      );
      return BleConnectRecoveryOutcome.effectUncertain(
        receipt: retained,
        error: error,
      );
    }
  }

  BleConnectRecoveryReceipt _retainAttemptRecovery({
    required _BleConnectAttempt attempt,
    required BleConnectRecoveryReason reason,
    required Object error,
  }) {
    final receipt = BleConnectRecoveryReceipt._(
      owner: attempt.owner,
      deviceId: attempt.deviceId,
      reason: reason,
      error: error,
      token: attempt.token,
    );
    _pendingRecoveries[attempt.deviceId] = receipt;
    return receipt;
  }

  BleConnectRecoveryReceipt _retainRecovery({
    required BleConnectRecoveryReceipt receipt,
    required BleConnectRecoveryReason reason,
    required Object error,
  }) {
    final retained = BleConnectRecoveryReceipt._(
      owner: receipt.owner,
      deviceId: receipt.deviceId,
      reason: reason,
      error: error,
      token: receipt._token,
    );
    _pendingRecoveries[receipt.deviceId] = retained;
    return retained;
  }

  bool _matchesPending(BleConnectRecoveryReceipt receipt) {
    final pending = _pendingRecoveries[receipt.deviceId];
    return pending?.owner == receipt.owner &&
        identical(pending?._token, receipt._token);
  }

  Future<T> _serialized<T>(
    String deviceId,
    Future<T> Function() operation,
  ) async {
    final predecessor = _tails[deviceId];
    final release = Completer<void>();
    final tail = release.future;
    _tails[deviceId] = tail;
    if (predecessor != null) await predecessor;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_tails[deviceId], tail)) {
        _tails.remove(deviceId);
      }
    }
  }
}

final class _BleConnectAttempt {
  const _BleConnectAttempt({
    required this.owner,
    required this.token,
    required this.deviceId,
  });

  final ChatTurnOwner owner;
  final Object token;
  final String deviceId;
}

enum _BleConnectionState { connected, disconnected }

_BleConnectionState _readConnectionState(
  BleConnectionEffectPort service,
  String deviceId,
) {
  return switch (service.getConnectionState(deviceId)) {
    'connected' => _BleConnectionState.connected,
    'disconnected' => _BleConnectionState.disconnected,
    final state => throw StateError(
      'BLE device $deviceId reported unknown connection state: $state.',
    ),
  };
}
