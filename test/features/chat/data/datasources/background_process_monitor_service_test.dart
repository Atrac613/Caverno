import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';

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

    test(
      'registers a started process and refreshes it to completion',
      () async {
        final started = await tools.start(
          command: 'printf "done\\n"',
          workingDirectory: tempDir.path,
          label: 'quick command',
        );

        final registered = monitor.registerProcessStartResult(
          result: started,
          arguments: {
            'command': 'printf "done\\n"',
            'working_directory': tempDir.path,
            'label': 'quick command',
          },
        );

        expect(registered, isNotNull);
        expect(registered!.isRunning, isTrue);
        expect(monitor.activeSnapshots.single.jobId, registered.jobId);

        await Future<void>.delayed(const Duration(milliseconds: 150));
        final refreshed = await monitor.refreshJob(registered.jobId);

        expect(refreshed, isNotNull);
        expect(refreshed!.status, 'exited');
        expect(refreshed.exitCode, 0);
        expect(refreshed.stdoutTail, contains('done'));
        expect(monitor.activeSnapshots, isEmpty);
      },
    );

    test('lists running jobs and supports finished filtering', () {
      final runningSnapshot = monitor.registerProcessStartResult(
        result: jsonEncode({
          'ok': true,
          'status': 'running',
          'job_id': 'proc_running',
          'command': 'sleep 1',
          'working_directory': tempDir.path,
        }),
        arguments: {'command': 'sleep 0.1', 'working_directory': tempDir.path},
      );
      final completedSnapshot = monitor.registerProcessStartResult(
        result: jsonEncode({
          'ok': true,
          'status': 'exited',
          'exit_code': 0,
          'job_id': 'proc_done',
          'command': 'printf "ok"',
          'working_directory': tempDir.path,
        }),
        arguments: {
          'command': 'printf "ok\\n"',
          'working_directory': tempDir.path,
        },
      );
      expect(runningSnapshot, isNotNull);
      expect(completedSnapshot, isNotNull);

      final onlyRunning = monitor.listJobs(includeFinished: false);
      expect(onlyRunning.every((snapshot) => snapshot.isRunning), isTrue);
      expect(
        onlyRunning.map((snapshot) => snapshot.jobId).toList(),
        contains('proc_running'),
      );

      final allJobs = monitor.listJobs();
      expect(allJobs.length, 2);
      expect(
        allJobs.map((snapshot) => snapshot.jobId),
        contains('proc_running'),
      );
      expect(allJobs.map((snapshot) => snapshot.jobId), contains('proc_done'));
    });

    test(
      'marks missing jobs as unknown when status cannot be refreshed',
      () async {
        final registered = monitor.registerProcessStartResult(
          result: jsonEncode({
            'ok': true,
            'status': 'running',
            'job_id': 'missing-job',
            'command': 'sleep 10',
            'working_directory': tempDir.path,
          }),
          arguments: const {},
        );

        expect(registered, isNotNull);
        final refreshed = await monitor.refreshJob('missing-job');

        expect(refreshed, isNotNull);
        expect(refreshed!.status, 'unknown');
        expect(refreshed.ok, isFalse);
        expect(monitor.activeSnapshots, isEmpty);
      },
    );
  });
}
