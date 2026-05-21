import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';

import '../../integration_test/test_support/plan_mode_post_scenario_settle.dart';

void main() {
  test('serializes post-scenario settle result', () {
    expect(
      const PlanModePostScenarioSettleResult(
        initiallySettled: false,
        settled: true,
        cancellationUsed: true,
      ).toJson(),
      const <String, bool>{
        'initiallySettled': false,
        'settled': true,
        'cancellationUsed': true,
      },
    );
  });

  test('detects pending approval state used by the scenario harness', () {
    expect(chatStateHasPlanModePendingApprovals(ChatState.initial()), isFalse);

    final pendingLocalCommand = PendingLocalCommand(
      id: 'local-1',
      command: 'echo ok',
      workingDirectory: '/tmp',
      reason: 'Verify pending approval detection.',
      warningTitle: null,
      warningMessage: null,
      completer: Completer<LocalCommandApproval>(),
    );

    expect(
      chatStateHasPlanModePendingApprovals(
        ChatState.initial().copyWith(pendingLocalCommand: pendingLocalCommand),
      ),
      isTrue,
    );
  });
}
