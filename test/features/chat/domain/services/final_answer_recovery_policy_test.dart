import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/final_answer_recovery_policy.dart';

void main() {
  const policy = FinalAnswerRecoveryPolicy();

  group('FinalAnswerRecoveryPolicy', () {
    test('recovers provider-confirmed output truncation', () {
      for (final finishReason in const [
        'length',
        'MAX_TOKENS',
        'max_output_tokens',
      ]) {
        expect(
          policy.recoveryReason(
            content: 'A short partial answer.',
            finishReason: finishReason,
          ),
          FinalAnswerRecoveryReason.lengthTruncated,
          reason: finishReason,
        );
      }
    });

    test('detects a substantial line repeated throughout a long answer', () {
      const repeatedLine = 'Then `lib/src/todo_storage.dart` will be written.';
      final response = [
        List.filled(4, repeatedLine).join('\n'),
        List.filled(900, 'x').join(),
      ].join('\n');

      expect(
        policy.recoveryReason(content: response),
        FinalAnswerRecoveryReason.excessiveRepetition,
      );
    });

    test('does not retry short or non-repetitive final answers', () {
      expect(
        policy.recoveryReason(
          content: List.filled(4, 'Verification passed.').join('\n'),
        ),
        isNull,
      );
      expect(
        policy.recoveryReason(content: List.filled(900, 'x').join()),
        isNull,
      );
    });

    test('ignores repetition inside fenced code', () {
      const repeatedCode = 'print("This intentionally repeated code line");';
      final response = [
        '```dart',
        List.filled(8, repeatedCode).join('\n'),
        '```',
        List.filled(900, 'x').join(),
      ].join('\n');

      expect(policy.recoveryReason(content: response), isNull);
    });

    test('does not count fenced code toward the prose threshold', () {
      const repeatedLine = 'The same short prose status appears again.';
      final response = [
        '```text',
        List.filled(1200, 'x').join(),
        '```',
        List.filled(4, repeatedLine).join('\n'),
      ].join('\n');

      expect(policy.recoveryReason(content: response), isNull);
    });

    test('builds a bounded tool-free replacement instruction', () {
      final prompt = policy.buildRetryPrompt(
        FinalAnswerRecoveryReason.excessiveRepetition,
      );

      expect(prompt, contains('at most 400 words'));
      expect(prompt, contains('verified tool results'));
      expect(prompt, contains('Do not include internal reasoning'));
      expect(prompt, contains('tool calls'));
    });
  });
}
