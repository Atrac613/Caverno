import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/built_in_local_command_mutation_preflight.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fence_refusal');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Map<String, dynamic> arguments(String command) => {
    'command': command,
    'working_directory': root.path,
    'allowed_read_root': root.path,
  };

  test(
    'names the refusal the executor would return for session 1afd70a6',
    () async {
      // `2>&1` keeps this off the internal read-only path, so the mutation
      // fence treats the outside operand as a write target. Approval cannot
      // change that, which is why the caller asks before approval.
      final refusal = await builtInLocalCommandFenceRefusal(
        toolName: 'local_execute_command',
        arguments: arguments(
          'ls -la /Library/Frameworks/Python.framework/Versions/ 2>&1',
        ),
      );

      expect(refusal, isNotNull);
      expect(
        (jsonDecode(refusal!.result) as Map)['code'],
        'project_mutation_outside_root',
      );
    },
  );

  test('an internal read outside the root is refused as a read', () async {
    final refusal = await builtInLocalCommandFenceRefusal(
      toolName: 'local_execute_command',
      arguments: arguments('ls -la /Library/Frameworks/'),
    );

    expect(refusal, isNotNull);
    expect(refusal!.isSuccess, isFalse);
  });

  test('commands inside the root and other tools pass through', () async {
    for (final command in [
      'ls -la 2>&1',
      '.venv/bin/python -m pytest -q 2>&1 | tail -5',
      '/usr/local/bin/python3 -m pytest --version 2>&1 | head -2',
    ]) {
      expect(
        await builtInLocalCommandFenceRefusal(
          toolName: 'local_execute_command',
          arguments: arguments(command),
        ),
        isNull,
        reason: command,
      );
    }
    expect(
      await builtInLocalCommandFenceRefusal(
        toolName: 'run_tests',
        arguments: arguments('ls /Library 2>&1'),
      ),
      isNull,
    );
  });
}
