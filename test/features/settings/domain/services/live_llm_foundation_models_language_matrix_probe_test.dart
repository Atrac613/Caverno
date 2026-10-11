import 'dart:async';

import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_foundation_models_language_matrix_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final failedLabels in [
    <String>{},
    {'japanese_text'},
    {'english_tool_bridge'},
    {'english_text'},
    {'english_text', 'japanese_text', 'english_tool_bridge'},
  ]) {
    test('aggregates status with English baseline precedence: $failedLabels', () async {
      final cases = <FoundationModelsLanguageProbeCase>[];
      final result = await LiveLlmFoundationModelsLanguageMatrixProbe(
        complete: (testCase) async {
          cases.add(testCase);
          return FoundationModelsLanguageProbeOutcome(
            label: testCase.label,
            passed: !failedLabels.contains(testCase.label),
            classification: failedLabels.contains(testCase.label)
                ? 'missing_marker'
                : 'accepted',
            preview: 'reply ${testCase.marker}',
          );
        },
      ).run();
      expect(cases.map((value) => value.label), [
        'english_text',
        'japanese_text',
        'english_tool_bridge',
      ]);
      expect(cases.map((value) => value.withToolBridge), [false, false, true]);
      expect(cases.map((value) => value.marker), [
        'CAVERNO_FM_LANG_EN',
        'CAVERNO_FM_LANG_JA',
        'CAVERNO_FM_LANG_TOOL',
      ]);
      expect(cases.map((value) => value.userPrompt), [
        'Reply with exactly CAVERNO_FM_LANG_EN and no extra text.',
        '\u6b21\u306e\u6587\u5b57\u5217\u3060\u3051\u3092\u8fd4\u3057\u3066\u304f\u3060\u3055\u3044: CAVERNO_FM_LANG_JA',
        'A diagnostic tool is listed, but do not call it. Reply with exactly CAVERNO_FM_LANG_TOOL and no extra text.',
      ]);
      expect(result.id, 'foundation_models_language_matrix');
      expect(
        result.status,
        failedLabels.isEmpty
            ? LiveLlmDiagnosticStatus.passed
            : failedLabels.contains('english_text')
            ? LiveLlmDiagnosticStatus.failed
            : LiveLlmDiagnosticStatus.warning,
      );
      expect(
        result.summary,
        failedLabels.isEmpty
            ? 'Foundation Models accepted English, Japanese, and tool-bridge prompts.'
            : failedLabels.contains('english_text')
            ? 'Foundation Models rejected the English baseline prompt.'
            : 'English baseline passed, but at least one language matrix case was rejected.',
      );
      expect(result.passedChecks, 3 - failedLabels.length);
      expect(result.totalChecks, 3);
      expect(
        result.details,
        cases
            .map(
              (value) =>
                  '${value.label}: ${failedLabels.contains(value.label) ? 'failed (missing_marker)' : 'passed (accepted)'}',
            )
            .join('\n'),
      );
      expect(
        result.modelContent,
        cases
            .map((value) => '${value.label}: reply ${value.marker}')
            .join('\n'),
      );
    });
  }

  test(
    'awaits each completion and continues after a classified failure',
    () async {
      final first = Completer<FoundationModelsLanguageProbeOutcome>();
      final labels = <String>[];
      final pending = LiveLlmFoundationModelsLanguageMatrixProbe(
        complete: (testCase) async {
          labels.add(testCase.label);
          if (labels.length == 1) return first.future;
          return FoundationModelsLanguageProbeOutcome(
            label: testCase.label,
            passed: true,
            classification: 'accepted',
            preview: 'ok',
          );
        },
      ).run();
      await Future<void>.delayed(Duration.zero);
      expect(labels, ['english_text']);
      first.complete(
        const FoundationModelsLanguageProbeOutcome(
          label: 'english_text',
          passed: false,
          classification: 'provider_unavailable',
          preview: ' unavailable ',
        ),
      );
      final result = await pending;
      expect(labels, ['english_text', 'japanese_text', 'english_tool_bridge']);
      expect(result.passedChecks, 2);
      expect(
        result.details,
        startsWith('english_text: failed (provider_unavailable)'),
      );
    },
  );

  test('bounds each evidence preview independently', () async {
    final result = await LiveLlmFoundationModelsLanguageMatrixProbe(
      complete: (testCase) async => FoundationModelsLanguageProbeOutcome(
        label: testCase.label,
        passed: true,
        classification: 'accepted',
        preview: '  ${'x' * 300}  ',
      ),
    ).run();
    expect(result.modelContent.split('\n'), [
      for (final label in [
        'english_text',
        'japanese_text',
        'english_tool_bridge',
      ])
        '$label: ${'x' * 240}...',
    ]);
  });
}
