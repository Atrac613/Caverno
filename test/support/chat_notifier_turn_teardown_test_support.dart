import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

const expectedTurnReleaseObligations = [
  'pythonScriptRuntime',
  'fileMutationRuntime',
  'backgroundProcesses',
  'sshOwner',
  'conversationTaintState',
  'pendingToolApprovals',
  'toolApprovalCache',
  'hiddenAssistantEvidence',
  'contentToolTurns',
  'turnEnd',
  'goalCompletionEvidence',
  // Moved out of the generation-keyed destructor, which reached them by
  // looking the owner back up.
  'participantTurnControls',
  'askUserQuestionRuntime',
  'responseMetadata',
  'contextSurgeryObservations',
  'modelEditTelemetry',
  'modelSwitchCompaction',
];

void expectExactTurnTeardown(ChatNotifier notifier) {
  final stateReport = notifier.turnStateReportForTest();
  expect(
    stateReport.values,
    everyElement(isTrue),
    reason: 'A terminal turn left state populated: $stateReport',
  );
  final release = notifier.lastTurnReleaseReportForTest();
  expect(
    release,
    isNotNull,
    reason: 'The turn did not drop its release scope.',
  );
  expect(release!.$1, orderedEquals(expectedTurnReleaseObligations));
  expect(release.$2, orderedEquals(expectedTurnReleaseObligations));
}
