import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/computer_use_runtime_coordinator.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 7, 31, 12);

ChatTurnOwner _owner(String conversationId, [int generation = 1]) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

ComputerUseOperationIdentity _identity({
  ChatTurnOwner? owner,
  String toolCallId = 'call-1',
  String toolName = 'computer_click',
  String argumentDigest = 'sha256:abc',
  String runtimeSessionId = 'runtime-1',
}) {
  return ComputerUseOperationIdentity(
    owner: owner ?? _owner('conversation-a'),
    toolCallId: toolCallId,
    toolName: toolName,
    argumentDigest: argumentDigest,
    runtimeSessionId: runtimeSessionId,
  );
}

ComputerUseArmingGrant _arm(
  ComputerUseRuntimeCoordinator coordinator,
  ComputerUseOperationIdentity identity, {
  int revision = 3,
  Duration ttl = const Duration(minutes: 1),
}) {
  final result = coordinator.arm(
    identity: identity,
    runtimeRevision: revision,
    armed: true,
    now: _now,
    expiresAt: _now.add(ttl),
  );
  expect(result.disposition, ComputerUseArmingDisposition.granted);
  return result.grant!;
}

ComputerUseRuntimePermit _consume(
  ComputerUseRuntimeCoordinator coordinator,
  ComputerUseArmingGrant grant, {
  ComputerUseOperationIdentity? identity,
  int revision = 3,
  DateTime? now,
}) {
  final result = coordinator.consumeGrant(
    grant: grant,
    identity: identity ?? grant.identity,
    runtimeRevision: revision,
    now: now ?? _now,
  );
  expect(result.disposition, ComputerUseGrantConsumeDisposition.consumed);
  return result.permit!;
}

ComputerUseRuntimeLease _acquire(
  ComputerUseRuntimeCoordinator coordinator,
  ComputerUseRuntimePermit permit, {
  DateTime? now,
}) {
  final result = coordinator.acquireLease(
    permit: permit,
    identity: permit.identity,
    currentRuntimeRevision: permit.runtimeRevision,
    now: now ?? _now,
  );
  expect(result.disposition, ComputerUseLeaseAcquisitionDisposition.acquired);
  return result.lease!;
}

void main() {
  group('operation identity', () {
    test('compares every immutable operation component', () {
      final owner = _owner('conversation-a');
      final identity = _identity(owner: owner);

      expect(_identity(owner: owner), identity);
      expect(_identity(owner: _owner('conversation-a', 2)), isNot(identity));
      expect(_identity(owner: owner, toolCallId: 'call-2'), isNot(identity));
      expect(
        _identity(owner: owner, toolName: 'computer_scroll'),
        isNot(identity),
      );
      expect(
        _identity(owner: owner, argumentDigest: 'sha256:def'),
        isNot(identity),
      );
      expect(
        _identity(owner: owner, runtimeSessionId: 'runtime-2'),
        isNot(identity),
      );
    });

    test('normalizes and rejects incomplete operation components', () {
      final normalized = _identity(
        toolCallId: ' call-1 ',
        toolName: ' computer_click ',
        argumentDigest: ' sha256:abc ',
        runtimeSessionId: ' runtime-1 ',
      );

      expect(normalized, _identity());
      for (final values in [
        (' ', 'computer_click', 'sha256:abc', 'runtime-1'),
        ('call-1', '\n', 'sha256:abc', 'runtime-1'),
        ('call-1', 'computer_click', '\t', 'runtime-1'),
        ('call-1', 'computer_click', 'sha256:abc', ''),
      ]) {
        expect(
          () => _identity(
            toolCallId: values.$1,
            toolName: values.$2,
            argumentDigest: values.$3,
            runtimeSessionId: values.$4,
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects a negative runtime revision before arming', () {
      expect(
        () => ComputerUseRuntimeCoordinator().arm(
          identity: _identity(),
          runtimeRevision: -1,
          armed: true,
          now: _now,
          expiresAt: _now.add(const Duration(minutes: 1)),
        ),
        throwsRangeError,
      );
    });
  });

  group('arming grant consumption', () {
    test('armed false creates no grant and nullable consume is typed', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final identity = _identity();

      final arming = coordinator.arm(
        identity: identity,
        runtimeRevision: 3,
        armed: false,
        now: _now,
        expiresAt: _now.add(const Duration(minutes: 1)),
      );
      final consume = coordinator.consumeGrant(
        grant: arming.grant,
        identity: identity,
        runtimeRevision: 3,
        now: _now,
      );

      expect(arming.disposition, ComputerUseArmingDisposition.notArmed);
      expect(arming.grant, isNull);
      expect(consume.disposition, ComputerUseGrantConsumeDisposition.noGrant);
      expect(consume.permit, isNull);
    });

    test('binds owner, call, digest, session, tool, and revision', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final identity = _identity();
      final grant = _arm(coordinator, identity);
      final mismatches = [
        _identity(owner: _owner('conversation-b')),
        _identity(toolCallId: 'call-2'),
        _identity(argumentDigest: 'sha256:def'),
        _identity(runtimeSessionId: 'runtime-2'),
        _identity(toolName: 'computer_scroll'),
      ];

      for (final mismatch in mismatches) {
        final result = coordinator.consumeGrant(
          grant: grant,
          identity: mismatch,
          runtimeRevision: 3,
          now: _now,
        );
        expect(
          result.disposition,
          ComputerUseGrantConsumeDisposition.identityMismatch,
        );
      }
      final wrongRevision = coordinator.consumeGrant(
        grant: grant,
        identity: identity,
        runtimeRevision: 4,
        now: _now,
      );

      expect(
        wrongRevision.disposition,
        ComputerUseGrantConsumeDisposition.revisionMismatch,
      );
      expect(_consume(coordinator, grant).identity, identity);
    });

    test('consumes once and rejects replay', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final identity = _identity();
      final grant = _arm(coordinator, identity);

      final permit = _consume(coordinator, grant);
      final replay = coordinator.consumeGrant(
        grant: grant,
        identity: identity,
        runtimeRevision: 3,
        now: _now,
      );

      expect(permit.identity, identity);
      expect(permit.runtimeRevision, 3);
      expect(replay.disposition, ComputerUseGrantConsumeDisposition.replayed);
      expect(replay.permit, isNull);
    });

    test('expires at the exact deadline', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final identity = _identity();
      final grant = _arm(
        coordinator,
        identity,
        ttl: const Duration(seconds: 5),
      );

      final result = coordinator.consumeGrant(
        grant: grant,
        identity: identity,
        runtimeRevision: 3,
        now: _now.add(const Duration(seconds: 5)),
      );

      expect(result.disposition, ComputerUseGrantConsumeDisposition.expired);
      expect(result.permit, isNull);
    });

    test('explicit disarming revokes an earlier matching grant', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final identity = _identity();
      final grant = _arm(coordinator, identity);

      coordinator.arm(
        identity: identity,
        runtimeRevision: 3,
        armed: false,
        now: _now,
        expiresAt: _now.add(const Duration(minutes: 1)),
      );
      final result = coordinator.consumeGrant(
        grant: grant,
        identity: identity,
        runtimeRevision: 3,
        now: _now,
      );

      expect(result.disposition, ComputerUseGrantConsumeDisposition.revoked);
    });

    test('rearming supersedes the earlier matching grant', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final identity = _identity();
      final earlier = _arm(coordinator, identity);
      final successor = _arm(coordinator, identity);

      final stale = coordinator.consumeGrant(
        grant: earlier,
        identity: identity,
        runtimeRevision: 3,
        now: _now,
      );

      expect(stale.disposition, ComputerUseGrantConsumeDisposition.superseded);
      expect(_consume(coordinator, successor).identity, identity);
    });
  });

  group('exclusive runtime lease', () {
    test('returns typed outcomes for missing and expired permits', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final missing = coordinator.acquireLease(
        permit: null,
        identity: _identity(),
        currentRuntimeRevision: 3,
        now: _now,
      );
      final permit = _consume(
        coordinator,
        _arm(coordinator, _identity(), ttl: const Duration(seconds: 5)),
      );
      final wrongIdentity = coordinator.acquireLease(
        permit: permit,
        identity: _identity(toolCallId: 'wrong-call'),
        currentRuntimeRevision: 3,
        now: _now,
      );
      final wrongRevision = coordinator.acquireLease(
        permit: permit,
        identity: permit.identity,
        currentRuntimeRevision: 4,
        now: _now,
      );
      final expired = coordinator.acquireLease(
        permit: permit,
        identity: permit.identity,
        currentRuntimeRevision: 3,
        now: _now.add(const Duration(seconds: 5)),
      );

      expect(
        missing.disposition,
        ComputerUseLeaseAcquisitionDisposition.noPermit,
      );
      expect(
        wrongIdentity.disposition,
        ComputerUseLeaseAcquisitionDisposition.identityMismatch,
      );
      expect(
        wrongRevision.disposition,
        ComputerUseLeaseAcquisitionDisposition.revisionMismatch,
      );
      expect(
        expired.disposition,
        ComputerUseLeaseAcquisitionDisposition.expired,
      );
    });

    test('uses a one-shot permit and an opaque token', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final permit = _consume(coordinator, _arm(coordinator, _identity()));

      final lease = _acquire(coordinator, permit);
      final replay = coordinator.acquireLease(
        permit: permit,
        identity: permit.identity,
        currentRuntimeRevision: permit.runtimeRevision,
        now: _now,
      );

      expect(lease.token.toString(), 'ComputerUseRuntimeLeaseToken(<opaque>)');
      expect(coordinator.activeLease, same(lease));
      expect(
        coordinator.isLeaseCurrent(permit.identity, 3, lease.token),
        isTrue,
      );
      expect(
        coordinator.isLeaseCurrent(permit.identity, 4, lease.token),
        isFalse,
      );
      expect(
        coordinator.isLeaseCurrent(
          _identity(toolCallId: 'different-call'),
          3,
          lease.token,
        ),
        isFalse,
      );
      expect(
        replay.disposition,
        ComputerUseLeaseAcquisitionDisposition.replayed,
      );
    });

    test('keeps a busy permit retryable and protects the successor lease', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final permitA = _consume(
        coordinator,
        _arm(coordinator, _identity(toolCallId: 'call-a')),
      );
      final permitB = _consume(
        coordinator,
        _arm(
          coordinator,
          _identity(owner: _owner('conversation-b'), toolCallId: 'call-b'),
        ),
      );
      final leaseA = _acquire(coordinator, permitA);

      final busy = coordinator.acquireLease(
        permit: permitB,
        identity: permitB.identity,
        currentRuntimeRevision: permitB.runtimeRevision,
        now: _now,
      );
      final releasedA = coordinator.releaseLease(leaseA.token);
      final leaseB = _acquire(coordinator, permitB);
      final staleReleaseA = coordinator.releaseLease(leaseA.token);

      expect(busy.disposition, ComputerUseLeaseAcquisitionDisposition.busy);
      expect(releasedA, ComputerUseLeaseReleaseDisposition.released);
      expect(leaseB.token, isNot(leaseA.token));
      expect(staleReleaseA, ComputerUseLeaseReleaseDisposition.alreadyReleased);
      expect(
        coordinator.isLeaseCurrent(permitA.identity, 3, leaseA.token),
        isFalse,
      );
      expect(
        coordinator.isLeaseCurrent(permitB.identity, 3, leaseB.token),
        isTrue,
      );
      expect(coordinator.activeLease, same(leaseB));
    });

    test('discards only a permit that has not acquired a lease', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final ready = _consume(
        coordinator,
        _arm(coordinator, _identity(toolCallId: 'ready')),
      );
      final acquired = _consume(
        coordinator,
        _arm(coordinator, _identity(toolCallId: 'acquired')),
      );
      final lease = _acquire(coordinator, acquired);

      expect(coordinator.discardPermit(ready), isTrue);
      expect(coordinator.discardPermit(ready), isFalse);
      expect(coordinator.discardPermit(acquired), isFalse);
      expect(
        coordinator
            .acquireLease(
              permit: ready,
              identity: ready.identity,
              currentRuntimeRevision: ready.runtimeRevision,
              now: _now,
            )
            .disposition,
        ComputerUseLeaseAcquisitionDisposition.noPermit,
      );
      expect(coordinator.activeLease, same(lease));
    });

    test('rejects a token issued by another coordinator', () {
      final coordinatorA = ComputerUseRuntimeCoordinator();
      final coordinatorB = ComputerUseRuntimeCoordinator();
      final leaseA = _acquire(
        coordinatorA,
        _consume(coordinatorA, _arm(coordinatorA, _identity())),
      );
      final leaseB = _acquire(
        coordinatorB,
        _consume(coordinatorB, _arm(coordinatorB, _identity())),
      );

      final result = coordinatorB.releaseLease(leaseA.token);

      expect(result, ComputerUseLeaseReleaseDisposition.staleToken);
      expect(
        coordinatorB.isLeaseCurrent(leaseB.identity, 3, leaseA.token),
        isFalse,
      );
      expect(coordinatorB.activeLease, same(leaseB));
    });
  });

  group('runtime epoch invalidation', () {
    test('helper restart holds the active lease until settlement', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final activePermit = _consume(
        coordinator,
        _arm(coordinator, _identity(toolCallId: 'active')),
      );
      final lease = _acquire(coordinator, activePermit);
      final pendingIdentity = _identity(toolCallId: 'pending');
      final pendingGrant = _arm(coordinator, pendingIdentity);

      final invalidation = coordinator.helperRestarted();
      final oldGrant = coordinator.consumeGrant(
        grant: pendingGrant,
        identity: pendingIdentity,
        runtimeRevision: 3,
        now: _now,
      );
      final successorPermit = _consume(
        coordinator,
        _arm(coordinator, _identity(toolCallId: 'successor')),
      );
      final blockedSuccessor = coordinator.acquireLease(
        permit: successorPermit,
        identity: successorPermit.identity,
        currentRuntimeRevision: successorPermit.runtimeRevision,
        now: _now,
      );
      final oldRelease = coordinator.releaseLease(lease.token);
      final settled = coordinator.settleInvalidatedLease(lease);
      final successorLease = _acquire(coordinator, successorPermit);

      expect(
        invalidation.disposition,
        ComputerUseRuntimeInvalidationDisposition.invalidated,
      );
      expect(
        invalidation.cause,
        ComputerUseRuntimeInvalidationCause.helperRestart,
      );
      expect(invalidation.previousEpoch, 0);
      expect(invalidation.runtimeEpoch, 1);
      expect(invalidation.invalidatedLease, same(lease));
      expect(
        oldGrant.disposition,
        ComputerUseGrantConsumeDisposition.runtimeInvalidated,
      );
      expect(
        blockedSuccessor.disposition,
        ComputerUseLeaseAcquisitionDisposition.busy,
      );
      expect(
        oldRelease,
        ComputerUseLeaseReleaseDisposition.invalidationPending,
      );
      expect(settled, isTrue);
      expect(coordinator.settleInvalidatedLease(lease), isFalse);
      expect(coordinator.activeLease, same(successorLease));
    });

    test('emergency stop invalidates a consumed permit', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final permit = _consume(coordinator, _arm(coordinator, _identity()));

      final invalidation = coordinator.emergencyStop();
      final acquisition = coordinator.acquireLease(
        permit: permit,
        identity: permit.identity,
        currentRuntimeRevision: permit.runtimeRevision,
        now: _now,
      );

      expect(
        invalidation.cause,
        ComputerUseRuntimeInvalidationCause.emergencyStop,
      );
      expect(coordinator.runtimeEpoch, 1);
      expect(
        acquisition.disposition,
        ComputerUseLeaseAcquisitionDisposition.runtimeInvalidated,
      );
    });
  });

  group('terminal clearing', () {
    test('owner clear is permanent and leaves other owners usable', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      final identityA = _identity(owner: ownerA, toolCallId: 'call-a');
      final permitA = _consume(coordinator, _arm(coordinator, identityA));
      final leaseA = _acquire(coordinator, permitA);
      final pendingIdentityA = _identity(
        owner: ownerA,
        toolCallId: 'pending-a',
      );
      final pendingGrantA = _arm(coordinator, pendingIdentityA);
      final permitB = _consume(
        coordinator,
        _arm(coordinator, _identity(owner: ownerB, toolCallId: 'call-b')),
      );

      final cleared = coordinator.clearOwner(ownerA);
      final repeated = coordinator.clearOwner(ownerA);
      final rejected = coordinator.arm(
        identity: identityA,
        runtimeRevision: 3,
        armed: true,
        now: _now,
        expiresAt: _now.add(const Duration(minutes: 1)),
      );
      final staleGrant = coordinator.consumeGrant(
        grant: pendingGrantA,
        identity: pendingIdentityA,
        runtimeRevision: 3,
        now: _now,
      );
      final stalePermit = coordinator.acquireLease(
        permit: permitA,
        identity: permitA.identity,
        currentRuntimeRevision: permitA.runtimeRevision,
        now: _now,
      );
      final blockedB = coordinator.acquireLease(
        permit: permitB,
        identity: permitB.identity,
        currentRuntimeRevision: permitB.runtimeRevision,
        now: _now,
      );
      final invalidatedRelease = coordinator.releaseLease(leaseA.token);
      final settled = coordinator.settleInvalidatedLease(leaseA);
      final leaseB = _acquire(coordinator, permitB);

      expect(cleared.disposition, ComputerUseTerminalClearDisposition.cleared);
      expect(cleared.invalidatedLease, same(leaseA));
      expect(
        repeated.disposition,
        ComputerUseTerminalClearDisposition.alreadyCleared,
      );
      expect(repeated.invalidatedLease, same(leaseA));
      expect(
        rejected.disposition,
        ComputerUseArmingDisposition.ownerTerminated,
      );
      expect(
        staleGrant.disposition,
        ComputerUseGrantConsumeDisposition.ownerTerminated,
      );
      expect(
        stalePermit.disposition,
        ComputerUseLeaseAcquisitionDisposition.ownerTerminated,
      );
      expect(blockedB.disposition, ComputerUseLeaseAcquisitionDisposition.busy);
      expect(
        invalidatedRelease,
        ComputerUseLeaseReleaseDisposition.invalidationPending,
      );
      expect(settled, isTrue);
      expect(coordinator.settleInvalidatedLease(leaseB), isFalse);
      expect(coordinator.activeLease, same(leaseB));
    });

    test('global clear is permanent across arm, consume, and acquire', () {
      final coordinator = ComputerUseRuntimeCoordinator();
      final identity = _identity();
      final permit = _consume(coordinator, _arm(coordinator, identity));
      final lease = _acquire(coordinator, permit);
      final pendingGrant = _arm(coordinator, _identity(toolCallId: 'pending'));

      final cleared = coordinator.clearAll();
      final arming = coordinator.arm(
        identity: identity,
        runtimeRevision: 3,
        armed: true,
        now: _now,
        expiresAt: _now.add(const Duration(minutes: 1)),
      );
      final consume = coordinator.consumeGrant(
        grant: pendingGrant,
        identity: pendingGrant.identity,
        runtimeRevision: 3,
        now: _now,
      );
      final acquisition = coordinator.acquireLease(
        permit: permit,
        identity: permit.identity,
        currentRuntimeRevision: permit.runtimeRevision,
        now: _now,
      );
      final repeated = coordinator.clearAll();
      final invalidatedRelease = coordinator.releaseLease(lease.token);
      final settled = coordinator.settleInvalidatedLease(lease);
      final settledRepeat = coordinator.clearAll();

      expect(cleared.disposition, ComputerUseTerminalClearDisposition.cleared);
      expect(cleared.invalidatedLease, same(lease));
      expect(coordinator.isLeaseCurrent(identity, 3, lease.token), isFalse);
      expect(
        arming.disposition,
        ComputerUseArmingDisposition.globallyTerminated,
      );
      expect(
        consume.disposition,
        ComputerUseGrantConsumeDisposition.globallyTerminated,
      );
      expect(
        acquisition.disposition,
        ComputerUseLeaseAcquisitionDisposition.globallyTerminated,
      );
      expect(
        repeated.disposition,
        ComputerUseTerminalClearDisposition.alreadyCleared,
      );
      expect(repeated.invalidatedLease, same(lease));
      expect(
        invalidatedRelease,
        ComputerUseLeaseReleaseDisposition.invalidationPending,
      );
      expect(settled, isTrue);
      expect(settledRepeat.invalidatedLease, isNull);
    });
  });
}
