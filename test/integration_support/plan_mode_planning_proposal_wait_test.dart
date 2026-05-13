import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_planning_proposal_wait.dart';

void main() {
  test('builds a stable planning progress key from observable state', () {
    final key = buildPlanModePlanningProgressKey(
      messageCount: 3,
      workflowDraftAvailable: true,
      taskDraftAvailable: false,
      workflowDraftPersisted: true,
      taskDraftPersisted: false,
      isGeneratingWorkflowProposal: false,
      isGeneratingTaskProposal: true,
      hasPendingDecision: false,
      workflowError: null,
      taskError: 'retry task proposal',
      workflowDraftReadyLogSeen: true,
      taskDraftReadyLogSeen: false,
      approvalUiReady: true,
    );

    expect(
      key,
      '3|true|false|true|false|false|true|false|null|retry task proposal|true|false|true',
    );
  });

  test('changes progress key when the approval UI becomes ready', () {
    final beforeApproval = buildPlanModePlanningProgressKey(
      messageCount: 3,
      workflowDraftAvailable: true,
      taskDraftAvailable: true,
      workflowDraftPersisted: true,
      taskDraftPersisted: true,
      isGeneratingWorkflowProposal: false,
      isGeneratingTaskProposal: false,
      hasPendingDecision: false,
      workflowError: null,
      taskError: null,
      workflowDraftReadyLogSeen: true,
      taskDraftReadyLogSeen: true,
      approvalUiReady: false,
    );
    final afterApproval = buildPlanModePlanningProgressKey(
      messageCount: 3,
      workflowDraftAvailable: true,
      taskDraftAvailable: true,
      workflowDraftPersisted: true,
      taskDraftPersisted: true,
      isGeneratingWorkflowProposal: false,
      isGeneratingTaskProposal: false,
      hasPendingDecision: false,
      workflowError: null,
      taskError: null,
      workflowDraftReadyLogSeen: true,
      taskDraftReadyLogSeen: true,
      approvalUiReady: true,
    );

    expect(beforeApproval, isNot(afterApproval));
  });
}
