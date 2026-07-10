import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_service.dart';

void main() {
  group('CodingVerificationFeedbackService', () {
    test('returns a passed snapshot for a direct mapped test target', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_verification_feedback_pass_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'int a = 1;\n',
      );
      final testFile = await _writeFile(
        root,
        'test/main_test.dart',
        'void main() {}\n',
      );

      final commands = <CodingVerificationCommand>[];
      final service = CodingVerificationFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return CodingVerificationCommandOutput(
            exitCode: 0,
            stdout: _machineOutput(testFile: testFile),
          );
        },
      );

      final run = await service.buildFeedbackRun(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        trigger: CodingVerificationTrigger.completionClaim,
        now: DateTime.fromMicrosecondsSinceEpoch(42),
      );
      final snapshot = run.snapshot;

      expect(snapshot, isNotNull);
      expect(
        snapshot!.validationStatus,
        ConversationExecutionValidationStatus.passed,
      );
      expect(snapshot.changedPaths, ['lib/main.dart']);
      expect(snapshot.targetBatches.single.targets, ['test/main_test.dart']);
      expect(snapshot.passedCount, 1);
      expect(snapshot.failedCount, 0);
      expect(run.toolResult, isNull);
      expect(commands.single.executable, 'flutter');
      expect(commands.single.arguments, [
        'test',
        '--machine',
        'test/main_test.dart',
      ]);

      final evidence = run.evidenceToolResult;
      expect(evidence, isNotNull);
      expect(evidence!.id, 'dart_test_verification_evidence_42');
      expect(evidence.name, CodingVerificationFeedbackService.evidenceToolName);
      final payload = jsonDecode(evidence.result) as Map<String, dynamic>;
      expect(
        payload['schema'],
        CodingVerificationFeedbackService.evidenceSchemaName,
      );
      expect(payload['validation_status'], 'passed');
      expect(payload['changed_paths'], ['lib/main.dart']);
      expect(payload['counts'], {'passed': 1, 'failed': 0, 'skipped': 0});
      expect(
        (payload['target_batches'] as List<dynamic>).single,
        containsPair('targets', ['test/main_test.dart']),
      );
      expect(payload['verification'], {
        'executable': 'flutter',
        'arguments': ['test', '--machine', 'test/main_test.dart'],
        'working_directory': root.absolute.path,
        'exit_code': 0,
        'duration_ms': isA<int>(),
        'timed_out': false,
      });
    });

    test('returns structured feedback for failing tests', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_verification_feedback_fail_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'int a = 1;\n',
      );
      final testFile = await _writeFile(
        root,
        'test/main_test.dart',
        'void main() {}\n',
      );

      final commands = <CodingVerificationCommand>[];
      final service = CodingVerificationFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return CodingVerificationCommandOutput(
            exitCode: 1,
            stdout: _machineOutput(
              testFile: testFile,
              result: 'failure',
              error: 'Expected: <2>\n  Actual: <1>',
              stackTrace:
                  '#0 main.<anonymous closure> (test/main_test.dart:7:5)',
            ),
          );
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        trigger: CodingVerificationTrigger.completionClaim,
        now: DateTime.fromMicrosecondsSinceEpoch(42),
      );

      expect(result, isNotNull);
      expect(result!.id, 'dart_test_feedback_42');
      expect(result.name, CodingVerificationFeedbackService.toolName);
      expect(commands, hasLength(1));

      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload['schema'], CodingVerificationFeedbackService.schemaName);
      expect(payload['provider'], 'dart_test_runner');
      expect(payload['trigger'], 'completionClaim');
      expect(payload['validation_status'], 'failed');
      expect(payload['changed_paths'], ['lib/main.dart']);
      expect(payload['counts'], containsPair('passed', 0));
      expect(payload['counts'], containsPair('failed', 1));
      final targetBatches = payload['target_batches'] as List<dynamic>;
      expect(
        targetBatches.single,
        containsPair('targets', ['test/main_test.dart']),
      );
      final failures = payload['failing_tests'] as List<dynamic>;
      expect(failures.single, containsPair('test_name', 'repairs edited file'));
      expect(
        failures.single,
        containsPair('relative_path', 'test/main_test.dart'),
      );
      expect(failures.single, containsPair('line', 7));
      expect(
        failures.single,
        containsPair('message', 'Expected: <2>\n  Actual: <1>'),
      );
      final telemetry = payload['telemetry'] as Map<String, dynamic>;
      expect(telemetry['command_attempt_count'], 1);
      final verification = payload['verification'] as Map<String, dynamic>;
      expect(verification['executable'], 'flutter');
      expect(verification['arguments'], [
        'test',
        '--machine',
        'test/main_test.dart',
      ]);
    });

    test(
      'falls back to the package test directory without a direct target',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_verification_feedback_test_dir_',
        );
        addTearDown(() => root.delete(recursive: true));
        final editedFile = await _writeFile(
          root,
          'lib/feature.dart',
          'int a = 1;\n',
        );
        final testFile = await _writeFile(
          root,
          'test/widget_test.dart',
          'void main() {}\n',
        );

        final commands = <CodingVerificationCommand>[];
        final service = CodingVerificationFeedbackService(
          commandRunner: (command, timeout) async {
            commands.add(command);
            return CodingVerificationCommandOutput(
              exitCode: 0,
              stdout: _machineOutput(testFile: testFile),
            );
          },
        );

        final snapshot = await service.collectSnapshot(
          projectRoot: root.path,
          changedPaths: [editedFile.path],
          trigger: CodingVerificationTrigger.completionClaim,
        );

        expect(snapshot, isNotNull);
        expect(snapshot!.targetBatches.single.targets, ['test']);
        expect(commands.single.arguments, ['test', '--machine', 'test']);
      },
    );

    test('records no_test_target when no package tests exist', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_verification_feedback_no_target_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'int a = 1;\n',
      );

      final commands = <CodingVerificationCommand>[];
      final service = CodingVerificationFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return const CodingVerificationCommandOutput(exitCode: 0);
        },
      );

      final snapshot = await service.collectSnapshot(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        trigger: CodingVerificationTrigger.completionClaim,
      );
      final toolResult = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        trigger: CodingVerificationTrigger.completionClaim,
      );

      expect(snapshot, isNotNull);
      expect(
        snapshot!.validationStatus,
        ConversationExecutionValidationStatus.unknown,
      );
      expect(snapshot.reason, 'no_test_target');
      expect(snapshot.targetBatches, isEmpty);
      expect(commands, isEmpty);
      expect(toolResult, isNull);
    });

    test('prefers fvm flutter test when FVM metadata is present', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_verification_feedback_fvm_',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/.fvm').create(recursive: true);
      await File('${root.path}/.fvm/fvm_config.json').writeAsString('{}');
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'int a = 1;\n',
      );
      final testFile = await _writeFile(
        root,
        'test/main_test.dart',
        'void main() {}\n',
      );

      final commands = <CodingVerificationCommand>[];
      final service = CodingVerificationFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return CodingVerificationCommandOutput(
            exitCode: 0,
            stdout: _machineOutput(testFile: testFile),
          );
        },
      );

      final snapshot = await service.collectSnapshot(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        trigger: CodingVerificationTrigger.completionClaim,
      );

      expect(
        snapshot?.validationStatus,
        ConversationExecutionValidationStatus.passed,
      );
      expect(commands, hasLength(1));
      expect(commands.single.executable, 'fvm');
      expect(commands.single.arguments, [
        'flutter',
        'test',
        '--machine',
        'test/main_test.dart',
      ]);
    });

    test(
      'falls back to dart test after an unavailable flutter command',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_verification_feedback_fallback_',
        );
        addTearDown(() => root.delete(recursive: true));
        final editedFile = await _writeFile(
          root,
          'lib/main.dart',
          'int a = 1;\n',
        );
        final testFile = await _writeFile(
          root,
          'test/main_test.dart',
          'void main() {}\n',
        );

        var runCount = 0;
        final commands = <CodingVerificationCommand>[];
        final service = CodingVerificationFeedbackService(
          commandRunner: (command, timeout) async {
            runCount += 1;
            commands.add(command);
            if (runCount == 1) {
              return const CodingVerificationCommandOutput(
                exitCode: -1,
                timedOut: true,
              );
            }
            return CodingVerificationCommandOutput(
              exitCode: 0,
              stdout: _machineOutput(testFile: testFile),
            );
          },
        );

        final snapshot = await service.collectSnapshot(
          projectRoot: root.path,
          changedPaths: [editedFile.path],
          trigger: CodingVerificationTrigger.completionClaim,
        );

        expect(
          snapshot?.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
        expect(commands, hasLength(2));
        expect(commands.first.executable, 'flutter');
        expect(commands[1].executable, 'dart');
        expect(commands[1].arguments, [
          'test',
          '--reporter=json',
          'test/main_test.dart',
        ]);
        expect(snapshot!.telemetry.commandAttemptCount, 2);
        expect(snapshot.telemetry.fallbackCommandCount, 1);
        expect(snapshot.telemetry.timedOutCommandCount, 1);
      },
    );

    test('runs verification from the nearest nested package root', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_verification_feedback_nested_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _writeFile(root, 'packages/example/pubspec.yaml', '''
name: nested_example
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      final editedFile = await _writeFile(
        root,
        'packages/example/lib/main.dart',
        'int a = 1;\n',
      );
      final testFile = await _writeFile(
        root,
        'packages/example/test/main_test.dart',
        'void main() {}\n',
      );
      final packageRoot = Directory.fromUri(
        root.uri.resolve('packages/example'),
      ).absolute.path;

      final commands = <CodingVerificationCommand>[];
      final service = CodingVerificationFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return CodingVerificationCommandOutput(
            exitCode: 0,
            stdout: _machineOutput(testFile: testFile),
          );
        },
      );

      final snapshot = await service.collectSnapshot(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        trigger: CodingVerificationTrigger.completionClaim,
      );

      expect(
        snapshot?.validationStatus,
        ConversationExecutionValidationStatus.passed,
      );
      expect(commands.single.workingDirectory, packageRoot);
      expect(commands.single.arguments, [
        'test',
        '--machine',
        'test/main_test.dart',
      ]);
      expect(snapshot!.targetBatches.single.packageRoot, packageRoot);
      expect(snapshot.targetBatches.single.targets, ['test/main_test.dart']);
    });

    test('caps failing tests and truncates long stack traces', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_verification_feedback_caps_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'int a = 1;\n',
      );
      final testFile = await _writeFile(
        root,
        'test/main_test.dart',
        'void main() {}\n',
      );
      final longStack = 's' * 50;

      final service = CodingVerificationFeedbackService(
        maxFailures: 2,
        maxStackChars: 10,
        commandRunner: (command, timeout) async {
          return CodingVerificationCommandOutput(
            exitCode: 1,
            stdout: _multiFailureOutput(
              testFile: testFile,
              stackTrace: longStack,
            ),
          );
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        trigger: CodingVerificationTrigger.completionClaim,
      );

      final payload = jsonDecode(result!.result) as Map<String, dynamic>;
      final failures = payload['failing_tests'] as List<dynamic>;
      expect(failures, hasLength(2));
      expect(payload['truncated_failure_count'], 1);
      expect(failures.first['stack_trace'], 'ssssssssss...');
    });
  });
}

Future<File> _writeFile(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = File.fromUri(root.uri.resolve(relativePath));
  await file.parent.create(recursive: true);
  return file.writeAsString(content);
}

String _machineOutput({
  required File testFile,
  String result = 'success',
  String? error,
  String? stackTrace,
}) {
  final events = <Map<String, Object?>>[
    {'type': 'start', 'time': 0},
    {
      'type': 'suite',
      'suite': {'id': 0, 'path': 'test/main_test.dart'},
      'time': 0,
    },
    {
      'type': 'testStart',
      'test': {
        'id': 1,
        'name': 'repairs edited file',
        'suiteID': 0,
        'line': 7,
        'column': 5,
        'url': testFile.uri.toString(),
      },
      'time': 1,
    },
    if (error != null)
      {
        'type': 'error',
        'testID': 1,
        'error': error,
        'stackTrace': ?stackTrace,
        'isFailure': true,
        'time': 2,
      },
    {
      'type': 'testDone',
      'testID': 1,
      'result': result,
      'skipped': false,
      'hidden': false,
      'time': 3,
    },
    {'type': 'done', 'success': result == 'success', 'time': 4},
  ];
  return events.map(jsonEncode).join('\n');
}

String _multiFailureOutput({
  required File testFile,
  required String stackTrace,
}) {
  final events = <Map<String, Object?>>[
    {'type': 'start', 'time': 0},
    {
      'type': 'suite',
      'suite': {'id': 0, 'path': 'test/main_test.dart'},
      'time': 0,
    },
  ];
  for (var id = 1; id <= 3; id += 1) {
    events.addAll([
      {
        'type': 'testStart',
        'test': {
          'id': id,
          'name': 'failure $id',
          'suiteID': 0,
          'line': id,
          'column': 1,
          'url': testFile.uri.toString(),
        },
        'time': id,
      },
      {
        'type': 'error',
        'testID': id,
        'error': 'Failure $id',
        'stackTrace': stackTrace,
        'isFailure': true,
        'time': id,
      },
      {
        'type': 'testDone',
        'testID': id,
        'result': 'failure',
        'skipped': false,
        'hidden': false,
        'time': id,
      },
    ]);
  }
  events.add({'type': 'done', 'success': false, 'time': 4});
  return events.map(jsonEncode).join('\n');
}
