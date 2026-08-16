import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';

void main() {
  group('BackgroundProcessMonitorService', () {
    late BackgroundProcessTools tools;
    late BackgroundProcessMonitorService monitor;
    late Directory tempDir;

    setUp(() async {
      tools = BackgroundProcessTools();
      monitor = BackgroundProcessMonitorService(
        tools: tools,
        pollInterval: const Duration(minutes: 1),
      );
      tempDir = await Directory.systemTemp.createTemp(
        'caverno_background_process_monitor_test_',
      );
    });

    tearDown(() async {
      monitor.dispose();
      await tools.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('registers an owned process and refreshes it to completion', () async {
      final owner = _owner('conversation-a', 1);
      final started = await tools.start(
        owner: owner,
        command: 'printf "done\\n"',
        workingDirectory: tempDir.path,
        label: 'quick command',
      );

      final registered = monitor.registerProcessStartResult(
        owner: owner,
        result: started,
        arguments: {
          'command': 'printf "done\\n"',
          'working_directory': tempDir.path,
          'label': 'quick command',
        },
      );

      expect(registered, isNotNull);
      expect(registered!.isRunning, isTrue);
      expect(monitor.activeSnapshots(owner).single.jobId, registered.jobId);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      final refreshed = await monitor.refreshJob(owner, registered.jobId);

      expect(refreshed, isNotNull);
      expect(refreshed!.status, 'exited');
      expect(refreshed.exitCode, 0);
      expect(refreshed.stdoutTail, contains('done'));
      expect(monitor.activeSnapshots(owner), isEmpty);
    });

    test('lists, filters, and resolves snapshots only for the exact owner', () {
      final owner = _owner('conversation-a', 2);
      final peer = _owner('conversation-b', 2);
      final running = monitor.registerProcessStartResult(
        owner: owner,
        result: _payload(
          jobId: 'proc_running',
          status: 'running',
          command: 'sleep 1',
          startedAt: '2026-07-29T00:00:00.000Z',
        ),
        arguments: {'working_directory': tempDir.path},
      );
      final finished = monitor.registerProcessStartResult(
        owner: owner,
        result: _payload(
          jobId: 'proc_done',
          status: 'exited',
          command: 'printf done',
          startedAt: '2026-07-29T01:00:00.000Z',
          exitCode: 0,
        ),
        arguments: {'working_directory': tempDir.path},
      );

      expect(running, isNotNull);
      expect(finished, isNotNull);
      expect(
        monitor.listJobs(owner, includeFinished: false).map((job) => job.jobId),
        ['proc_running'],
      );
      expect(
        monitor
            .listJobs(owner, jobIds: const [' proc_running ', '', 'missing'])
            .map((job) => job.jobId),
        ['proc_running'],
      );
      expect(monitor.listJobs(owner, limit: 1).map((job) => job.jobId), [
        'proc_done',
      ]);
      expect(monitor.listJobs(owner, limit: 0), hasLength(2));
      expect(monitor.snapshots(owner), hasLength(2));
      expect(monitor.byJobId(owner, 'proc_done'), same(finished));

      expect(monitor.snapshots(peer), isEmpty);
      expect(monitor.listJobs(peer), isEmpty);
      expect(monitor.activeSnapshots(peer), isEmpty);
      expect(monitor.byJobId(peer, 'proc_running'), isNull);
      expect(finished!.toJson(), isNot(contains('owner')));
      expect(finished.toJson(), isNot(contains('conversation_id')));
    });

    test(
      'isolates identical job IDs and event streams across owners',
      () async {
        final owner = _owner('conversation-a', 7);
        final peer = _owner('conversation-b', 7);
        final ownerEvents = <BackgroundProcessMonitorSnapshot>[];
        final peerEvents = <BackgroundProcessMonitorSnapshot>[];
        final ownerSubscription = monitor
            .eventsFor(owner)
            .listen(ownerEvents.add);
        final peerSubscription = monitor.eventsFor(peer).listen(peerEvents.add);
        addTearDown(ownerSubscription.cancel);
        addTearDown(peerSubscription.cancel);

        final ownerSnapshot = monitor.registerProcessStartResult(
          owner: owner,
          result: _payload(
            jobId: 'shared-id',
            status: 'running',
            command: 'owner command',
          ),
          arguments: {'working_directory': tempDir.path},
        );
        final peerSnapshot = monitor.registerProcessStartResult(
          owner: peer,
          result: _payload(
            jobId: 'shared-id',
            status: 'exited',
            command: 'peer command',
            exitCode: 0,
          ),
          arguments: {'working_directory': tempDir.path},
        );
        await Future<void>.delayed(Duration.zero);

        expect(ownerSnapshot!.command, 'owner command');
        expect(peerSnapshot!.command, 'peer command');
        expect(monitor.byJobId(owner, 'shared-id')!.command, 'owner command');
        expect(monitor.byJobId(peer, 'shared-id')!.command, 'peer command');
        expect(monitor.listJobs(owner).single.command, 'owner command');
        expect(monitor.listJobs(peer).single.command, 'peer command');
        expect(ownerEvents.map((event) => event.command), ['owner command']);
        expect(peerEvents.map((event) => event.command), ['peer command']);

        monitor.clearOwner(owner);
        final lateRegistration = monitor.registerProcessStartResult(
          owner: owner,
          result: _payload(
            jobId: 'late',
            status: 'running',
            command: 'late owner command',
          ),
          arguments: {'working_directory': tempDir.path},
        );
        await Future<void>.delayed(Duration.zero);

        expect(lateRegistration, isNull);
        expect(monitor.listJobs(owner), isEmpty);
        expect(monitor.listJobs(peer).single.command, 'peer command');
        expect(ownerEvents, hasLength(1));
        expect(peerEvents, hasLength(1));
      },
    );

    test(
      'classifies failed refreshes within only the requested owner',
      () async {
        final owner = _owner('conversation-a', 3);
        final peer = _owner('conversation-b', 3);
        final results = <String, String>{
          'missing': jsonEncode({
            'ok': false,
            'code': 'job_not_found',
            'job_id': 'missing',
            'error': 'Process disappeared.',
          }),
          'invalid': 'not-json',
          'unowned': 'not-json',
        };
        final localMonitor = BackgroundProcessMonitorService(
          tools: tools,
          pollInterval: const Duration(minutes: 1),
          statusReader:
              ({required owner, required jobId, int? tailChars}) async =>
                  results[jobId]!,
        );
        addTearDown(localMonitor.dispose);
        for (final jobId in const ['missing', 'invalid']) {
          localMonitor.registerProcessStartResult(
            owner: owner,
            result: _payload(
              jobId: jobId,
              status: 'running',
              command: 'sleep 10',
            ),
            arguments: {'working_directory': tempDir.path},
          );
        }

        final missing = await localMonitor.refreshJob(owner, 'missing');
        final invalid = await localMonitor.refreshJob(owner, 'invalid');
        final unowned = await localMonitor.refreshJob(owner, 'unowned');

        expect(missing!.status, 'unknown');
        expect(missing.ok, isFalse);
        expect(missing.error, 'Process disappeared.');
        expect(invalid!.status, 'unknown');
        expect(invalid.ok, isFalse);
        expect(invalid.error, 'Process status returned invalid JSON.');
        expect(unowned!.status, 'unknown');
        expect(unowned.ok, isFalse);
        expect(unowned.error, 'Process status returned invalid JSON.');
        expect(localMonitor.byJobId(owner, 'unowned'), same(unowned));
        expect(localMonitor.snapshots(peer), isEmpty);
        expect(localMonitor.activeSnapshots(owner), isEmpty);
      },
    );

    test(
      'refreshes distinct owned jobs once and preserves payload fields',
      () async {
        final owner = _owner('conversation-a', 4);
        final calls = <String>[];
        final localMonitor = BackgroundProcessMonitorService(
          tools: tools,
          pollInterval: const Duration(minutes: 1),
          statusReader:
              ({required owner, required jobId, int? tailChars}) async {
                calls.add(jobId);
                return jsonEncode({
                  'ok': true,
                  'job_id': jobId,
                  'status': 'exited',
                  'pid': '42',
                  'exit_code': '2',
                  'elapsed_ms': '900',
                  'finished_at': '2026-07-29T02:00:00.000Z',
                  'stdout_tail': 'stdout',
                  'stderr_tail': 'stderr',
                  'stdout_truncated': true,
                  'stderr_truncated': true,
                });
              },
        );
        addTearDown(localMonitor.dispose);
        for (final jobId in const ['job-a', 'job-b']) {
          localMonitor.registerProcessStartResult(
            owner: owner,
            result: _payload(
              jobId: jobId,
              status: 'running',
              command: 'command-$jobId',
              startedAt: '2026-07-29T01:00:00.000Z',
            ),
            arguments: {'working_directory': tempDir.path, 'label': 'build'},
          );
        }

        final refreshed = await localMonitor.refreshJobs(owner, const [
          'job-a',
          'job-a',
          'job-b',
        ]);

        expect(calls, ['job-a', 'job-b']);
        expect(refreshed, hasLength(2));
        expect(refreshed.first.pid, 42);
        expect(refreshed.first.exitCode, 2);
        expect(refreshed.first.elapsedMs, 900);
        expect(
          refreshed.first.startedAt.toIso8601String(),
          startsWith('2026-07-29T01:00:00'),
        );
        expect(refreshed.first.finishedAt, isNotNull);
        expect(refreshed.first.stdoutTail, 'stdout');
        expect(refreshed.first.stderrTail, 'stderr');
        expect(refreshed.first.stdoutTruncated, isTrue);
        expect(refreshed.first.stderrTruncated, isTrue);
        expect(refreshed.first.hasFailedExit, isTrue);
        expect(refreshed.first.isTerminal, isTrue);
        expect(await localMonitor.refreshActiveJobs(owner), isEmpty);
        expect(calls, ['job-a', 'job-b']);
      },
    );

    test(
      'rejects refresh and registration that complete after owner retirement',
      () async {
        final owner = _owner('conversation-a', 5);
        final peer = _owner('conversation-b', 5);
        final statusStarted = Completer<void>();
        final statusResult = Completer<String>();
        var statusCalls = 0;
        final localMonitor = BackgroundProcessMonitorService(
          tools: tools,
          pollInterval: const Duration(minutes: 1),
          statusReader: ({required owner, required jobId, int? tailChars}) {
            statusCalls += 1;
            if (!statusStarted.isCompleted) {
              statusStarted.complete();
            }
            return statusResult.future;
          },
        );
        addTearDown(localMonitor.dispose);
        localMonitor.registerProcessStartResult(
          owner: owner,
          result: _payload(
            jobId: 'job-a',
            status: 'running',
            command: 'owner command',
          ),
          arguments: {'working_directory': tempDir.path},
        );
        localMonitor.registerProcessStartResult(
          owner: peer,
          result: _payload(
            jobId: 'job-b',
            status: 'exited',
            command: 'peer command',
            exitCode: 0,
          ),
          arguments: {'working_directory': tempDir.path},
        );
        final ownerEvents = <BackgroundProcessMonitorSnapshot>[];
        final subscription = localMonitor
            .eventsFor(owner)
            .listen(ownerEvents.add);
        addTearDown(subscription.cancel);

        final refresh = localMonitor.refreshJob(owner, 'job-a');
        await statusStarted.future;
        localMonitor.clearOwner(owner);
        statusResult.complete(
          _payload(
            jobId: 'job-a',
            status: 'exited',
            command: 'resurrected command',
            exitCode: 0,
          ),
        );

        expect(await refresh, isNull);
        expect(localMonitor.snapshots(owner), isEmpty);
        expect(localMonitor.listJobs(peer).single.command, 'peer command');
        expect(
          localMonitor.registerProcessStartResult(
            owner: owner,
            result: _payload(
              jobId: 'late',
              status: 'running',
              command: 'late command',
            ),
            arguments: {'working_directory': tempDir.path},
          ),
          isNull,
        );
        expect(await localMonitor.refreshJob(owner, 'job-a'), isNull);
        expect(statusCalls, 1);
        await Future<void>.delayed(Duration.zero);
        expect(ownerEvents, isEmpty);
      },
    );

    test(
      'retiring one owner fences its queued poll while peer polling continues',
      () async {
        final retiredOwner = _owner('conversation-a', 6);
        final peer = _owner('conversation-b', 6);
        final ownerPollStarted = Completer<void>();
        final peerPollStarted = Completer<void>();
        final ownerPollResult = Completer<String>();
        var ownerCalls = 0;
        var peerCalls = 0;
        final localMonitor = BackgroundProcessMonitorService(
          tools: tools,
          pollInterval: const Duration(milliseconds: 5),
          statusReader: ({required owner, required jobId, int? tailChars}) {
            if (owner == retiredOwner) {
              ownerCalls += 1;
              if (!ownerPollStarted.isCompleted) {
                ownerPollStarted.complete();
              }
              return ownerPollResult.future;
            }
            peerCalls += 1;
            if (!peerPollStarted.isCompleted) {
              peerPollStarted.complete();
            }
            return Future<String>.value(
              _payload(
                jobId: jobId,
                status: 'running',
                command: 'peer command',
              ),
            );
          },
        );
        addTearDown(localMonitor.dispose);
        for (final entry in [(retiredOwner, 'job-a'), (peer, 'job-b')]) {
          localMonitor.registerProcessStartResult(
            owner: entry.$1,
            result: _payload(
              jobId: entry.$2,
              status: 'running',
              command: 'running command',
            ),
            arguments: {'working_directory': tempDir.path},
          );
        }
        final ownerEvents = <BackgroundProcessMonitorSnapshot>[];
        final peerEvents = <BackgroundProcessMonitorSnapshot>[];
        final ownerSubscription = localMonitor
            .eventsFor(retiredOwner)
            .listen(ownerEvents.add);
        final peerSubscription = localMonitor
            .eventsFor(peer)
            .listen(peerEvents.add);
        addTearDown(ownerSubscription.cancel);
        addTearDown(peerSubscription.cancel);

        await Future.wait([
          ownerPollStarted.future,
          peerPollStarted.future,
        ]).timeout(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(ownerCalls, 1);
        final peerCallsBeforeClear = peerCalls;

        localMonitor.clearOwner(retiredOwner);
        ownerPollResult.complete(
          _payload(
            jobId: 'job-a',
            status: 'exited',
            command: 'late owner command',
            exitCode: 0,
          ),
        );
        await _waitUntil(
          () => peerCalls > peerCallsBeforeClear,
          timeout: const Duration(seconds: 1),
        );
        await Future<void>.delayed(Duration.zero);

        expect(localMonitor.snapshots(retiredOwner), isEmpty);
        expect(localMonitor.snapshots(peer), isNotEmpty);
        expect(ownerEvents, isEmpty);
        expect(peerEvents, isNotEmpty);
        localMonitor.clearOwner(peer);
      },
    );

    test('clearOwner and dispose are isolated and idempotent', () async {
      final owner = _owner('conversation-a', 8);
      final peer = _owner('conversation-b', 8);
      for (final entry in [(owner, 'job-a'), (peer, 'job-b')]) {
        monitor.registerProcessStartResult(
          owner: entry.$1,
          result: _payload(
            jobId: entry.$2,
            status: 'running',
            command: 'command-${entry.$2}',
          ),
          arguments: {'working_directory': tempDir.path},
        );
      }
      final eventsDone = Completer<void>();
      final subscription = monitor
          .eventsFor(peer)
          .listen((_) {}, onDone: eventsDone.complete);
      addTearDown(subscription.cancel);

      monitor
        ..clearOwner(owner)
        ..clearOwner(owner);
      expect(monitor.snapshots(owner), isEmpty);
      expect(monitor.snapshots(peer).single.jobId, 'job-b');

      monitor
        ..dispose()
        ..dispose();
      await eventsDone.future.timeout(const Duration(seconds: 1));
      expect(monitor.snapshots(peer), isEmpty);
      expect(monitor.listJobs(peer), isEmpty);
      expect(
        monitor.registerProcessStartResult(
          owner: peer,
          result: _payload(
            jobId: 'late',
            status: 'running',
            command: 'late command',
          ),
          arguments: {'working_directory': tempDir.path},
        ),
        isNull,
      );
      expect(await monitor.refreshJobs(peer, const ['job-b']), isEmpty);
    });

    test('snapshot copy and JSON preserve the external payload shape', () {
      final snapshot = BackgroundProcessMonitorSnapshot(
        jobId: 'job',
        status: 'running',
        command: 'command',
        workingDirectory: '/tmp',
        label: 'label',
        pid: 10,
        elapsedMs: 20,
        startedAt: DateTime.parse('2026-07-29T00:00:00.000Z'),
        lastCheckedAt: DateTime.parse('2026-07-29T00:00:01.000Z'),
        stdoutTail: 'out',
        stderrTail: 'err',
      );
      final exited = snapshot.copyWith(
        jobId: 'job-2',
        status: 'exited',
        command: 'new command',
        workingDirectory: '/workspace',
        label: 'new label',
        pid: 11,
        exitCode: 0,
        elapsedMs: 30,
        startedAt: DateTime.parse('2026-07-29T00:00:02.000Z'),
        finishedAt: DateTime.parse('2026-07-29T00:00:03.000Z'),
        lastCheckedAt: DateTime.parse('2026-07-29T00:00:04.000Z'),
        stdoutTail: 'new out',
        stderrTail: 'new err',
        stdoutTruncated: true,
        stderrTruncated: true,
        ok: false,
        error: 'error',
      );

      expect(snapshot.isRunning, isTrue);
      expect(snapshot.isTerminal, isFalse);
      expect(snapshot.hasFailedExit, isFalse);
      expect(exited.isRunning, isFalse);
      expect(exited.isTerminal, isTrue);
      expect(exited.toJson(), {
        'job_id': 'job-2',
        'status': 'exited',
        'command': 'new command',
        'working_directory': '/workspace',
        'label': 'new label',
        'pid': 11,
        'exit_code': 0,
        'elapsed_ms': 30,
        'started_at': '2026-07-29T00:00:02.000Z',
        'finished_at': '2026-07-29T00:00:03.000Z',
        'last_checked_at': '2026-07-29T00:00:04.000Z',
        'stdout_tail': 'new out',
        'stderr_tail': 'new err',
        'stdout_truncated': true,
        'stderr_truncated': true,
        'ok': false,
        'error': 'error',
      });
    });

    test('rejects malformed process start results', () {
      final owner = _owner('conversation-a', 9);

      expect(
        monitor.registerProcessStartResult(
          owner: owner,
          result: 'not-json',
          arguments: const {},
        ),
        isNull,
      );
      expect(
        monitor.registerProcessStartResult(
          owner: owner,
          result: '{"ok":false,"job_id":"failed"}',
          arguments: const {},
        ),
        isNull,
      );
      expect(
        monitor.registerProcessStartResult(
          owner: owner,
          result: '{"ok":true}',
          arguments: const {},
        ),
        isNull,
      );
      expect(monitor.snapshots(owner), isEmpty);
    });

    test('a running job stays listable in the next turn', () async {
      final owner = _owner('conversation-a', 1);
      final successor = _owner('conversation-a', 2);
      monitor.registerProcessStartResult(
        owner: owner,
        result: _payload(
          jobId: 'job-a',
          status: 'running',
          command: 'long release',
        ),
        arguments: {'working_directory': tempDir.path},
      );

      monitor.clearOwner(owner);

      expect(monitor.listJobs(owner), isEmpty);
      expect(monitor.listJobs(successor).single.jobId, 'job-a');
      expect(monitor.activeSnapshots(successor).single.command, 'long release');
      expect(monitor.byJobId(successor, 'job-a'), isNotNull);
    });

    test('a finished job is not carried into the next turn', () async {
      final owner = _owner('conversation-a', 1);
      final successor = _owner('conversation-a', 2);
      monitor.registerProcessStartResult(
        owner: owner,
        result: _payload(
          jobId: 'job-a',
          status: 'exited',
          command: 'quick command',
          exitCode: 0,
        ),
        arguments: {'working_directory': tempDir.path},
      );

      monitor.clearOwner(owner);

      expect(monitor.listJobs(successor), isEmpty);
    });

    test('another conversation never inherits a carried job', () async {
      final owner = _owner('conversation-a', 1);
      final stranger = _owner('conversation-b', 1);
      monitor.registerProcessStartResult(
        owner: owner,
        result: _payload(
          jobId: 'job-a',
          status: 'running',
          command: 'long release',
        ),
        arguments: {'working_directory': tempDir.path},
      );

      monitor.clearOwner(owner);

      expect(monitor.listJobs(stranger), isEmpty);
    });

    test('clearConversation drops what clearOwner carried', () async {
      final owner = _owner('conversation-a', 1);
      final successor = _owner('conversation-a', 2);
      monitor.registerProcessStartResult(
        owner: owner,
        result: _payload(
          jobId: 'job-a',
          status: 'running',
          command: 'long release',
        ),
        arguments: {'working_directory': tempDir.path},
      );

      monitor.clearOwner(owner);
      monitor.clearConversation('conversation-a');

      expect(monitor.listJobs(successor), isEmpty);
    });
  });
}

ChatTurnOwner _owner(String conversationId, int generation) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

String _payload({
  required String jobId,
  required String status,
  required String command,
  String startedAt = '2026-07-29T00:00:00.000Z',
  int? exitCode,
}) {
  return jsonEncode({
    'ok': true,
    'job_id': jobId,
    'status': status,
    'command': command,
    'working_directory': '/tmp',
    'started_at': startedAt,
    'exit_code': ?exitCode,
  });
}

Future<void> _waitUntil(
  bool Function() predicate, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before the timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
