import 'package:caverno/features/chat/application/runtime/duplicate_command_answer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DuplicateCommandAnswerPolicy.afterRecovery', () {
    const policy = DuplicateCommandAnswerPolicy();
    const output = 'test_watcher.py';

    String after(String recoveryText) =>
        policy.afterRecovery(recoveryText: recoveryText, previousAnswer: output);

    test('a written answer wins over the earlier output', () {
      expect(
        after('レビュー結果: test_watcher.py にテストがありません。'),
        'レビュー結果: test_watcher.py にテストがありません。',
      );
    });

    test('empty or thinking-only text falls back to the output', () {
      expect(after(''), output);
      expect(after('<think>reviewing the diff</think>'), output);
    });

    test('an inline tool call is not an answer', () {
      expect(
        after(
          'Checking again. <tool_use>{"name":"local_execute_command",'
          '"arguments":{"command":"git status"}}</tool_use>',
        ),
        output,
      );
      expect(after('<tool_call>{"name":"read_file"'), output);
    });
  });
}
