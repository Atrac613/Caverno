import 'package:flutter_test/flutter_test.dart';

import 'plan_mode_scenario_spec.dart';

void assertPlanModeUiExpectations(
  WidgetTester tester,
  List<PlanModeUiExpectation> expectations,
  PlanModeUiPhase phase,
) {
  for (final expectation in expectations.where((item) => item.phase == phase)) {
    final finder = find.textContaining(expectation.text);
    if (expectation.shouldBePresent) {
      expect(
        finder,
        findsAtLeastNWidgets(expectation.minCount),
        reason:
            'Expected UI to show "${expectation.text}" during $phase at least ${expectation.minCount} time(s).',
      );
    } else {
      expect(
        finder,
        findsNothing,
        reason: 'Expected UI to hide "${expectation.text}" during $phase.',
      );
    }
  }
}

void assertPlanModeLogExpectations(
  List<String> logs,
  List<PlanModeLogExpectation> expectations,
) {
  for (final expectation in expectations) {
    final count = countPlanModeLogsMatching(logs, expectation.pattern);

    if (expectation.exactCount != null) {
      expect(
        count,
        expectation.exactCount,
        reason:
            'Expected exactly ${expectation.exactCount} log(s) containing "${expectation.pattern}".',
      );
    }
    if (expectation.minCount != null) {
      expect(
        count,
        greaterThanOrEqualTo(expectation.minCount!),
        reason:
            'Expected at least ${expectation.minCount} log(s) containing "${expectation.pattern}".',
      );
    }
    if (expectation.maxCount != null) {
      expect(
        count,
        lessThanOrEqualTo(expectation.maxCount!),
        reason:
            'Expected at most ${expectation.maxCount} log(s) containing "${expectation.pattern}".',
      );
    }
  }
}

Future<void> waitForPlanModeLogExpectationLowerBounds(
  WidgetTester tester,
  List<String> logs,
  List<PlanModeLogExpectation> expectations, {
  Duration timeout = const Duration(seconds: 5),
  bool useFramePump = true,
}) async {
  if (planModeLogLowerBoundsSatisfied(logs, expectations)) {
    return;
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (useFramePump) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (planModeLogLowerBoundsSatisfied(logs, expectations)) {
      return;
    }
  }
}
