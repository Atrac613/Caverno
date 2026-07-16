import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/cli3_contention_soak.dart';
import '../../tool/cli3_contention_soak_report.dart';

void main() {
  test(
    'passing report recommends direct file locking without sensitive paths',
    () {
      const options = Cli3ContentionSoakOptions(
        workers: 2,
        iterations: 2,
        maxP95Milliseconds: 10,
      );
      final report = Cli3ContentionSoakReport(
        options: options,
        workers: <Cli3ContentionWorkerResult>[
          _worker(
            frontend: 'flutterGui',
            processId: 101,
            runtimeWaitMicros: <int>[1000, 2000],
            memoryOperationMicros: <int>[2000, 3000],
          ),
          _worker(
            frontend: 'terminal',
            processId: 202,
            runtimeWaitMicros: <int>[3000, 4000],
            memoryOperationMicros: <int>[4000, 5000],
          ),
        ],
        elapsed: const Duration(milliseconds: 20),
      );

      expect(report.passed, isTrue);
      expect(report.decision, 'direct_file_locking_sufficient');
      expect(report.runtimeSuccesses, 4);
      expect(report.memorySuccesses, 4);
      expect(report.runtimeLatency.p50Milliseconds, 2);
      expect(report.runtimeLatency.p95Milliseconds, 4);
      expect(report.throughputOperationsPerSecond, 400);

      final json = report.toJson();
      expect(json['schema'], cli3ContentionSoakSchema);
      expect(json['schemaVersion'], cli3ContentionSoakSchemaVersion);
      expect(json['status'], 'passed');
      expect(
        (json['metrics'] as Map<String, Object>)['runtime'],
        containsPair('conflicts', 2),
      );
      final serialized = jsonEncode(json);
      final markdown = report.toMarkdown();
      for (final sensitiveValue in <String>[
        '/private/tmp/sensitive-root',
        '/Users/example/private-workspace',
        'conversation-secret',
        '.lease',
      ]) {
        expect(serialized, isNot(contains(sensitiveValue)));
        expect(markdown, isNot(contains(sensitiveValue)));
      }
      expect(markdown, contains('## Decision Reasons'));
      expect(markdown, contains('Conversation + workspace'));
    },
  );

  test('failed threshold recommends investigating a local daemon', () {
    const options = Cli3ContentionSoakOptions(
      workers: 2,
      iterations: 1,
      maxP95Milliseconds: 10,
    );
    final report = Cli3ContentionSoakReport(
      options: options,
      workers: <Cli3ContentionWorkerResult>[
        _worker(
          frontend: 'flutterGui',
          processId: 101,
          iterations: 1,
          runtimeWaitMicros: <int>[11000],
          memoryOperationMicros: <int>[1000],
        ),
        _worker(
          frontend: 'terminal',
          processId: 202,
          iterations: 1,
          runtimeWaitMicros: <int>[1000],
          memoryOperationMicros: <int>[1000],
        ),
      ],
      elapsed: const Duration(milliseconds: 20),
    );

    expect(report.passed, isFalse);
    expect(report.decision, 'investigate_local_daemon');
    expect(report.blockingReasons, hasLength(1));
    expect(report.blockingReasons.single, contains('exceeds 10.000 ms'));
  });

  test(
    'runs mixed ownership work in separate operating system processes',
    () async {
      final dataRoot = await Directory.systemTemp.createTemp(
        'caverno_cli3_contention_test_',
      );
      addTearDown(() async {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
      });

      final report = await runCli3ContentionSoak(
        dataRoot: dataRoot,
        options: const Cli3ContentionSoakOptions(
          workers: 2,
          iterations: 4,
          hold: Duration(milliseconds: 1),
          operationTimeout: Duration(seconds: 2),
          retryInterval: Duration(milliseconds: 1),
          maxP95Milliseconds: 2000,
        ),
        workerScriptPath:
            '${Directory.current.path}/tool/cli3_contention_soak_worker.dart',
      );

      expect(report.workers, hasLength(2));
      expect(
        report.workers.map((worker) => worker.processId).toSet(),
        hasLength(2),
      );
      expect(report.workers.map((worker) => worker.frontend).toSet(), <String>{
        'flutterGui',
        'terminal',
      });
      expect(report.runtimeSuccesses, 8);
      expect(report.memorySuccesses, 8);
      expect(report.runtimeTimeouts, 0);
      expect(report.memoryTimeouts, 0);
      expect(report.invalidOwnerDiagnostics, 0);
      expect(report.passed, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Cli3ContentionWorkerResult _worker({
  required String frontend,
  required int processId,
  required List<int> runtimeWaitMicros,
  required List<int> memoryOperationMicros,
  int iterations = 2,
}) {
  return Cli3ContentionWorkerResult(
    frontend: frontend,
    processId: processId,
    runtimeSuccesses: iterations,
    runtimeConflicts: 1,
    runtimeTimeouts: 0,
    runtimeWaitMicros: runtimeWaitMicros,
    memorySuccesses: iterations,
    memoryTimeouts: 0,
    memoryOperationMicros: memoryOperationMicros,
    genericOwnerDiagnostics: 0,
    invalidOwnerDiagnostics: 0,
  );
}
