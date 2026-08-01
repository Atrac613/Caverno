import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/background_process_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/local_command_tool_handler.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  late Directory workingDirectory;
  late BackgroundProcessTools tools;
  late BackgroundProcessToolRuntimeAdapter adapter;

  setUp(() async {
    workingDirectory = await Directory.systemTemp.createTemp(
      'caverno-background-runtime-',
    );
    tools = BackgroundProcessTools();
    adapter = BackgroundProcessToolRuntimeAdapter(tools);
  });

  tearDown(() async {
    await tools.dispose();
    if (workingDirectory.existsSync()) {
      await workingDirectory.delete(recursive: true);
    }
  });

  test(
    'binds start and lookup to the exact runtime process identity',
    () async {
      final start = await adapter.start(
        owner,
        LocalCommandExecutionRequest(
          toolCallId: 'start-1',
          toolName: 'process_start',
          command: 'sleep 10',
          workingDirectory: workingDirectory.path,
          arguments: const {'command': 'sleep 10'},
        ),
      );

      expect(start.disposition, LocalCommandCompletionDisposition.completed);
      final started = start.value!;
      expect(started.startedByRequest, isTrue);
      final identity = started.identity!;
      expect(identity.externalProcessId, isNotEmpty);
      expect(int.tryParse(identity.backendProcessId), isNotNull);
      expect(identity.isRunning, isTrue);
      final payload = jsonDecode(started.result.result) as Map<String, dynamic>;
      expect(payload['job_id'], identity.externalProcessId);

      final lookup = await adapter.lookup(
        owner,
        'lookup-1',
        identity.externalProcessId,
      );
      expect(lookup.value, identity);

      await adapter.cancel(
        owner,
        'cancel-1',
        identity,
        requireTermination: true,
      );
    },
  );

  test(
    'rejects a mismatched backend identity without killing the job',
    () async {
      final start = await adapter.start(
        owner,
        LocalCommandExecutionRequest(
          toolCallId: 'start-1',
          toolName: 'process_start',
          command: 'sleep 10',
          workingDirectory: workingDirectory.path,
          arguments: const {'command': 'sleep 10'},
        ),
      );
      final identity = start.value!.identity!;
      final wrongIdentity = (
        externalProcessId: identity.externalProcessId,
        backendProcessId: '${int.parse(identity.backendProcessId) + 1}',
        isRunning: true,
      );

      final rejected = await adapter.cancel(
        owner,
        'cancel-wrong',
        wrongIdentity,
        requireTermination: true,
      );
      final rejectedPayload =
          jsonDecode(rejected.value!.result) as Map<String, dynamic>;
      expect(rejectedPayload['code'], 'background_process_identity_mismatch');
      expect(
        tools
            .identity(owner: owner, jobId: identity.externalProcessId)
            ?.isRunning,
        isTrue,
      );

      final cancelled = await adapter.cancel(
        owner,
        'cancel-exact',
        identity,
        requireTermination: true,
      );
      final cancelledPayload =
          jsonDecode(cancelled.value!.result) as Map<String, dynamic>;
      expect(cancelledPayload['status'], 'exited');
    },
  );

  test('maps a retired owner to an owner-expired completion', () async {
    await tools.clearOwner(owner: owner);

    final start = await adapter.start(
      owner,
      LocalCommandExecutionRequest(
        toolCallId: 'start-retired',
        toolName: 'process_start',
        command: 'echo should-not-run',
        workingDirectory: workingDirectory.path,
        arguments: const {'command': 'echo should-not-run'},
      ),
    );

    expect(start.disposition, LocalCommandCompletionDisposition.ownerExpired);
    expect(start.value, isNull);
  });

  test(
    'preserves a recovery identity when late termination is unconfirmed',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      tools = BackgroundProcessTools(
        processStarter: (executable, arguments, directory) async {
          entered.complete();
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
              return const BackgroundProcessTerminationReport.unconfirmed(
                rootTerminationConfirmed: false,
                descendantTerminationConfirmed: false,
              );
            },
      );
      adapter = BackgroundProcessToolRuntimeAdapter(tools);

      final startFuture = adapter.start(
        owner,
        LocalCommandExecutionRequest(
          toolCallId: 'late-start',
          toolName: 'process_start',
          command: 'sleep 30',
          workingDirectory: workingDirectory.path,
          arguments: const {'command': 'sleep 30'},
        ),
      );
      await entered.future;
      final clearFuture = tools.clearOwner(owner: owner);
      release.complete();
      final completion = await startFuture;

      expect(
        completion.disposition,
        LocalCommandCompletionDisposition.completed,
      );
      expect(completion.value!.identity, isNotNull);
      expect(completion.value!.startedByRequest, isTrue);
      final payload =
          jsonDecode(completion.value!.result.result) as Map<String, dynamic>;
      expect(payload['termination_unconfirmed'], isTrue);
      expect(payload['recovery_token'], isNotEmpty);

      final receipt = tools.pendingRecoveryReceipts(owner: owner).single;
      await tools.acknowledgeUnconfirmedTermination(receipt);
      await clearFuture;
      Process.killPid(receipt.processId, ProcessSignal.sigkill);
    },
  );
}
