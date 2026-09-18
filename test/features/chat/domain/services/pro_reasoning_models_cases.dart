part of 'chat_domain_services_test.dart';

void _runProReasoningModels() {
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
