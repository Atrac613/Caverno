import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/browser_session_ownership_coordinator.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 4,
  );

  group('BrowserSessionOperationIdentity', () {
    test('normalizes and compares the complete immutable identity', () {
      final first = BrowserSessionOperationIdentity(
        owner: ownerA,
        toolCallId: ' call-1 ',
        toolName: ' browser_click ',
      );
      final equal = BrowserSessionOperationIdentity(
        owner: ownerA,
        toolCallId: 'call-1',
        toolName: 'browser_click',
      );
      final differentCall = BrowserSessionOperationIdentity(
        owner: ownerA,
        toolCallId: 'call-2',
        toolName: 'browser_click',
      );

      expect(first.toolCallId, 'call-1');
      expect(first.toolName, 'browser_click');
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(differentCall));
    });

    test('rejects empty tool call and tool names', () {
      expect(
        () => BrowserSessionOperationIdentity(
          owner: ownerA,
          toolCallId: ' ',
          toolName: 'browser_click',
        ),
        throwsArgumentError,
      );
      expect(
        () => BrowserSessionOperationIdentity(
          owner: ownerA,
          toolCallId: 'call-1',
          toolName: '\n',
        ),
        throwsArgumentError,
      );
    });
  });

  group('BrowserSessionOwnershipCoordinator acquisition', () {
    test('distinguishes acquired, busy, and ownerExpired', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final sessionEpoch = coordinator.captureSessionEpoch();
      final operationA = _operation(ownerA, 'call-a');
      final operationB = _operation(ownerB, 'call-b');

      final acquired = coordinator.acquire(operationA, sessionEpoch);
      final busy = coordinator.acquire(operationB, sessionEpoch);
      coordinator.clearOwner(ownerB);
      final expired = coordinator.acquire(operationB, sessionEpoch);

      expect(acquired.kind, BrowserSessionLeaseAcquisitionKind.acquired);
      expect(acquired.lease, isNotNull);
      expect(busy.kind, BrowserSessionLeaseAcquisitionKind.busy);
      expect(busy.lease, isNull);
      expect(expired.kind, BrowserSessionLeaseAcquisitionKind.ownerExpired);
      expect(expired.lease, isNull);
    });

    test('serializes A and B with monotonic opaque lease epochs', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final operationA = _operation(ownerA, 'call-a');
      final operationB = _operation(ownerB, 'call-b');
      final leaseA = _acquire(coordinator, operationA);

      expect(
        coordinator.acquire(operationB, coordinator.captureSessionEpoch()).kind,
        BrowserSessionLeaseAcquisitionKind.busy,
      );
      expect(_release(coordinator, operationA, leaseA), isTrue);

      final leaseB = _acquire(coordinator, operationB);
      expect(leaseB.token.epoch, greaterThan(leaseA.token.epoch));
      expect(_isCurrent(coordinator, operationB, leaseB), isTrue);
    });

    test('requires token identity even when lease epochs match', () {
      final firstCoordinator = BrowserSessionOwnershipCoordinator();
      final secondCoordinator = BrowserSessionOwnershipCoordinator();
      final operation = _operation(ownerA, 'call-a');
      final firstLease = _acquire(firstCoordinator, operation);
      final foreignLease = _acquire(secondCoordinator, operation);

      expect(firstLease.token.epoch, foreignLease.token.epoch);
      expect(
        firstCoordinator.release(
          operation,
          firstLease.sessionEpoch,
          foreignLease.token,
        ),
        isFalse,
      );
      expect(_isCurrent(firstCoordinator, operation, firstLease), isTrue);
    });

    test('cannot settle a lease while its operation is still current', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final operation = _operation(ownerA, 'call-a');
      final lease = _acquire(coordinator, operation);

      expect(coordinator.settleInvalidatedLease(lease), isFalse);
      expect(_isCurrent(coordinator, operation, lease), isTrue);
    });

    test('rejects a foreign session snapshot with the same numeric epoch', () {
      final firstCoordinator = BrowserSessionOwnershipCoordinator();
      final secondCoordinator = BrowserSessionOwnershipCoordinator();
      final firstEpoch = firstCoordinator.captureSessionEpoch();
      final foreignEpoch = secondCoordinator.captureSessionEpoch();

      expect(firstEpoch.epoch, foreignEpoch.epoch);
      final result = firstCoordinator.acquire(
        _operation(ownerA, 'call-a'),
        foreignEpoch,
      );

      expect(result.kind, BrowserSessionLeaseAcquisitionKind.staleSession);
      expect(result.lease, isNull);
    });
  });

  group('BrowserSessionOwnershipCoordinator stale work', () {
    test('stale A release and revision cannot disturb successor B', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final operationA = _operation(ownerA, 'call-a');
      final operationB = _operation(ownerB, 'call-b');
      final leaseA = _acquire(coordinator, operationA);
      expect(_release(coordinator, operationA, leaseA), isTrue);
      final leaseB = _acquire(coordinator, operationB);

      expect(_release(coordinator, operationA, leaseA), isFalse);
      expect(
        coordinator.advancePageRevision(
          operationA,
          leaseA.sessionEpoch,
          leaseA.token,
        ),
        isNull,
      );
      expect(_isCurrent(coordinator, operationB, leaseB), isTrue);
      expect(
        coordinator.isPageRevisionCurrent(
          operationB,
          leaseB.sessionEpoch,
          leaseB.token,
          leaseB.pageRevision,
        ),
        isTrue,
      );
    });

    test('rejects an old snapshot after exact and global revision changes', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final operation = _operation(ownerA, 'call-a');
      final lease = _acquire(coordinator, operation);

      final successor = coordinator.advancePageRevision(
        operation,
        lease.sessionEpoch,
        lease.token,
      );
      expect(successor, isNotNull);
      expect(
        coordinator.isPageRevisionCurrent(
          operation,
          lease.sessionEpoch,
          lease.token,
          lease.pageRevision,
        ),
        isFalse,
      );
      expect(
        coordinator.isPageRevisionCurrent(
          operation,
          lease.sessionEpoch,
          lease.token,
          successor!,
        ),
        isTrue,
      );

      expect(
        coordinator.invalidatePageRevisionGlobally(lease.sessionEpoch),
        isTrue,
      );
      expect(
        coordinator.isPageRevisionCurrent(
          operation,
          lease.sessionEpoch,
          lease.token,
          successor,
        ),
        isFalse,
      );
      final recaptured = coordinator.capturePageRevision(
        operation,
        lease.sessionEpoch,
        lease.token,
      );
      expect(recaptured, isNotNull);
      expect(recaptured!.revision, greaterThan(successor.revision));
    });

    test('validates a same-owner lease against the exact tool call', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final firstCall = _operation(ownerA, 'call-1');
      final secondCall = _operation(ownerA, 'call-2');
      final wrongTool = _operation(ownerA, 'call-1', toolName: 'browser_fill');
      final lease = _acquire(coordinator, firstCall);

      for (final poison in [secondCall, wrongTool]) {
        expect(
          coordinator.isLeaseCurrent(poison, lease.sessionEpoch, lease.token),
          isFalse,
        );
        expect(
          coordinator.capturePageRevision(
            poison,
            lease.sessionEpoch,
            lease.token,
          ),
          isNull,
        );
        expect(
          coordinator.advancePageRevision(
            poison,
            lease.sessionEpoch,
            lease.token,
          ),
          isNull,
        );
        expect(
          coordinator.release(poison, lease.sessionEpoch, lease.token),
          isFalse,
        );
      }
      expect(_isCurrent(coordinator, firstCall, lease), isTrue);
      expect(_release(coordinator, firstCall, lease), isTrue);
    });

    test('rejects an unknown operation captured before session clear', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final staleEpoch = coordinator.captureSessionEpoch();
      final unknownOwner = ChatTurnOwner(
        conversationId: 'never-acquired',
        interactionGeneration: 1,
      );

      coordinator.clearAll();
      final result = coordinator.acquire(
        _operation(unknownOwner, 'late-call'),
        staleEpoch,
      );

      expect(result.kind, BrowserSessionLeaseAcquisitionKind.staleSession);
      expect(result.lease, isNull);
    });

    test('accepts a future owner with the current post-clear epoch', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final staleEpoch = coordinator.captureSessionEpoch();
      coordinator.invalidateSession();
      final currentEpoch = coordinator.captureSessionEpoch();
      final futureOwner = ChatTurnOwner(
        conversationId: 'future-owner',
        interactionGeneration: 1,
      );

      expect(currentEpoch.epoch, greaterThan(staleEpoch.epoch));
      expect(
        coordinator
            .acquire(_operation(futureOwner, 'current-call'), currentEpoch)
            .kind,
        BrowserSessionLeaseAcquisitionKind.acquired,
      );
    });

    test('rejects a late page event from the prior browser session', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final staleEpoch = coordinator.captureSessionEpoch();
      coordinator.invalidateSession();
      final currentEpoch = coordinator.captureSessionEpoch();
      final operation = _operation(ownerA, 'current-call');
      final lease = coordinator.acquire(operation, currentEpoch).lease!;

      expect(coordinator.invalidatePageRevisionGlobally(staleEpoch), isFalse);
      expect(
        coordinator.isPageRevisionCurrent(
          operation,
          currentEpoch,
          lease.token,
          lease.pageRevision,
        ),
        isTrue,
      );
    });
  });

  group('BrowserSessionOwnershipCoordinator terminalization', () {
    test('terminal owner revokes its lease without blocking another owner', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final operationA = _operation(ownerA, 'call-a');
      final operationB = _operation(ownerB, 'call-b');
      final leaseA = _acquire(coordinator, operationA);

      final cleared = coordinator.clearOwner(ownerA);
      final repeated = coordinator.clearOwner(ownerA);
      expect(cleared.becameTerminal, isTrue);
      expect(cleared.invalidatedLease, same(leaseA));
      expect(repeated.becameTerminal, isFalse);
      expect(repeated.invalidatedLease, same(leaseA));
      expect(_isCurrent(coordinator, operationA, leaseA), isFalse);
      expect(
        coordinator.acquire(operationA, coordinator.captureSessionEpoch()).kind,
        BrowserSessionLeaseAcquisitionKind.ownerExpired,
      );

      expect(
        coordinator.acquire(operationB, coordinator.captureSessionEpoch()).kind,
        BrowserSessionLeaseAcquisitionKind.busy,
      );
      expect(coordinator.settleInvalidatedLease(leaseA), isTrue);
      expect(coordinator.settleInvalidatedLease(leaseA), isFalse);
      final leaseB = _acquire(coordinator, operationB);
      expect(_isCurrent(coordinator, operationB, leaseB), isTrue);
    });

    test('global clear fences known owners but permits a future owner', () {
      final coordinator = BrowserSessionOwnershipCoordinator();
      final operationA = _operation(ownerA, 'call-a');
      final operationB = _operation(ownerB, 'call-b');
      final leaseA = _acquire(coordinator, operationA);
      expect(_release(coordinator, operationA, leaseA), isTrue);
      final leaseB = _acquire(coordinator, operationB);

      final invalidation = coordinator.clearAll();
      final currentEpoch = coordinator.captureSessionEpoch();

      expect(invalidation.invalidatedLease, same(leaseB));
      expect(invalidation.previousEpoch.epoch, lessThan(currentEpoch.epoch));
      expect(invalidation.currentEpoch, same(currentEpoch));
      expect(_isCurrent(coordinator, operationB, leaseB), isFalse);
      expect(
        coordinator.acquire(operationA, currentEpoch).kind,
        BrowserSessionLeaseAcquisitionKind.ownerExpired,
      );
      expect(
        coordinator.acquire(operationB, currentEpoch).kind,
        BrowserSessionLeaseAcquisitionKind.ownerExpired,
      );

      final successor = ChatTurnOwner(
        conversationId: ownerA.conversationId,
        interactionGeneration: ownerA.interactionGeneration + 1,
      );
      expect(
        coordinator
            .acquire(_operation(successor, 'call-next'), currentEpoch)
            .kind,
        BrowserSessionLeaseAcquisitionKind.busy,
      );
      expect(coordinator.settleInvalidatedLease(leaseB), isTrue);
      expect(
        coordinator
            .acquire(_operation(successor, 'call-next'), currentEpoch)
            .kind,
        BrowserSessionLeaseAcquisitionKind.acquired,
      );
    });
  });

  group('BrowserSessionOwnershipCoordinator effect recovery', () {
    test(
      'retains an exact settled effect until external reconciliation',
      () async {
        final coordinator = BrowserSessionOwnershipCoordinator();
        final foreignCoordinator = BrowserSessionOwnershipCoordinator();
        final operation = _operation(ownerA, 'call-a');
        final lease = _acquire(coordinator, operation);
        final permit = coordinator.authorizeEffect(lease)!;
        await permit.runEffect(() async {});
        final receipt = permit.receipt!;

        final foreignLease = _acquire(foreignCoordinator, operation);
        final foreignPermit = foreignCoordinator.authorizeEffect(foreignLease)!;
        await foreignPermit.runEffect(() async {});
        final foreignReceipt = foreignPermit.receipt!;

        coordinator.clearOwner(ownerA);

        expect(_release(coordinator, operation, lease), isFalse);
        expect(coordinator.settleInvalidatedLease(lease), isFalse);
        expect(coordinator.pendingEffectRecovery, same(receipt));
        expect(coordinator.clearEffectRecovery(foreignReceipt), isFalse);
        expect(coordinator.clearEffectRecovery(receipt), isTrue);
        expect(coordinator.pendingEffectRecovery, isNull);
      },
    );

    test(
      'does not clear a receipt while its callback is still active',
      () async {
        final coordinator = BrowserSessionOwnershipCoordinator();
        final operation = _operation(ownerA, 'call-a');
        final lease = _acquire(coordinator, operation);
        final permit = coordinator.authorizeEffect(lease)!;
        final started = Completer<void>();
        final release = Completer<void>();

        final pending = permit.runEffect(() async {
          started.complete();
          await release.future;
        });
        await started.future;
        final receipt = permit.receipt!;

        expect(coordinator.clearEffectRecovery(receipt), isFalse);
        release.complete();
        await pending;
        expect(coordinator.clearEffectRecovery(receipt), isTrue);
      },
    );
  });
}

BrowserSessionOperationIdentity _operation(
  ChatTurnOwner owner,
  String toolCallId, {
  String toolName = 'browser_click',
}) {
  return BrowserSessionOperationIdentity(
    owner: owner,
    toolCallId: toolCallId,
    toolName: toolName,
  );
}

BrowserSessionLease _acquire(
  BrowserSessionOwnershipCoordinator coordinator,
  BrowserSessionOperationIdentity operation,
) {
  final result = coordinator.acquire(
    operation,
    coordinator.captureSessionEpoch(),
  );
  expect(result.kind, BrowserSessionLeaseAcquisitionKind.acquired);
  return result.lease!;
}

bool _isCurrent(
  BrowserSessionOwnershipCoordinator coordinator,
  BrowserSessionOperationIdentity operation,
  BrowserSessionLease lease,
) {
  return coordinator.isLeaseCurrent(operation, lease.sessionEpoch, lease.token);
}

bool _release(
  BrowserSessionOwnershipCoordinator coordinator,
  BrowserSessionOperationIdentity operation,
  BrowserSessionLease lease,
) {
  return coordinator.release(operation, lease.sessionEpoch, lease.token);
}
