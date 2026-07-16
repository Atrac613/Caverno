import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/application/persistence/caverno_chat_memory_mutation_coordinator.dart';
import 'package:caverno/features/chat/application/runtime/caverno_execution_lease.dart';

import 'cli3_contention_soak_report.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 9) {
    stderr.writeln('Invalid CLI3 contention worker arguments.');
    exitCode = 64;
    return;
  }
  final dataRoot = Directory(arguments[0]);
  final workspace = Directory(arguments[1]);
  final frontend = arguments[2];
  final options = Cli3ContentionSoakOptions(
    workers: int.parse(arguments[3]),
    iterations: int.parse(arguments[4]),
    hold: Duration(milliseconds: int.parse(arguments[5])),
    operationTimeout: Duration(milliseconds: int.parse(arguments[6])),
    retryInterval: Duration(milliseconds: int.parse(arguments[7])),
    maxP95Milliseconds: double.parse(arguments[8]),
  );
  final leaseService = CavernoExecutionLeaseService(
    dataRoot: dataRoot,
    frontend: frontend,
    ownerId: '$frontend-$pid',
  );
  final memoryCoordinator = CavernoChatMemoryMutationCoordinator(
    dataRoot: dataRoot,
    frontend: frontend,
    retryInterval: options.retryInterval,
    timeout: options.operationTimeout,
    leaseService: leaseService,
  );
  final runtimeResources = <CavernoExecutionLeaseResource>[
    CavernoExecutionLeaseResource.conversation('cli3-contention-conversation'),
    CavernoExecutionLeaseResource.codingWorkspace(workspace.path),
  ];
  stdout.writeln(jsonEncode(<String, Object>{'event': 'ready', 'pid': pid}));
  await stdout.flush();
  final start = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 15));
  if (start != 'start') {
    throw StateError('Unexpected contention worker barrier command.');
  }

  var runtimeSuccesses = 0;
  var runtimeConflicts = 0;
  var runtimeTimeouts = 0;
  var memorySuccesses = 0;
  var memoryTimeouts = 0;
  var genericOwnerDiagnostics = 0;
  var invalidOwnerDiagnostics = 0;
  final runtimeWaitMicros = <int>[];
  final memoryOperationMicros = <int>[];

  for (var iteration = 0; iteration < options.iterations; iteration += 1) {
    final runtimeStopwatch = Stopwatch()..start();
    CavernoExecutionLeaseHandle? runtimeHandle;
    while (runtimeHandle == null &&
        runtimeStopwatch.elapsed < options.operationTimeout) {
      try {
        runtimeHandle = leaseService.acquire(runtimeResources);
      } on CavernoExecutionLeaseConflict catch (error) {
        runtimeConflicts += 1;
        final owner = error.owner;
        if (owner == null) {
          genericOwnerDiagnostics += 1;
        } else if ((owner.frontend != 'flutterGui' &&
                owner.frontend != 'terminal') ||
            owner.processId <= 0) {
          invalidOwnerDiagnostics += 1;
        }
        await Future<void>.delayed(options.retryInterval);
      }
    }
    if (runtimeHandle == null) {
      runtimeTimeouts += 1;
    } else {
      runtimeWaitMicros.add(runtimeStopwatch.elapsedMicroseconds);
      await Future<void>.delayed(options.hold);
      runtimeHandle.release();
      runtimeSuccesses += 1;
    }

    final memoryStopwatch = Stopwatch()..start();
    try {
      await memoryCoordinator.run<void>(() async {
        await Future<void>.delayed(options.hold);
      });
      memoryOperationMicros.add(memoryStopwatch.elapsedMicroseconds);
      memorySuccesses += 1;
    } on CavernoChatMemoryMutationTimeout {
      memoryTimeouts += 1;
    }
  }

  final result = Cli3ContentionWorkerResult(
    frontend: frontend,
    processId: pid,
    runtimeSuccesses: runtimeSuccesses,
    runtimeConflicts: runtimeConflicts,
    runtimeTimeouts: runtimeTimeouts,
    runtimeWaitMicros: runtimeWaitMicros,
    memorySuccesses: memorySuccesses,
    memoryTimeouts: memoryTimeouts,
    memoryOperationMicros: memoryOperationMicros,
    genericOwnerDiagnostics: genericOwnerDiagnostics,
    invalidOwnerDiagnostics: invalidOwnerDiagnostics,
  );
  stdout.writeln(
    jsonEncode(<String, Object>{'event': 'result', 'result': result.toJson()}),
  );
  await stdout.flush();
}
