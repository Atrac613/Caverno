import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late BackgroundProcessTools tools;
  late StreamController<({String conversationId, int elapsedMs, int? exitCode})>
  finished;
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 1,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('caverno_bg_finished_');
    finished = StreamController.broadcast();
    tools = BackgroundProcessTools(
      onJobFinished:
          ({required conversationId, required elapsedMs, exitCode}) =>
              finished.add((
                conversationId: conversationId,
                elapsedMs: elapsedMs,
                exitCode: exitCode,
              )),
    );
  });

  tearDown(() async {
    await tools.dispose();
    await finished.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> start(String command) async {
    final execution = await tools.startExecution(
      owner: owner,
      command: command,
      workingDirectory: tempDir.path,
    );
    final decoded = jsonDecode(execution.result) as Map<String, dynamic>;
    expect(decoded['ok'], isTrue, reason: execution.result);
  }

  test('reports an exited job once, with its conversation', () async {
    final report = finished.stream.first;
    await start('sleep 0.2; exit 3');

    final job = await report.timeout(const Duration(seconds: 10));
    expect(job.conversationId, 'conversation-a');
    expect(job.exitCode, 3);
    expect(job.elapsedMs, greaterThanOrEqualTo(150));
  }, skip: !LocalShellTools.isDesktopPlatform);

  test('reports a job stopped from the sidebar', () async {
    final report = finished.stream.first;
    await start('sleep 30');
    final jobId = tools.conversationJobs('conversation-a').single.jobId;

    expect(tools.stopConversationJob('conversation-a', jobId), isTrue);

    final job = await report.timeout(const Duration(seconds: 10));
    expect(job.exitCode, isNot(0));
  }, skip: !LocalShellTools.isDesktopPlatform);
}
