import 'dart:async';

import 'package:caverno/core/services/ble_connection_effect_port.dart';
import 'package:caverno/features/chat/data/datasources/ble_connect_attempt_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/ble_connect_attempt_coordinator.dart';
import 'package:caverno/features/chat/domain/services/ble_connection_runtime_contract.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 1,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 1,
  );

  test(
    'compensates connect-then-throw and reports effect uncertainty',
    () async {
      final service = _PoisonBleService()..poisonNextConnect('device-a');
      final adapter = _adapter(service);

      final acknowledgement = await adapter.connect(
        _identity(ownerA, 'call-a', 'device-a'),
      );

      expect(
        acknowledgement.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(service.connectCallsFor('device-a'), 1);
      expect(service.disconnectCallsFor('device-a'), 1);
      expect(service.getConnectionState('device-a'), 'disconnected');
      expect(adapter.pendingRecoveryForDevice('device-a'), isNull);
    },
  );

  test('does not disconnect an inherited connection after a throw', () async {
    final service = _PoisonBleService()
      ..setConnected('device-a')
      ..poisonNextConnect('device-a');
    final adapter = _adapter(service);

    final acknowledgement = await adapter.connect(
      _identity(ownerA, 'call-a', 'device-a'),
    );

    expect(acknowledgement.disposition, BleSerializedConnectDisposition.failed);
    expect(service.disconnectCallsFor('device-a'), 0);
    expect(service.getConnectionState('device-a'), 'connected');
    expect(adapter.pendingRecoveryForDevice('device-a'), isNull);
  });

  test(
    'retains an exact recovery receipt when conditional disconnect fails',
    () async {
      final service = _PoisonBleService()
        ..poisonNextConnect('device-a')
        ..disconnectError = StateError('disconnect unavailable');
      final adapter = _adapter(service);
      final firstIdentity = _identity(ownerA, 'call-a', 'device-a');

      final first = await adapter.connect(firstIdentity);
      final receipt = adapter.pendingRecoveryForDevice('device-a');

      expect(
        first.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(receipt, isNotNull);
      expect(receipt!.owner, ownerA);
      expect(receipt.deviceId, 'device-a');
      expect(receipt.reason, BleConnectRecoveryReason.disconnectFailed);

      final blocked = await adapter.connect(
        _identity(ownerB, 'call-b', 'device-a'),
      );
      expect(
        blocked.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(service.connectCallsFor('device-a'), 1);

      final foreignAdapter = _adapter(service);
      expect(await foreignAdapter.clearRecovery(receipt), isFalse);
      expect(adapter.pendingRecoveryForDevice('device-a'), isNotNull);

      service.disconnectError = null;
      final reconciled = await adapter.reconcileRecovery(receipt);
      expect(reconciled.disposition, BleConnectRecoveryDisposition.reconciled);
      expect(adapter.pendingRecoveryForDevice('device-a'), isNull);

      final successor = await adapter.connect(
        _identity(ownerB, 'call-c', 'device-a'),
      );
      expect(successor.disposition, BleSerializedConnectDisposition.connected);
      expect(service.connectCallsFor('device-a'), 2);
    },
  );

  test(
    'retains unread post-throw state while another device can proceed',
    () async {
      final service = _PoisonBleService()
        ..poisonNextConnect('device-a')
        ..poisonNextPostConnectStateRead('device-a');
      final adapter = _adapter(service);

      final first = await adapter.connect(
        _identity(ownerA, 'call-a', 'device-a'),
      );
      final receipt = adapter.pendingRecoveryForDevice('device-a');

      expect(
        first.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(receipt, isNotNull);
      expect(receipt!.reason, BleConnectRecoveryReason.postConnectStateUnknown);
      expect(service.disconnectCallsFor('device-a'), 0);

      final sameDevice = await adapter.connect(
        _identity(ownerB, 'call-b', 'device-a'),
      );
      final otherDevice = await adapter.connect(
        _identity(ownerB, 'call-c', 'device-b'),
      );

      expect(
        sameDevice.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(
        otherDevice.disposition,
        BleSerializedConnectDisposition.connected,
      );
      expect(service.connectCallsFor('device-a'), 1);
      expect(service.connectCallsFor('device-b'), 1);
    },
  );

  test(
    'keeps a same-device successor fenced through conditional disconnect',
    () async {
      final disconnectStarted = Completer<void>();
      final releaseDisconnect = Completer<void>();
      final service = _PoisonBleService()
        ..poisonNextConnect('device-a')
        ..disconnectStarted = disconnectStarted
        ..releaseDisconnect = releaseDisconnect;
      final adapter = _adapter(service);

      final first = adapter.connect(_identity(ownerA, 'call-a', 'device-a'));
      await disconnectStarted.future;
      final successor = adapter.connect(
        _identity(ownerB, 'call-b', 'device-a'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.connectCallsFor('device-a'), 1);

      releaseDisconnect.complete();
      final firstResult = await first;
      final successorResult = await successor;

      expect(
        firstResult.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(
        successorResult.disposition,
        BleSerializedConnectDisposition.connected,
      );
      expect(service.connectCallsFor('device-a'), 2);
      expect(service.disconnectCallsFor('device-a'), 1);
      expect(service.getConnectionState('device-a'), 'connected');
    },
  );

  test(
    'retains recovery when expired-owner compensation cannot disconnect',
    () async {
      final service = _PoisonBleService()
        ..disconnectError = StateError('disconnect unavailable');
      var lifecycleChecks = 0;
      final adapter = _adapter(
        service,
        acknowledgeOwner: (identity) {
          lifecycleChecks += 1;
          return BleOwnerLifecycleAcknowledgement(
            identity: identity,
            disposition: lifecycleChecks == 1
                ? BleOwnerLifecycleDisposition.current
                : BleOwnerLifecycleDisposition.ownerExpired,
          );
        },
      );

      final acknowledgement = await adapter.connect(
        _identity(ownerA, 'call-a', 'device-a'),
      );
      final receipt = adapter.pendingRecoveryForDevice('device-a');

      expect(
        acknowledgement.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(receipt, isNotNull);
      expect(receipt!.reason, BleConnectRecoveryReason.disconnectFailed);
      expect(service.connectCallsFor('device-a'), 1);
      expect(service.disconnectCallsFor('device-a'), 1);

      final successor = await adapter.connect(
        _identity(ownerB, 'call-b', 'device-a'),
      );
      expect(
        successor.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(service.connectCallsFor('device-a'), 1);
    },
  );

  test(
    'retains recovery when connect throws after expiry and rollback fails',
    () async {
      final service = _PoisonBleService()
        ..poisonNextConnect('device-a')
        ..disconnectError = StateError('disconnect unavailable');
      var lifecycleChecks = 0;
      final adapter = _adapter(
        service,
        acknowledgeOwner: (identity) {
          lifecycleChecks += 1;
          return BleOwnerLifecycleAcknowledgement(
            identity: identity,
            disposition: lifecycleChecks == 1
                ? BleOwnerLifecycleDisposition.current
                : BleOwnerLifecycleDisposition.ownerExpired,
          );
        },
      );

      final acknowledgement = await adapter.connect(
        _identity(ownerA, 'call-a', 'device-a'),
      );
      final receipt = adapter.pendingRecoveryForDevice('device-a');

      expect(
        acknowledgement.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(receipt, isNotNull);
      expect(receipt!.reason, BleConnectRecoveryReason.disconnectFailed);
      expect(service.connectCallsFor('device-a'), 1);
      expect(service.disconnectCallsFor('device-a'), 1);
    },
  );
}

BleConnectAttemptRuntimeAdapter _adapter(
  _PoisonBleService service, {
  BleOwnerLifecycleCallback? acknowledgeOwner,
}) {
  return BleConnectAttemptRuntimeAdapter(
    coordinator: BleConnectAttemptCoordinator(),
    service: service,
    acknowledgeOwner:
        acknowledgeOwner ??
        (identity) => BleOwnerLifecycleAcknowledgement(
          identity: identity,
          disposition: BleOwnerLifecycleDisposition.current,
        ),
  );
}

BleConnectionRuntimeIdentity _identity(
  ChatTurnOwner owner,
  String toolCallId,
  String deviceId,
) {
  return BleConnectionRuntimeIdentity(
    owner: owner,
    toolCallId: toolCallId,
    toolName: canonicalBleConnectToolName,
    deviceId: deviceId,
  );
}

final class _PoisonBleService implements BleConnectionEffectPort {
  final Set<String> _connected = {};
  final Set<String> _poisonedConnects = {};
  final Set<String> _poisonedPostConnectStateReads = {};
  final Map<String, int> _connectCalls = {};
  final Map<String, int> _disconnectCalls = {};

  Object? disconnectError;
  Completer<void>? disconnectStarted;
  Completer<void>? releaseDisconnect;

  void setConnected(String deviceId) {
    _connected.add(deviceId);
  }

  void poisonNextConnect(String deviceId) {
    _poisonedConnects.add(deviceId);
  }

  void poisonNextPostConnectStateRead(String deviceId) {
    _poisonedPostConnectStateReads.add(deviceId);
  }

  int connectCallsFor(String deviceId) => _connectCalls[deviceId] ?? 0;

  int disconnectCallsFor(String deviceId) => _disconnectCalls[deviceId] ?? 0;

  @override
  Future<void> connect(String deviceId) async {
    _connectCalls.update(deviceId, (value) => value + 1, ifAbsent: () => 1);
    _connected.add(deviceId);
    if (_poisonedConnects.remove(deviceId)) {
      throw StateError('connect callback failed after commit');
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _disconnectCalls.update(deviceId, (value) => value + 1, ifAbsent: () => 1);
    disconnectStarted?.complete();
    final release = releaseDisconnect;
    if (release != null) await release.future;
    final error = disconnectError;
    if (error != null) throw error;
    _connected.remove(deviceId);
  }

  @override
  String getConnectionState(String deviceId) {
    if ((_connectCalls[deviceId] ?? 0) > 0 &&
        _poisonedPostConnectStateReads.remove(deviceId)) {
      throw StateError('connection state unavailable after connect');
    }
    return _connected.contains(deviceId) ? 'connected' : 'disconnected';
  }
}
