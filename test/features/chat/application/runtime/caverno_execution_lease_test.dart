import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/application/runtime/caverno_execution_lease.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_support/dart_tool_process.dart';

void main() {
  late Directory dataRoot;
  final processes = <Process>[];

  setUp(() async {
    dataRoot = await Directory.systemTemp.createTemp(
      'caverno_execution_lease_',
    );
  });

  tearDown(() async {
    for (final process in processes) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
    if (await dataRoot.exists()) {
      await dataRoot.delete(recursive: true);
    }
  });

  test('normalizes duplicates and blocks same-process reentry', () {
    final resource = CavernoExecutionLeaseResource.conversation(
      'sensitive-conversation-identifier',
    );
    final equivalent = CavernoExecutionLeaseResource.conversation(
      '  sensitive-conversation-identifier  ',
    );
    final owner = CavernoExecutionLeaseService(
      dataRoot: dataRoot,
      frontend: 'gui',
      ownerId: 'owner-one',
      processId: 101,
      now: () => DateTime.utc(2026, 7, 16, 1, 2, 3),
    );
    final contender = CavernoExecutionLeaseService(
      dataRoot: dataRoot,
      frontend: 'terminal',
      ownerId: 'owner-two',
      processId: 202,
    );

    final handle = owner.acquire(<CavernoExecutionLeaseResource>[
      resource,
      equivalent,
    ]);

    expect(handle.resources, hasLength(1));
    expect(
      () => contender.acquire(<CavernoExecutionLeaseResource>[resource]),
      throwsA(
        isA<CavernoExecutionLeaseConflict>()
            .having((error) => error.owner?.frontend, 'frontend', 'gui')
            .having((error) => error.owner?.processId, 'processId', 101),
      ),
    );
    final files = owner.leaseDirectory.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(files.single.path, isNot(contains(resource.identity)));
    expect(files.single.readAsStringSync(), isNot(contains(resource.identity)));

    handle.release();
    handle.release();
    expect(handle.isReleased, isTrue);
    contender.acquire(<CavernoExecutionLeaseResource>[resource]).release();
  });

  test(
    'canonical workspace aliases resolve to one resource',
    () {
      final workspace = Directory.fromUri(dataRoot.uri.resolve('workspace/'))
        ..createSync();
      final alias = Link.fromUri(dataRoot.uri.resolve('workspace-alias'))
        ..createSync(workspace.path);

      final direct = CavernoExecutionLeaseResource.codingWorkspace(
        workspace.path,
      );
      final throughAlias = CavernoExecutionLeaseResource.codingWorkspace(
        alias.path,
      );

      expect(throughAlias.identity, direct.identity);
      expect(throughAlias.displayTarget, direct.displayTarget);
    },
    skip: Platform.isWindows,
  );

  test('reports an external owner and recovers after abrupt exit', () async {
    final resource = CavernoExecutionLeaseResource.conversation(
      'conversation-external',
    );
    final probe = await _startProbe(
      dataRoot: dataRoot,
      resource: resource,
      processes: processes,
    );
    final contender = CavernoExecutionLeaseService(
      dataRoot: dataRoot,
      frontend: 'gui',
    );

    expect(
      () => contender.acquire(<CavernoExecutionLeaseResource>[resource]),
      throwsA(
        isA<CavernoExecutionLeaseConflict>()
            .having(
              (error) => error.owner?.frontend,
              'frontend',
              'terminal-probe',
            )
            .having((error) => error.owner?.processId, 'processId', probe.pid),
      ),
    );

    expect(probe.kill(ProcessSignal.sigkill), isTrue);
    await probe.exitCode.timeout(const Duration(seconds: 5));
    processes.remove(probe);

    contender.acquire(<CavernoExecutionLeaseResource>[resource]).release();
  });

  test('isolates resources and explicit data roots', () async {
    final heldResource = CavernoExecutionLeaseResource.conversation(
      'conversation-held',
    );
    final probe = await _startProbe(
      dataRoot: dataRoot,
      resource: heldResource,
      processes: processes,
    );
    final sameRoot = CavernoExecutionLeaseService(
      dataRoot: dataRoot,
      frontend: 'gui',
    );
    final otherRootDirectory = Directory.fromUri(
      dataRoot.uri.resolve('isolated/'),
    );
    final otherRoot = CavernoExecutionLeaseService(
      dataRoot: otherRootDirectory,
      frontend: 'terminal',
    );

    sameRoot.acquire(<CavernoExecutionLeaseResource>[
      CavernoExecutionLeaseResource.conversation('conversation-free'),
    ]).release();
    otherRoot.acquire(<CavernoExecutionLeaseResource>[heldResource]).release();

    await _releaseProbe(probe, processes);
  });

  test('rolls back a partial multi-resource acquisition', () async {
    final blocked = CavernoExecutionLeaseResource.conversation(
      'conversation-blocked',
    );
    final acquiredFirst = CavernoExecutionLeaseResource.codingWorkspace(
      Directory.fromUri(dataRoot.uri.resolve('workspace/')).path,
    );
    final probe = await _startProbe(
      dataRoot: dataRoot,
      resource: blocked,
      processes: processes,
    );
    final contender = CavernoExecutionLeaseService(
      dataRoot: dataRoot,
      frontend: 'gui',
    );

    expect(
      () => contender.acquire(<CavernoExecutionLeaseResource>[
        blocked,
        acquiredFirst,
      ]),
      throwsA(isA<CavernoExecutionLeaseConflict>()),
    );
    contender.acquire(<CavernoExecutionLeaseResource>[acquiredFirst]).release();

    await _releaseProbe(probe, processes);
  });

  test(
    'falls back to a safe conflict when owner metadata is invalid',
    () async {
      final resource = CavernoExecutionLeaseResource.conversation(
        'conversation-invalid-owner',
      );
      final probe = await _startProbe(
        dataRoot: dataRoot,
        resource: resource,
        processes: processes,
        metadataMode: 'invalid',
      );
      final contender = CavernoExecutionLeaseService(
        dataRoot: dataRoot,
        frontend: 'gui',
      );

      expect(
        () => contender.acquire(<CavernoExecutionLeaseResource>[resource]),
        throwsA(
          isA<CavernoExecutionLeaseConflict>()
              .having((error) => error.owner, 'owner', isNull)
              .having(
                (error) => error.message,
                'message',
                contains('another Caverno process'),
              ),
        ),
      );

      await _releaseProbe(probe, processes);
    },
  );
}

Future<Process> _startProbe({
  required Directory dataRoot,
  required CavernoExecutionLeaseResource resource,
  required List<Process> processes,
  String metadataMode = 'valid',
}) async {
  final process = await Process.start(dartToolExecutable(), <String>[
    'test/integration_support/caverno_execution_lease_probe.dart',
    dataRoot.path,
    resource.kind.name,
    resource.identity,
    metadataMode,
  ], workingDirectory: Directory.current.path);
  processes.add(process);
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  try {
    final line = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 15));
    final event = jsonDecode(line) as Map<String, dynamic>;
    expect(event['status'], 'acquired');
    expect(event['pid'], process.pid);
    return process;
  } on Object catch (error) {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    processes.remove(process);
    final diagnostics = await stderrFuture;
    throw StateError('Lease probe failed: $error\n$diagnostics');
  }
}

Future<void> _releaseProbe(Process process, List<Process> processes) async {
  process.stdin.writeln('release');
  await process.stdin.flush();
  await process.stdin.close();
  expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
  processes.remove(process);
}
