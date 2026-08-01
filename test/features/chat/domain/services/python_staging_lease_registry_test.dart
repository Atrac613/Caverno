import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/python_staging_lease_registry.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = _owner('conversation-a', 7);
  final ownerB = _owner('conversation-b', 7);

  group('Python staging identities', () {
    test('normalizes attempts and keeps tokens opaque', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = PythonStagingAttempt(
        owner: ownerA,
        toolCallId: ' call-a ',
        toolName: ' run_python_script ',
      );

      expect(attempt, _attempt(ownerA, 'call-a'));
      expect(attempt.toolCallId, 'call-a');
      expect(attempt.toolName, 'run_python_script');
      expect(attempt.hashCode, _attempt(ownerA, 'call-a').hashCode);
      expect(
        () => PythonStagingAttempt(
          owner: ownerA,
          toolCallId: ' ',
          toolName: 'run_python_script',
        ),
        throwsArgumentError,
      );

      final first = registry.reserve(attempt);
      final second = registry.reserve(_attempt(ownerB, 'call-b'));
      expect(first.status, PythonStagingReserveStatus.reserved);
      expect(first.token.toString(), 'PythonStagingLeaseToken(<opaque>)');
      expect(first.token, isNot(same(second.token)));
      expect(
        registry.reserve(_attempt(ownerA, 'call-a')).status,
        PythonStagingReserveStatus.attemptConflict,
      );
    });

    test('requires canonical paths and replacement markers', () {
      final identity = PythonStagingDirectoryIdentity(
        canonicalPath: ' /tmp/python-a ',
        markerNonce: ' marker-a ',
        deviceId: 4,
        inode: 9,
      );

      expect(identity.canonicalPath, '/tmp/python-a');
      expect(identity.markerNonce, 'marker-a');
      expect(
        identity,
        PythonStagingDirectoryIdentity(
          canonicalPath: '/tmp/python-a',
          markerNonce: 'marker-a',
          deviceId: 4,
          inode: 9,
        ),
      );
      for (final path in [
        'relative/path',
        '/',
        '/tmp/../successor',
        '/tmp/./a',
        '/tmp//a',
        '/tmp/a/',
      ]) {
        expect(
          () => PythonStagingDirectoryIdentity(
            canonicalPath: path,
            markerNonce: 'marker',
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => PythonStagingDirectoryIdentity(
          canonicalPath: '/tmp/python-a',
          markerNonce: '',
        ),
        throwsArgumentError,
      );
      expect(
        () => PythonStagingDirectoryIdentity(
          canonicalPath: '/tmp/python-a',
          markerNonce: 'marker',
          deviceId: 4,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Python staging lease lifecycle', () {
    test('deep-freezes metadata and exposes exact directory identity', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);
      final labels = <Object?>['owner-a'];
      final owners = <String, Object?>{'primary': 'conversation-a'};
      final metadata = <String, dynamic>{
        'nested': {
          'labels': labels,
          'owners': owners,
          'flags': <Object?>['staged'],
        },
      };

      final committed = registry.commit(
        attempt: attempt,
        token: token,
        directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
        metadata: metadata,
      );
      labels.add('poisoned');
      owners['primary'] = 'conversation-b';
      metadata['nested'] = {'late': true};

      final lease = committed.activeLease!;
      expect(committed.status, PythonStagingCommitStatus.committed);
      expect(lease.attempt, attempt);
      expect(lease.token, same(token));
      expect(lease.directoryPath, '/tmp/python-a');
      expect(lease.directoryIdentity.markerNonce, 'marker-a');
      expect(lease.metadata, {
        'nested': {
          'labels': ['owner-a'],
          'owners': {'primary': 'conversation-a'},
          'flags': ['staged'],
        },
      });
      expect(() => lease.metadata['late'] = true, throwsUnsupportedError);
      expect(
        () => ((lease.metadata['nested'] as Map)['labels'] as List).add('late'),
        throwsUnsupportedError,
      );
      expect(registry.isLeaseCurrent(attempt: attempt, token: token), isTrue);
    });

    test('rejects mutable metadata without consuming the reservation', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);

      expect(
        () => registry.commit(
          attempt: attempt,
          token: token,
          directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
          metadata: {'mutable': _MutableValue()},
        ),
        throwsArgumentError,
      );
      expect(
        () => registry.commit(
          attempt: attempt,
          token: token,
          directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
          metadata: {
            'notJson': <Object?>{'value'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => registry.commit(
          attempt: attempt,
          token: token,
          directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
          metadata: {'notFinite': double.negativeInfinity},
        ),
        throwsArgumentError,
      );
      expect(
        () => registry.commit(
          attempt: attempt,
          token: token,
          directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
          metadata: {
            'mutableKey': {_MutableValue(): true},
          },
        ),
        throwsArgumentError,
      );
      expect(
        registry
            .commit(
              attempt: attempt,
              token: token,
              directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
            )
            .status,
        PythonStagingCommitStatus.committed,
      );
    });

    test('claims and settles cleanup exactly once', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);
      final identity = _identity('/tmp/python-a', 'marker-a');
      final lease = _commit(registry, attempt, token, identity);

      final claimed = registry.claimCleanup(attempt: attempt, token: token);
      expect(claimed.status, PythonStagingCleanupClaimStatus.claimed);
      expect(claimed.claim!.lease, same(lease));
      expect(registry.isLeaseCurrent(attempt: attempt, token: token), isFalse);
      expect(
        registry.claimCleanup(attempt: attempt, token: token).status,
        PythonStagingCleanupClaimStatus.alreadyClaimed,
      );
      expect(
        registry
            .commit(attempt: attempt, token: token, directoryIdentity: identity)
            .status,
        PythonStagingCommitStatus.cleanupAlreadyClaimed,
      );
      expect(
        registry.settleCleanup(claim: claimed.claim!, succeeded: true),
        PythonStagingCleanupSettleStatus.settled,
      );
      expect(
        registry.settleCleanup(claim: claimed.claim!, succeeded: true),
        PythonStagingCleanupSettleStatus.alreadySettled,
      );
      expect(
        registry.claimCleanup(attempt: attempt, token: token).status,
        PythonStagingCleanupClaimStatus.alreadySettled,
      );
      expect(registry.outstandingCleanupAttempts(), isEmpty);
    });

    test('reopens failed cleanup without reusing the old claim', () {
      final notifications = <PythonStagingAttempt>[];
      final registry = PythonStagingLeaseRegistry(
        onCleanupPending: notifications.add,
      );
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);
      _commit(registry, attempt, token, _identity('/tmp/python-a', 'marker-a'));
      final first = registry
          .claimCleanup(attempt: attempt, token: token)
          .claim!;

      expect(
        registry.settleCleanup(claim: first, succeeded: false),
        PythonStagingCleanupSettleStatus.reopened,
      );
      expect(registry.isLeaseCurrent(attempt: attempt, token: token), isFalse);
      expect(notifications, [attempt]);
      expect(registry.pendingCleanupAttempts, [attempt]);
      expect(
        () => registry.pendingCleanupAttempts.clear(),
        throwsUnsupportedError,
      );
      final retry = registry.claimPendingCleanup(owner: ownerA);
      expect(retry.status, PythonStagingCleanupClaimStatus.claimed);
      expect(retry.claim, isNot(same(first)));
      expect(registry.pendingCleanupAttempts, isEmpty);
      expect(registry.outstandingCleanupAttempts(owner: ownerA), [attempt]);
      expect(
        () => registry.outstandingCleanupAttempts().clear(),
        throwsUnsupportedError,
      );
      expect(
        registry.settleCleanup(claim: first, succeeded: true),
        PythonStagingCleanupSettleStatus.staleClaim,
      );
      expect(
        registry.settleCleanup(claim: retry.claim!, succeeded: true),
        PythonStagingCleanupSettleStatus.settled,
      );
      expect(registry.outstandingCleanupAttempts(owner: ownerA), isEmpty);
    });
  });

  group('Python staging retirement', () {
    test('gives cleanup to exactly one side when owner clear wins', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);
      final lease = _commit(
        registry,
        attempt,
        token,
        _identity('/tmp/python-a', 'marker-a'),
      );

      final cleared = registry.clearOwner(ownerA);
      expect(cleared.cleanupClaims.single.lease, same(lease));
      expect(
        registry.claimCleanup(attempt: attempt, token: token).status,
        PythonStagingCleanupClaimStatus.alreadyClaimed,
      );
      expect(registry.clearOwner(ownerA).cleanupClaims, isEmpty);
      expect(
        registry.settleCleanup(
          claim: cleared.cleanupClaims.single,
          succeeded: true,
        ),
        PythonStagingCleanupSettleStatus.settled,
      );
    });

    test('lets terminal cleanup retry after a failed claimant', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);
      _commit(registry, attempt, token, _identity('/tmp/python-a', 'marker-a'));
      final first = registry.clearOwner(ownerA).cleanupClaims.single;

      expect(
        registry.settleCleanup(claim: first, succeeded: false),
        PythonStagingCleanupSettleStatus.reopened,
      );
      final retry = registry.clearOwner(ownerA).cleanupClaims.single;
      expect(retry, isNot(same(first)));
      expect(
        registry.settleCleanup(claim: retry, succeeded: true),
        PythonStagingCleanupSettleStatus.settled,
      );
    });

    test('turns a late allocation into handler-owned cleanup', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);

      final cleared = registry.clearOwner(ownerA);
      expect(cleared.retiredReservationCount, 1);
      expect(cleared.cleanupClaims, isEmpty);
      final late = registry.commit(
        attempt: attempt,
        token: token,
        directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
      );
      expect(late.status, PythonStagingCommitStatus.ownerCleared);
      expect(late.activeLease, isNull);
      expect(late.cleanupClaim, isNotNull);
      expect(
        registry.settleCleanup(claim: late.cleanupClaim!, succeeded: true),
        PythonStagingCleanupSettleStatus.settled,
      );
      expect(
        registry.reserve(_attempt(ownerA, 'call-b')).status,
        PythonStagingReserveStatus.ownerCleared,
      );
    });

    test('isolates owners during clearAll and claim settlement', () {
      final registry = PythonStagingLeaseRegistry();
      final attemptA = _attempt(ownerA, 'call-a');
      final attemptB = _attempt(ownerB, 'call-b');
      final tokenA = _reserve(registry, attemptA);
      final tokenB = _reserve(registry, attemptB);
      _commit(
        registry,
        attemptA,
        tokenA,
        _identity('/tmp/python-a', 'marker-a'),
      );
      _commit(
        registry,
        attemptB,
        tokenB,
        _identity('/tmp/python-b', 'marker-b'),
      );

      final clearedA = registry.clearOwner(ownerA);
      expect(clearedA.cleanupClaims, hasLength(1));
      expect(registry.outstandingCleanupAttempts(owner: ownerA), [attemptA]);
      expect(registry.outstandingCleanupAttempts(owner: ownerB), [attemptB]);
      expect(registry.isLeaseCurrent(attempt: attemptB, token: tokenB), isTrue);
      final clearedAll = registry.clearAll();
      expect(clearedAll.cleanupClaims, hasLength(1));
      expect(clearedAll.cleanupClaims.single.lease.attempt, attemptB);
      expect(() => clearedAll.cleanupClaims.clear(), throwsUnsupportedError);
    });
  });

  group('Python staging successor protection', () {
    test('never reuses a claimed canonical path after settlement', () {
      final registry = PythonStagingLeaseRegistry();
      final firstAttempt = _attempt(ownerA, 'call-a');
      final firstToken = _reserve(registry, firstAttempt);
      _commit(
        registry,
        firstAttempt,
        firstToken,
        _identity('/tmp/python-shared', 'marker-a'),
      );
      final claim = registry
          .claimCleanup(attempt: firstAttempt, token: firstToken)
          .claim!;
      registry.settleCleanup(claim: claim, succeeded: true);

      final successor = _attempt(ownerB, 'call-b');
      final successorToken = _reserve(registry, successor);
      expect(
        registry
            .commit(
              attempt: successor,
              token: successorToken,
              directoryIdentity: _identity(
                '/tmp/python-shared',
                'marker-successor',
              ),
            )
            .status,
        PythonStagingCommitStatus.pathConflict,
      );
      expect(
        registry
            .commit(
              attempt: successor,
              token: successorToken,
              directoryIdentity: _identity(
                '/tmp/python-successor',
                'marker-successor',
              ),
            )
            .status,
        PythonStagingCommitStatus.committed,
      );
    });

    test('uses one claim key for Windows case variants', () {
      final registry = PythonStagingLeaseRegistry();
      final firstAttempt = _attempt(ownerA, 'call-a');
      final secondAttempt = _attempt(ownerB, 'call-b');
      final firstToken = _reserve(registry, firstAttempt);
      final secondToken = _reserve(registry, secondAttempt);

      expect(
        registry
            .commit(
              attempt: firstAttempt,
              token: firstToken,
              directoryIdentity: _identity(r'C:\Temp\Python-A', 'marker-a'),
            )
            .status,
        PythonStagingCommitStatus.committed,
      );
      expect(
        registry
            .commit(
              attempt: secondAttempt,
              token: secondToken,
              directoryIdentity: _identity(r'c:\temp\python-a', 'marker-b'),
            )
            .status,
        PythonStagingCommitStatus.pathConflict,
      );
    });

    test('rejects wrong attempts without changing an active lease', () {
      final registry = PythonStagingLeaseRegistry();
      final attemptA = _attempt(ownerA, 'call-a');
      final attemptB = _attempt(ownerB, 'call-b');
      final tokenA = _reserve(registry, attemptA);
      final tokenB = _reserve(registry, attemptB);
      _commit(
        registry,
        attemptA,
        tokenA,
        _identity('/tmp/python-a', 'marker-a'),
      );

      expect(
        registry
            .commit(
              attempt: attemptB,
              token: tokenA,
              directoryIdentity: _identity('/tmp/poison', 'marker-poison'),
            )
            .status,
        PythonStagingCommitStatus.attemptMismatch,
      );
      expect(
        registry.claimCleanup(attempt: attemptA, token: tokenB).status,
        PythonStagingCleanupClaimStatus.attemptMismatch,
      );
      expect(registry.isLeaseCurrent(attempt: attemptA, token: tokenA), isTrue);
    });

    test('cancels only reservations that never acquired a lease', () {
      final registry = PythonStagingLeaseRegistry();
      final attempt = _attempt(ownerA, 'call-a');
      final token = _reserve(registry, attempt);

      expect(
        registry.releaseReservation(attempt: attempt, token: token),
        PythonStagingReservationReleaseStatus.cancelled,
      );
      expect(
        registry.releaseReservation(attempt: attempt, token: token),
        PythonStagingReservationReleaseStatus.alreadyReleased,
      );
      final late = registry.commit(
        attempt: attempt,
        token: token,
        directoryIdentity: _identity('/tmp/python-a', 'marker-a'),
      );
      expect(late.status, PythonStagingCommitStatus.reservationReleased);
      expect(late.cleanupClaim, isNotNull);
    });
  });
}

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

PythonStagingAttempt _attempt(ChatTurnOwner owner, String toolCallId) =>
    PythonStagingAttempt(
      owner: owner,
      toolCallId: toolCallId,
      toolName: 'run_python_script',
    );

PythonStagingDirectoryIdentity _identity(String path, String marker) =>
    PythonStagingDirectoryIdentity(canonicalPath: path, markerNonce: marker);

PythonStagingLeaseToken _reserve(
  PythonStagingLeaseRegistry registry,
  PythonStagingAttempt attempt,
) => registry.reserve(attempt).token!;

PythonStagingLease _commit(
  PythonStagingLeaseRegistry registry,
  PythonStagingAttempt attempt,
  PythonStagingLeaseToken token,
  PythonStagingDirectoryIdentity identity,
) => registry
    .commit(attempt: attempt, token: token, directoryIdentity: identity)
    .activeLease!;

final class _MutableValue {}
