import 'package:caverno/core/types/goal_completion_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tool policy never asks at a completion boundary', () {
    expect(
      GoalCompletionPolicy.tool.shouldAskImmediatelyAtBoundary(
        budgetExhausted: true,
        noRemainingWork: true,
      ),
      isFalse,
    );
    expect(GoalCompletionPolicy.tool.allowsCompletionElicitation, isFalse);
  });

  test('tool-or-ask asks at budget exhaustion after tool silence', () {
    expect(
      GoalCompletionPolicy.toolOrAsk.shouldAskImmediatelyAtBoundary(
        budgetExhausted: true,
        noRemainingWork: false,
      ),
      isTrue,
    );
    expect(GoalCompletionPolicy.toolOrAsk.allowsCompletionElicitation, isTrue);
  });

  test('ask policy reaches confirmation without a tool call', () {
    expect(
      GoalCompletionPolicy.ask.shouldAskImmediatelyAtBoundary(
        budgetExhausted: false,
        noRemainingWork: true,
      ),
      isTrue,
    );
    expect(GoalCompletionPolicy.ask.acceptsToolCompletion, isFalse);
    expect(GoalCompletionPolicy.ask.allowsCompletionElicitation, isFalse);
  });
}
