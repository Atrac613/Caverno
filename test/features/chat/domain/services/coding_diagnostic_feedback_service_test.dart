import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/coding_diagnostic_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/language_diagnostics_bridge.dart';

void main() {
  group('CodingDiagnosticFeedbackService', () {
    test('returns analyzer diagnostics for edited Dart files only', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_diagnostic_feedback_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'void main() {}\n',
      );
      final unrelatedFile = await _writeFile(
        root,
        'lib/unrelated.dart',
        'void helper() {}\n',
      );
      await _writeFile(root, 'README.md', '# Notes\n');

      final commands = <CodingDiagnosticCommand>[];
      final service = CodingDiagnosticFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return CodingDiagnosticCommandOutput(
            exitCode: 3,
            stdout: [
              'ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|${editedFile.path}|4|12|3|Undefined name foo.',
              'WARNING|STATIC_WARNING|UNUSED_IMPORT|${unrelatedFile.path}|1|1|6|Unused import.',
            ].join('\n'),
          );
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path, '${root.path}/README.md'],
      );

      expect(result, isNotNull);
      expect(result!.name, CodingDiagnosticFeedbackService.toolName);
      expect(commands, hasLength(1));
      expect(commands.single.executable, 'dart');
      expect(
        commands.single.arguments,
        containsAll(['analyze', '--format=machine']),
      );
      expect(commands.single.arguments, contains('lib/main.dart'));
      expect(commands.single.arguments, isNot(contains('README.md')));

      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload['schema'], CodingDiagnosticFeedbackService.schemaName);
      expect(payload['provider'], 'dart_analyzer');
      expect(payload['changed_paths'], ['lib/main.dart']);
      expect(payload['diagnostic_count'], 1);
      expect(payload['new_diagnostic_count'], 1);
      expect(payload['current_diagnostic_count'], 1);
      expect(payload['baseline_applied'], isFalse);
      final bridge =
          payload['language_diagnostics_bridge'] as Map<String, dynamic>;
      expect(bridge['provider'], 'dart_analyzer');
      expect(bridge['protocol'], 'dart_analyzer_cli');
      expect(bridge['status'], 'ready');
      final capabilities = bridge['capabilities'] as Map<String, dynamic>;
      expect(capabilities['diagnostics'], isTrue);
      expect(capabilities['document_symbols'], isFalse);
      expect(capabilities['go_to_definition'], isFalse);
      expect(payload['telemetry'], containsPair('command_attempt_count', 1));
      final diagnostics = payload['diagnostics'] as List<dynamic>;
      expect(
        diagnostics.single,
        containsPair('relative_path', 'lib/main.dart'),
      );
      expect(diagnostics.single, containsPair('severity', 'Error'));
      expect(diagnostics.single, containsPair('line', 4));
      expect(diagnostics.single, containsPair('column', 12));
      expect(diagnostics.single, containsPair('code', 'UNDEFINED_IDENTIFIER'));
      expect(
        diagnostics.single,
        containsPair('message', 'Undefined name foo.'),
      );
    });

    test('prefers fvm dart analyze when FVM metadata is present', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_diagnostic_feedback_fvm_',
      );
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/.fvm').create(recursive: true);
      await File('${root.path}/.fvm/fvm_config.json').writeAsString('{}');
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'void main() {}\n',
      );

      final commands = <CodingDiagnosticCommand>[];
      final service = CodingDiagnosticFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return const CodingDiagnosticCommandOutput(exitCode: 0);
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
      );

      expect(result, isNull);
      expect(commands, hasLength(1));
      expect(commands.single.executable, 'fvm');
      expect(commands.single.arguments.take(3), [
        'dart',
        'analyze',
        '--format=machine',
      ]);
    });

    test('falls back to flutter analyze output', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_diagnostic_feedback_flutter_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'void main() {}\n',
      );
      final bullet = String.fromCharCode(0x2022);

      final commands = <CodingDiagnosticCommand>[];
      final service = CodingDiagnosticFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          if (commands.length == 1) {
            return const CodingDiagnosticCommandOutput(exitCode: 3);
          }
          return CodingDiagnosticCommandOutput(
            exitCode: 1,
            stdout:
                'error $bullet Undefined name foo. $bullet lib/main.dart:4:12 $bullet undefined_identifier',
          );
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
      );

      expect(result, isNotNull);
      expect(commands, hasLength(2));
      expect(commands.first.executable, 'dart');
      expect(commands[1].executable, 'flutter');
      expect(commands[1].arguments, contains('--no-pub'));
      expect(commands[1].arguments, contains('--no-congratulate'));

      final payload = jsonDecode(result!.result) as Map<String, dynamic>;
      final diagnostics = payload['diagnostics'] as List<dynamic>;
      expect(diagnostics.single, containsPair('severity', 'Error'));
      expect(diagnostics.single, containsPair('line', 4));
      expect(diagnostics.single, containsPair('column', 12));
      expect(diagnostics.single, containsPair('code', 'undefined_identifier'));
      expect(
        diagnostics.single,
        containsPair('message', 'Undefined name foo.'),
      );
    });

    test('runs analyzer from the nearest nested package root', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_diagnostic_feedback_nested_',
      );
      addTearDown(() => root.delete(recursive: true));
      await _writeFile(root, 'README.md', '# Workspace\n');
      await _writeFile(root, 'packages/example/pubspec.yaml', '''
name: nested_example
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      final editedFile = await _writeFile(
        root,
        'packages/example/lib/main.dart',
        'void main() {}\n',
      );
      final packageRoot = Directory.fromUri(
        root.uri.resolve('packages/example'),
      ).absolute.path;

      final commands = <CodingDiagnosticCommand>[];
      final service = CodingDiagnosticFeedbackService(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return const CodingDiagnosticCommandOutput(
            exitCode: 3,
            stdout:
                'ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|lib/main.dart|2|9|3|Undefined name nestedValue.',
          );
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
      );

      expect(result, isNotNull);
      expect(commands, hasLength(1));
      expect(commands.single.workingDirectory, packageRoot);
      expect(commands.single.arguments, contains('lib/main.dart'));
      expect(
        commands.single.arguments,
        isNot(contains('packages/example/lib/main.dart')),
      );

      final payload = jsonDecode(result!.result) as Map<String, dynamic>;
      expect(payload['project_root'], root.absolute.path);
      expect(payload['changed_paths'], ['packages/example/lib/main.dart']);
      expect(
        (payload['analyzer'] as Map<String, dynamic>)['working_directory'],
        packageRoot,
      );
      final diagnostics = payload['diagnostics'] as List<dynamic>;
      expect(
        diagnostics.single,
        containsPair('relative_path', 'packages/example/lib/main.dart'),
      );
      expect(
        diagnostics.single,
        containsPair('message', 'Undefined name nestedValue.'),
      );
    });

    test(
      'returns null when analyzer output has no changed-file diagnostics',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_diagnostic_feedback_empty_',
        );
        addTearDown(() => root.delete(recursive: true));
        final editedFile = await _writeFile(
          root,
          'lib/main.dart',
          'void main() {}\n',
        );

        final service = CodingDiagnosticFeedbackService(
          commandRunner: (command, timeout) async {
            return const CodingDiagnosticCommandOutput(
              exitCode: 0,
              stdout: 'No issues found!',
            );
          },
        );

        final result = await service.buildFeedbackToolResult(
          projectRoot: root.path,
          changedPaths: [editedFile.path],
        );

        expect(result, isNull);
      },
    );

    test('caps diagnostics per file and across the payload', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_diagnostic_feedback_caps_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'void main() {}\n',
      );

      final machineLines = List<String>.generate(
        5,
        (index) =>
            'WARNING|STATIC_WARNING|CODE_$index|${editedFile.path}|${index + 1}|1|1|Issue $index.',
      );
      final service = CodingDiagnosticFeedbackService(
        maxDiagnosticsPerFile: 2,
        maxTotalDiagnostics: 3,
        commandRunner: (command, timeout) async {
          return CodingDiagnosticCommandOutput(
            exitCode: 2,
            stdout: machineLines.join('\n'),
          );
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
      );

      final payload = jsonDecode(result!.result) as Map<String, dynamic>;
      expect(payload['diagnostic_count'], 2);
      expect(payload['truncated_diagnostic_count'], 3);
    });

    test('returns only diagnostics introduced after the baseline', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_diagnostic_feedback_baseline_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'void main() {}\n',
      );

      var runCount = 0;
      final service = CodingDiagnosticFeedbackService(
        commandRunner: (command, timeout) async {
          runCount += 1;
          final diagnostics = [
            'WARNING|STATIC_WARNING|UNUSED_LOCAL_VARIABLE|${editedFile.path}|2|7|5|The value of the local variable is not used.',
            if (runCount > 1)
              'ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|${editedFile.path}|4|12|3|Undefined name newFailure.',
          ];
          return CodingDiagnosticCommandOutput(
            exitCode: 3,
            stdout: diagnostics.join('\n'),
          );
        },
      );

      final baseline = await service.captureBaseline(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
      );
      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
        baseline: baseline,
      );

      expect(result, isNotNull);
      final payload = jsonDecode(result!.result) as Map<String, dynamic>;
      expect(payload['baseline_applied'], isTrue);
      expect(payload['baseline_diagnostic_count'], 1);
      expect(payload['current_diagnostic_count'], 2);
      expect(payload['existing_diagnostic_count'], 1);
      expect(payload['diagnostic_count'], 1);
      final diagnostics = payload['diagnostics'] as List<dynamic>;
      expect(
        diagnostics.single,
        containsPair('message', 'Undefined name newFailure.'),
      );
      expect(jsonEncode(diagnostics), isNot(contains('local variable')));
    });

    test('records command fallback telemetry in the payload', () async {
      final root = await Directory.systemTemp.createTemp(
        'caverno_diagnostic_feedback_telemetry_',
      );
      addTearDown(() => root.delete(recursive: true));
      final editedFile = await _writeFile(
        root,
        'lib/main.dart',
        'void main() {}\n',
      );

      var runCount = 0;
      final service = CodingDiagnosticFeedbackService(
        commandRunner: (command, timeout) async {
          runCount += 1;
          if (runCount == 1) {
            return const CodingDiagnosticCommandOutput(
              exitCode: -1,
              timedOut: true,
            );
          }
          return CodingDiagnosticCommandOutput(
            exitCode: 3,
            stdout:
                'ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|${editedFile.path}|4|12|3|Undefined name telemetryFailure.',
          );
        },
      );

      final result = await service.buildFeedbackToolResult(
        projectRoot: root.path,
        changedPaths: [editedFile.path],
      );

      expect(result, isNotNull);
      final payload = jsonDecode(result!.result) as Map<String, dynamic>;
      final telemetry = payload['telemetry'] as Map<String, dynamic>;
      expect(telemetry['command_attempt_count'], 2);
      expect(telemetry['fallback_command_count'], 1);
      expect(telemetry['timed_out_command_count'], 1);
      expect(telemetry['start_error_command_count'], 0);
      expect(telemetry['duration_ms'], isA<int>());
      final attempts = telemetry['attempts'] as List<dynamic>;
      expect(attempts, hasLength(2));
      expect(attempts.first, containsPair('timed_out', true));
      expect(attempts.last, containsPair('diagnostic_count', 1));
      expect(
        payload['analyzer'],
        containsPair('executable', attempts.last['executable']),
      );
    });

    test(
      'falls back when the primary language diagnostics provider fails',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'caverno_diagnostic_feedback_lsp_fallback_',
        );
        addTearDown(() => root.delete(recursive: true));
        final editedFile = await _writeFile(
          root,
          'lib/main.dart',
          'void main() {}\n',
        );

        final service = CodingDiagnosticFeedbackService(
          provider: LanguageDiagnosticsBridgeFallbackProvider(
            primary: const _ThrowingDiagnosticProvider('lsp_server'),
            fallback: _SnapshotDiagnosticProvider(
              providerName: 'dart_analyzer',
              projectRoot: root.path,
              changedPaths: const ['lib/main.dart'],
              diagnostics: [
                CodeDiagnostic(
                  absolutePath: editedFile.path,
                  severity: 'Error',
                  line: 1,
                  column: 1,
                  message: 'Fallback diagnostic.',
                  code: 'fallback_error',
                  source: 'dart',
                ),
              ],
              bridge: LanguageDiagnosticsBridgeMetadata.dartAnalyzerCli(),
            ),
          ),
        );

        final result = await service.buildFeedbackToolResult(
          projectRoot: root.path,
          changedPaths: [editedFile.path],
        );

        expect(result, isNotNull);
        final payload = jsonDecode(result!.result) as Map<String, dynamic>;
        expect(payload['provider'], 'dart_analyzer');
        expect(payload['diagnostic_count'], 1);
        final bridge =
            payload['language_diagnostics_bridge'] as Map<String, dynamic>;
        expect(bridge['status'], 'degraded');
        expect(bridge['attempted_primary_provider'], 'lsp_server');
        expect(bridge['degrade_reason'], 'primary_failed');
      },
    );
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

class _ThrowingDiagnosticProvider implements CodingDiagnosticFeedbackProvider {
  const _ThrowingDiagnosticProvider(this.providerName);

  @override
  final String providerName;

  @override
  Future<CodingDiagnosticSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    throw StateError('Language server crashed.');
  }
}

class _SnapshotDiagnosticProvider implements CodingDiagnosticFeedbackProvider {
  const _SnapshotDiagnosticProvider({
    required this.providerName,
    required this.projectRoot,
    required this.changedPaths,
    required this.diagnostics,
    required this.bridge,
  });

  @override
  final String providerName;
  final String projectRoot;
  final List<String> changedPaths;
  final List<CodeDiagnostic> diagnostics;
  final LanguageDiagnosticsBridgeMetadata bridge;

  @override
  Future<CodingDiagnosticSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    return CodingDiagnosticSnapshot(
      providerName: providerName,
      projectRoot: Directory(this.projectRoot).absolute.path,
      changedPaths: this.changedPaths,
      diagnostics: diagnostics,
      telemetry: const CodingDiagnosticTelemetry(durationMs: 1, attempts: []),
      bridge: bridge,
    );
  }
}
