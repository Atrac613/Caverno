import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/git_tools.dart';

void main() {
  group('GitTools.normalizeCommand', () {
    test('strips a leading git binary prefix', () {
      expect(GitTools.normalizeCommand('git status --short'), 'status --short');
    });

    test('removes repeated git prefixes and control tokens', () {
      expect(
        GitTools.normalizeCommand(
          'git <|"|>git commit -m "Add tokyo_weather_next_week.csv"<|"|>',
        ),
        'commit -m "Add tokyo_weather_next_week.csv"',
      );
    });
  });

  group('GitTools.isReadOnly', () {
    test('classifies normalized prefixed commands correctly', () {
      expect(GitTools.isReadOnly('git status --short'), isTrue);
      expect(
        GitTools.isReadOnly(
          'git <|"|>git commit -m "Add tokyo_weather_next_week.csv"<|"|>',
        ),
        isFalse,
      );
    });

    test('classifies tag pattern listings as read-only', () {
      expect(
        GitTools.isReadOnly("tag -l '1.3.4*' --sort=-version:refname"),
        isTrue,
      );
      expect(
        GitTools.isReadOnly('tag --list 1.3.4* --sort=-version:refname'),
        isTrue,
      );
      expect(GitTools.isReadOnly('tag 1.3.4+15'), isFalse);
    });
  });

  group('GitTools.firstShellControlOperator', () {
    test('detects shell operators outside quotes', () {
      expect(
        GitTools.firstShellControlOperator(
          'add README.md && commit -m "Add README"',
        ),
        '&&',
      );
      expect(GitTools.firstShellControlOperator('status | cat'), '|');
      expect(GitTools.firstShellControlOperator('status > out.txt'), '>');
    });

    test('ignores shell-like text inside quotes', () {
      expect(
        GitTools.firstShellControlOperator(
          'commit -m "Document A && B; keep pipe | literal"',
        ),
        isNull,
      );
    });
  });

  group('GitTools.execute', () {
    test('runs init, commit, and revert lifecycle commands', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'git_tools_lifecycle_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      Map<String, dynamic> decode(String raw) =>
          jsonDecode(raw) as Map<String, dynamic>;

      final initResult = decode(
        await GitTools.execute(command: 'init', workingDirectory: tempDir.path),
      );
      expect(initResult['exit_code'], 0);
      expect(Directory('${tempDir.path}/.git').existsSync(), isTrue);

      await File('${tempDir.path}/sample.txt').writeAsString('hello\n');

      final emailResult = decode(
        await GitTools.execute(
          command: 'config user.email "canary@example.com"',
          workingDirectory: tempDir.path,
        ),
      );
      expect(emailResult['exit_code'], 0);

      final nameResult = decode(
        await GitTools.execute(
          command: 'config user.name "Canary Bot"',
          workingDirectory: tempDir.path,
        ),
      );
      expect(nameResult['exit_code'], 0);

      final addResult = decode(
        await GitTools.execute(
          command: 'add sample.txt',
          workingDirectory: tempDir.path,
        ),
      );
      expect(addResult['exit_code'], 0);

      final commitResult = decode(
        await GitTools.execute(
          command: 'commit -m "Add sample"',
          workingDirectory: tempDir.path,
        ),
      );
      expect(commitResult['exit_code'], 0);
      expect(File('${tempDir.path}/sample.txt').existsSync(), isTrue);

      final revertResult = decode(
        await GitTools.execute(
          command: 'revert --no-edit HEAD',
          workingDirectory: tempDir.path,
        ),
      );
      expect(revertResult['exit_code'], 0);
      expect(File('${tempDir.path}/sample.txt').existsSync(), isFalse);

      final statusResult = decode(
        await GitTools.execute(
          command: 'status --short',
          workingDirectory: tempDir.path,
        ),
      );
      expect(statusResult['exit_code'], 0);
      expect((statusResult['stdout'] as String).trim(), isEmpty);
    });

    test('rejects chained commands before execution', () async {
      final tempDir = await Directory.systemTemp.createTemp('git_tools_test_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Process.run('git', ['init'], workingDirectory: tempDir.path);
      await File('${tempDir.path}/README.md').writeAsString('hello\n');

      final raw = await GitTools.execute(
        command: 'add README.md && commit -m "Add README"',
        workingDirectory: tempDir.path,
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      expect(decoded['exit_code'], 2);
      expect(decoded['error'], contains('one git subcommand'));
      expect(decoded['error'], contains('&&'));
    });
  });
}
