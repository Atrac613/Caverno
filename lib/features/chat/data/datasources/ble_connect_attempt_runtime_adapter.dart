import '../../../../core/services/ble_connection_effect_port.dart';
import '../../domain/services/ble_connect_attempt_coordinator.dart';
import '../../domain/services/ble_connection_runtime_contract.dart';
import 'ble_serialized_connect_runtime_adapter.dart';

/// Adapts the serialized BLE coordinator to the typed connection boundary.
final class BleConnectAttemptRuntimeAdapter
    implements BleSerializedConnectPort {
  BleConnectAttemptRuntimeAdapter({
    required BleConnectAttemptCoordinator coordinator,
    required BleConnectionEffectPort service,
    required BleOwnerLifecycleCallback acknowledgeOwner,
    BleRollbackErrorCallback? onRollbackError,
  }) : _coordinator = coordinator,
       _service = service,
       _delegate = BleSerializedConnectRuntimeAdapter(
         runner: _BleConnectAttemptCoordinatorRunner(
           coordinator: coordinator,
           service: service,
         ),
         acknowledgeOwner: acknowledgeOwner,
         onRollbackError: onRollbackError,
       );

  final BleConnectAttemptCoordinator _coordinator;
  final BleConnectionEffectPort _service;
  final BleSerializedConnectRuntimeAdapter _delegate;

  @override
  Future<BleSerializedConnectAcknowledgement> connect(
    BleConnectionRuntimeIdentity identity,
  ) {
    return _delegate.connect(identity);
  }

  BleConnectRecoveryReceipt? pendingRecoveryForDevice(String deviceId) {
    return _coordinator.pendingRecoveryForDevice(deviceId);
  }

  Future<BleConnectRecoveryOutcome> reconcileRecovery(
    BleConnectRecoveryReceipt receipt,
  ) {
    return _coordinator.reconcileRecovery(
      receipt: receipt,
      service: _service,
      onRollbackError: (_) {},
    );
  }

  Future<bool> clearRecovery(BleConnectRecoveryReceipt receipt) {
    return _coordinator.clearRecovery(receipt);
  }
}

final class _BleConnectAttemptCoordinatorRunner
    implements BleConnectAttemptRunner {
  const _BleConnectAttemptCoordinatorRunner({
    required BleConnectAttemptCoordinator coordinator,
    required BleConnectionEffectPort service,
  }) : _coordinator = coordinator,
       _service = service;

  final BleConnectAttemptCoordinator _coordinator;
  final BleConnectionEffectPort _service;

  @override
  Future<BleConnectAttemptRunOutcome> run(
    BleConnectionRuntimeIdentity identity, {
    required bool Function() ownerIsCurrent,
    required void Function(Object error) onRollbackError,
  }) async {
    var ownerIdentityMismatch = false;
    final outcome = await _coordinator.connect(
      owner: identity.owner,
      deviceId: identity.deviceId,
      service: _service,
      ownerIsCurrent: (reportedOwner) {
        if (reportedOwner != identity.owner) {
          ownerIdentityMismatch = true;
          return false;
        }
        return ownerIsCurrent();
      },
      onRollbackError: onRollbackError,
    );
    if (ownerIdentityMismatch) {
      throw StateError('BLE attempt owner identity mismatch.');
    }
    if (outcome.effectUncertain) {
      return BleConnectAttemptRunOutcome.effectUncertain(outcome.error);
    }
    return switch (outcome.kind) {
      BleConnectAttemptOutcomeKind.connected =>
        const BleConnectAttemptRunOutcome.connected(),
      BleConnectAttemptOutcomeKind.ownerExpired =>
        const BleConnectAttemptRunOutcome.ownerExpired(),
      BleConnectAttemptOutcomeKind.failed => BleConnectAttemptRunOutcome.failed(
        outcome.error,
      ),
    };
  }
}
