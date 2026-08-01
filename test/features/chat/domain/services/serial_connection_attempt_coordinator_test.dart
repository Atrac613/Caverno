import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_attempt_coordinator.dart';
import 'package:caverno/features/chat/domain/services/serial_connection_tool_contract.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = _owner('conversation-a');
  final ownerB = _owner('conversation-b');

  group('SerialConnectionAttemptIdentity', () {
    test('normalizes and compares owner, call, tool, port, and options', () {
      final first = SerialConnectionAttemptIdentity(
        owner: ownerA,
        toolCallId: ' call-a ',
        toolName: ' serial_open ',
        portName: ' /dev/cu.sensor ',
        options: _options(),
      );
      final equal = _identity(ownerA, 'call-a');
      final differentCall = _identity(ownerA, 'call-b');
      final differentPort = _identity(
        ownerA,
        'call-a',
        portName: '/dev/cu.other',
      );
      final differentOptions = _identity(
        ownerA,
        'call-a',
        options: _options(baudRate: 115200),
      );

      expect(first.toolCallId, 'call-a');
      expect(first.toolName, 'serial_open');
      expect(first.portName, '/dev/cu.sensor');
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(differentCall));
      expect(first, isNot(differentPort));
      expect(first, isNot(differentOptions));
    });

    test('rejects every empty identity component', () {
      for (final values in [
        (call: ' ', tool: 'serial_open', port: '/dev/cu.sensor'),
        (call: 'call-a', tool: '\n', port: '/dev/cu.sensor'),
        (call: 'call-a', tool: 'serial_open', port: '\t'),
      ]) {
        expect(
          () => SerialConnectionAttemptIdentity(
            owner: ownerA,
            toolCallId: values.call,
            toolName: values.tool,
            portName: values.port,
            options: _options(),
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('SerialConnectionAttemptCoordinator leases', () {
    test('holds an exclusive lease per port while allowing another port', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operationA = _identity(ownerA, 'call-a');
      final operationB = _identity(ownerB, 'call-b');
      final otherPort = _identity(
        ownerB,
        'call-other',
        portName: '/dev/cu.other',
      );

      final leaseA = _acquire(coordinator, operationA);
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.busy,
      );
      expect(
        coordinator.acquire(otherPort).kind,
        SerialConnectionAttemptAcquisitionKind.acquired,
      );
      expect(leaseA.identity, operationA);
    });

    test('rejects a registry-foreign token with the same numeric epoch', () {
      final first = SerialConnectionAttemptCoordinator();
      final second = SerialConnectionAttemptCoordinator();
      final operation = _identity(ownerA, 'call-a');
      final firstLease = _acquire(first, operation);
      final foreignLease = _acquire(second, operation);

      expect(firstLease.token.epoch, foreignLease.token.epoch);
      expect(first.releaseNoEffect(operation, foreignLease.token), isFalse);
      expect(first.releaseNoEffect(operation, firstLease.token), isTrue);
    });

    test('commits a current opened receipt and releases the port', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operationA = _identity(ownerA, 'call-a');
      final operationB = _identity(ownerB, 'call-b');
      final lease = _acquireOpening(coordinator, operationA);
      final opened = coordinator.markOpened(
        operationA,
        lease.token,
        sessionFingerprint: 'session-a',
      );

      expect(opened.kind, SerialConnectionMarkOpenedKind.openedCurrent);
      expect(
        coordinator.finishCurrent(opened.receipt!),
        SerialConnectionCommitKind.committed,
      );
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.acquired,
      );
    });

    test('releases an exact opening lease only after no effect', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operationA = _identity(ownerA, 'call-a');
      final operationB = _identity(ownerB, 'call-b');
      final lease = _acquireOpening(coordinator, operationA);

      expect(coordinator.releaseNoEffect(operationB, lease.token), isFalse);
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.busy,
      );
      expect(coordinator.releaseNoEffect(operationA, lease.token), isTrue);
      expect(coordinator.releaseNoEffect(operationA, lease.token), isFalse);
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.acquired,
      );
    });

    test('requires beginOpen before recording an opened session', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operation = _identity(ownerA, 'call-a');
      final lease = _acquire(coordinator, operation);

      expect(
        coordinator
            .markOpened(operation, lease.token, sessionFingerprint: 'session-a')
            .kind,
        SerialConnectionMarkOpenedKind.rejected,
      );
      expect(
        coordinator.beginOpen(operation, lease.token),
        SerialConnectionBeginOpenKind.begun,
      );
      expect(
        coordinator
            .markOpened(operation, lease.token, sessionFingerprint: 'session-a')
            .kind,
        SerialConnectionMarkOpenedKind.openedCurrent,
      );
    });
  });

  group('SerialConnectionAttemptCoordinator retirement and rollback', () {
    test(
      'retirement before begin removes the reservation and prevents launch',
      () {
        final coordinator = SerialConnectionAttemptCoordinator();
        final operationA = _identity(ownerA, 'call-a');
        final operationB = _identity(ownerB, 'call-b');
        final lease = _acquire(coordinator, operationA);

        final retirement = coordinator.clearOwner(ownerA);

        expect(retirement.isEmpty, isTrue);
        expect(
          coordinator.beginOpen(operationA, lease.token),
          SerialConnectionBeginOpenKind.ownerRetired,
        );
        expect(
          coordinator
              .markOpened(
                operationA,
                lease.token,
                sessionFingerprint: 'session-a',
              )
              .kind,
          SerialConnectionMarkOpenedKind.rejected,
        );
        expect(
          coordinator.acquire(operationB).kind,
          SerialConnectionAttemptAcquisitionKind.acquired,
        );
      },
    );

    test('retirement during open preserves work and requires rollback', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operationA = _identity(ownerA, 'call-a');
      final operationB = _identity(ownerB, 'call-b');
      final lease = _acquireOpening(coordinator, operationA);

      final retirement = coordinator.clearOwner(ownerA);
      expect(retirement.opensInFlight, hasLength(1));
      expect(retirement.opensInFlight.single, same(lease));
      expect(retirement.rollbackRequired, isEmpty);
      expect(() => retirement.opensInFlight.add(lease), throwsUnsupportedError);
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.busy,
      );
      final opened = coordinator.markOpened(
        operationA,
        lease.token,
        sessionFingerprint: ' session-a ',
      );

      expect(opened.kind, SerialConnectionMarkOpenedKind.rollbackRequired);
      expect(opened.receipt, isNotNull);
      expect(opened.receipt!.sessionFingerprint, 'session-a');
      expect(
        coordinator.acquire(operationA).kind,
        SerialConnectionAttemptAcquisitionKind.ownerRetired,
      );
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.busy,
      );
    });

    test('retirement after open prevents a current commit', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operation = _identity(ownerA, 'call-a');
      final lease = _acquireOpening(coordinator, operation);
      final opened = coordinator.markOpened(
        operation,
        lease.token,
        sessionFingerprint: 'session-a',
      );

      expect(opened.kind, SerialConnectionMarkOpenedKind.openedCurrent);
      final retirement = coordinator.clearOwner(ownerA);
      expect(retirement.opensInFlight, isEmpty);
      expect(retirement.rollbackRequired, hasLength(1));
      expect(retirement.rollbackRequired.single, same(opened.receipt));
      expect(
        coordinator.finishCurrent(opened.receipt!),
        SerialConnectionCommitKind.rollbackRequired,
      );
    });

    test('requires the exact observed session before rollback', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operation = _identity(ownerA, 'call-a');
      final receipt = _retiredOpenedReceipt(coordinator, operation);

      final mismatch = coordinator.beginRollback(
        receipt,
        observedSessionFingerprint: 'successor-session',
      );
      expect(mismatch.kind, SerialConnectionRollbackBeginKind.sessionMismatch);
      expect(mismatch.permit, isNull);

      final begun = coordinator.beginRollback(
        receipt,
        observedSessionFingerprint: 'session-a',
      );
      expect(begun.kind, SerialConnectionRollbackBeginKind.begun);
      expect(begun.permit, isNotNull);
    });

    test('does not begin rollback while the owner remains current', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operation = _identity(ownerA, 'call-a');
      final lease = _acquireOpening(coordinator, operation);
      final receipt = coordinator
          .markOpened(operation, lease.token, sessionFingerprint: 'session-a')
          .receipt!;

      expect(
        coordinator
            .beginRollback(receipt, observedSessionFingerprint: 'session-a')
            .kind,
        SerialConnectionRollbackBeginKind.ownerCurrent,
      );
    });

    test('retains the lease after rollback failure and permits retry', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operationA = _identity(ownerA, 'call-a');
      final operationB = _identity(ownerB, 'call-b');
      final receipt = _retiredOpenedReceipt(coordinator, operationA);
      final first = _beginRollback(coordinator, receipt);

      expect(
        coordinator.finishRollback(first, succeeded: false),
        SerialConnectionRollbackFinishKind.retryRequired,
      );
      expect(coordinator.pendingCleanupReceipts, [receipt]);
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.busy,
      );

      final retry = _beginRollback(coordinator, receipt);
      expect(retry.epoch, greaterThan(first.epoch));
      expect(
        coordinator.finishRollback(first, succeeded: true),
        SerialConnectionRollbackFinishKind.rejected,
      );
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.busy,
      );
      expect(
        coordinator.finishRollback(retry, succeeded: true),
        SerialConnectionRollbackFinishKind.released,
      );
      expect(
        coordinator.acquire(operationB).kind,
        SerialConnectionAttemptAcquisitionKind.acquired,
      );
    });

    test('stale rollback cannot release a successor lease', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final operationA = _identity(ownerA, 'call-a');
      final operationB = _identity(ownerB, 'call-b');
      final receipt = _retiredOpenedReceipt(coordinator, operationA);
      final rollback = _beginRollback(coordinator, receipt);
      expect(
        coordinator.finishRollback(rollback, succeeded: true),
        SerialConnectionRollbackFinishKind.released,
      );
      final successor = _acquire(coordinator, operationB);

      expect(
        coordinator.finishRollback(rollback, succeeded: true),
        SerialConnectionRollbackFinishKind.rejected,
      );
      expect(coordinator.releaseNoEffect(operationB, successor.token), isTrue);
    });
  });

  group('SerialConnectionAttemptCoordinator poison and clear', () {
    test('same owner different call cannot mutate the active attempt', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final firstCall = _identity(ownerA, 'call-1');
      final secondCall = _identity(ownerA, 'call-2');
      final wrongTool = _identity(ownerA, 'call-1', toolName: 'serial_close');
      final wrongOptions = _identity(
        ownerA,
        'call-1',
        options: _options(baudRate: 115200),
      );
      final lease = _acquireOpening(coordinator, firstCall);

      for (final poison in [secondCall, wrongTool, wrongOptions]) {
        expect(
          coordinator
              .markOpened(poison, lease.token, sessionFingerprint: 'poison')
              .kind,
          SerialConnectionMarkOpenedKind.rejected,
        );
        expect(coordinator.releaseNoEffect(poison, lease.token), isFalse);
      }
      expect(
        coordinator
            .markOpened(firstCall, lease.token, sessionFingerprint: 'session-a')
            .kind,
        SerialConnectionMarkOpenedKind.openedCurrent,
      );
    });

    test('clearAll retires owners and preserves rollback obligations', () {
      final coordinator = SerialConnectionAttemptCoordinator();
      final opening = _identity(ownerA, 'call-opening');
      final opened = _identity(
        ownerB,
        'call-opened',
        portName: '/dev/cu.other',
      );
      final openingLease = _acquireOpening(coordinator, opening);
      final openedLease = _acquireOpening(coordinator, opened);
      final openedReceipt = coordinator
          .markOpened(
            opened,
            openedLease.token,
            sessionFingerprint: 'session-b',
          )
          .receipt!;

      final retirement = coordinator.clearAll();
      expect(retirement.opensInFlight, hasLength(1));
      expect(retirement.opensInFlight.single, same(openingLease));
      expect(retirement.rollbackRequired, hasLength(1));
      expect(retirement.rollbackRequired.single, same(openedReceipt));
      expect(
        () => retirement.rollbackRequired.add(openedReceipt),
        throwsUnsupportedError,
      );
      expect(
        coordinator
            .acquire(_identity(ownerA, 'call-new', portName: '/dev/cu.free'))
            .kind,
        SerialConnectionAttemptAcquisitionKind.ownerRetired,
      );
      expect(
        coordinator
            .markOpened(
              opening,
              openingLease.token,
              sessionFingerprint: 'session-a',
            )
            .kind,
        SerialConnectionMarkOpenedKind.rollbackRequired,
      );
      expect(
        coordinator.finishCurrent(openedReceipt),
        SerialConnectionCommitKind.rollbackRequired,
      );

      final futureOwner = _owner('future-owner');
      expect(
        coordinator
            .acquire(
              _identity(futureOwner, 'call-future', portName: '/dev/cu.free'),
            )
            .kind,
        SerialConnectionAttemptAcquisitionKind.acquired,
      );
    });
  });
}

ChatTurnOwner _owner(String conversationId) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: 1,
  );
}

SerialConnectionAttemptIdentity _identity(
  ChatTurnOwner owner,
  String toolCallId, {
  String toolName = 'serial_open',
  String portName = '/dev/cu.sensor',
  SerialConnectionOptions? options,
}) {
  return SerialConnectionAttemptIdentity(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
    portName: portName,
    options: options ?? _options(),
  );
}

SerialConnectionOptions _options({int baudRate = 9600}) {
  return SerialConnectionOptions(
    baudRate: baudRate,
    dataBits: 8,
    parity: 'none',
    stopBits: 1,
    flowControl: 'none',
  );
}

SerialConnectionAttemptLease _acquire(
  SerialConnectionAttemptCoordinator coordinator,
  SerialConnectionAttemptIdentity identity,
) {
  final result = coordinator.acquire(identity);
  expect(result.kind, SerialConnectionAttemptAcquisitionKind.acquired);
  return result.lease!;
}

SerialConnectionAttemptLease _acquireOpening(
  SerialConnectionAttemptCoordinator coordinator,
  SerialConnectionAttemptIdentity identity,
) {
  final lease = _acquire(coordinator, identity);
  expect(
    coordinator.beginOpen(identity, lease.token),
    SerialConnectionBeginOpenKind.begun,
  );
  return lease;
}

SerialConnectionOpenedReceipt _retiredOpenedReceipt(
  SerialConnectionAttemptCoordinator coordinator,
  SerialConnectionAttemptIdentity identity,
) {
  final lease = _acquireOpening(coordinator, identity);
  coordinator.clearOwner(identity.owner);
  final result = coordinator.markOpened(
    identity,
    lease.token,
    sessionFingerprint: 'session-a',
  );
  expect(result.kind, SerialConnectionMarkOpenedKind.rollbackRequired);
  return result.receipt!;
}

SerialConnectionRollbackPermit _beginRollback(
  SerialConnectionAttemptCoordinator coordinator,
  SerialConnectionOpenedReceipt receipt,
) {
  final result = coordinator.beginRollback(
    receipt,
    observedSessionFingerprint: receipt.sessionFingerprint,
  );
  expect(result.kind, SerialConnectionRollbackBeginKind.begun);
  return result.permit!;
}
