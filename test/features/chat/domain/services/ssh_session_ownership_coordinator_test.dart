import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/ssh_session_ownership_coordinator.dart';
import 'package:test/test.dart';

final _ownerA = _owner('conversation-a', 7);
final _ownerB = _owner('conversation-b', 7);

ChatTurnOwner _owner(String conversationId, int generation) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

SshConnectionOperationIdentity _connection(
  ChatTurnOwner owner,
  String call, {
  String tool = 'ssh_connect',
  String digest = 'sha256:connection-a',
}) {
  return SshConnectionOperationIdentity((
    owner: owner,
    toolCallId: call,
    toolName: tool,
    connectionDigest: digest,
  ));
}

SshExternalSessionFingerprint _fingerprint(String value) =>
    SshExternalSessionFingerprint(value);

SshCommandOperationIdentity _command(
  ChatTurnOwner owner,
  String call, {
  String tool = 'ssh_execute_command',
  String digest = 'sha256:command-a',
}) => SshCommandOperationIdentity((
  owner: owner,
  toolCallId: call,
  toolName: tool,
  commandDigest: digest,
));

SshConnectAttempt _begin(
  SshSessionOwnershipCoordinator coordinator,
  SshConnectionOperationIdentity identity,
) {
  final result = coordinator.beginConnect(identity);
  expect(result.status, SshOwnershipStatus.started);
  return result.attempt!;
}

SshConnectCompletionResult _complete(
  SshSessionOwnershipCoordinator coordinator,
  SshConnectAttempt attempt,
  String fingerprint,
) {
  return coordinator.completeConnect(
    identity: attempt.identity,
    token: attempt.token,
    externalFingerprint: _fingerprint(fingerprint),
  );
}

SshActivatedSession _activate(
  SshSessionOwnershipCoordinator coordinator,
  SshConnectionOperationIdentity identity,
  String fingerprint,
) {
  final result = _complete(
    coordinator,
    _begin(coordinator, identity),
    fingerprint,
  );
  expect(result.status, SshOwnershipStatus.activated);
  return result.session!;
}

SshCommandLease _lease(
  SshSessionOwnershipCoordinator coordinator,
  SshCommandOperationIdentity operation,
  SshActivatedSession session,
) {
  final result = coordinator.acquireCommandLease(
    operation: operation,
    sessionToken: session.token,
  );
  expect(result.status, SshOwnershipStatus.acquired);
  return result.lease!;
}

void main() {
  group('connection identity and local tokens', () {
    test('normalizes and validates every external identity string', () {
      final connection = _connection(
        _ownerA,
        ' call-a ',
        tool: ' ssh_connect ',
        digest: ' sha256:connection-a ',
      );
      final command = _command(
        _ownerA,
        ' command-a ',
        tool: ' ssh_execute_command ',
        digest: ' sha256:command-a ',
      );
      final fingerprint = _fingerprint(' external-a ');

      expect(connection.toolCallId, 'call-a');
      expect(connection.toolName, 'ssh_connect');
      expect(connection.connectionDigest, 'sha256:connection-a');
      expect(command.toolCallId, 'command-a');
      expect(command.toolName, 'ssh_execute_command');
      expect(command.commandDigest, 'sha256:command-a');
      expect(fingerprint.value, 'external-a');

      expect(() => _connection(_ownerA, ' '), throwsArgumentError);
      expect(
        () => _connection(_ownerA, 'call', tool: '\n'),
        throwsArgumentError,
      );
      expect(
        () => _connection(_ownerA, 'call', digest: ''),
        throwsArgumentError,
      );
      expect(() => _command(_ownerA, ' '), throwsArgumentError);
      expect(() => _command(_ownerA, 'call', tool: ' '), throwsArgumentError);
      expect(
        () => _command(_ownerA, 'call', digest: '\n'),
        throwsArgumentError,
      );
      expect(() => _fingerprint(' '), throwsArgumentError);
    });

    test('compares owner, call, tool, and connection digest', () {
      final identity = _connection(_ownerA, 'call-a');

      expect(_connection(_ownerA, 'call-a'), identity);
      expect(_connection(_ownerB, 'call-a'), isNot(identity));
      expect(_connection(_ownerA, 'call-b'), isNot(identity));
      expect(
        _connection(_ownerA, 'call-a', tool: 'ssh_other'),
        isNot(identity),
      );
      expect(
        _connection(_ownerA, 'call-a', digest: 'sha256:other'),
        isNot(identity),
      );
    });

    test('keeps connect and activated tokens opaque and registry-local', () {
      final first = SshSessionOwnershipCoordinator();
      final second = SshSessionOwnershipCoordinator();
      final identity = _connection(_ownerA, 'call-a');
      final localAttempt = _begin(first, identity);
      final foreignAttempt = _begin(second, identity);

      final foreignCompletion = first.completeConnect(
        identity: identity,
        token: foreignAttempt.token,
        externalFingerprint: _fingerprint('external-foreign'),
      );
      final local = _complete(first, localAttempt, 'external-local');

      expect(localAttempt.token, isNot(foreignAttempt.token));
      expect(foreignCompletion.status, SshOwnershipStatus.foreignCapability);
      expect(foreignCompletion.cleanupReceipt, isNull);
      expect(first.activeSession(_ownerA), same(local.session));
    });
  });

  group('connect ownership and completion', () {
    test('isolates equal-generation peers', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final attemptA = _begin(coordinator, _connection(_ownerA, 'call-a'));
      final attemptB = _begin(coordinator, _connection(_ownerB, 'call-b'));

      final sessionA = _complete(coordinator, attemptA, 'external-a').session!;
      final sessionB = _complete(coordinator, attemptB, 'external-b').session!;

      expect(coordinator.activeSession(_ownerA), same(sessionA));
      expect(coordinator.activeSession(_ownerB), same(sessionB));
    });

    test('stale same-owner completion requires exact cleanup', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final firstIdentity = _connection(_ownerA, 'call-a');
      final secondIdentity = _connection(
        _ownerA,
        'call-b',
        digest: 'sha256:connection-b',
      );
      final first = _begin(coordinator, firstIdentity);
      final second = _begin(coordinator, secondIdentity);

      expect(
        coordinator.finishConnect(firstIdentity, first.token),
        SshOwnershipStatus.staleToken,
      );
      final stale = _complete(coordinator, first, 'external-stale');
      final active = _complete(coordinator, second, 'external-current');
      final wrongObservation = coordinator.authorizeDisconnect(
        receipt: stale.cleanupReceipt!,
        observedFingerprint: active.session!.externalFingerprint,
      );

      expect(stale.status, SshOwnershipStatus.staleToken);
      expect(stale.session, isNull);
      expect(stale.cleanupReceipt?.connectionIdentity, firstIdentity);
      expect(stale.cleanupReceipt?.connectToken, first.token);
      expect(wrongObservation.status, SshOwnershipStatus.fingerprintMismatch);
      expect(coordinator.activeSession(_ownerA), same(active.session));
    });

    test('finished connect cannot disturb a same-owner successor', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final identity = _connection(_ownerA, 'finished-call');
      final attempt = _begin(coordinator, identity);

      expect(
        coordinator.finishConnect(identity, attempt.token),
        SshOwnershipStatus.completed,
      );
      final successor = _activate(
        coordinator,
        _connection(_ownerA, 'successor-call'),
        'external-successor',
      );
      final late = _complete(coordinator, attempt, 'external-finished-late');

      expect(late.status, SshOwnershipStatus.staleToken);
      expect(late.cleanupReceipt?.connectionIdentity, identity);
      expect(coordinator.activeSession(_ownerA), same(successor));
    });

    test('owner retirement turns late completion into cleanup receipt', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final identity = _connection(_ownerA, 'late-call');
      final attempt = _begin(coordinator, identity);

      final cleared = coordinator.clearOwner(_ownerA);
      final late = _complete(coordinator, attempt, 'external-late');
      final repeated = coordinator.completeConnect(
        identity: identity,
        token: attempt.token,
        externalFingerprint: _fingerprint('external-late'),
      );

      expect(cleared.cleanupReceipts, isEmpty);
      expect(late.status, SshOwnershipStatus.ownerRetired);
      expect(late.cleanupReceipt?.owner, _ownerA);
      expect(late.cleanupReceipt?.connectToken, attempt.token);
      expect(late.cleanupReceipt?.sessionToken, isNull);
      expect(repeated.status, SshOwnershipStatus.alreadyCompleted);
      expect(repeated.cleanupReceipt, same(late.cleanupReceipt));
      expect(
        coordinator.beginConnect(_connection(_ownerA, 'new-call')).status,
        SshOwnershipStatus.ownerRetired,
      );
    });

    test('rejects identity poison without consuming the attempt', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final identity = _connection(_ownerA, 'call-a');
      final attempt = _begin(coordinator, identity);
      final poisons = [
        _connection(_ownerB, 'call-a'),
        _connection(_ownerA, 'call-b'),
        _connection(_ownerA, 'call-a', tool: 'ssh_other'),
        _connection(_ownerA, 'call-a', digest: 'sha256:poison'),
      ];

      for (final poison in poisons) {
        expect(
          coordinator
              .completeConnect(
                identity: poison,
                token: attempt.token,
                externalFingerprint: _fingerprint('external-poison'),
              )
              .status,
          SshOwnershipStatus.identityMismatch,
        );
      }
      expect(_complete(coordinator, attempt, 'external-a').session, isNotNull);
    });

    test('activation replaces only the same owner', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final oldA = _activate(
        coordinator,
        _connection(_ownerA, 'old-a'),
        'external-old-a',
      );
      final peer = _activate(
        coordinator,
        _connection(_ownerB, 'peer'),
        'external-peer',
      );

      final replacement = _complete(
        coordinator,
        _begin(coordinator, _connection(_ownerA, 'replacement-a')),
        'external-new-a',
      );

      expect(replacement.status, SshOwnershipStatus.activated);
      expect(replacement.cleanupReceipt?.connectToken, isNull);
      expect(replacement.cleanupReceipt?.sessionToken, same(oldA.token));
      expect(
        replacement.cleanupReceipt?.expectedFingerprint,
        oldA.externalFingerprint,
      );
      expect(coordinator.activeSession(_ownerA), same(replacement.session));
      expect(coordinator.activeSession(_ownerB), same(peer));
    });
  });

  group('command leases', () {
    test('binds owner, call, tool, and exact active session', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final session = _activate(
        coordinator,
        _connection(_ownerA, 'connect'),
        'external-a',
      );
      final operation = _command(_ownerA, 'command-a');
      final lease = _lease(coordinator, operation, session);

      for (final poison in [
        _command(_ownerB, 'command-a'),
        _command(_ownerA, 'command-b'),
        _command(_ownerA, 'command-a', tool: 'ssh_other'),
        _command(_ownerA, 'command-a', digest: 'sha256:other-command'),
      ]) {
        expect(
          coordinator.releaseCommandLease(
            operation: poison,
            sessionToken: session.token,
            leaseToken: lease.token,
          ),
          SshOwnershipStatus.identityMismatch,
        );
      }
      expect(
        coordinator.isCommandLeaseCurrent(
          operation,
          session.token,
          lease.token,
        ),
        isTrue,
      );
      expect(
        coordinator.releaseCommandLease(
          operation: operation,
          sessionToken: session.token,
          leaseToken: lease.token,
        ),
        SshOwnershipStatus.completed,
      );
    });

    test('stale release cannot accept or release a successor lease', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final operation = _command(_ownerA, 'command-a');
      final oldSession = _activate(
        coordinator,
        _connection(_ownerA, 'connect-old'),
        'external-old',
      );
      final oldLease = _lease(coordinator, operation, oldSession);
      final newSession = _activate(
        coordinator,
        _connection(_ownerA, 'connect-new'),
        'external-new',
      );
      final newLease = _lease(coordinator, operation, newSession);

      final stale = coordinator.releaseCommandLease(
        operation: operation,
        sessionToken: oldSession.token,
        leaseToken: oldLease.token,
      );

      expect(stale, SshOwnershipStatus.staleSession);
      expect(
        coordinator.isCommandLeaseCurrent(
          operation,
          newSession.token,
          newLease.token,
        ),
        isTrue,
      );
    });

    test('rejects foreign session and command lease tokens', () {
      final first = SshSessionOwnershipCoordinator();
      final second = SshSessionOwnershipCoordinator();
      final operation = _command(_ownerA, 'command-a');
      final localSession = _activate(
        first,
        _connection(_ownerA, 'connect-local'),
        'external-local',
      );
      final foreignSession = _activate(
        second,
        _connection(_ownerA, 'connect-foreign'),
        'external-foreign',
      );
      final foreignLease = _lease(second, operation, foreignSession);

      expect(
        first
            .acquireCommandLease(
              operation: operation,
              sessionToken: foreignSession.token,
            )
            .status,
        SshOwnershipStatus.foreignCapability,
      );
      expect(
        first.releaseCommandLease(
          operation: operation,
          sessionToken: localSession.token,
          leaseToken: foreignLease.token,
        ),
        SshOwnershipStatus.foreignCapability,
      );
      expect(first.activeSession(_ownerA), same(localSession));
    });
  });

  group('retirement and conditional cleanup', () {
    test('stale retire cannot remove a successor or equal-generation peer', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final old = _activate(
        coordinator,
        _connection(_ownerA, 'old'),
        'external-old',
      );
      final successor = _activate(
        coordinator,
        _connection(_ownerA, 'successor'),
        'external-successor',
      );
      final peer = _activate(
        coordinator,
        _connection(_ownerB, 'peer'),
        'external-peer',
      );

      final stale = coordinator.retireSession(_ownerA, old.token);
      final wrongOwner = coordinator.retireSession(_ownerB, successor.token);

      expect(stale.status, SshOwnershipStatus.alreadyCompleted);
      expect(stale.cleanupReceipt?.sessionToken, same(old.token));
      expect(wrongOwner.status, SshOwnershipStatus.identityMismatch);
      expect(coordinator.activeSession(_ownerA), same(successor));
      expect(coordinator.activeSession(_ownerB), same(peer));
    });

    test(
      'failed cleanup remains retryable but rejects successor fingerprint',
      () {
        final coordinator = SshSessionOwnershipCoordinator();
        final old = _activate(
          coordinator,
          _connection(_ownerA, 'old'),
          'external-old',
        );
        final replacement = _complete(
          coordinator,
          _begin(coordinator, _connection(_ownerA, 'replacement')),
          'external-new',
        );
        final receipt = replacement.cleanupReceipt!;
        final firstAuthorization = coordinator.authorizeDisconnect(
          receipt: receipt,
          observedFingerprint: old.externalFingerprint,
        );

        expect(
          coordinator.finishDisconnect(
            firstAuthorization.permit!,
            succeeded: false,
          ),
          SshOwnershipStatus.retryRequired,
        );
        expect(
          coordinator
              .authorizeDisconnect(
                receipt: receipt,
                observedFingerprint: replacement.session!.externalFingerprint,
              )
              .status,
          SshOwnershipStatus.fingerprintMismatch,
        );

        final retry = coordinator.authorizeDisconnect(
          receipt: receipt,
          observedFingerprint: old.externalFingerprint,
        );
        expect(retry.status, SshOwnershipStatus.authorized);
        expect(
          coordinator.finishDisconnect(
            firstAuthorization.permit!,
            succeeded: true,
          ),
          SshOwnershipStatus.staleToken,
        );
        expect(
          coordinator.finishDisconnect(retry.permit!, succeeded: true),
          SshOwnershipStatus.completed,
        );
        expect(
          coordinator
              .authorizeDisconnect(
                receipt: receipt,
                observedFingerprint: old.externalFingerprint,
              )
              .status,
          SshOwnershipStatus.alreadyCompleted,
        );
        expect(coordinator.activeSession(_ownerA), same(replacement.session));
      },
    );

    test('foreign cleanup capabilities cannot affect local receipts', () {
      final first = SshSessionOwnershipCoordinator();
      final second = SshSessionOwnershipCoordinator();
      final old = _activate(first, _connection(_ownerA, 'old'), 'external-old');
      final localReceipt = _complete(
        first,
        _begin(first, _connection(_ownerA, 'new')),
        'external-new',
      ).cleanupReceipt!;
      final foreignOld = _activate(
        second,
        _connection(_ownerA, 'foreign-old'),
        'external-foreign-old',
      );
      final foreignReceipt = _complete(
        second,
        _begin(second, _connection(_ownerA, 'foreign-new')),
        'external-foreign-new',
      ).cleanupReceipt!;

      final localPermit = first
          .authorizeDisconnect(
            receipt: localReceipt,
            observedFingerprint: old.externalFingerprint,
          )
          .permit!;
      expect(
        first
            .authorizeDisconnect(
              receipt: foreignReceipt,
              observedFingerprint: foreignOld.externalFingerprint,
            )
            .status,
        SshOwnershipStatus.foreignCapability,
      );
      expect(
        second.finishDisconnect(localPermit, succeeded: true),
        SshOwnershipStatus.foreignCapability,
      );
      expect(
        first.finishDisconnect(localPermit, succeeded: true),
        SshOwnershipStatus.completed,
      );
    });

    test('clear is exact, terminal, and returns immutable receipts', () {
      final coordinator = SshSessionOwnershipCoordinator();
      final sessionA = _activate(
        coordinator,
        _connection(_ownerA, 'connect-a'),
        'external-a',
      );
      final sessionB = _activate(
        coordinator,
        _connection(_ownerB, 'connect-b'),
        'external-b',
      );
      final pendingOwner = _owner('conversation-pending', 7);
      final pending = _begin(
        coordinator,
        _connection(pendingOwner, 'connect-pending'),
      );

      final clearedA = coordinator.clearOwner(_ownerA);

      expect(clearedA.cleanupReceipts.single.sessionToken, sessionA.token);
      expect(() => clearedA.cleanupReceipts.clear(), throwsUnsupportedError);
      expect(coordinator.activeSession(_ownerA), isNull);
      expect(coordinator.activeSession(_ownerB), same(sessionB));
      expect(
        coordinator.beginConnect(_connection(_ownerA, 'late')).status,
        SshOwnershipStatus.ownerRetired,
      );

      final clearedAll = coordinator.clearAll();
      final latePending = _complete(
        coordinator,
        pending,
        'external-pending-late',
      );
      expect(clearedAll.cleanupReceipts.single.sessionToken, sessionB.token);
      expect(latePending.status, SshOwnershipStatus.registryCleared);
      expect(latePending.cleanupReceipt?.owner, pendingOwner);
      expect(
        coordinator
            .beginConnect(_connection(_owner('future', 1), 'future'))
            .status,
        SshOwnershipStatus.registryCleared,
      );
      expect(coordinator.clearAll().cleanupReceipts, isEmpty);
    });
  });
}
