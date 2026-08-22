import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/duplicate_recovery_prompt_builder.dart';

void main() {
  const builder = DuplicateRecoveryPromptBuilder();
  final readFileCalls = [
    ToolCallInfo(
      id: 'tool-1',
      name: 'read_file',
      arguments: const {'path': 'js/main.js'},
    ),
  ];

  group('DuplicateRecoveryPromptBuilder', () {
    test('keeps the plain reuse instruction when nothing was shortened', () {
      final prompt = builder.buildFollowUpPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
      );

      expect(prompt, contains('Use the previous tool results'));
      expect(prompt, isNot(contains('shortened to fit the prompt budget')));
    });

    test('replaces the reuse instruction for a shortened result', () {
      // Session a0ca65b7: the guard told the model to reuse results the prompt
      // budget had cut, leaving the forbidden repeat as its only move.
      final prompt = builder.buildFollowUpPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
        budgetReducedToolNames: const {'read_file'},
      );

      expect(prompt, isNot(contains('Use the previous tool results')));
      expect(
        prompt,
        contains('The earlier read_file result was shortened to fit the '
            'prompt budget'),
      );
      expect(prompt, contains('offset, and a small limit'));
    });

    test('adds the range-read escape to the inspection prompt', () {
      final prompt = builder.buildInspectionPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
        budgetReducedToolNames: const {'read_file'},
      );

      expect(
        prompt,
        contains('Do not repeat identical read-only inspection tools'),
      );
      expect(prompt, contains('shortened to fit the prompt budget'));
      expect(prompt, contains('offset, and a small limit'));
    });

    test('ignores a shortened tool the model is not repeating', () {
      final prompt = builder.buildInspectionPrompt(
        toolCalls: readFileCalls,
        hasSavedTask: true,
        budgetReducedToolNames: const {'search_files'},
      );

      expect(prompt, isNot(contains('shortened to fit the prompt budget')));
    });
  });
}
