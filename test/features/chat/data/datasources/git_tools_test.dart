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
