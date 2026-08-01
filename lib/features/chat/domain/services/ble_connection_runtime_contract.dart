import '../entities/chat_turn_owner.dart';

const String canonicalBleConnectToolName = 'ble_connect';

/// Exact owner, tool call, and device identity for one BLE connection.
final class BleConnectionRuntimeIdentity {
  BleConnectionRuntimeIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String deviceId,
  }) : toolCallId = _requiredExactValue(toolCallId, 'toolCallId'),
       toolName = _canonicalToolName(toolName),
       deviceId = _requiredTrimmedValue(deviceId, 'deviceId');

  final ChatTurnOwner owner;
  final String toolCallId;
  final String toolName;
  final String deviceId;

  bool belongsTo(BleConnectionRuntimeIdentity expected) => this == expected;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BleConnectionRuntimeIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.deviceId == deviceId;
  }

  @override
  int get hashCode => Object.hash(owner, toolCallId, toolName, deviceId);
}

enum BleOwnerLifecycleDisposition { current, ownerExpired, effectUncertain }

/// Exact lifecycle acknowledgement captured at a runtime boundary.
final class BleOwnerLifecycleAcknowledgement {
  const BleOwnerLifecycleAcknowledgement({
    required this.identity,
    required this.disposition,
  });

  final BleConnectionRuntimeIdentity identity;
  final BleOwnerLifecycleDisposition disposition;
}

typedef BleOwnerLifecycleCallback =
    BleOwnerLifecycleAcknowledgement Function(
      BleConnectionRuntimeIdentity identity,
    );

enum BleScanLookupDisposition { resolved, ownerExpired, failed }

/// Exact scan lookup result for the requested device ID.
final class BleScanLookupAcknowledgement {
  const BleScanLookupAcknowledgement.resolved({
    required this.identity,
    this.displayName,
  }) : disposition = BleScanLookupDisposition.resolved,
       errorMessage = null;

  const BleScanLookupAcknowledgement.ownerExpired({required this.identity})
    : disposition = BleScanLookupDisposition.ownerExpired,
      displayName = null,
      errorMessage = null;

  BleScanLookupAcknowledgement.failed({
    required this.identity,
    required Object error,
  }) : disposition = BleScanLookupDisposition.failed,
       displayName = null,
       errorMessage = error.toString();

  final BleConnectionRuntimeIdentity identity;
  final BleScanLookupDisposition disposition;
  final String? displayName;
  final String? errorMessage;
}

typedef BleScanLookupCallback =
    Future<BleScanLookupAcknowledgement> Function(
      BleConnectionRuntimeIdentity identity,
    );

enum BleSerializedConnectDisposition {
  connected,
  ownerExpired,
  failed,
  effectUncertain,
}

/// Exact completion after serialized connect and any required rollback.
final class BleSerializedConnectAcknowledgement {
  const BleSerializedConnectAcknowledgement.connected({required this.identity})
    : disposition = BleSerializedConnectDisposition.connected,
      errorMessage = null;

  const BleSerializedConnectAcknowledgement.ownerExpired({
    required this.identity,
  }) : disposition = BleSerializedConnectDisposition.ownerExpired,
       errorMessage = null;

  BleSerializedConnectAcknowledgement.failed({
    required this.identity,
    required Object error,
  }) : disposition = BleSerializedConnectDisposition.failed,
       errorMessage = error.toString();

  BleSerializedConnectAcknowledgement.effectUncertain({
    required this.identity,
    Object? error,
  }) : disposition = BleSerializedConnectDisposition.effectUncertain,
       errorMessage = error?.toString();

  final BleConnectionRuntimeIdentity identity;
  final BleSerializedConnectDisposition disposition;
  final String? errorMessage;
}

/// Serialized BLE effect boundary implemented by the attempt coordinator.
abstract interface class BleSerializedConnectPort {
  Future<BleSerializedConnectAcknowledgement> connect(
    BleConnectionRuntimeIdentity identity,
  );
}

typedef BleRollbackErrorCallback =
    void Function(BleConnectionRuntimeIdentity identity, Object error);

enum BleConnectAttemptRunDisposition {
  connected,
  ownerExpired,
  failed,
  effectUncertain,
}

/// Transport-neutral outcome returned by the existing attempt coordinator.
final class BleConnectAttemptRunOutcome {
  const BleConnectAttemptRunOutcome.connected()
    : disposition = BleConnectAttemptRunDisposition.connected,
      error = null;

  const BleConnectAttemptRunOutcome.ownerExpired()
    : disposition = BleConnectAttemptRunDisposition.ownerExpired,
      error = null;

  const BleConnectAttemptRunOutcome.failed(this.error)
    : disposition = BleConnectAttemptRunDisposition.failed;

  const BleConnectAttemptRunOutcome.effectUncertain(this.error)
    : disposition = BleConnectAttemptRunDisposition.effectUncertain;

  final BleConnectAttemptRunDisposition disposition;
  final Object? error;
}

/// Narrow seam around per-device serialization and conditional rollback.
abstract interface class BleConnectAttemptRunner {
  Future<BleConnectAttemptRunOutcome> run(
    BleConnectionRuntimeIdentity identity, {
    required bool Function() ownerIsCurrent,
    required void Function(Object error) onRollbackError,
  });
}

String _requiredExactValue(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return value;
}

String _requiredTrimmedValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be empty.');
  }
  return normalized;
}

String _canonicalToolName(String value) {
  if (value != canonicalBleConnectToolName) {
    throw ArgumentError.value(
      value,
      'toolName',
      'toolName must be exactly $canonicalBleConnectToolName.',
    );
  }
  return value;
}
