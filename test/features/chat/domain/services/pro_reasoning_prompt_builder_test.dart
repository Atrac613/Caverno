import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_prompt_builder.dart';

void main() {
  const builder = ProReasoningPromptBuilder();

  group('frame parsing', () {
    test('extracts a fenced JSON object and bounds list fields', () {
      final frame = builder.parseFrame('''
Model preamble.
```json
{
  "sub_questions": [" A ", "B", "C", "D", "E", "ignored"],
  "investigation_steps": [" Inspect evidence "],
  "success_criteria": [" Be correct "],
  "requires_investigation": true
}
```
''', 'Fallback question');

      expect(frame.subQuestions, ['A', 'B', 'C', 'D', 'E']);
      expect(frame.investigationSteps, ['Inspect evidence']);
      expect(frame.successCriteria, ['Be correct']);
      expect(frame.requiresInvestigation, isTrue);
    });

    test('falls back safely when the model does not return JSON', () {
      final frame = builder.parseFrame(
        'I cannot produce the requested object.',
        '  Original question  ',
      );

      expect(frame.subQuestions, ['Original question']);
      expect(frame.investigationSteps, isEmpty);
      expect(frame.successCriteria, hasLength(2));
      expect(frame.requiresInvestigation, isFalse);
    });
  });

  test(
    'candidate prompts keep a shared prefix and vary only in the suffix',
    () {
      const frame = ProReasoningFrame(
        subQuestions: ['Correctness', 'Operational risk'],
        investigationSteps: [],
        successCriteria: ['Ground claims', 'State tradeoffs'],
        requiresInvestigation: false,
      );
      final prefix = builder.buildCandidateSharedPrefix(
        question: 'Choose an approach.',
        frame: frame,
        evidence: 'Measured fact.',
      );
      final correctnessPrompt = builder.buildCandidatePrompt(
        sharedPrefix: prefix,
        angle: 'Focus on correctness.',
      );
      final riskPrompt = builder.buildCandidatePrompt(
        sharedPrefix: prefix,
        angle: 'Focus on operational risk.',
      );

      expect(correctnessPrompt.substring(0, prefix.length), prefix);
      expect(riskPrompt.substring(0, prefix.length), prefix);
      expect(prefix, isNot(contains('Focus on correctness.')));
      expect(prefix, isNot(contains('Focus on operational risk.')));
      expect(
        prefix,
        allOf(
          contains('Treat explicit evidence limitations as hard constraints'),
          contains('external resource does not exist merely because'),
        ),
      );
      expect(
        correctnessPrompt.indexOf('## Candidate assignment'),
        prefix.length + 2,
      );
      expect(correctnessPrompt, endsWith('ensemble or this assignment.'));
      expect(riskPrompt, endsWith('ensemble or this assignment.'));
    },
  );

  group('critique parsing', () {
    final candidates = [
      _candidate(2, 'First answer'),
      _candidate(7, 'Second answer'),
    ];

    test('uses surviving candidate indices in the JSON response example', () {
      final prompt = builder.buildCritiquePrompt(
        question: 'Choose the best answer.',
        frame: const ProReasoningFrame(
          subQuestions: ['Which answer is grounded?'],
          investigationSteps: [],
          successCriteria: ['Use the evidence'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured fact.',
        candidates: candidates,
      );

      expect(prompt, contains('"winner_index": 2'));
      expect(prompt, contains('"ranking": [2,7]'));
      expect(prompt, isNot(contains('"winner_index": 0')));
    });

    test('filters invalid indices and accepts JSON embedded in prose', () {
      final critique = builder.parseCritique(
        '''Result: {"winner_index":"7","ranking":[7,99,2,7],"contradictions":[" conflict "],"assessment":" solid "}''',
        candidates,
      );

      expect(critique.winnerIndex, 7);
      expect(critique.ranking, [7, 2]);
      expect(critique.contradictions, ['conflict']);
      expect(critique.assessment, 'solid');
    });

    test('falls back to the first surviving candidate on malformed JSON', () {
      final critique = builder.parseCritique('not-json', candidates);

      expect(critique.winnerIndex, 2);
      expect(critique.ranking, [2, 7]);
      expect(critique.contradictions, isEmpty);
      expect(critique.assessment, contains('first surviving candidate'));
    });
  });
}

ProReasoningCandidate _candidate(int index, String answer) {
  return ProReasoningCandidate(
    index: index,
    answer: answer,
    angle: 'Angle $index',
    model: 'test-model',
    endpointId: 'endpoint',
    endpointLabel: 'Endpoint',
    thinkingRequested: true,
    thinkingObserved: false,
    duration: Duration.zero,
  );
}
