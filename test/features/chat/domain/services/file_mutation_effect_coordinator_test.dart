import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/file_mutation_effect_coordinator.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  final ownerANext = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 5,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 4,
  );

  FileMutationOperationIdentity attempt(
    ChatTurnOwner owner, {
    String call = 'call-a',
    String path = '/workspace/file.txt',
  }) {
    return FileMutationOperationIdentity(
      owner: owner,
      toolCallId: call,
      toolName: 'write_file',
      canonicalPath: path,
    );
  }

  group('FileMutationOperationIdentity', () {
    test('normalizes and validates all string identity fields', () {
      final identity = FileMutationOperationIdentity(
        owner: ownerA,
        toolCallId: ' call-a ',
        toolName: ' write_file ',
        canonicalPath: ' /workspace/file.txt ',
      );

      expect(identity.toolCallId, 'call-a');
      expect(identity.toolName, 'write_file');
      expect(identity.canonicalPath, '/workspace/file.txt');
      for (final values in [
        (' ', 'write_file', '/workspace/file.txt'),
        ('call-a', '\n', '/workspace/file.txt'),
        ('call-a', 'write_file', '\t'),
      ]) {
        expect(
          () => FileMutationOperationIdentity(
            owner: ownerA,
            toolCallId: values.$1,
            toolName: values.$2,
            canonicalPath: values.$3,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('FileMutationEffectCoordinator', () {
    test('rejects blank filesystem evidence without advancing state', () {
      final coordinator = FileMutationEffectCoordinator();
      final identity = attempt(ownerA);
      expect(
        () => coordinator.acquire(identity, beforeFingerprint: ' '),
        throwsArgumentError,
      );
      final lease = coordinator
          .acquire(identity, beforeFingerprint: ' before ')
          .lease!;
      expect(lease.beforeFingerprint, 'before');
      expect(coordinator.beginEffect(identity, lease), isTrue);
      expect(
        () => coordinator.markApplied(
          identity,
          lease,
          expectedAfterFingerprint: '\n',
          compensationToken: 'restore',
        ),
        throwsArgumentError,
      );
      expect(
        () => coordinator.markApplied(
          identity,
          lease,
          expectedAfterFingerprint: 'after',
          compensationToken: '\t',
        ),
        throwsArgumentError,
      );
      final receipt = coordinator
          .markApplied(
            identity,
            lease,
            expectedAfterFingerprint: ' after ',
            compensationToken: ' restore ',
          )
          .receipt!;
      expect(receipt.expectedAfterFingerprint, 'after');
      expect(receipt.compensationToken, 'restore');
      expect(
        () => coordinator.beginCompensation(
          identity,
          receipt,
          observedCurrentFingerprint: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        coordinator.beginCompensation(
          identity,
          receipt,
          observedCurrentFingerprint: ' after ',
        ),
        FileMutationCompensationDisposition.ready,
      );
    });

    test('holds a path until a current owner commits the exact receipt', () {
      final coordinator = FileMutationEffectCoordinator();
      final identity = attempt(ownerA);
      final acquired = coordinator.acquire(
        identity,
        beforeFingerprint: 'before-a',
      );
      final lease = acquired.lease!;

      expect(acquired.disposition, FileMutationAcquireDisposition.acquired);
      expect(
        coordinator
            .acquire(
              attempt(ownerB, call: 'call-b'),
              beforeFingerprint: 'before-b',
            )
            .disposition,
        FileMutationAcquireDisposition.pathBusy,
      );
      expect(coordinator.beginEffect(identity, lease), isTrue);

      final applied = coordinator.markApplied(
        identity,
        lease,
        expectedAfterFingerprint: 'after-a',
        compensationToken: 'restore-a',
      );

      expect(applied.disposition, FileMutationApplyDisposition.applied);
      expect(
        coordinator.finishCommitted(identity, applied.receipt!),
        FileMutationCommitDisposition.committed,
      );
      expect(coordinator.isPathBusy(identity.canonicalPath), isFalse);
      expect(
        coordinator
            .acquire(
              attempt(ownerB, call: 'call-b'),
              beforeFingerprint: 'before-b',
            )
            .disposition,
        FileMutationAcquireDisposition.acquired,
      );
    });

    test('retirement before execution prevents the filesystem effect', () {
      final coordinator = FileMutationEffectCoordinator();
      final identity = attempt(ownerA);
      final lease = coordinator
          .acquire(identity, beforeFingerprint: 'before')
          .lease!;

      final retirement = coordinator.retireOwner(ownerA);

      expect(retirement.effectsInFlight, isEmpty);
      expect(retirement.compensationRequired, isEmpty);
      expect(coordinator.beginEffect(identity, lease), isFalse);
      expect(coordinator.isPathBusy(identity.canonicalPath), isFalse);
      expect(
        coordinator.acquire(identity, beforeFingerprint: 'later').disposition,
        FileMutationAcquireDisposition.ownerRetired,
      );
    });

    test('retirement during execution requires compensation after apply', () {
      final coordinator = FileMutationEffectCoordinator();
      final identity = attempt(ownerA);
      final lease = coordinator
          .acquire(identity, beforeFingerprint: 'before')
          .lease!;
      expect(coordinator.beginEffect(identity, lease), isTrue);

      final retirement = coordinator.retireOwner(ownerA);
      final applied = coordinator.markApplied(
        identity,
        lease,
        expectedAfterFingerprint: 'after',
        compensationToken: 'restore',
      );

      expect(retirement.effectsInFlight, [same(lease)]);
      expect(
        applied.disposition,
        FileMutationApplyDisposition.compensationRequired,
      );
      expect(
        coordinator.finishCommitted(identity, applied.receipt!),
        FileMutationCommitDisposition.compensationRequired,
      );
      expect(
        coordinator.beginCompensation(
          identity,
          applied.receipt!,
          observedCurrentFingerprint: 'after',
        ),
        FileMutationCompensationDisposition.ready,
      );
      expect(
        coordinator.completeCompensation(
          identity,
          applied.receipt!,
          succeeded: true,
        ),
        FileMutationCompensationDisposition.reverted,
      );
      expect(coordinator.isPathBusy(identity.canonicalPath), isFalse);
    });

    test('fingerprint conflict preserves the lease and successor bytes', () {
      final coordinator = FileMutationEffectCoordinator();
      final identity = attempt(ownerA);
      final lease = coordinator
          .acquire(identity, beforeFingerprint: 'before')
          .lease!;
      expect(coordinator.beginEffect(identity, lease), isTrue);
      final receipt = coordinator
          .markApplied(
            identity,
            lease,
            expectedAfterFingerprint: 'after-a',
            compensationToken: 'restore-a',
          )
          .receipt!;
      coordinator.retireOwner(ownerA);

      expect(
        coordinator.beginCompensation(
          identity,
          receipt,
          observedCurrentFingerprint: 'successor-after',
        ),
        FileMutationCompensationDisposition.fingerprintConflict,
      );
      expect(coordinator.isPathBusy(identity.canonicalPath), isTrue);
      expect(
        coordinator
            .acquire(
              attempt(ownerB, call: 'call-b'),
              beforeFingerprint: 'before-b',
            )
            .disposition,
        FileMutationAcquireDisposition.pathBusy,
      );
    });

    test('failed compensation can be retried without releasing the path', () {
      final coordinator = FileMutationEffectCoordinator();
      final identity = attempt(ownerA);
      final lease = coordinator
          .acquire(identity, beforeFingerprint: 'before')
          .lease!;
      expect(coordinator.beginEffect(identity, lease), isTrue);
      final receipt = coordinator
          .markApplied(
            identity,
            lease,
            expectedAfterFingerprint: 'after',
            compensationToken: 'restore',
          )
          .receipt!;
      coordinator.retireOwner(ownerA);

      expect(
        coordinator.beginCompensation(
          identity,
          receipt,
          observedCurrentFingerprint: 'after',
        ),
        FileMutationCompensationDisposition.ready,
      );
      expect(
        coordinator.completeCompensation(identity, receipt, succeeded: false),
        FileMutationCompensationDisposition.failed,
      );
      expect(coordinator.isPathBusy(identity.canonicalPath), isTrue);
      expect(
        coordinator.beginCompensation(
          identity,
          receipt,
          observedCurrentFingerprint: 'after',
        ),
        FileMutationCompensationDisposition.ready,
      );
    });

    test('same owner with another tool call cannot use the lease', () {
      final coordinator = FileMutationEffectCoordinator();
      final identity = attempt(ownerA, call: 'call-a');
      final poisoned = attempt(ownerA, call: 'call-b');
      final lease = coordinator
          .acquire(identity, beforeFingerprint: 'before')
          .lease!;

      expect(lease.belongsTo(identity), isTrue);
      expect(lease.belongsTo(poisoned), isFalse);
      expect(coordinator.beginEffect(poisoned, lease), isFalse);
      expect(coordinator.finishWithoutEffect(poisoned, lease), isFalse);
      expect(coordinator.beginEffect(identity, lease), isTrue);
    });

    test('stale lease cannot release a successor at the same path', () {
      final coordinator = FileMutationEffectCoordinator();
      final firstIdentity = attempt(ownerA, call: 'first');
      final first = coordinator
          .acquire(firstIdentity, beforeFingerprint: 'before-a')
          .lease!;
      expect(coordinator.finishWithoutEffect(firstIdentity, first), isTrue);

      final successorIdentity = attempt(ownerB, call: 'successor');
      final successor = coordinator
          .acquire(successorIdentity, beforeFingerprint: 'before-b')
          .lease!;

      expect(coordinator.finishWithoutEffect(firstIdentity, first), isFalse);
      expect(coordinator.isPathBusy(successorIdentity.canonicalPath), isTrue);
      expect(
        coordinator.finishWithoutEffect(successorIdentity, successor),
        isTrue,
      );
    });

    test('next generation is isolated from an in-flight predecessor', () {
      final coordinator = FileMutationEffectCoordinator();
      final oldIdentity = attempt(ownerA, call: 'shared');
      final oldLease = coordinator
          .acquire(oldIdentity, beforeFingerprint: 'before')
          .lease!;

      expect(
        coordinator
            .acquire(
              attempt(ownerANext, call: 'shared'),
              beforeFingerprint: 'next',
            )
            .disposition,
        FileMutationAcquireDisposition.pathBusy,
      );
      expect(
        coordinator.beginEffect(attempt(ownerANext, call: 'shared'), oldLease),
        isFalse,
      );
    });

    test('clearAll returns exact pending work and blocks resurrection', () {
      final coordinator = FileMutationEffectCoordinator();
      final appliedIdentity = attempt(ownerA, path: '/workspace/applied.txt');
      final appliedLease = coordinator
          .acquire(appliedIdentity, beforeFingerprint: 'before-a')
          .lease!;
      expect(coordinator.beginEffect(appliedIdentity, appliedLease), isTrue);
      final receipt = coordinator
          .markApplied(
            appliedIdentity,
            appliedLease,
            expectedAfterFingerprint: 'after-a',
            compensationToken: 'restore-a',
          )
          .receipt!;
      final runningIdentity = attempt(
        ownerB,
        call: 'running',
        path: '/workspace/running.txt',
      );
      final runningLease = coordinator
          .acquire(runningIdentity, beforeFingerprint: 'before-b')
          .lease!;
      expect(coordinator.beginEffect(runningIdentity, runningLease), isTrue);

      final retirement = coordinator.clearAll();

      expect(retirement.compensationRequired, [same(receipt)]);
      expect(retirement.effectsInFlight, [same(runningLease)]);
      expect(
        coordinator
            .acquire(
              attempt(
                ChatTurnOwner(
                  conversationId: 'conversation-c',
                  interactionGeneration: 1,
                ),
              ),
              beforeFingerprint: 'later',
            )
            .disposition,
        FileMutationAcquireDisposition.ownerRetired,
      );
    });
  });
}
