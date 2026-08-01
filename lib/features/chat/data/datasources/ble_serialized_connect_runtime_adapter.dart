import '../../domain/services/ble_connection_runtime_contract.dart';

/// Verifies lifecycle and rollback acknowledgements around a serialized run.
final class BleSerializedConnectRuntimeAdapter
    implements BleSerializedConnectPort {
  const BleSerializedConnectRuntimeAdapter({
    required BleConnectAttemptRunner runner,
    required BleOwnerLifecycleCallback acknowledgeOwner,
    BleRollbackErrorCallback? onRollbackError,
  }) : _runner = runner,
       _acknowledgeOwner = acknowledgeOwner,
       _onRollbackError = onRollbackError;

  final BleConnectAttemptRunner _runner;
  final BleOwnerLifecycleCallback _acknowledgeOwner;
  final BleRollbackErrorCallback? _onRollbackError;

  @override
  Future<BleSerializedConnectAcknowledgement> connect(
    BleConnectionRuntimeIdentity identity,
  ) async {
    var lifecycleUncertain = false;
    Object? rollbackError;
    try {
      final outcome = await _runner.run(
        identity,
        ownerIsCurrent: () {
          try {
            final acknowledgement = _acknowledgeOwner(identity);
            if (!acknowledgement.identity.belongsTo(identity)) {
              lifecycleUncertain = true;
              return false;
            }
            switch (acknowledgement.disposition) {
              case BleOwnerLifecycleDisposition.current:
                return true;
              case BleOwnerLifecycleDisposition.ownerExpired:
                return false;
              case BleOwnerLifecycleDisposition.effectUncertain:
                lifecycleUncertain = true;
                return false;
            }
          } catch (_) {
            lifecycleUncertain = true;
            return false;
          }
        },
        onRollbackError: (error) {
          rollbackError = error;
          try {
            _onRollbackError?.call(identity, error);
          } catch (_) {}
        },
      );
      if (lifecycleUncertain || rollbackError != null) {
        return BleSerializedConnectAcknowledgement.effectUncertain(
          identity: identity,
          error: rollbackError,
        );
      }
      return switch (outcome.disposition) {
        BleConnectAttemptRunDisposition.connected =>
          BleSerializedConnectAcknowledgement.connected(identity: identity),
        BleConnectAttemptRunDisposition.ownerExpired =>
          BleSerializedConnectAcknowledgement.ownerExpired(identity: identity),
        BleConnectAttemptRunDisposition.failed =>
          BleSerializedConnectAcknowledgement.failed(
            identity: identity,
            error: outcome.error ?? 'Unknown BLE connection error',
          ),
        BleConnectAttemptRunDisposition.effectUncertain =>
          BleSerializedConnectAcknowledgement.effectUncertain(
            identity: identity,
            error: outcome.error,
          ),
      };
    } catch (error) {
      return BleSerializedConnectAcknowledgement.effectUncertain(
        identity: identity,
        error: error,
      );
    }
  }
}
