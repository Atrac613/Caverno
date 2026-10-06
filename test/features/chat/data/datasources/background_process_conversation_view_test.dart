import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

void main() {
  group('BackgroundProcessConversationView', () {
    late BackgroundProcessTools tools;
    late Directory tempDir;
    final ownerA1 = ChatTurnOwner(
      conversationId: 'conversation-a',
      interactionGeneration: 1,
    );
    final ownerA2 = ChatTurnOwner(
      conversationId: 'conversation-a',
      interactionGeneration: 2,
    );
    final ownerB = ChatTurnOwner(
      conversationId: 'conversation-b',
      interactionGeneration: 1,
    );

    setUp(() async {
      tools = BackgroundProcessTools();
      tempDir = await Directory.systemTemp.createTemp(
        'caverno_background_process_view_test_',
      );
    });

    tearDown(() async {
      await tools.dispose();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<String> start(ChatTurnOwner owner, String command) async {
      final execution = await tools.startExecution(
        owner: owner,
        command: command,
        workingDirectory: tempDir.path,
        label: command,
      );
      final decoded = jsonDecode(execution.result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue, reason: execution.result);
      return decoded['job_id'] as String;
    }

    test('lists only the conversation\'s jobs, owned and carried', () async {
      final owned = await start(ownerA1, 'sleep 5');
      await start(ownerB, 'sleep 5');

      await tools.clearOwner(owner: ownerA1);
      final fresh = await start(ownerA2, 'sleep 6');

      final jobs = tools.conversationJobs('conversation-a');
      expect(jobs.map((job) => job.jobId), unorderedEquals([owned, fresh]));
      expect(jobs.every((job) => job.isRunning), isTrue);
      expect(jobs.first.jobId, fresh, reason: 'newest first');
    }, skip: !LocalShellTools.isDesktopPlatform);

    test('reading does not adopt a carried job', () async {
      final carried = await start(ownerA1, 'sleep 5');
      await tools.clearOwner(owner: ownerA1);

      tools.conversationJobs('conversation-a');

      expect(tools.carriedJobIds(owner: ownerA2), [carried]);
    }, skip: !LocalShellTools.isDesktopPlatform);

    test('stop ends a running job and reports its output', () async {
      final jobId = await start(ownerA1, 'printf "hello\\n"; sleep 30');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(tools.stopConversationJob('conversation-b', jobId), isFalse);
      expect(tools.stopConversationJob('conversation-a', jobId), isTrue);
      await tools.waitExecution(owner: ownerA1, jobId: jobId, waitMs: 5000);

      final job = tools.conversationJobs('conversation-a').single;
      expect(job.isRunning, isFalse);
      expect(job.stdoutTail, contains('hello'));
      expect(tools.stopConversationJob('conversation-a', jobId), isFalse);
    }, skip: !LocalShellTools.isDesktopPlatform);
  });
}
