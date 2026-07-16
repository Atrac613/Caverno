import 'dart:io';

import 'package:caverno/features/chat/application/persistence/caverno_chat_memory_mutation_coordinator.dart';
import 'package:caverno/features/chat/application/runtime/caverno_execution_lease.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dataRoot;

  setUp(() async {
    dataRoot = await Directory.systemTemp.createTemp(
      'caverno_chat_memory_coordinator_',
    );
  });

  tearDown(() async {
    if (await dataRoot.exists()) {
      await dataRoot.delete(recursive: true);
    }
  });

  test('waits for the global lease and releases it after success', () async {
    final held =
        CavernoExecutionLeaseService(
          dataRoot: dataRoot,
          frontend: 'gui',
        ).acquire(<CavernoExecutionLeaseResource>[
          CavernoExecutionLeaseResource.chatMemory(),
        ]);
    final coordinator = CavernoChatMemoryMutationCoordinator(
      dataRoot: dataRoot,
      frontend: 'terminal',
      retryInterval: const Duration(milliseconds: 5),
      timeout: const Duration(seconds: 1),
    );
    var mutationStarted = false;

    final resultFuture = coordinator.run<int>(() async {
      mutationStarted = true;
      return 7;
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(mutationStarted, isFalse);

    held.release();
    expect(await resultFuture, 7);

    CavernoExecutionLeaseService(dataRoot: dataRoot, frontend: 'gui').acquire(
      <CavernoExecutionLeaseResource>[
        CavernoExecutionLeaseResource.chatMemory(),
      ],
    ).release();
  });

  test('releases the global lease when the mutation fails', () async {
    final coordinator = CavernoChatMemoryMutationCoordinator(
      dataRoot: dataRoot,
      frontend: 'terminal',
    );

    await expectLater(
      coordinator.run<void>(() async {
        throw StateError('mutation failed');
      }),
      throwsA(isA<StateError>()),
    );

    CavernoExecutionLeaseService(dataRoot: dataRoot, frontend: 'gui').acquire(
      <CavernoExecutionLeaseResource>[
        CavernoExecutionLeaseResource.chatMemory(),
      ],
    ).release();
  });

  test(
    'reports a stable timeout while another owner keeps the lease',
    () async {
      final held =
          CavernoExecutionLeaseService(
            dataRoot: dataRoot,
            frontend: 'gui',
          ).acquire(<CavernoExecutionLeaseResource>[
            CavernoExecutionLeaseResource.chatMemory(),
          ]);
      addTearDown(held.release);
      final coordinator = CavernoChatMemoryMutationCoordinator(
        dataRoot: dataRoot,
        frontend: 'terminal',
        retryInterval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        coordinator.run<void>(() async {}),
        throwsA(
          isA<CavernoChatMemoryMutationTimeout>().having(
            (error) => error.message,
            'message',
            'Timed out waiting for the global chat-memory mutation lease after '
                '30 ms.',
          ),
        ),
      );
    },
  );
}
