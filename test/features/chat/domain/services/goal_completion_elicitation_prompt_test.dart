import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/goal_completion_elicitation_prompt.dart';

void main() {
  test('names the tool and offers all three answers', () {
    final prompt = GoalCompletionElicitationPrompt.build(languageCode: 'ja');

    expect(prompt, contains('update_goal'));
    // Reporting remaining work must stay a first-class answer: an elicitation
    // that only offered completion would be leading, and a false completion
    // ends the run.
    expect(prompt, contains('completed: true'));
    expect(prompt, contains('message'));
    expect(prompt, contains('blocked_reason'));
    expect(prompt, contains('"ja"'));
  });

  test('falls back to en for a blank language code', () {
    expect(
      GoalCompletionElicitationPrompt.build(languageCode: '   '),
      contains('"en"'),
    );
  });
}
