import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/bounded_command_output.dart';
import 'package:caverno/features/chat/data/datasources/local_shell_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps small output verbatim and ignores empty chunks', () {
    final output = BoundedCommandOutput(60)
      ..add('first\n')
      ..add('')
      ..add('last\n');
    expect(output.text, 'first\nlast\n');
    expect(output.truncated, isFalse);
  });

  for (final chunkSize in [1, 7, 10000]) {
    test(
      'keeps the failure tail within the limit with chunks of $chunkSize',
      () {
        final source =
            'START\n${'x' * 1000}\nAssertionError: required check failed\n';
        final output = BoundedCommandOutput(120);
        for (var index = 0; index < source.length; index += chunkSize) {
          output.add(
            source.substring(
              index,
              (index + chunkSize).clamp(0, source.length),
            ),
          );
        }
        expect(output.text.length, 120);
        expect(output.text, startsWith('START\n'));
        expect(
          output.text,
          endsWith('AssertionError: required check failed\n'),
        );
        expect(output.text, contains(BoundedCommandOutput.omission));
        expect(output.truncated, isTrue);
      },
    );
  }

  test('tiny budgets remain bounded', () {
    final output = BoundedCommandOutput(3)
      ..add('abcdef')
      ..add('gh');
    expect(output.text, 'agh');
    expect(output.truncated, isTrue);
  });

  test('native execution retains a failure after a large traceback', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('command_tail_');
    addTearDown(() => root.delete(recursive: true));
    final executed = await LocalShellTools.executeResult(
      command:
          "printf 'START\\n'; printf '%16000s' x; printf '\\nAssertionError: module missing\\n'; exit 1",
      workingDirectory: root.path,
    );
    final payload = jsonDecode(executed.result) as Map<String, dynamic>;
    expect(executed.outcome?.exitCode, 1);
    expect(payload['stdout_truncated'], isTrue);
    expect((payload['stdout'] as String).length, 12000);
    expect(payload['stdout'], startsWith('START\n'));
    expect(payload['stdout'], endsWith('AssertionError: module missing\n'));
  });
}
