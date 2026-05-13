import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_workflow_execution_completion.dart';

void main() {
  test('caps blocked workflow timeout at fifteen seconds', () {
    expect(
      resolvePlanModeBlockedWorkflowTimeout(const Duration(seconds: 3)),
      const Duration(seconds: 3),
    );
    expect(
      resolvePlanModeBlockedWorkflowTimeout(const Duration(seconds: 15)),
      const Duration(seconds: 15),
    );
    expect(
      resolvePlanModeBlockedWorkflowTimeout(const Duration(seconds: 45)),
      const Duration(seconds: 15),
    );
  });
}
