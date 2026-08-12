import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_authored_tool_dispatcher.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory outside;
  late _RecordingVerificationRunner verifier;
  late PersonalEvalAuthoredToolDispatcher dispatcher;

  setUp(() {
    root = Directory.systemTemp.createTempSync('authored_eval_tools_');
    outside = Directory.systemTemp.createTempSync('authored_eval_outside_');
    Directory('${root.path}/src').createSync();
    File('${root.path}/src/value.dart').writeAsStringSync('const value = 1;\n');
    File('${root.path}/bin_verify.dart').writeAsStringSync('protected\n');
    verifier = _RecordingVerificationRunner();
    dispatcher = PersonalEvalAuthoredToolDispatcher(
      root: root,
      verificationCommand: 'dart run bin/verify.dart',
      verificationRunner: verifier,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (outside.existsSync()) outside.deleteSync(recursive: true);
  });

  test('exposes only the bounded authored fixture tools', () {
    final names = dispatcher
        .getOpenAiToolDefinitions()
        .map((tool) => (tool['function'] as Map<String, dynamic>)['name'])
        .toList();

    expect(names, [
      'list_directory',
      'read_file',
      'edit_file',
      'write_file',
      'local_execute_command',
    ]);
  });

  test('allows a source edit inside the disposable workspace', () async {
    final result = await dispatcher.executeTool(
      name: 'edit_file',
      arguments: const {
        'path': 'src/value.dart',
        'old_text': 'value = 1',
        'new_text': 'value = 2',
      },
    );

    expect(result.isSuccess, isTrue);
    expect(
      File('${root.path}/src/value.dart').readAsStringSync(),
      contains('2'),
    );
  });

  test('rejects reads and writes outside the fixture', () async {
    final outsideFile = File('${outside.path}/secret.txt')
      ..writeAsStringSync('secret');

    final read = await dispatcher.executeTool(
      name: 'read_file',
      arguments: {'path': outsideFile.path},
    );
    final write = await dispatcher.executeTool(
      name: 'write_file',
      arguments: {'path': outsideFile.path, 'content': 'changed'},
    );

    expect(read.isSuccess, isFalse);
    expect(write.isSuccess, isFalse);
    expect(outsideFile.readAsStringSync(), 'secret');
  });

  test('rejects a fixture symlink that escapes the workspace', () async {
    final outsideFile = File('${outside.path}/secret.txt')
      ..writeAsStringSync('secret');
    Link('${root.path}/src/escape').createSync(outside.path);

    final read = await dispatcher.executeTool(
      name: 'read_file',
      arguments: const {'path': 'src/escape/secret.txt'},
    );
    final write = await dispatcher.executeTool(
      name: 'write_file',
      arguments: const {'path': 'src/escape/created.txt', 'content': 'escaped'},
    );

    expect(read.isSuccess, isFalse);
    expect(write.isSuccess, isFalse);
    expect(outsideFile.readAsStringSync(), 'secret');
    expect(File('${outside.path}/created.txt').existsSync(), isFalse);
  });

  test('rejects mutation of verifier and package metadata', () async {
    for (final path in ['bin_verify.dart', 'pubspec.yaml']) {
      final result = await dispatcher.executeTool(
        name: 'write_file',
        arguments: {'path': path, 'content': 'fake pass'},
      );
      expect(result.isSuccess, isFalse, reason: path);
    }

    expect(
      File('${root.path}/bin_verify.dart').readAsStringSync(),
      'protected\n',
    );
    expect(File('${root.path}/pubspec.yaml').existsSync(), isFalse);
  });

  test('runs only the exact verifier at the fixture root', () async {
    final rejectedCommand = await dispatcher.executeTool(
      name: 'local_execute_command',
      arguments: const {'command': 'rm -rf src'},
    );
    final rejectedDirectory = await dispatcher.executeTool(
      name: 'local_execute_command',
      arguments: {
        'command': 'dart run bin/verify.dart',
        'working_directory': '${root.path}/src',
      },
    );
    final accepted = await dispatcher.executeTool(
      name: 'local_execute_command',
      arguments: const {'command': 'dart run bin/verify.dart'},
    );

    expect(rejectedCommand.isSuccess, isFalse);
    expect(rejectedDirectory.isSuccess, isFalse);
    expect(accepted.isSuccess, isTrue);
    expect(verifier.commands, ['dart run bin/verify.dart']);
    expect(verifier.directories, [root.absolute.path]);
    expect(jsonDecode(accepted.result)['exit_code'], 0);
  });
}

class _RecordingVerificationRunner implements PersonalEvalVerificationRunner {
  final List<String> commands = [];
  final List<String> directories = [];

  @override
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  }) async {
    commands.add(command);
    directories.add(workingDirectory);
    return const PersonalEvalVerificationOutcome(
      result: PersonalEvalVerificationResult.passed,
      exitCode: 0,
      stdout: 'passed\n',
    );
  }
}
