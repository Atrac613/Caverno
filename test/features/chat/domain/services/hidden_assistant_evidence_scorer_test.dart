import 'package:caverno/features/chat/domain/services/hidden_assistant_evidence_scorer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HiddenAssistantEvidenceScorer', () {
    const scoreMatrix = <String, int>{
      '': 0,
      '   ': 0,
      'Hidden draft only': 0,
      'Visible assistant response': 0,
      'Task complete': 2,
      'Task completed': 2,
      'VALIDATION PASSED': 2,
      'Tests passed': 2,
      'The run was successful': 2,
      'Next task': 1,
      'Saved task in the plan': 1,
      'Task failed': 0,
      'Task complete but tests failed': 2,
      'Validation passed but deployment failed': 2,
      'Task incomplete': 2,
      'Task complete; tests passed; next task': 5,
    };

    for (final entry in scoreMatrix.entries) {
      test('scores ${entry.key.isEmpty ? 'empty text' : entry.key}', () {
        expect(HiddenAssistantEvidenceScorer.score(entry.key), entry.value);
      });
    }
  });
}
