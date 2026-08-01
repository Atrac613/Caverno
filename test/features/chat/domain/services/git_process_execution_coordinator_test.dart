import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/git_process_execution_coordinator.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = _owner('conversation-a', 7);
  final ownerB = _owner('conversation-b', 7);

  group('GitProcessExecutionIdentity', () {
    test('normalizes and compares every exact identity field', () {
      final identity = GitProcessExecutionIdentity(
        owner: ownerA,
        toolCallId: ' call-a ',
        toolName: ' git_execute ',
        repositoryIdentity: ' repo-a ',
        worktreeIdentity: ' worktree-a ',
        argumentDigest: ' sha256:aaa ',
      );

      expect(identity, _identity(ownerA));
      expect(identity.hashCode, _identity(ownerA).hashCode);
      expect(identity.toolCallId, 'call-a');
      expect(identity.toolName, 'git_execute');
      expect(identity.repositoryIdentity, 'repo-a');
      expect(identity.worktreeIdentity, 'worktree-a');
      expect(identity.argumentDigest, 'sha256:aaa');
      for (final poison in [
        _identity(ownerB),
        _identity(ownerA, call: 'call-b'),
        _identity(ownerA, tool: 'git_other'),
        _identity(ownerA, repository: 'repo-b'),
        _identity(ownerA, worktree: 'worktree-b'),
        _identity(ownerA, digest: 'sha256:bbb'),
      ]) {
        expect(identity, isNot(poison));
      }
    });

    test('rejects an empty identity component', () {
      for (final values in [
        (' ', 'git_execute', 'repo', 'worktree', 'digest'),
        ('call', '\n', 'repo', 'worktree', 'digest'),
        ('call', 'git_execute', '\t', 'worktree', 'digest'),
        ('call', 'git_execute', 'repo', '', 'digest'),
        ('call', 'git_execute', 'repo', 'worktree', ' '),
      ]) {
        expect(
          () => GitProcessExecutionIdentity(
            owner: ownerA,
            toolCallId: values.$1,
            toolName: values.$2,
            repositoryIdentity: values.$3,
            worktreeIdentity: values.$4,
            argumentDigest: values.$5,
          ),
          throwsArgumentError,
        );
      }
    });
  });

  group('GitProcessExecutionCoordinator lifecycle', () {
    test('abandons a reservation without releasing its successor', () {
      final coordinator = GitProcessExecutionCoordinator();
      final abandoned = _identity(ownerA);
      final successor = _identity(ownerB, call: 'successor');
      final token = _reserve(coordinator, abandoned);

      expect(
        coordinator.reserve(successor).disposition,
        GitProcessReserveDisposition.resourceBusy,
      );
      expect(
        coordinator.abandonBeforeStart(abandoned, token),
        GitProcessAbandonDisposition.abandoned,
      );
      expect(
        coordinator.abandonBeforeStart(abandoned, token),
        GitProcessAbandonDisposition.alreadyAbandoned,
      );
      expect(
        coordinator.start(abandoned, token),
        GitProcessStartDisposition.alreadyCompleted,
      );
      expect(
        coordinator
            .complete(
              identity: abandoned,
              token: token,
              effectKind: GitProcessEffectKind.noEffect,
            )
            .disposition,
        GitProcessCompletionDisposition.notStarted,
      );
      expect(
        coordinator.reserve(abandoned).disposition,
        GitProcessReserveDisposition.attemptConflict,
      );

      final successorToken = _reserve(coordinator, successor);
      expect(
        coordinator.start(successor, successorToken),
        GitProcessStartDisposition.started,
      );
      expect(
        coordinator.abandonBeforeStart(abandoned, token),
        GitProcessAbandonDisposition.alreadyAbandoned,
      );
      expect(
        coordinator.reserve(_identity(ownerA, call: 'third')).disposition,
        GitProcessReserveDisposition.resourceBusy,
      );
      expect(
        coordinator.abandonBeforeStart(successor, successorToken),
        GitProcessAbandonDisposition.alreadyStarted,
      );
    });

    test('settles no-effect work and protects its running successor', () {
      final coordinator = GitProcessExecutionCoordinator();
      final first = _identity(ownerA);
      final peer = _identity(ownerB, call: 'call-b');
      final firstToken = _reserve(coordinator, first);

      expect(
        coordinator.reserve(peer).disposition,
        GitProcessReserveDisposition.resourceBusy,
      );
      expect(
        coordinator.start(first, firstToken),
        GitProcessStartDisposition.started,
      );
      expect(
        coordinator.start(first, firstToken),
        GitProcessStartDisposition.alreadyStarted,
      );
      final noEffect = coordinator.complete(
        identity: first,
        token: firstToken,
        effectKind: GitProcessEffectKind.noEffect,
      );
      expect(noEffect.disposition, GitProcessCompletionDisposition.noEffect);
      expect(noEffect.isLate, isFalse);
      expect(noEffect.receipt, isNull);

      final successorToken = _reserve(coordinator, peer);
      expect(
        coordinator.start(peer, successorToken),
        GitProcessStartDisposition.started,
      );
      expect(
        coordinator
            .requestCancellation(
              identity: first,
              token: firstToken,
              cause: GitProcessCancellationCause.userRequested,
            )
            .disposition,
        GitProcessCancellationDisposition.alreadyCompleted,
      );
      expect(
        coordinator.release(identity: first, token: firstToken).disposition,
        GitProcessReleaseDisposition.alreadyReleased,
      );
      expect(
        coordinator
            .requestCancellation(
              identity: peer,
              token: successorToken,
              cause: GitProcessCancellationCause.userRequested,
            )
            .disposition,
        GitProcessCancellationDisposition.requested,
      );
      expect(
        coordinator
            .complete(
              identity: peer,
              token: successorToken,
              effectKind: GitProcessEffectKind.noEffect,
            )
            .disposition,
        GitProcessCompletionDisposition.noEffect,
      );
    });

    test('isolates same-owner calls and every execution identity field', () {
      final coordinator = GitProcessExecutionCoordinator();
      final first = _identity(ownerA, call: 'call-a');
      final second = _identity(
        ownerA,
        call: 'call-b',
        repository: 'repo-b',
        worktree: 'worktree-b',
      );
      final firstToken = _reserve(coordinator, first);
      final secondToken = _reserve(coordinator, second);
      final poisons = [
        _identity(ownerA, call: 'wrong-call'),
        _identity(ownerA, tool: 'wrong-tool'),
        _identity(ownerA, repository: 'wrong-repo'),
        _identity(ownerA, worktree: 'wrong-worktree'),
        _identity(ownerA, digest: 'wrong-digest'),
      ];

      for (final poison in poisons) {
        expect(
          coordinator.start(poison, firstToken),
          GitProcessStartDisposition.invalidAttempt,
        );
      }
      expect(
        coordinator.start(first, secondToken),
        GitProcessStartDisposition.invalidAttempt,
      );
      expect(
        coordinator.start(first, firstToken),
        GitProcessStartDisposition.started,
      );
      expect(
        coordinator.start(second, secondToken),
        GitProcessStartDisposition.started,
      );

      final committed = coordinator.complete(
        identity: first,
        token: firstToken,
        effectKind: GitProcessEffectKind.committed,
      );
      expect(
        committed.disposition,
        GitProcessCompletionDisposition.effectCommitted,
      );
      expect(
        coordinator.release(identity: first, token: firstToken).disposition,
        GitProcessReleaseDisposition.released,
      );
      expect(
        coordinator
            .requestCancellation(
              identity: second,
              token: secondToken,
              cause: GitProcessCancellationCause.timeout,
            )
            .disposition,
        GitProcessCancellationDisposition.requested,
      );
    });

    test('retains an exact committed receipt for later reconciliation', () {
      final coordinator = GitProcessExecutionCoordinator();
      final first = _identity(ownerA);
      final second = _identity(
        ownerB,
        call: 'second-call',
        repository: 'second-repo',
        worktree: 'second-worktree',
      );
      final firstToken = _reserveAndStart(coordinator, first);
      final secondToken = _reserveAndStart(coordinator, second);
      final firstReceipt = coordinator
          .complete(
            identity: first,
            token: firstToken,
            effectKind: GitProcessEffectKind.committed,
          )
          .receipt!;
      final secondReceipt = coordinator
          .complete(
            identity: second,
            token: secondToken,
            effectKind: GitProcessEffectKind.committed,
          )
          .receipt!;

      expect(
        coordinator.requireReconciliation(
          identity: first,
          token: firstToken,
          effectReceipt: secondReceipt,
        ),
        GitProcessRequireReconciliationDisposition.invalidEffectReceipt,
      );
      final required = coordinator.requireReconciliation(
        identity: first,
        token: firstToken,
        effectReceipt: firstReceipt,
      );

      expect(required, GitProcessRequireReconciliationDisposition.required);
      expect(
        coordinator.requireReconciliation(
          identity: first,
          token: firstToken,
          effectReceipt: firstReceipt,
        ),
        GitProcessRequireReconciliationDisposition.alreadyRequired,
      );
      expect(
        coordinator.release(identity: first, token: firstToken).disposition,
        GitProcessReleaseDisposition.reconciliationRequired,
      );
    });

    test('rejects a token issued by another coordinator', () {
      final coordinator = GitProcessExecutionCoordinator();
      final foreign = GitProcessExecutionCoordinator();
      final identity = _identity(ownerA);
      final token = _reserve(coordinator, identity);
      final foreignToken = _reserve(foreign, identity);

      expect(token.toString(), 'GitProcessAttemptToken(<opaque>)');
      expect(token, isNot(foreignToken));
      expect(
        coordinator.start(identity, foreignToken),
        GitProcessStartDisposition.invalidAttempt,
      );
      expect(
        coordinator.abandonBeforeStart(identity, foreignToken),
        GitProcessAbandonDisposition.invalidAttempt,
      );
      expect(
        coordinator
            .requestCancellation(
              identity: identity,
              token: foreignToken,
              cause: GitProcessCancellationCause.timeout,
            )
            .disposition,
        GitProcessCancellationDisposition.invalidAttempt,
      );
      expect(
        coordinator
            .complete(
              identity: identity,
              token: foreignToken,
              effectKind: GitProcessEffectKind.noEffect,
            )
            .disposition,
        GitProcessCompletionDisposition.invalidAttempt,
      );
      expect(
        coordinator
            .release(identity: identity, token: foreignToken)
            .disposition,
        GitProcessReleaseDisposition.invalidAttempt,
      );
      expect(
        coordinator.start(identity, token),
        GitProcessStartDisposition.started,
      );
    });
  });

  group('GitProcessExecutionCoordinator retirement', () {
    test('prevents launch when the exact owner retires before start', () {
      final coordinator = GitProcessExecutionCoordinator();
      final identity = _identity(ownerA);
      final token = _reserve(coordinator, identity);

      final work = coordinator.clearOwner(ownerA);

      expect(work.preventedStartCount, 1);
      expect(work.cancellationRequests, isEmpty);
      expect(work.reconciliationRequired, isEmpty);
      expect(() => work.cancellationRequests.clear(), throwsUnsupportedError);
      expect(() => work.reconciliationRequired.clear(), throwsUnsupportedError);
      expect(
        coordinator.start(identity, token),
        GitProcessStartDisposition.ownerRetired,
      );
      expect(
        coordinator.reserve(_identity(ownerA, call: 'new-call')).disposition,
        GitProcessReserveDisposition.ownerRetired,
      );

      final peer = _identity(ownerB, call: 'peer-call');
      final peerToken = _reserve(coordinator, peer);
      expect(
        coordinator.start(peer, peerToken),
        GitProcessStartDisposition.started,
      );
    });

    test(
      'marks a running owner completion late and requires reconciliation',
      () {
        final coordinator = GitProcessExecutionCoordinator();
        final identity = _identity(ownerA);
        final token = _reserveAndStart(coordinator, identity);

        final work = coordinator.clearOwner(ownerA);

        expect(work.preventedStartCount, 0);
        expect(work.cancellationRequests, hasLength(1));
        final cancellation = work.cancellationRequests.single;
        expect(cancellation.identity, identity);
        expect(cancellation.token, same(token));
        expect(cancellation.cause, GitProcessCancellationCause.ownerRetired);
        expect(work.reconciliationRequired, isEmpty);

        final completion = coordinator.complete(
          identity: identity,
          token: token,
          effectKind: GitProcessEffectKind.committed,
          effectDetails: const {'base_head': 'abc', 'merged_head': 'def'},
        );
        expect(
          completion.disposition,
          GitProcessCompletionDisposition.reconciliationRequired,
        );
        expect(completion.isLate, isTrue);
        expect(completion.receipt?.kind, GitProcessEffectKind.committed);
        expect(
          coordinator.release(identity: identity, token: token).disposition,
          GitProcessReleaseDisposition.reconciliationRequired,
        );
        expect(
          coordinator
              .release(
                identity: identity,
                token: token,
                reconciliationReceipt: _recordReconciliation(
                  coordinator,
                  identity,
                  token,
                  completion.receipt!,
                ),
              )
              .disposition,
          GitProcessReleaseDisposition.reconciledAndReleased,
        );
      },
    );

    test('turns an unaccepted committed receipt into reconciliation work', () {
      final coordinator = GitProcessExecutionCoordinator();
      final identity = _identity(ownerA);
      final token = _reserveAndStart(coordinator, identity);
      final labels = <Object?>['merge'];
      final details = <String, dynamic>{
        'labels': labels,
        'refs': <String, dynamic>{'head': 'def'},
      };
      final completion = coordinator.complete(
        identity: identity,
        token: token,
        effectKind: GitProcessEffectKind.committed,
        effectDetails: details,
      );
      labels.add('poisoned');
      (details['refs'] as Map)['head'] = 'poisoned';

      expect(
        completion.disposition,
        GitProcessCompletionDisposition.effectCommitted,
      );
      expect(completion.isLate, isFalse);
      final receipt = completion.receipt!;
      expect(receipt.details, {
        'labels': ['merge'],
        'refs': {'head': 'def'},
      });
      expect(
        () => (receipt.details['labels'] as List).add('late'),
        throwsUnsupportedError,
      );
      expect(
        () => (receipt.details['refs'] as Map)['head'] = 'late',
        throwsUnsupportedError,
      );
      expect(
        coordinator
            .recordReconciliation(
              identity: identity,
              token: token,
              effectReceipt: receipt,
            )
            .disposition,
        GitProcessReconciliationDisposition.notRequired,
      );

      final retirement = coordinator.clearOwner(ownerA);
      expect(retirement.reconciliationRequired, [receipt]);
      expect(
        coordinator.release(identity: identity, token: token).disposition,
        GitProcessReleaseDisposition.reconciliationRequired,
      );
      expect(
        coordinator
            .release(
              identity: identity,
              token: token,
              reconciliationReceipt: _recordReconciliation(
                coordinator,
                identity,
                token,
                receipt,
              ),
            )
            .disposition,
        GitProcessReleaseDisposition.reconciledAndReleased,
      );
    });

    test('rejects aliased mutable effect details before completion', () {
      final coordinator = GitProcessExecutionCoordinator();
      final identity = _identity(ownerA);
      final token = _reserveAndStart(coordinator, identity);

      expect(
        () => coordinator.complete(
          identity: identity,
          token: token,
          effectKind: GitProcessEffectKind.committed,
          effectDetails: {'mutable': _MutableValue()},
        ),
        throwsArgumentError,
      );
      expect(
        () => coordinator.complete(
          identity: identity,
          token: token,
          effectKind: GitProcessEffectKind.committed,
          effectDetails: {
            'set': <Object?>{'not-json'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => coordinator.complete(
          identity: identity,
          token: token,
          effectKind: GitProcessEffectKind.committed,
          effectDetails: {'number': double.infinity},
        ),
        throwsArgumentError,
      );
      expect(
        () => coordinator.complete(
          identity: identity,
          token: token,
          effectKind: GitProcessEffectKind.committed,
          effectDetails: {
            'mutableKey': {_MutableValue(): true},
          },
        ),
        throwsArgumentError,
      );
      expect(
        coordinator
            .complete(
              identity: identity,
              token: token,
              effectKind: GitProcessEffectKind.noEffect,
            )
            .disposition,
        GitProcessCompletionDisposition.noEffect,
      );
    });

    test(
      'never accepts a partial-or-unknown effect without reconciliation',
      () {
        final coordinator = GitProcessExecutionCoordinator();
        final identity = _identity(ownerA);
        final token = _reserveAndStart(coordinator, identity);

        final partial = coordinator.complete(
          identity: identity,
          token: token,
          effectKind: GitProcessEffectKind.partialOrUnknown,
          effectDetails: const {
            'merge_started': true,
            'worktree_removed': false,
          },
        );

        expect(
          partial.disposition,
          GitProcessCompletionDisposition.reconciliationRequired,
        );
        expect(partial.isLate, isFalse);
        expect(partial.receipt?.kind, GitProcessEffectKind.partialOrUnknown);
        expect(
          coordinator.release(identity: identity, token: token).disposition,
          GitProcessReleaseDisposition.reconciliationRequired,
        );
        expect(coordinator.clearOwner(ownerA).reconciliationRequired, [
          partial.receipt,
        ]);
        expect(
          coordinator
              .release(
                identity: identity,
                token: token,
                reconciliationReceipt: _recordReconciliation(
                  coordinator,
                  identity,
                  token,
                  partial.receipt!,
                ),
              )
              .disposition,
          GitProcessReleaseDisposition.reconciledAndReleased,
        );
      },
    );

    test('binds reconciliation receipts to one exact effect and lease', () {
      final coordinator = GitProcessExecutionCoordinator();
      final first = _identity(ownerA, call: 'first');
      final second = _identity(
        ownerB,
        call: 'second',
        repository: 'repo-b',
        worktree: 'worktree-b',
      );
      final firstToken = _reserveAndStart(coordinator, first);
      final secondToken = _reserveAndStart(coordinator, second);
      final firstEffect = coordinator
          .complete(
            identity: first,
            token: firstToken,
            effectKind: GitProcessEffectKind.partialOrUnknown,
          )
          .receipt!;
      final secondEffect = coordinator
          .complete(
            identity: second,
            token: secondToken,
            effectKind: GitProcessEffectKind.partialOrUnknown,
          )
          .receipt!;

      expect(
        coordinator
            .recordReconciliation(
              identity: first,
              token: firstToken,
              effectReceipt: secondEffect,
            )
            .disposition,
        GitProcessReconciliationDisposition.invalidEffectReceipt,
      );
      expect(
        coordinator
            .recordReconciliation(
              identity: second,
              token: firstToken,
              effectReceipt: firstEffect,
            )
            .disposition,
        GitProcessReconciliationDisposition.invalidAttempt,
      );

      final firstRecorded = coordinator.recordReconciliation(
        identity: first,
        token: firstToken,
        effectReceipt: firstEffect,
      );
      final secondReceipt = _recordReconciliation(
        coordinator,
        second,
        secondToken,
        secondEffect,
      );
      expect(
        firstRecorded.disposition,
        GitProcessReconciliationDisposition.recorded,
      );
      final firstReceipt = firstRecorded.receipt!;
      expect(
        firstReceipt.toString(),
        'GitProcessReconciliationReceipt(<opaque>)',
      );
      final replay = coordinator.recordReconciliation(
        identity: first,
        token: firstToken,
        effectReceipt: firstEffect,
      );
      expect(
        replay.disposition,
        GitProcessReconciliationDisposition.alreadyRecorded,
      );
      expect(replay.receipt, same(firstReceipt));

      expect(
        coordinator
            .release(
              identity: first,
              token: firstToken,
              reconciliationReceipt: secondReceipt,
            )
            .disposition,
        GitProcessReleaseDisposition.invalidReconciliationReceipt,
      );
      expect(
        coordinator
            .reserve(_identity(ownerB, call: 'blocked-successor'))
            .disposition,
        GitProcessReserveDisposition.resourceBusy,
      );
      expect(
        coordinator
            .release(
              identity: first,
              token: firstToken,
              reconciliationReceipt: firstReceipt,
            )
            .disposition,
        GitProcessReleaseDisposition.reconciledAndReleased,
      );
      expect(
        coordinator
            .release(
              identity: first,
              token: firstToken,
              reconciliationReceipt: firstReceipt,
            )
            .disposition,
        GitProcessReleaseDisposition.alreadyReleased,
      );
      expect(
        coordinator
            .recordReconciliation(
              identity: first,
              token: firstToken,
              effectReceipt: firstEffect,
            )
            .disposition,
        GitProcessReconciliationDisposition.alreadyRecorded,
      );
      _reserve(coordinator, _identity(ownerB, call: 'successor'));
    });

    test('returns exact global cancellation and reconciliation work', () {
      final coordinator = GitProcessExecutionCoordinator();
      final reserved = _identity(
        ownerA,
        call: 'reserved',
        worktree: 'reserved-worktree',
      );
      final running = _identity(
        ownerB,
        call: 'running',
        repository: 'running-repo',
        worktree: 'running-worktree',
      );
      final ownerC = _owner('conversation-c', 7);
      final committed = _identity(
        ownerC,
        call: 'committed',
        repository: 'committed-repo',
        worktree: 'committed-worktree',
      );
      final reservedToken = _reserve(coordinator, reserved);
      final runningToken = _reserveAndStart(coordinator, running);
      final committedToken = _reserveAndStart(coordinator, committed);
      final committedReceipt = coordinator
          .complete(
            identity: committed,
            token: committedToken,
            effectKind: GitProcessEffectKind.committed,
          )
          .receipt!;

      final work = coordinator.clearAll();

      expect(work.preventedStartCount, 1);
      expect(work.cancellationRequests, hasLength(1));
      expect(work.cancellationRequests.single.identity, running);
      expect(work.cancellationRequests.single.token, same(runningToken));
      expect(work.reconciliationRequired, [committedReceipt]);
      expect(
        coordinator.start(reserved, reservedToken),
        GitProcessStartDisposition.ownerRetired,
      );
      final lateNoEffect = coordinator.complete(
        identity: running,
        token: runningToken,
        effectKind: GitProcessEffectKind.noEffect,
      );
      expect(
        lateNoEffect.disposition,
        GitProcessCompletionDisposition.noEffect,
      );
      expect(lateNoEffect.isLate, isTrue);
      expect(
        coordinator
            .reserve(_identity(_owner('conversation-d', 1), call: 'new'))
            .disposition,
        GitProcessReserveDisposition.ownerRetired,
      );
    });
  });

  test('timeout cancellation fences a later committed effect', () {
    final coordinator = GitProcessExecutionCoordinator();
    final identity = _identity(ownerA);
    final token = _reserve(coordinator, identity);
    expect(
      coordinator
          .requestCancellation(
            identity: identity,
            token: token,
            cause: GitProcessCancellationCause.timeout,
          )
          .disposition,
      GitProcessCancellationDisposition.notRunning,
    );
    expect(
      coordinator.start(identity, token),
      GitProcessStartDisposition.started,
    );

    final requested = coordinator.requestCancellation(
      identity: identity,
      token: token,
      cause: GitProcessCancellationCause.timeout,
    );
    final repeated = coordinator.requestCancellation(
      identity: identity,
      token: token,
      cause: GitProcessCancellationCause.userRequested,
    );
    expect(requested.disposition, GitProcessCancellationDisposition.requested);
    expect(requested.request?.identity, identity);
    expect(requested.request?.token, same(token));
    expect(requested.request?.cause, GitProcessCancellationCause.timeout);
    expect(
      repeated.disposition,
      GitProcessCancellationDisposition.alreadyRequested,
    );
    expect(repeated.request, same(requested.request));

    final completion = coordinator.complete(
      identity: identity,
      token: token,
      effectKind: GitProcessEffectKind.committed,
    );
    expect(
      completion.disposition,
      GitProcessCompletionDisposition.reconciliationRequired,
    );
    expect(completion.isLate, isFalse);
    expect(
      coordinator.release(identity: identity, token: token).disposition,
      GitProcessReleaseDisposition.reconciliationRequired,
    );
  });
}

ChatTurnOwner _owner(String conversationId, int generation) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

GitProcessExecutionIdentity _identity(
  ChatTurnOwner owner, {
  String call = 'call-a',
  String tool = 'git_execute',
  String repository = 'repo-a',
  String worktree = 'worktree-a',
  String digest = 'sha256:aaa',
}) {
  return GitProcessExecutionIdentity(
    owner: owner,
    toolCallId: call,
    toolName: tool,
    repositoryIdentity: repository,
    worktreeIdentity: worktree,
    argumentDigest: digest,
  );
}

GitProcessAttemptToken _reserve(
  GitProcessExecutionCoordinator coordinator,
  GitProcessExecutionIdentity identity,
) {
  final result = coordinator.reserve(identity);
  expect(result.disposition, GitProcessReserveDisposition.reserved);
  return result.token!;
}

GitProcessAttemptToken _reserveAndStart(
  GitProcessExecutionCoordinator coordinator,
  GitProcessExecutionIdentity identity,
) {
  final token = _reserve(coordinator, identity);
  expect(
    coordinator.start(identity, token),
    GitProcessStartDisposition.started,
  );
  return token;
}

GitProcessReconciliationReceipt _recordReconciliation(
  GitProcessExecutionCoordinator coordinator,
  GitProcessExecutionIdentity identity,
  GitProcessAttemptToken token,
  GitProcessEffectReceipt effectReceipt,
) {
  final result = coordinator.recordReconciliation(
    identity: identity,
    token: token,
    effectReceipt: effectReceipt,
  );
  expect(result.disposition, GitProcessReconciliationDisposition.recorded);
  return result.receipt!;
}

final class _MutableValue {
  var value = 0;
}
