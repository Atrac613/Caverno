import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';

void main() {
  group('BackgroundProcessTools', () {
    late BackgroundProcessTools tools;
    late Directory tempDir;

    setUp(() async {
      tools = BackgroundProcessTools();
      tempDir = await Directory.systemTemp.createTemp(
        'caverno_background_process_test_',
      );
    });

    tearDown(() async {
      await tools.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('starts a process and reports completion through wait', () async {
      final started =
          jsonDecode(
                await tools.start(
                  command: 'printf "ready\\n"',
                  workingDirectory: tempDir.path,
                  label: 'quick command',
                ),
              )
              as Map<String, dynamic>;

      expect(started['ok'], isTrue);
      expect(started['status'], 'running');
      final jobId = started['job_id'] as String;

      final waited =
          jsonDecode(await tools.wait(jobId: jobId, waitMs: 1000))
              as Map<String, dynamic>;

      expect(waited['ok'], isTrue);
      expect(waited['status'], 'exited');
      expect(waited['exit_code'], 0);
      expect(waited['stdout_tail'], contains('ready'));
    });

    test('reuses an existing running job for the same command', () async {
      final first =
          jsonDecode(
                await tools.start(
                  command: 'sleep 1; echo done',
                  workingDirectory: tempDir.path,
                ),
              )
              as Map<String, dynamic>;
      final second =
          jsonDecode(
                await tools.start(
                  command: 'sleep 1; echo done',
                  workingDirectory: tempDir.path,
                ),
              )
              as Map<String, dynamic>;

      expect(second['ok'], isTrue);
      expect(second['duplicate_existing'], isTrue);
      expect(second['job_id'], first['job_id']);

      await tools.cancel(jobId: first['job_id'] as String);
    });

    test('returns job_not_found for unknown job status', () async {
      final status =
          jsonDecode(await tools.status(jobId: 'missing'))
              as Map<String, dynamic>;

      expect(status['ok'], isFalse);
      expect(status['code'], 'job_not_found');
    });
  });
}
