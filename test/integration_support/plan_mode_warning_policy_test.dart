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
  });
}
