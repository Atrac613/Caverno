import 'package:caverno/features/chat/domain/services/goal_completion_shadow.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agreement (no disagreement recorded)', () {
    test('both complete', () {
      expect(
        GoalCompletionShadow.compare(
          toolCompletionOutcome: GoalUpdateAckOutcome.completionRecorded,
          lexicalCompleted: true,
        ),
        isNull,
      );
    });

    test('both reject', () {
      expect(
        GoalCompletionShadow.compare(
          toolCompletionOutcome: GoalUpdateAckOutcome.completionRejected,
          lexicalCompleted: false,
        ),
        isNull,
      );
    });

    test('neither acts', () {
      expect(
        GoalCompletionShadow.compare(
          toolCompletionOutcome: null,
          lexicalCompleted: false,
        ),
        isNull,
      );
    });

    test('a progress-only tool call is not a completion claim', () {
      expect(
        GoalCompletionShadow.compare(
          toolCompletionOutcome: GoalUpdateAckOutcome.progressLogged,
          lexicalCompleted: false,
        ),
        isNull,
      );
    });
  });

  group('disagreement', () {
    test('tool accepted, lexical missed — the case the tool fixes', () {
      expect(
        GoalCompletionShadow.compare(
          toolCompletionOutcome: GoalUpdateAckOutcome.completionRecorded,
          lexicalCompleted: false,
        ),
        GoalCompletionShadowDisagreement.toolAcceptedLexicalMissed,
      );
    });

    test('tool rejected, lexical completed — the tool is stricter', () {
      expect(
        GoalCompletionShadow.compare(
          toolCompletionOutcome: GoalUpdateAckOutcome.completionRejected,
          lexicalCompleted: true,
        ),
        GoalCompletionShadowDisagreement.toolRejectedLexicalCompleted,
      );
    });

    test('lexical completed on prose with no tool completion', () {
      expect(
        GoalCompletionShadow.compare(
          toolCompletionOutcome: null,
          lexicalCompleted: true,
        ),
        GoalCompletionShadowDisagreement.lexicalCompletedToolSilent,
      );
    });
  });

  test('every disagreement has a stable, distinct label', () {
    final labels = GoalCompletionShadowDisagreement.values
        .map(GoalCompletionShadow.labelFor)
        .toSet();
    expect(labels.length, GoalCompletionShadowDisagreement.values.length);
    expect(
      labels,
      containsAll(<String>[
        'goal_completion_tool_accepted_lexical_missed',
        'goal_completion_lexical_only',
        'goal_completion_tool_rejected_lexical_completed',
      ]),
    );
  });
}
