part of 'chat_domain_services_test.dart';

void _runGoalCompletionElicitationPrompt() {
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
