import 'package:caverno/features/chat/data/datasources/ble_connection_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:caverno/features/chat/domain/services/turn_tool_approval_coordinator.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 9,
  );

  group('BleConnectionRuntimeIdentity', () {
    test('normalizes the device but preserves the opaque tool call ID', () {
      final identity = BleConnectionRuntimeIdentity(
        owner: owner,
        toolCallId: ' call-ble ',
        toolName: 'ble_connect',
        deviceId: ' device-a ',
      );

      expect(identity.owner, owner);
      expect(identity.toolCallId, ' call-ble ');
      expect(identity.toolName, 'ble_connect');
      expect(identity.deviceId, 'device-a');
      expect(
        identity,
        BleConnectionRuntimeIdentity(
          owner: owner,
          toolCallId: ' call-ble ',
          toolName: 'ble_connect',
          deviceId: 'device-a',
        ),
      );
    });

    test('rejects blank fields and noncanonical tool names', () {
      expect(
        () => BleConnectionRuntimeIdentity(
          owner: owner,
          toolCallId: ' ',
          toolName: 'ble_connect',
          deviceId: 'device-a',
        ),
        throwsArgumentError,
      );
      expect(
        () => BleConnectionRuntimeIdentity(
          owner: owner,
          toolCallId: 'call-ble',
          toolName: 'ble_connect',
          deviceId: '\n',
        ),
        throwsArgumentError,
      );
      expect(
        () => BleConnectionRuntimeIdentity(
          owner: owner,
          toolCallId: 'call-ble',
          toolName: 'BLE_CONNECT',
          deviceId: 'device-a',
        ),
        throwsArgumentError,
      );
    });
  });

  group('BleConnectionToolRuntimeAdapter', () {
    test(
      'bridges exact scan, approval, and serialized connect facts',
      () async {
        final fixture = _Fixture(owner)..displayName = 'Desk Sensor';

        final result = await fixture.handle();

        expect(result, _success('Desk Sensor'));
        expect(fixture.scanIdentities, hasLength(1));
        expect(fixture.connect.identities, hasLength(1));
        final identity = fixture.connect.identities.single;
        expect(fixture.scanIdentities.single, identity);
        expect(fixture.ownerIdentities, everyElement(identity));
        expect(fixture.manual.requests.single.toolCallId, 'call-ble');
        expect(fixture.manual.requests.single.toolName, 'ble_connect');
        expect(fixture.manual.requests.single.actionKind, 'ble_connect');
        expect(fixture.manual.requests.single.arguments, {
          'device_id': 'device-a',
        });
        expect(fixture.manual.requests.single.targetDisplayName, 'Desk Sensor');
        expect(
          () => fixture.manual.requests.single.arguments['device_id'] = 'other',
          throwsUnsupportedError,
        );
      },
    );

    test('uses the explicit device ID when scan name is absent', () async {
      final fixture = _Fixture(owner);

      final result = await fixture.handle();

      expect(result, _success('device-a'));
      expect(fixture.manual.requests.single.targetDisplayName, isNull);
      expect(fixture.connect.identities.single.deviceId, 'device-a');
    });

    test('returns an exact manual denial without connecting', () async {
      final fixture = _Fixture(owner)
        ..manual.decision = ManualToolApprovalDecision.denied(
          _failure('User cancelled BLE connection'),
        );

      final result = await fixture.handle();

      expect(result, _failure('User cancelled BLE connection'));
      expect(fixture.scanIdentities, hasLength(1));
      expect(fixture.connect.identities, isEmpty);
    });

    test('rejects cross-owner, cross-call, and cross-device scans', () async {
      final otherOwner = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: owner.interactionGeneration,
      );
      final poisoners =
          <BleConnectionRuntimeIdentity Function(BleConnectionRuntimeIdentity)>[
            (identity) => _changedIdentity(identity, owner: otherOwner),
            (identity) => _changedIdentity(identity, toolCallId: 'other-call'),
            (identity) => _changedIdentity(identity, deviceId: 'device-b'),
          ];

      for (final poison in poisoners) {
        final fixture = _Fixture(owner)..scanIdentityMapper = poison;

        final result = await fixture.handle();

        expect(result, _failure('The approval turn expired before execution'));
        expect(fixture.manual.requests, isEmpty);
        expect(fixture.connect.identities, isEmpty);
      }
    });

    test('rejects a poisoned lifecycle acknowledgement before scan', () async {
      final fixture = _Fixture(owner)
        ..ownerIdentityMapper = (identity) =>
            _changedIdentity(identity, deviceId: 'device-b');

      final result = await fixture.handle();

      expect(result, _failure('The approval turn expired before execution'));
      expect(fixture.scanIdentities, isEmpty);
      expect(fixture.connect.identities, isEmpty);
    });

    test('stops when the owner expires after scan resolution', () async {
      final fixture = _Fixture(owner)
        ..ownerDispositions.addAll([
          BleOwnerLifecycleDisposition.current,
          BleOwnerLifecycleDisposition.ownerExpired,
        ]);

      final result = await fixture.handle();

      expect(result, _failure('The approval turn expired before execution'));
      expect(fixture.scanIdentities, hasLength(1));
      expect(fixture.manual.requests, isEmpty);
      expect(fixture.connect.identities, isEmpty);
    });

    test('treats poisoned connect completion as effect uncertain', () async {
      final fixture = _Fixture(owner)
        ..connect.identityMapper = (identity) =>
            _changedIdentity(identity, toolCallId: 'other-call');

      final result = await fixture.handle();

      expect(result, _effectsUncertain());
    });

    test(
      'maps owner-expired and uncertain attempts to safe uncertainty',
      () async {
        for (final disposition in [
          BleSerializedConnectDisposition.ownerExpired,
          BleSerializedConnectDisposition.effectUncertain,
        ]) {
          final fixture = _Fixture(owner)..connect.disposition = disposition;

          final result = await fixture.handle();

          expect(result, _effectsUncertain());
        }
      },
    );

    test('keeps a typed no-effect connection failure distinct', () async {
      final fixture = _Fixture(owner)
        ..connect.disposition = BleSerializedConnectDisposition.failed
        ..connect.error = StateError('adapter failure');

      final result = await fixture.handle();

      expect(
        result,
        _failure('BLE connect failed: Bad state: adapter failure'),
      );
    });

    test('treats an untyped attempt throw as effect uncertain', () async {
      final fixture = _Fixture(owner)..connect.throwOnConnect = true;

      final result = await fixture.handle();

      expect(result, _effectsUncertain());
    });

    test('maps an exact scan failure without starting approval', () async {
      final fixture = _Fixture(owner)
        ..scanDisposition = BleScanLookupDisposition.failed;

      final result = await fixture.handle();

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('BLE scan lookup failed'));
      expect(fixture.manual.requests, isEmpty);
      expect(fixture.connect.identities, isEmpty);
    });

    test('preserves handler validation before runtime callbacks', () async {
      for (final request in [
        _request(owner, toolCallId: ' '),
        _request(owner, deviceId: ' '),
        _request(owner, toolName: 'serial_open'),
      ]) {
        final fixture = _Fixture(owner);

        final result = await fixture.adapter.handle(request);

        expect(result.isSuccess, isFalse);
        expect(fixture.ownerIdentities, isEmpty);
        expect(fixture.scanIdentities, isEmpty);
        expect(fixture.connect.identities, isEmpty);
        expect(fixture.manual.requests, isEmpty);
      }
    });

    test('passes normalized device identity through every callback', () async {
      final fixture = _Fixture(owner);

      final result = await fixture.handle(deviceId: '  device-a  ');

      expect(result, _success('device-a'));
      expect(
        [
          ...fixture.ownerIdentities,
          ...fixture.scanIdentities,
          ...fixture.connect.identities,
        ].map((identity) => identity.deviceId),
        everyElement('device-a'),
      );
    });
  });
}

final class _OwnerPort implements ToolApprovalOwnerPort {
  final Set<ChatTurnOwner> current = {};

  @override
  bool isCurrent(ChatTurnOwner owner) => current.contains(owner);
}

final class _ManualPort implements ManualToolApprovalPort {
  ManualToolApprovalDecision decision =
      const ManualToolApprovalDecision.approved();
  final List<ManualToolApprovalRequest> requests = [];

  @override
  Future<ManualToolApprovalDecision> requestApproval(
    ChatTurnOwner owner,
    ManualToolApprovalRequest request,
  ) async {
    requests.add(request);
    return decision;
  }
}

final class _AutoReviewPort implements ToolApprovalAutoReviewPort {
  @override
  Future<ToolApprovalAutoReviewDecision?> review(
    ChatTurnOwner owner,
    ToolApprovalAutoReviewRequest request, {
    required ToolApprovalAutoReviewDomain domain,
  }) async {
    return null;
  }
}

final class _AuditPort implements ToolApprovalAuditPort {
  @override
  Future<void> record(
    ChatTurnOwner owner,
    ToolApprovalAuditRecord record,
  ) async {}
}

final class _SerializedConnectPort implements BleSerializedConnectPort {
  final List<BleConnectionRuntimeIdentity> identities = [];
  BleSerializedConnectDisposition disposition =
      BleSerializedConnectDisposition.connected;
  BleConnectionRuntimeIdentity Function(BleConnectionRuntimeIdentity)?
  identityMapper;
  Object error = StateError('connection failed');
  bool throwOnConnect = false;

  @override
  Future<BleSerializedConnectAcknowledgement> connect(
    BleConnectionRuntimeIdentity identity,
  ) async {
    identities.add(identity);
    if (throwOnConnect) throw StateError('transport completion unavailable');
    final acknowledgementIdentity = identityMapper?.call(identity) ?? identity;
    return switch (disposition) {
      BleSerializedConnectDisposition.connected =>
        BleSerializedConnectAcknowledgement.connected(
          identity: acknowledgementIdentity,
        ),
      BleSerializedConnectDisposition.ownerExpired =>
        BleSerializedConnectAcknowledgement.ownerExpired(
          identity: acknowledgementIdentity,
        ),
      BleSerializedConnectDisposition.failed =>
        BleSerializedConnectAcknowledgement.failed(
          identity: acknowledgementIdentity,
          error: error,
        ),
      BleSerializedConnectDisposition.effectUncertain =>
        BleSerializedConnectAcknowledgement.effectUncertain(
          identity: acknowledgementIdentity,
          error: error,
        ),
    };
  }
}

final class _Fixture {
  _Fixture(this.owner) {
    ownerPort.current.add(owner);
    approvalCoordinator = TurnToolApprovalCoordinator(
      manualApprovalPort: manual,
      autoReviewPort: _AutoReviewPort(),
      auditPort: _AuditPort(),
      ownerPort: ownerPort,
    );
    adapter = BleConnectionToolRuntimeAdapter(
      approvalCoordinator: approvalCoordinator,
      acknowledgeOwner: (identity) {
        ownerIdentities.add(identity);
        final acknowledgementIdentity =
            ownerIdentityMapper?.call(identity) ?? identity;
        final disposition = ownerDispositions.isEmpty
            ? BleOwnerLifecycleDisposition.current
            : ownerDispositions.removeAt(0);
        return BleOwnerLifecycleAcknowledgement(
          identity: acknowledgementIdentity,
          disposition: disposition,
        );
      },
      lookupScanResult: (identity) async {
        scanIdentities.add(identity);
        final acknowledgementIdentity =
            scanIdentityMapper?.call(identity) ?? identity;
        return switch (scanDisposition) {
          BleScanLookupDisposition.resolved =>
            BleScanLookupAcknowledgement.resolved(
              identity: acknowledgementIdentity,
              displayName: displayName,
            ),
          BleScanLookupDisposition.ownerExpired =>
            BleScanLookupAcknowledgement.ownerExpired(
              identity: acknowledgementIdentity,
            ),
          BleScanLookupDisposition.failed =>
            BleScanLookupAcknowledgement.failed(
              identity: acknowledgementIdentity,
              error: StateError('scan unavailable'),
            ),
        };
      },
      connectPort: connect,
    );
  }

  final ChatTurnOwner owner;
  final _OwnerPort ownerPort = _OwnerPort();
  final _ManualPort manual = _ManualPort();
  final _SerializedConnectPort connect = _SerializedConnectPort();
  final List<BleConnectionRuntimeIdentity> ownerIdentities = [];
  final List<BleConnectionRuntimeIdentity> scanIdentities = [];
  final List<BleOwnerLifecycleDisposition> ownerDispositions = [];
  late final TurnToolApprovalCoordinator approvalCoordinator;
  late final BleConnectionToolRuntimeAdapter adapter;

  BleConnectionRuntimeIdentity Function(BleConnectionRuntimeIdentity)?
  ownerIdentityMapper;
  BleConnectionRuntimeIdentity Function(BleConnectionRuntimeIdentity)?
  scanIdentityMapper;
  BleScanLookupDisposition scanDisposition = BleScanLookupDisposition.resolved;
  String? displayName;

  Future<McpToolResult> handle({String deviceId = 'device-a'}) {
    return adapter.handle(_request(owner, deviceId: deviceId));
  }
}

BleConnectionToolRequest _request(
  ChatTurnOwner owner, {
  String toolCallId = 'call-ble',
  String toolName = 'ble_connect',
  String deviceId = 'device-a',
}) {
  return BleConnectionToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    deviceId: deviceId,
    approvalMode: ToolApprovalMode.defaultPermissions,
    reason: 'Connect the requested sensor.',
    conversationMessages: const <Message>[],
  );
}

BleConnectionRuntimeIdentity _changedIdentity(
  BleConnectionRuntimeIdentity identity, {
  ChatTurnOwner? owner,
  String? toolCallId,
  String? deviceId,
}) {
  return BleConnectionRuntimeIdentity(
    owner: owner ?? identity.owner,
    toolCallId: toolCallId ?? identity.toolCallId,
    toolName: identity.toolName,
    deviceId: deviceId ?? identity.deviceId,
  );
}

McpToolResult _success(String target) {
  return McpToolResult(
    toolName: 'ble_connect',
    result: 'Connected to $target',
    isSuccess: true,
  );
}

McpToolResult _failure(String message) {
  return McpToolResult(
    toolName: 'ble_connect',
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}

McpToolResult _effectsUncertain() {
  return _failure(
    'The BLE connection may have completed after its owner expired or its '
    'completion identity changed; inspect possible side effects before '
    'retrying',
  );
}
