import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

import '../../integration_test/test_support/plan_mode_planning_decisions.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  group('buildPlanModeLivePlanningDecisionAnswer', () {
    test('uses the first option when no scripted selection is present', () {
      final answer = buildPlanModeLivePlanningDecisionAnswer(_decision(), null);

      expect(answer.decisionId, 'format');
      expect(answer.optionId, 'json');
      expect(answer.optionLabel, 'JSON report');
    });

    test('matches scripted options with normalized labels', () {
      final answer = buildPlanModeLivePlanningDecisionAnswer(
        _decision(),
        const PlanModeScenarioDecisionSelection(
          question: 'Which report format?',
          optionLabel: '  "markdown   report"  ',
        ),
      );

      expect(answer.optionId, 'markdown');
      expect(answer.optionLabel, 'Markdown report');
    });

    test('uses scripted free text before options', () {
      final answer = buildPlanModeLivePlanningDecisionAnswer(
        _decision(allowFreeText: true),
        const PlanModeScenarioDecisionSelection(
          question: 'Which report format?',
          freeTextAnswer: '  Plain text  ',
        ),
      );

      expect(answer.optionId, 'free_text');
      expect(answer.optionLabel, 'Plain text');
    });

    test('throws when no option or free-text fallback is available', () {
      expect(
        () => buildPlanModeLivePlanningDecisionAnswer(
          _decision(options: const <WorkflowPlanningDecisionOption>[]),
          null,
        ),
        throwsStateError,
      );
    });
  });

  testWidgets('extracts visible decision questions while filtering controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: <Widget>[
            Text('Choose Before Planning'),
            Text('Continue with this choice'),
            Text('Which report format should the first slice generate?'),
            Text('Cancel'),
          ],
        ),
      ),
    );

    expect(
      extractVisiblePlanModeDecisionQuestion(tester),
      'Which report format should the first slice generate?',
    );
  });
}

WorkflowPlanningDecision _decision({
  bool allowFreeText = false,
  List<WorkflowPlanningDecisionOption>
  options = const <WorkflowPlanningDecisionOption>[
    WorkflowPlanningDecisionOption(id: 'json', label: 'JSON report'),
    WorkflowPlanningDecisionOption(id: 'markdown', label: 'Markdown report'),
  ],
}) {
  return WorkflowPlanningDecision(
    id: 'format',
    question: 'Which report format?',
    allowFreeText: allowFreeText,
    options: options,
  );
}
