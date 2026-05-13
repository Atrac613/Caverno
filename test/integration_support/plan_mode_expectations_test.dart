import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_expectations.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  group('assertPlanModeUiExpectations', () {
    testWidgets('validates visible and hidden phase text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: <Widget>[
              Text('Review the generated workflow'),
              Text('Approve plan'),
              Text('Approve plan'),
            ],
          ),
        ),
      );

      assertPlanModeUiExpectations(tester, const <PlanModeUiExpectation>[
        PlanModeUiExpectation.present(
          phase: PlanModeUiPhase.proposal,
          text: 'Approve plan',
          minCount: 2,
        ),
        PlanModeUiExpectation.absent(
          phase: PlanModeUiPhase.proposal,
          text: 'Missing action',
        ),
        PlanModeUiExpectation.absent(
          phase: PlanModeUiPhase.decision,
          text: 'Approve plan',
        ),
      ], PlanModeUiPhase.proposal);
    });
  });

  group('assertPlanModeLogExpectations', () {
    test('validates exact, min, and max counts', () {
      assertPlanModeLogExpectations(
        const <String>[
          'alpha event',
          'alpha again',
          'beta event',
          'gamma event',
        ],
        const <PlanModeLogExpectation>[
          PlanModeLogExpectation(pattern: 'alpha', exactCount: 2),
          PlanModeLogExpectation(pattern: 'beta', minCount: 1),
          PlanModeLogExpectation(pattern: 'delta', maxCount: 0),
        ],
      );
    });

    test('fails when a count is outside the expected range', () {
      expect(
        () => assertPlanModeLogExpectations(
          const <String>['alpha event'],
          const <PlanModeLogExpectation>[
            PlanModeLogExpectation(pattern: 'alpha', exactCount: 2),
          ],
        ),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('waitForPlanModeLogExpectationLowerBounds', () {
    testWidgets('waits until log lower bounds are satisfied', (tester) async {
      final logs = <String>['alpha event'];
      await tester.runAsync(() async {
        final timer = Timer(const Duration(milliseconds: 20), () {
          logs.add('alpha again');
          logs.add('beta event');
        });

        try {
          await waitForPlanModeLogExpectationLowerBounds(
            tester,
            logs,
            const <PlanModeLogExpectation>[
              PlanModeLogExpectation(pattern: 'alpha', minCount: 2),
              PlanModeLogExpectation(pattern: 'beta', exactCount: 1),
            ],
            timeout: const Duration(seconds: 1),
            useFramePump: false,
          );
        } finally {
          timer.cancel();
        }
      });

      expect(
        planModeLogLowerBoundsSatisfied(logs, const <PlanModeLogExpectation>[
          PlanModeLogExpectation(pattern: 'alpha', minCount: 2),
          PlanModeLogExpectation(pattern: 'beta', exactCount: 1),
        ]),
        isTrue,
      );
    });
  });
}
