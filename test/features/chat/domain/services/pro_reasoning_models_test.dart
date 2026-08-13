import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test('depth presets expose measured candidate and time budgets', () {
    expect(
      ProReasoningDepth.values.map(
        (depth) => (
          candidates: depth.candidateCount,
          deadline: depth.deadline,
          investigationIterations: depth.investigationIterations,
        ),
      ),
      [
        (
          candidates: 2,
          deadline: const Duration(minutes: 6),
          investigationIterations: 4,
        ),
        (
          candidates: 3,
          deadline: const Duration(minutes: 10),
          investigationIterations: 6,
        ),
        (
          candidates: 4,
          deadline: const Duration(minutes: 20),
          investigationIterations: 10,
        ),
      ],
    );
  });

  test('fallback frame preserves the trimmed original question', () {
    final frame = ProReasoningFrame.fallback('  What should we ship?  ');

    expect(frame.subQuestions, ['What should we ship?']);
    expect(frame.investigationSteps, isEmpty);
    expect(frame.successCriteria, hasLength(2));
    expect(frame.requiresInvestigation, isFalse);
  });
}
