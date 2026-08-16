import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

void main() {
  group('BackgroundProcessTools', () {
    late BackgroundProcessTools tools;
    late Directory tempDir;
    late ChatTurnOwner owner;

    setUp(() async {
      tools = BackgroundProcessTools();
      owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 1,
      );
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
      final startExecution = await tools.startExecution(
        owner: owner,
        command: 'printf "ready\\n"',
        workingDirectory: tempDir.path,
        label: 'quick command',
      );
      final started = jsonDecode(startExecution.result) as Map<String, dynamic>;

      expect(started['ok'], isTrue);
      expect(started['status'], 'running');
      expect(startExecution.outcome?.processState, ToolProcessState.running);
      final jobId = started['job_id'] as String;

      final waitExecution = await tools.waitExecution(
        owner: owner,
        jobId: jobId,
        waitMs: 1000,
      );
      final waited = jsonDecode(waitExecution.result) as Map<String, dynamic>;

      expect(waited['ok'], isTrue);
      expect(waited['status'], 'exited');
      expect(waited['exit_code'], 0);
      expect(waited['stdout_tail'], contains('ready'));
      expect(waitExecution.outcome?.processState, ToolProcessState.exited);
      expect(waitExecution.outcome?.exitCode, 0);
    });

    test('reuses an existing running job for the same command', () async {
      final first =
          jsonDecode(
                await tools.start(
                  owner: owner,
                  command: 'sleep 1; echo done',
                  workingDirectory: tempDir.path,
                ),
              )
              as Map<String, dynamic>;
      final second =
          jsonDecode(
                await tools.start(
                  owner: owner,
                  command: 'sleep 1; echo done',
                  workingDirectory: tempDir.path,
                ),
              )
              as Map<String, dynamic>;

      expect(second['ok'], isTrue);
      expect(second['duplicate_existing'], isTrue);
      expect(second['job_id'], first['job_id']);

      await tools.cancel(owner: owner, jobId: first['job_id'] as String);
    });

    test(
      'does not deduplicate matching commands across conversations',
      () async {
        final peerOwner = ChatTurnOwner(
          conversationId: 'conversation-b',
          interactionGeneration: owner.interactionGeneration,
        );
        final first = await _startLongRunningJob(tools, owner, tempDir);
        final peer = await _startLongRunningJob(tools, peerOwner, tempDir);

        expect(peer['duplicate_existing'], isNot(isTrue));
        expect(peer['job_id'], isNot(first['job_id']));

        await tools.cancel(owner: owner, jobId: first['job_id'] as String);
        await tools.cancel(owner: peerOwner, jobId: peer['job_id'] as String);
      },
    );

    test('does not deduplicate matching commands across generations', () async {
      final nextGenerationOwner = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );
      final first = await _startLongRunningJob(tools, owner, tempDir);
      final nextGeneration = await _startLongRunningJob(
        tools,
        nextGenerationOwner,
        tempDir,
      );

      expect(nextGeneration['duplicate_existing'], isNot(isTrue));
      expect(nextGeneration['job_id'], isNot(first['job_id']));

      await tools.cancel(owner: owner, jobId: first['job_id'] as String);
      await tools.cancel(
        owner: nextGenerationOwner,
        jobId: nextGeneration['job_id'] as String,
      );
    });

    test(
      'wrong-owner cancel is indistinguishable from an unknown job',
      () async {
        final peerOwner = ChatTurnOwner(
          conversationId: 'conversation-b',
          interactionGeneration: 1,
        );
        final started = await _startLongRunningJob(tools, owner, tempDir);
        final jobId = started['job_id'] as String;

        final foreignCancel =
            jsonDecode(await tools.cancel(owner: peerOwner, jobId: jobId))
                as Map<String, dynamic>;
        final unknownStatus =
            jsonDecode(await tools.status(owner: peerOwner, jobId: jobId))
                as Map<String, dynamic>;

        expect(foreignCancel, unknownStatus);
        expect(foreignCancel['code'], 'job_not_found');
        final ownerStatus =
            jsonDecode(await tools.status(owner: owner, jobId: jobId))
                as Map<String, dynamic>;
        expect(ownerStatus['ok'], isTrue);

        await tools.cancel(owner: owner, jobId: jobId);
      },
    );

    test('clearOwner retires only the exact owner', () async {
      final peerOwner = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );
      final first = await _startLongRunningJob(tools, owner, tempDir);
      final peer = await _startLongRunningJob(tools, peerOwner, tempDir);
      final firstJobId = first['job_id'] as String;
      final peerJobId = peer['job_id'] as String;

      await tools.clearOwner(owner: owner);

      final clearedStatus =
          jsonDecode(await tools.status(owner: owner, jobId: firstJobId))
              as Map<String, dynamic>;
      final peerStatus =
          jsonDecode(await tools.status(owner: peerOwner, jobId: peerJobId))
              as Map<String, dynamic>;
      expect(clearedStatus['code'], 'job_not_found');
      expect(peerStatus['ok'], isTrue);

      await tools.cancel(owner: peerOwner, jobId: peerJobId);
    });

    test('clearOwner rejects a new start for the retired owner', () async {
      await tools.clearOwner(owner: owner);

      final result =
          jsonDecode(
                await tools.start(
                  owner: owner,
                  command: 'echo should-not-run',
                  workingDirectory: tempDir.path,
                ),
              )
              as Map<String, dynamic>;

      expect(result['ok'], isFalse);
      expect(result['code'], 'background_process_owner_retired');
    });

    test('clearOwner fences a late process start', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final startedProcess = Completer<Process>();
      tools = BackgroundProcessTools(
        processStarter: (executable, arguments, workingDirectory) async {
          entered.complete();
          await release.future;
          final process = await Process.start(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          );
          startedProcess.complete(process);
          return process;
        },
      );

      final startFuture = tools.start(
        owner: owner,
        command: 'sleep 10',
        workingDirectory: tempDir.path,
      );
      await entered.future;
      final clearFuture = tools.clearOwner(owner: owner);
      release.complete();

      final result = jsonDecode(await startFuture) as Map<String, dynamic>;
      await clearFuture;
      final process = await startedProcess.future;
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
      );

      expect(result['ok'], isFalse);
      expect(result['code'], 'process_start_cancelled');
      expect(exitCode, isNot(0));
    });

    test('dispose fences all late process starts', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final startedProcess = Completer<Process>();
      tools = BackgroundProcessTools(
        processStarter: (executable, arguments, workingDirectory) async {
          entered.complete();
          await release.future;
          final process = await Process.start(
            executable,
            arguments,
            workingDirectory: workingDirectory,
          );
          startedProcess.complete(process);
          return process;
        },
      );

      final startFuture = tools.start(
        owner: owner,
        command: 'sleep 10',
        workingDirectory: tempDir.path,
      );
      await entered.future;
      final disposeFuture = tools.dispose();
      release.complete();

      final result = jsonDecode(await startFuture) as Map<String, dynamic>;
      await disposeFuture;
      final process = await startedProcess.future;
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
      );

      expect(result['ok'], isFalse);
      expect(result['code'], 'process_start_cancelled');
      expect(exitCode, isNot(0));
      final afterDispose =
          jsonDecode(
                await tools.start(
                  owner: owner,
                  command: 'printf "should not run"',
                  workingDirectory: tempDir.path,
                ),
              )
              as Map<String, dynamic>;
      expect(afterDispose['code'], 'background_process_tools_disposed');
    });

    test('wait does not return a retired job after clearOwner', () async {
      final started = await _startLongRunningJob(tools, owner, tempDir);
      final jobId = started['job_id'] as String;

      final waitFuture = tools.wait(owner: owner, jobId: jobId, waitMs: 30000);
      final clearFuture = tools.clearOwner(owner: owner);
      final waited =
          jsonDecode(await waitFuture.timeout(const Duration(seconds: 2)))
              as Map<String, dynamic>;
      await clearFuture;

      expect(waited['ok'], isFalse);
      expect(waited['code'], 'job_not_found');
      final status =
          jsonDecode(await tools.status(owner: owner, jobId: jobId))
              as Map<String, dynamic>;
      expect(status, waited);
    });

    test(
      'validates support, working directory, and startup failures',
      () async {
        expect(tools.isSupported, LocalShellTools.isDesktopPlatform);
        final missingDirectory =
            jsonDecode(
                  await tools.start(
                    owner: owner,
                    command: 'printf "unused"',
                    workingDirectory: '${tempDir.path}/missing',
                  ),
                )
                as Map<String, dynamic>;
        expect(missingDirectory['code'], 'working_directory_not_found');

        tools = BackgroundProcessTools(
          processStarter: (_, _, _) async => throw StateError('start failed'),
        );
        final failed =
            jsonDecode(
                  await tools.start(
                    owner: owner,
                    command: 'printf "unused"',
                    workingDirectory: tempDir.path,
                  ),
                )
                as Map<String, dynamic>;
        expect(failed['code'], 'process_start_failed');
        expect(failed['error'], contains('start failed'));
        await tools.clearOwner(owner: owner);
      },
    );

    test('clearOwner fences a late startup failure', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      tools = BackgroundProcessTools(
        processStarter: (_, _, _) async {
          entered.complete();
          await release.future;
          throw StateError('late failure');
        },
      );

      final startFuture = tools.start(
        owner: owner,
        command: 'printf "unused"',
        workingDirectory: tempDir.path,
      );
      await entered.future;
      final clearFuture = tools.clearOwner(owner: owner);
      release.complete();

      final result = jsonDecode(await startFuture) as Map<String, dynamic>;
      await clearFuture;
      expect(result['code'], 'process_start_cancelled');
    });

    test(
      'tail clips retained output and wait preserves timeout state',
      () async {
        final longOutput = List<String>.filled(25050, 'x').join();
        final completed =
            jsonDecode(
                  await tools.start(
                    owner: owner,
                    command: "printf '$longOutput'",
                    workingDirectory: tempDir.path,
                  ),
                )
                as Map<String, dynamic>;
        final completedJobId = completed['job_id'] as String;
        await tools.wait(owner: owner, jobId: completedJobId, waitMs: 2000);
        final tail =
            jsonDecode(
                  await tools.tail(
                    owner: owner,
                    jobId: completedJobId,
                    maxChars: 10,
                  ),
                )
                as Map<String, dynamic>;
        expect(tail['stdout_tail'], 'xxxxxxxxxx');
        expect(tail['stdout_truncated'], isTrue);

        final running = await _startLongRunningJob(tools, owner, tempDir);
        final runningJobId = running['job_id'] as String;
        final elapsed = Stopwatch()..start();
        final timedOut =
            jsonDecode(
                  await tools.wait(
                    owner: owner,
                    jobId: runningJobId,
                    waitMs: 0,
                  ),
                )
                as Map<String, dynamic>;
        elapsed.stop();
        expect(timedOut['status'], 'running');
        // Clamped up, not honoured: the floor is what the model actually picks,
        // so it decides how many 16k-token polls a long build costs. Session
        // 783fd214 spent 55% of a million-token session at the previous 5s one.
        expect(elapsed.elapsedMilliseconds, greaterThanOrEqualTo(14500));
        await tools.cancel(owner: owner, jobId: runningJobId);
      },
    );

    test('wait and clearOwner reject empty owner state', () async {
      final waited =
          jsonDecode(
                await tools.wait(owner: owner, jobId: 'missing', waitMs: 0),
              )
              as Map<String, dynamic>;
      expect(waited['code'], 'job_not_found');
      await tools.clearOwner(owner: owner);
    });

    test('returns job_not_found for unknown job status', () async {
      final status =
          jsonDecode(await tools.status(owner: owner, jobId: 'missing'))
              as Map<String, dynamic>;

      expect(status['ok'], isFalse);
      expect(status['code'], 'job_not_found');
    });

    test('a later turn adopts a job the previous turn left running', () async {
      final started = await _startLongRunningJob(tools, owner, tempDir);
      final jobId = started['job_id'] as String;
      final successor = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );

      await tools.clearOwner(owner: owner);
      expect(tools.carriedJobIds(owner: successor), [jobId]);

      final adopted =
          jsonDecode(await tools.status(owner: successor, jobId: jobId))
              as Map<String, dynamic>;

      expect(adopted['ok'], isTrue);
      expect(adopted['status'], 'running');
      expect(adopted['pid'], started['pid']);
      expect(tools.carriedJobIds(owner: successor), isEmpty);

      await tools.cancel(owner: successor, jobId: jobId);
    });

    test('another conversation cannot adopt a carried job', () async {
      final started = await _startLongRunningJob(tools, owner, tempDir);
      final jobId = started['job_id'] as String;
      final stranger = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 1,
      );

      await tools.clearOwner(owner: owner);

      expect(tools.carriedJobIds(owner: stranger), isEmpty);
      final status =
          jsonDecode(await tools.status(owner: stranger, jobId: jobId))
              as Map<String, dynamic>;
      expect(status['code'], 'job_not_found');
    });

    test('restarting a carried command adopts it instead of forking', () async {
      final started = await _startLongRunningJob(tools, owner, tempDir);
      final successor = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );

      await tools.clearOwner(owner: owner);
      final restarted = await _startLongRunningJob(tools, successor, tempDir);

      expect(restarted['job_id'], started['job_id']);
      expect(restarted['pid'], started['pid']);
      expect(restarted['duplicate_existing'], isTrue);
      expect(restarted['carried_from_earlier_turn'], isTrue);

      await tools.cancel(
        owner: successor,
        jobId: restarted['job_id'] as String,
      );
    });

    test('clearConversation terminates what clearOwner carried', () async {
      final started = await _startLongRunningJob(tools, owner, tempDir);
      final successor = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );

      await tools.clearOwner(owner: owner);
      await tools.clearConversation(conversationId: owner.conversationId);

      expect(tools.carriedJobIds(owner: successor), isEmpty);
      final status =
          jsonDecode(
                await tools.status(
                  owner: successor,
                  jobId: started['job_id'] as String,
                ),
              )
              as Map<String, dynamic>;
      expect(status['code'], 'job_not_found');
      final probe = await Process.run('/bin/kill', ['-0', '${started['pid']}']);
      expect(probe.exitCode, isNot(0));
    });

  });
}

Future<Map<String, dynamic>> _startLongRunningJob(
  BackgroundProcessTools tools,
  ChatTurnOwner owner,
  Directory workingDirectory,
) async {
  return jsonDecode(
        await tools.start(
          owner: owner,
          command: 'sleep 60',
          workingDirectory: workingDirectory.path,
        ),
      )
      as Map<String, dynamic>;
}
