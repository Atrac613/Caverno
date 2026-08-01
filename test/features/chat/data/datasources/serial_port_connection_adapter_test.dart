import 'package:caverno/features/chat/data/datasources/serial_port_connection_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_attempt_coordinator.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_tool_contract.dart';
import 'package:test/test.dart';

final ownerA = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 1,
);

void main() {
  group('SerialPortConnectionAdapter open', () {
    test(
      'forwards the exact target and returns its session identity',
      () async {
        final service = _FakeSerialPortService()
          ..resultJson = '{"success":true,"session_fingerprint":"session-open"}'
          ..currentFingerprint = 'session-successor';
        final adapter = SerialPortConnectionAdapter(
          service: service,
          ownerIsCurrent: (owner) => owner == ownerA,
        );
        final request = _request();

        final result = await adapter.open(ownerA, request);

        expect(result.belongsTo(ownerA, request), isTrue);
        expect(result.kind, SerialConnectionResultKind.completed);
        expect(
          result.resultJson,
          '{"success":true,"session_fingerprint":"session-open"}',
        );
        expect(result.sessionFingerprint, 'session-open');
        expect(service.openCalls.single, (
          port: '/dev/cu.sensor',
          baudRate: 115200,
          dataBits: 7,
          parity: 'even',
          stopBits: 2,
          flowControl: 'rtscts',
        ));
      },
    );

    test('marks an exact completion when its owner expires', () async {
      final service = _FakeSerialPortService();
      final adapter = SerialPortConnectionAdapter(
        service: service,
        ownerIsCurrent: (_) => false,
      );
      final request = _request();

      final result = await adapter.open(ownerA, request);

      expect(result.belongsTo(ownerA, request), isTrue);
      expect(result.kind, SerialConnectionResultKind.ownerExpired);
      expect(result.sessionFingerprint, 'session-a');
    });
  });

  group('SerialPortConnectionAdapter rollback', () {
    for (final entry
        in <(SerialSessionCloseKind, SerialConnectionRollbackKind)>[
          (SerialSessionCloseKind.closed, SerialConnectionRollbackKind.closed),
          (
            SerialSessionCloseKind.alreadyAbsent,
            SerialConnectionRollbackKind.alreadyAbsent,
          ),
          (
            SerialSessionCloseKind.sessionMismatch,
            SerialConnectionRollbackKind.sessionMismatch,
          ),
        ]) {
      test('maps ${entry.$1.name} for the exact receipt', () async {
        final service = _FakeSerialPortService()..closeKind = entry.$1;
        final adapter = SerialPortConnectionAdapter(
          service: service,
          ownerIsCurrent: (_) => false,
        );
        final permit = _rollbackPermit();

        final result = await adapter.rollbackOpen(permit);

        expect(result.kind, entry.$2);
        expect(result.belongsTo(ownerA, _request(), 'session-a'), isTrue);
        expect(service.closeCalls.single, (
          port: '/dev/cu.sensor',
          fingerprint: 'session-a',
        ));
      });
    }

    test('preserves a successor session on fingerprint mismatch', () async {
      final service = _FakeSerialPortService()
        ..currentFingerprint = 'session-successor'
        ..closeKind = SerialSessionCloseKind.sessionMismatch;
      final adapter = SerialPortConnectionAdapter(
        service: service,
        ownerIsCurrent: (_) => false,
      );

      final result = await adapter.rollbackOpen(_rollbackPermit());

      expect(result.kind, SerialConnectionRollbackKind.sessionMismatch);
      expect(service.currentFingerprint, 'session-successor');
    });

    test('returns a failed exact completion when cleanup throws', () async {
      final service = _FakeSerialPortService()..closeError = StateError('busy');
      final adapter = SerialPortConnectionAdapter(
        service: service,
        ownerIsCurrent: (_) => false,
      );

      final result = await adapter.rollbackOpen(_rollbackPermit());

      expect(result.kind, SerialConnectionRollbackKind.failed);
      expect(result.errorMessage, contains('busy'));
      expect(result.belongsTo(ownerA, _request(), 'session-a'), isTrue);
    });
  });
}

SerialConnectionRequest _request() {
  return const SerialConnectionRequest(
    toolCallId: 'call-a',
    portName: '/dev/cu.sensor',
    options: SerialConnectionOptions(
      baudRate: 115200,
      dataBits: 7,
      parity: 'even',
      stopBits: 2,
      flowControl: 'rtscts',
    ),
  );
}

SerialConnectionRollbackPermit _rollbackPermit() {
  final coordinator = SerialConnectionAttemptCoordinator();
  final identity = SerialConnectionAttemptIdentity(
    owner: ownerA,
    toolCallId: 'call-a',
    toolName: 'serial_open',
    portName: '/dev/cu.sensor',
    options: _request().options,
  );
  final lease = coordinator.acquire(identity).lease!;
  expect(
    coordinator.beginOpen(identity, lease.token),
    SerialConnectionBeginOpenKind.begun,
  );
  final receipt = coordinator
      .markOpened(identity, lease.token, sessionFingerprint: 'session-a')
      .receipt!;
  coordinator.clearOwner(ownerA);
  return coordinator
      .beginRollback(receipt, observedSessionFingerprint: 'session-a')
      .permit!;
}

final class _FakeSerialPortService implements SerialSessionPort {
  final List<
    ({
      String port,
      int baudRate,
      int dataBits,
      String parity,
      int stopBits,
      String flowControl,
    })
  >
  openCalls = [];
  final List<({String port, String fingerprint})> closeCalls = [];
  String? currentFingerprint = 'session-a';
  String resultJson = '{"success":true}';
  SerialSessionCloseKind closeKind = SerialSessionCloseKind.closed;
  Object? closeError;

  @override
  Future<String> open(
    String portName, {
    int baudRate = 9600,
    int dataBits = 8,
    String parity = 'none',
    int stopBits = 1,
    String flowControl = 'none',
  }) async {
    openCalls.add((
      port: portName,
      baudRate: baudRate,
      dataBits: dataBits,
      parity: parity,
      stopBits: stopBits,
      flowControl: flowControl,
    ));
    return resultJson;
  }

  @override
  String? sessionFingerprint(String portName) => currentFingerprint;

  @override
  Future<SerialSessionCloseKind> closeIfSessionMatches(
    String portName,
    String expectedFingerprint,
  ) async {
    closeCalls.add((port: portName, fingerprint: expectedFingerprint));
    if (closeError case final error?) throw error;
    if (closeKind == SerialSessionCloseKind.closed) {
      currentFingerprint = null;
    }
    return closeKind;
  }
}
