import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

void main() {
  late Directory workingDirectory;
  late ChatTurnOwner owner;
  final toolsToDispose = <BackgroundProcessTools>[];

  setUp(() async {
    workingDirectory = await Directory.systemTemp.createTemp(
      'caverno-background-launch-lease-',
    );
    owner = ChatTurnOwner(
      conversationId: 'conversation-a',
      interactionGeneration: 9,
    );
  });

  tearDown(() async {
    for (final tools in toolsToDispose) {
      final receipts = tools.pendingRecoveryReceipts(owner: owner);
      for (final receipt in receipts) {
        await tools.acknowledgeUnconfirmedTermination(receipt);
      }
      await tools.dispose();
    }
    if (workingDirectory.existsSync()) {
      await workingDirectory.delete(recursive: true);
    }
  });

  test('clearOwner waits for a gated pending launch lease', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final startedProcess = Completer<Process>();
    final tools = BackgroundProcessTools(
      processStarter: (executable, arguments, directory) async {
        entered.complete();
        await release.future;
        final process = await Process.start(
          executable,
          arguments,
          workingDirectory: directory,
        );
        startedProcess.complete(process);
        return process;
      },
    );
    toolsToDispose.add(tools);

    final startFuture = tools.start(
      owner: owner,
      command: 'sleep 30',
      workingDirectory: workingDirectory.path,
    );
    await entered.future;
    var clearCompleted = false;
    final clearFuture = tools.clearOwner(owner: owner).then((_) {
      clearCompleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clearCompleted, isFalse);

    release.complete();
    final result = jsonDecode(await startFuture) as Map<String, dynamic>;
    await clearFuture;
    expect(result['code'], 'process_start_cancelled');
    expect(
      await startedProcess.future.then((value) => value.exitCode),
      isNot(0),
    );
  });

  test('dispose waits for a gated pending launch lease', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final tools = BackgroundProcessTools(
      processStarter: (executable, arguments, directory) async {
        entered.complete();
        await release.future;
        return Process.start(
          executable,
          arguments,
          workingDirectory: directory,
        );
      },
    );
    toolsToDispose.add(tools);

    final startFuture = tools.start(
      owner: owner,
      command: 'sleep 30',
      workingDirectory: workingDirectory.path,
    );
    await entered.future;
    var disposeCompleted = false;
    final disposeFuture = tools.dispose().then((_) {
      disposeCompleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(disposeCompleted, isFalse);

    release.complete();
    final result = jsonDecode(await startFuture) as Map<String, dynamic>;
    await disposeFuture;
    expect(result['code'], 'process_start_cancelled');
  });

  test('late launch retirement terminates a forked descendant', () async {
    final marker = File('${workingDirectory.path}/survived.marker');
    final childPidFile = File('${workingDirectory.path}/child.pid');
    final entered = Completer<void>();
    final release = Completer<void>();
    final command =
        "(trap '' TERM; sleep 2; printf survived > '${marker.path}'; "
        "while :; do sleep 1; done) & child=\$!; "
        "printf '%s' \"\$child\" > '${childPidFile.path}'; wait";
    final tools = BackgroundProcessTools(
      processStarter: (executable, arguments, directory) async {
        final process = await Process.start(
          executable,
          arguments,
          workingDirectory: directory,
        );
        await _waitForFile(childPidFile);
        entered.complete();
        await release.future;
        return process;
      },
    );
    toolsToDispose.add(tools);

    final startFuture = tools.start(
      owner: owner,
      command: command,
      workingDirectory: workingDirectory.path,
    );
    await entered.future;
    final childPid = int.parse(await childPidFile.readAsString());
    final clearFuture = tools.clearOwner(owner: owner);
    release.complete();

    final result = jsonDecode(await startFuture) as Map<String, dynamic>;
    await clearFuture;
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    final childProbe = await Process.run('/bin/kill', ['-0', '$childPid']);
    expect(result['code'], 'process_start_cancelled');
    expect(childProbe.exitCode, isNot(0));
    expect(marker.existsSync(), isFalse);
  });

  test(
    'failed termination retains an exact receipt and fences a successor',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var terminationAttempts = 0;
      final tools = BackgroundProcessTools(
        processStarter: (executable, arguments, directory) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return Process.start(
            executable,
            arguments,
            workingDirectory: directory,
          );
        },
        processTerminator:
            (
              process, {
              required processGroupId,
              required knownDescendantProcessIds,
            }) async {
              terminationAttempts += 1;
              if (terminationAttempts == 1) {
                return const BackgroundProcessTerminationReport.unconfirmed(
                  rootTerminationConfirmed: false,
                  descendantTerminationConfirmed: false,
                  error: 'injected termination failure',
                );
              }
              process.kill(ProcessSignal.sigkill);
              await process.exitCode.timeout(const Duration(seconds: 2));
              return const BackgroundProcessTerminationReport.confirmed();
            },
      );
      toolsToDispose.add(tools);

      final command = 'sleep 30';
      final startFuture = tools.start(
        owner: owner,
        command: command,
        workingDirectory: workingDirectory.path,
      );
      await entered.future;
      var clearCompleted = false;
      final clearFuture = tools.clearOwner(owner: owner).then((_) {
        clearCompleted = true;
      });
      release.complete();
      final uncertain = jsonDecode(await startFuture) as Map<String, dynamic>;
      await Future<void>.delayed(Duration.zero);
      expect(uncertain['termination_unconfirmed'], isTrue);
      expect(clearCompleted, isFalse);

      final successor = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 1,
      );
      final blocked =
          jsonDecode(
                await tools.start(
                  owner: successor,
                  command: command,
                  workingDirectory: workingDirectory.path,
                ),
              )
              as Map<String, dynamic>;
      expect(blocked['code'], 'background_process_resource_fenced');

      final receipt = tools.recoveryReceipt(
        owner: owner,
        jobId: uncertain['job_id'] as String,
        processId: uncertain['pid'] as int,
        recoveryToken: uncertain['recovery_token'] as String,
      );
      expect(receipt, isNotNull);
      expect(
        tools.recoveryReceipt(
          owner: owner,
          jobId: uncertain['job_id'] as String,
          processId: uncertain['pid'] as int,
          recoveryToken: 'poisoned-token',
        ),
        isNull,
      );

      final reconciled = await tools.reconcileTermination(receipt!);
      expect(
        reconciled.disposition,
        BackgroundProcessRecoveryDisposition.terminationConfirmed,
      );
      await clearFuture;
      expect(clearCompleted, isTrue);
      final exactRetry = await tools.reconcileTermination(receipt);
      expect(
        exactRetry.disposition,
        BackgroundProcessRecoveryDisposition.alreadyResolved,
      );

      final successorStart =
          jsonDecode(
                await tools.start(
                  owner: successor,
                  command: command,
                  workingDirectory: workingDirectory.path,
                ),
              )
              as Map<String, dynamic>;
      expect(successorStart['ok'], isTrue);
      await tools.clearOwner(owner: successor);
    },
  );

  test('lost descendant discovery remains fenced after root exit', () async {
    var terminationAttempts = 0;
    final tools = BackgroundProcessTools(
      processTerminator:
          (
            process, {
            required processGroupId,
            required knownDescendantProcessIds,
          }) async {
            terminationAttempts += 1;
            process.kill(ProcessSignal.sigkill);
            await process.exitCode.timeout(const Duration(seconds: 2));
            return const BackgroundProcessTerminationReport.unconfirmed(
              rootTerminationConfirmed: true,
              descendantTerminationConfirmed: false,
              descendantDiscoveryConfirmed: false,
              error: 'injected descendant discovery failure',
            );
          },
    );
    toolsToDispose.add(tools);
    final started =
        jsonDecode(
              await tools.start(
                owner: owner,
                command: 'sleep 30',
                workingDirectory: workingDirectory.path,
              ),
            )
            as Map<String, dynamic>;
    expect(started['ok'], isTrue);

    // Retiring the turn only carries the running job; the conversation ending
    // is what terminates it, so that is where the recovery receipt appears.
    await tools.clearOwner(owner: owner);
    final clearFuture = tools.clearConversation(
      conversationId: owner.conversationId,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final receipt = tools.pendingRecoveryReceipts(owner: owner).single;
    final retry = await tools.reconcileTermination(receipt);
    expect(
      retry.disposition,
      BackgroundProcessRecoveryDisposition.terminationUnconfirmed,
    );
    expect(terminationAttempts, 1);

    await tools.acknowledgeUnconfirmedTermination(receipt);
    await clearFuture;
  });

  test('force release requires the exact recovery receipt', () async {
    final tools = BackgroundProcessTools(
      processTerminator:
          (
            process, {
            required processGroupId,
            required knownDescendantProcessIds,
          }) async {
            return const BackgroundProcessTerminationReport.unconfirmed(
              rootTerminationConfirmed: false,
              descendantTerminationConfirmed: false,
              error: 'injected permanent failure',
            );
          },
    );
    toolsToDispose.add(tools);
    final started =
        jsonDecode(
              await tools.start(
                owner: owner,
                command: 'sleep 30',
                workingDirectory: workingDirectory.path,
              ),
            )
            as Map<String, dynamic>;
    final identity = tools.identity(
      owner: owner,
      jobId: started['job_id'] as String,
    )!;

    var clearCompleted = false;
    await tools.clearOwner(owner: owner);
    final clearFuture = tools
        .clearConversation(conversationId: owner.conversationId)
        .then((_) {
          clearCompleted = true;
        });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clearCompleted, isFalse);
    final receipts = tools.pendingRecoveryReceipts(owner: owner);
    expect(receipts, hasLength(1));
    expect(receipts.single.processId, identity.processId);

    final acknowledgement = await tools.acknowledgeUnconfirmedTermination(
      receipts.single,
    );
    expect(
      acknowledgement.disposition,
      BackgroundProcessRecoveryDisposition.riskAcknowledged,
    );
    await clearFuture;
    expect(clearCompleted, isTrue);

    Process.killPid(identity.processId, ProcessSignal.sigkill);
  });
}

Future<void> _waitForFile(File file) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TimeoutException('Timed out waiting for ${file.path}.');
}
