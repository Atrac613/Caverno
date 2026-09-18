import 'dart:async';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/file_mutation_path_fence.dart';
import 'package:test/test.dart';

/// Completes once every microtask queued so far has run, so a test can assert
/// that a blocked caller has *not* started rather than waiting on a timeout.
Future<void> _settle() async {
  for (var turn = 0; turn < 8; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('mutation-fence-');
  });

  tearDown(() async {
    if (workspace.existsSync()) {
      await workspace.delete(recursive: true);
    }
  });

  String at(String name) => '${workspace.path}${Platform.pathSeparator}$name';

  group('runExclusive', () {
    test('serializes two callers on the same path', () async {
      final fence = FileMutationPathFence();
      final order = <String>[];
      final first = Completer<void>();

      final a = fence.runExclusive(at('a.txt'), () async {
        order.add('a-start');
        await first.future;
        order.add('a-end');
      });
      final b = fence.runExclusive(at('a.txt'), () async {
        order.add('b-start');
      });

      await _settle();
      expect(order, ['a-start'], reason: 'b must not start while a holds it');
      first.complete();
      await Future.wait([a, b]);
      expect(order, ['a-start', 'a-end', 'b-start']);
    });

    test('lets different paths run at the same time', () async {
      final fence = FileMutationPathFence();
      final started = <String>[];
      final release = Completer<void>();

      final a = fence.runExclusive(at('a.txt'), () async {
        started.add('a');
        await release.future;
      });
      final b = fence.runExclusive(at('b.txt'), () async {
        started.add('b');
        await release.future;
      });

      await _settle();
      expect(started, ['a', 'b']);
      release.complete();
      await Future.wait([a, b]);
    });

    test('collapses a symlink and its target onto one lease', () async {
      final target = File(at('target.txt'))..writeAsStringSync('x');
      final link = Link(at('alias.txt'))..createSync(target.path);
      final fence = FileMutationPathFence();
      final order = <String>[];
      final held = Completer<void>();

      // The reason this class exists: two different spellings of one file are
      // one filesystem effect, and lexical keys alone would let them overlap.
      final viaTarget = fence.runExclusive(target.path, () async {
        order.add('target-start');
        await held.future;
        order.add('target-end');
      });
      final viaLink = fence.runExclusive(link.path, () async {
        order.add('link-start');
      });

      await _settle();
      expect(order, ['target-start']);
      held.complete();
      await Future.wait([viaTarget, viaLink]);
      expect(order, ['target-start', 'target-end', 'link-start']);
    });

    test('collapses a lexical alias of the same file', () async {
      final fence = FileMutationPathFence();
      final direct = at('a.txt');
      final indirect =
          '${workspace.path}${Platform.pathSeparator}.'
          '${Platform.pathSeparator}a.txt';
      final order = <String>[];
      final held = Completer<void>();

      final first = fence.runExclusive(direct, () async {
        order.add('direct');
        await held.future;
      });
      final second = fence.runExclusive(indirect, () async {
        order.add('indirect');
      });

      await _settle();
      expect(order, ['direct']);
      held.complete();
      await Future.wait([first, second]);
      expect(order, ['direct', 'indirect']);
    });

    test('a thrown operation releases its path for the next caller', () async {
      final fence = FileMutationPathFence();
      final ran = <String>[];

      await expectLater(
        fence.runExclusive(at('a.txt'), () async {
          ran.add('first');
          throw StateError('boom');
        }),
        throwsStateError,
      );
      await fence.runExclusive(at('a.txt'), () async => ran.add('second'));

      expect(ran, ['first', 'second']);
    });

    test('a queued caller still runs after its predecessor throws', () async {
      final fence = FileMutationPathFence();
      final ran = <String>[];
      final held = Completer<void>();

      final failing = fence.runExclusive(at('a.txt'), () async {
        ran.add('first');
        await held.future;
        throw StateError('boom');
      });
      final queued = fence.runExclusive(
        at('a.txt'),
        () async => ran.add('second'),
      );

      await _settle();
      held.complete();
      await expectLater(failing, throwsStateError);
      await queued;
      expect(ran, ['first', 'second']);
    });

    test('rejects an empty or untrimmed path', () async {
      final fence = FileMutationPathFence();
      expect(
        () => fence.runExclusive('', () async {}),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => fence.runExclusive(' ${at('a.txt')}', () async {}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('runExclusiveAll', () {
    test('overlapping callers in opposite order do not deadlock', () async {
      final fence = FileMutationPathFence();
      final done = <String>[];
      // Sorted acquisition is the only thing keeping this from deadlocking:
      // naive in-order locking has each caller holding what the other wants.
      final forward = fence.runExclusiveAll(
        [at('a.txt'), at('b.txt')],
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          done.add('forward');
        },
      );
      final reverse = fence.runExclusiveAll(
        [at('b.txt'), at('a.txt')],
        () async {
          done.add('reverse');
        },
      );

      await Future.wait([forward, reverse]).timeout(const Duration(seconds: 5));
      expect(done, hasLength(2));
    });

    test('the same path twice takes one lease rather than self-blocking', () {
      final fence = FileMutationPathFence();
      return expectLater(
        fence.runExclusiveAll([at('a.txt'), at('a.txt')], () async => 'ok'),
        completion('ok'),
      );
    });

    test('blocks a single-path caller on any member of the group', () async {
      final fence = FileMutationPathFence();
      final order = <String>[];
      final held = Completer<void>();

      // Wait for the group to be holding its leases before racing it. The
      // fence orders holders, not callers: runExclusiveAll resolves one key
      // per path before it acquires anything, so a single-path caller issued
      // at the same moment can finish resolving first and win the path.
      final holding = Completer<void>();
      final group = fence.runExclusiveAll([at('a.txt'), at('b.txt')], () async {
        order.add('group');
        holding.complete();
        await held.future;
      });
      await holding.future;

      final single = fence.runExclusive(at('b.txt'), () async {
        order.add('single');
      });

      await _settle();
      expect(order, ['group']);
      held.complete();
      await Future.wait([group, single]);
      expect(order, ['group', 'single']);
    });

    test('a throw releases every lease it took', () async {
      final fence = FileMutationPathFence();
      await expectLater(
        fence.runExclusiveAll([at('a.txt'), at('b.txt')], () async {
          throw StateError('boom');
        }),
        throwsStateError,
      );
      // Both paths must be free, not just the last one released.
      await fence
          .runExclusiveAll([at('a.txt'), at('b.txt')], () async {})
          .timeout(const Duration(seconds: 5));
    });
  });

  group('single-path transactions', () {
    test(
      'holds the path from begin until the settlement releases it',
      () async {
        final fence = FileMutationPathFence();
        final order = <String>[];
        final transaction = await fence.beginTransaction(
          path: at('a.txt'),
          transactionToken: 'tx-1',
        );
        fence.markHandoffReady(transaction);

        final waiting = fence.runExclusive(at('a.txt'), () async {
          order.add('waiting');
        });

        await _settle();
        expect(order, isEmpty, reason: 'the transaction still holds the path');

        // A settlement that does not release keeps the path held.
        final pending = await fence.settleTransaction<bool>(
          path: at('a.txt'),
          transactionToken: 'tx-1',
          operation: () async => false,
          releaseWhen: (value) => value,
        );
        expect(pending!.value, isFalse);
        await _settle();
        expect(order, isEmpty);

        final settled = await fence.settleTransaction<bool>(
          path: at('a.txt'),
          transactionToken: 'tx-1',
          operation: () async => true,
          releaseWhen: (value) => value,
        );
        expect(settled!.value, isTrue);
        await waiting;
        expect(order, ['waiting']);
      },
    );

    test('settleTransaction waits for the handoff before running', () async {
      final fence = FileMutationPathFence();
      final transaction = await fence.beginTransaction(
        path: at('a.txt'),
        transactionToken: 'tx-1',
      );
      var ran = false;

      final settlement = fence.settleTransaction<bool>(
        path: at('a.txt'),
        transactionToken: 'tx-1',
        operation: () async {
          ran = true;
          return true;
        },
        releaseWhen: (value) => value,
      );

      await _settle();
      expect(ran, isFalse, reason: 'the handoff has not been marked ready');
      fence.markHandoffReady(transaction);
      await settlement;
      expect(ran, isTrue);
    });

    test('returns null for an unknown token or a mismatched path', () async {
      final fence = FileMutationPathFence();
      await fence.beginTransaction(path: at('a.txt'), transactionToken: 'tx-1');

      expect(
        await fence.settleTransaction<bool>(
          path: at('a.txt'),
          transactionToken: 'tx-missing',
          operation: () async => true,
          releaseWhen: (_) => true,
        ),
        isNull,
      );
      expect(
        await fence.settleTransaction<bool>(
          path: at('other.txt'),
          transactionToken: 'tx-1',
          operation: () async => true,
          releaseWhen: (_) => true,
        ),
        isNull,
      );
    });

    test('rejects a token that is already active', () async {
      final fence = FileMutationPathFence();
      await fence.beginTransaction(path: at('a.txt'), transactionToken: 'tx-1');
      await expectLater(
        fence.beginTransaction(path: at('b.txt'), transactionToken: 'tx-1'),
        throwsStateError,
      );
    });

    test('finishWithoutEffect releases the path', () async {
      final fence = FileMutationPathFence();
      final transaction = await fence.beginTransaction(
        path: at('a.txt'),
        transactionToken: 'tx-1',
      );
      fence.finishWithoutEffect(transaction);

      await fence
          .runExclusive(at('a.txt'), () async {})
          .timeout(const Duration(seconds: 5));
      // The transaction is gone, so operating on it again is a programming
      // error rather than a silent no-op.
      expect(() => fence.finishWithoutEffect(transaction), throwsStateError);
    });
  });

  group('group transactions', () {
    test('holds every path until the settlement releases them', () async {
      final fence = FileMutationPathFence();
      final order = <String>[];
      await fence.beginTransactionAll(
        paths: [at('a.txt'), at('b.txt')],
        transactionToken: 'tx-group',
      );

      final waiting = fence.runExclusive(at('b.txt'), () async {
        order.add('waiting');
      });
      await _settle();
      expect(order, isEmpty);

      final settled = await fence.settleTransactionAll<bool>(
        transactionToken: 'tx-group',
        operation: () async => true,
        releaseWhen: (value) => value,
      );
      expect(settled!.value, isTrue);
      await waiting;
      expect(order, ['waiting']);
    });

    test('serializes concurrent settlements of one transaction', () async {
      final fence = FileMutationPathFence();
      await fence.beginTransactionAll(
        paths: [at('a.txt')],
        transactionToken: 'tx-group',
      );
      final order = <String>[];
      final first = Completer<void>();

      final one = fence.settleTransactionAll<bool>(
        transactionToken: 'tx-group',
        operation: () async {
          order.add('one-start');
          await first.future;
          order.add('one-end');
          return false;
        },
        releaseWhen: (value) => value,
      );
      final two = fence.settleTransactionAll<bool>(
        transactionToken: 'tx-group',
        operation: () async {
          order.add('two-start');
          return true;
        },
        releaseWhen: (value) => value,
      );

      await _settle();
      expect(order, ['one-start'], reason: 'settlements must not interleave');
      first.complete();
      await Future.wait([one, two]);
      expect(order, ['one-start', 'one-end', 'two-start']);
    });

    test('finishTransactionAllByToken reports whether it found one', () async {
      final fence = FileMutationPathFence();
      await fence.beginTransactionAll(
        paths: [at('a.txt')],
        transactionToken: 'tx-group',
      );

      expect(fence.finishTransactionAllByToken('tx-group'), isTrue);
      expect(fence.finishTransactionAllByToken('tx-group'), isFalse);
      await fence
          .runExclusive(at('a.txt'), () async {})
          .timeout(const Duration(seconds: 5));
    });

    test('settleTransactionAll returns null for an unknown token', () async {
      final fence = FileMutationPathFence();
      expect(
        await fence.settleTransactionAll<bool>(
          transactionToken: 'tx-missing',
          operation: () async => true,
          releaseWhen: (_) => true,
        ),
        isNull,
      );
    });

    test('rejects a group token that is already active', () async {
      final fence = FileMutationPathFence();
      await fence.beginTransactionAll(
        paths: [at('a.txt')],
        transactionToken: 'tx-group',
      );
      await expectLater(
        fence.beginTransactionAll(
          paths: [at('b.txt')],
          transactionToken: 'tx-group',
        ),
        throwsStateError,
      );
    });

    test('a throwing settlement does not strand the next one', () async {
      final fence = FileMutationPathFence();
      await fence.beginTransactionAll(
        paths: [at('a.txt')],
        transactionToken: 'tx-group',
      );

      await expectLater(
        fence.settleTransactionAll<bool>(
          transactionToken: 'tx-group',
          operation: () async => throw StateError('boom'),
          releaseWhen: (value) => value,
        ),
        throwsStateError,
      );
      // The serialization tail has to survive the failure, or every later
      // recovery attempt on this transaction would hang.
      final settled = await fence
          .settleTransactionAll<bool>(
            transactionToken: 'tx-group',
            operation: () async => true,
            releaseWhen: (value) => value,
          )
          .timeout(const Duration(seconds: 5));
      expect(settled!.value, isTrue);
    });

    test('finishTransactionAll twice is a programming error', () async {
      final fence = FileMutationPathFence();
      final transaction = await fence.beginTransactionAll(
        paths: [at('a.txt')],
        transactionToken: 'tx-group',
      );
      fence.finishTransactionAll(transaction);
      expect(() => fence.finishTransactionAll(transaction), throwsStateError);
    });
  });

  group('target swapped under a held fence', () {
    test(
      'rejects a queued caller whose path changed while it waited',
      () async {
        final first = File(at('first.txt'))..writeAsStringSync('1');
        File(at('second.txt')).writeAsStringSync('2');
        final link = Link(at('alias.txt'))..createSync(first.path);
        final fence = FileMutationPathFence();
        final holding = Completer<void>();
        final held = Completer<void>();

        final holder = fence.runExclusive(link.path, () async {
          holding.complete();
          await held.future;
        });
        await holding.future;

        // Queued against the lease the holder took on first.txt.
        final queued = fence.runExclusive(link.path, () async => 'ran');

        await _settle();
        // Repoint the alias while the queued caller is parked. Without the
        // re-resolve after acquisition it would now mutate second.txt under a
        // lease that only ever protected first.txt.
        link.deleteSync();
        Link(at('alias.txt')).createSync(at('second.txt'));

        held.complete();
        await holder;
        await expectLater(queued, throwsStateError);

        expect(first.readAsStringSync(), '1');
      },
    );

    test('rejects a multi-path caller whose target changed', () async {
      File(at('first.txt')).writeAsStringSync('1');
      File(at('second.txt')).writeAsStringSync('2');
      final link = Link(at('alias.txt'))..createSync(at('first.txt'));
      final fence = FileMutationPathFence();
      final holding = Completer<void>();
      final held = Completer<void>();

      final holder = fence.runExclusive(link.path, () async {
        holding.complete();
        await held.future;
      });
      await holding.future;

      final queued = fence.runExclusiveAll([
        link.path,
        at('other.txt'),
      ], () async => 'ran');

      await _settle();
      link.deleteSync();
      Link(at('alias.txt')).createSync(at('second.txt'));

      held.complete();
      await holder;
      await expectLater(queued, throwsStateError);
    });
  });

  group('lifecycle', () {
    test('close waits for work in flight and then refuses more', () async {
      final fence = FileMutationPathFence();
      final held = Completer<void>();
      var finished = false;

      // Close only waits for leases that were actually acquired, and
      // runExclusive resolves its path key before acquiring one. Closing
      // before that lands makes the operation throw instead of running.
      final holding = Completer<void>();
      final running = fence.runExclusive(at('a.txt'), () async {
        holding.complete();
        await held.future;
        finished = true;
      });
      await holding.future;

      var closed = false;
      final closing = fence.close().then((_) => closed = true);
      await _settle();
      expect(closed, isFalse, reason: 'a held lease must delay close');

      held.complete();
      await running;
      await closing;
      expect(finished, isTrue);

      await expectLater(
        fence.runExclusive(at('b.txt'), () async {}),
        throwsStateError,
      );
    });

    test('a caller queued when close lands is refused, not stranded', () async {
      final fence = FileMutationPathFence();
      final holding = Completer<void>();
      final held = Completer<void>();

      final holder = fence.runExclusive(at('a.txt'), () async {
        holding.complete();
        await held.future;
      });
      await holding.future;
      final queued = fence.runExclusive(at('a.txt'), () async => 'ran');
      await _settle();

      final closing = fence.close();
      held.complete();
      await holder;

      await expectLater(queued, throwsStateError);
      await closing.timeout(const Duration(seconds: 5));
    });

    test('close completes immediately when nothing is held', () async {
      final fence = FileMutationPathFence();
      await fence.close().timeout(const Duration(seconds: 5));
    });

    test('clearAll refuses to run while work is active', () async {
      final fence = FileMutationPathFence();
      final held = Completer<void>();
      final running = fence.runExclusive(at('a.txt'), () async {
        await held.future;
      });

      await _settle();
      expect(fence.clearAll, throwsStateError);

      held.complete();
      await running;
      fence.clearAll();
    });

    test('clearAll refuses while a transaction is open', () async {
      final fence = FileMutationPathFence();
      final transaction = await fence.beginTransaction(
        path: at('a.txt'),
        transactionToken: 'tx-1',
      );
      expect(fence.clearAll, throwsStateError);
      fence.finishWithoutEffect(transaction);
      fence.clearAll();
    });
  });

  group('resolvePathKey', () {
    test('gives a symlink and its target the same key', () async {
      final target = File(at('target.txt'))..writeAsStringSync('x');
      final link = Link(at('alias.txt'))..createSync(target.path);

      expect(
        await FileMutationPathFence.resolvePathKey(link.path),
        await FileMutationPathFence.resolvePathKey(target.path),
      );
    });

    test('keeps distinct files distinct', () async {
      File(at('a.txt')).writeAsStringSync('a');
      File(at('b.txt')).writeAsStringSync('b');

      expect(
        await FileMutationPathFence.resolvePathKey(at('a.txt')),
        isNot(await FileMutationPathFence.resolvePathKey(at('b.txt'))),
      );
    });

    test(
      'resolves a path that does not exist yet through its parent',
      () async {
        // write_file creates its target, so the fence has to key a missing path
        // by the real directory it will land in.
        final missing = at('not-created-yet.txt');
        final key = await FileMutationPathFence.resolvePathKey(missing);

        expect(key, endsWith('not-created-yet.txt'));
        expect(
          key,
          await FileMutationPathFence.resolvePathKey(missing),
          reason: 'the key must be stable before the file exists',
        );
      },
    );

    test('a missing path keys the same before and after creation', () async {
      final path = at('created-later.txt');
      final before = await FileMutationPathFence.resolvePathKey(path);
      File(path).writeAsStringSync('x');
      final after = await FileMutationPathFence.resolvePathKey(path);

      // Otherwise a create and a follow-up write on one file would take two
      // different leases and could overlap.
      expect(after, before);
    });

    test('sync and async resolution agree', () async {
      final path = at('a.txt');
      File(path).writeAsStringSync('x');

      expect(
        FileMutationPathFence.resolvePathKeySync(path),
        await FileMutationPathFence.resolvePathKey(path),
      );
    });

    test('rejects an empty or untrimmed path', () {
      expect(
        () => FileMutationPathFence.resolvePathKeySync(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => FileMutationPathFence.resolvePathKeySync(' /tmp/a.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
