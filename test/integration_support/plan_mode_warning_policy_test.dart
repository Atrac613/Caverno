import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_warning_policy.dart';

void main() {
  group('summarizeScenarioWarnings', () {
    test(
      'allows recovered create parse warnings after later recovery markers',
      () {
        const warning =
            '[LLM] Recovered raw text response after create parse failure';
        final summary = summarizeScenarioWarnings(
          warnings: const <String>[warning],
          allowedPatterns: const <String>[],
          logs: const <String>[
            '[Workflow] Task status changed: Create README.md -> completed',
            warning,
            '[Memory] Failed to parse LLM memory extraction JSON (falling back to rule-based)',
          ],
        );

        expect(summary.allowedWarnings, contains(warning));
        expect(summary.unexpectedWarnings, isEmpty);
      },
    );

    test('keeps unrecovered create parse warnings unexpected', () {
      const warning =
          '[LLM] Recovered raw text response after create parse failure';
      final summary = summarizeScenarioWarnings(
        warnings: const <String>[warning],
        allowedPatterns: const <String>[],
        logs: const <String>['[Workflow] Task proposal ready', warning],
      );

      expect(summary.allowedWarnings, isEmpty);
      expect(summary.unexpectedWarnings, contains(warning));
    });

    test('still respects explicitly allowed warning patterns', () {
      const warning = '[Workflow] Workflow proposal recovered on retry';
      final summary = summarizeScenarioWarnings(
        warnings: const <String>[warning],
        allowedPatterns: const <String>[
          '[Workflow] Workflow proposal recovered on retry',
        ],
        logs: const <String>[warning],
      );

      expect(summary.allowedWarnings, contains(warning));
      expect(summary.unexpectedWarnings, isEmpty);
    });

    test('allows post-completion memory extraction transport warnings', () {
      const createWarning =
          '[LLM] createChatCompletion error: ClientException: Connection closed before full header was received';
      const memoryWarning =
          '[Memory] LLM memory extraction error: ClientException: Connection closed before full header was received';
      final summary = summarizeScenarioWarnings(
        warnings: const <String>[createWarning, memoryWarning],
        allowedPatterns: const <String>[],
        logs: const <String>[
          '[LLM] ========== streamChatCompletion ==========',
          '[LLM] Final answer content',
          createWarning,
          memoryWarning,
        ],
      );

      expect(summary.allowedWarnings, contains(createWarning));
      expect(summary.allowedWarnings, contains(memoryWarning));
      expect(summary.unexpectedWarnings, isEmpty);
    });

    test(
      'allows continuation stream disconnect warnings after validation reaches memory extraction',
      () {
        const streamWarning =
            '[LLM] streamChatCompletion error: ClientException: Connection closed before full header was received';
        const notifierWarning =
            '[ChatNotifier] _continueAfterContentToolResults onError: ClientException: Connection closed before full header was received';
        final summary = summarizeScenarioWarnings(
          warnings: const <String>[streamWarning, notifierWarning],
          allowedPatterns: const <String>[],
          logs: const <String>[
            '[ContentTool]   - local_execute_command: {command: python3 test_ping.py}',
            streamWarning,
            notifierWarning,
            '[LLM] ========== createChatCompletion ==========',
            '[LLM]   [0] system: You extract reusable user memory from a conversation.',
            '[Memory] LLM memory extraction succeeded',
          ],
        );

        expect(summary.allowedWarnings, contains(streamWarning));
        expect(summary.allowedWarnings, contains(notifierWarning));
        expect(summary.unexpectedWarnings, isEmpty);
      },
    );
  });
}
