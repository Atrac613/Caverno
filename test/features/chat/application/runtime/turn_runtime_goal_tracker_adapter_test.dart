import 'dart:io';

import 'package:caverno/features/chat/application/runtime/turn_runtime_goal_tracker_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_tracker_registry.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:test/test.dart';

void main() {
  group('TurnRuntimeGoalTrackerAdapter', () {
    test('maps every continuation delta field', () {
      final adapter = _adapter();
      final owner = _owner('conversation-a', 3);
      const evidence = ToolResultCompletionEvidence(
        unresolvedErrorCount: 2,
        diagnosticSignature: 'diagnostic-a',
      );

      final snapshot = adapter.applyDelta(owner, (
        consecutiveAutoContinuationsDelta: 2,
        diagnosticRepairContinuationsDelta: 1,
        diagnosticRepairExtensionUsed: true,
        noProgressStreak: 4,
        consecutiveValidationMisses: 3,
        failedVerificationObserved: true,
        previousEvidence: evidence,
        previousDiagnosticSignature: 'diagnostic-a',
        identicalDiagnosticSignatureStreak: 2,
        pendingPostRepairReplayOutcome: true,
        pendingRepairContractOutcome: true,
        repairNoMutationRetryUsed: true,
        completionElicitationMutationGeneration: 8,
        markBudgetNoticePresented: false,
        removeTracker: false,
      ));

      expect(snapshot.consecutiveAutoContinuations, 2);
      expect(snapshot.diagnosticRepairContinuations, 1);
      expect(snapshot.diagnosticRepairExtensionUsed, isTrue);
      expect(snapshot.noProgressStreak, 4);
      expect(snapshot.consecutiveValidationMisses, 3);
      expect(snapshot.failedVerificationObserved, isTrue);
      expect(snapshot.previousEvidence?.unresolvedErrorCount, 2);
      expect(snapshot.previousDiagnosticSignature, 'diagnostic-a');
      expect(snapshot.identicalDiagnosticSignatureStreak, 2);
      expect(snapshot.pendingPostRepairReplayOutcome, isTrue);
      expect(snapshot.pendingRepairContractOutcome, isTrue);
      expect(snapshot.repairNoMutationRetryUsed, isTrue);
      expect(snapshot.completionElicitationMutationGeneration, 8);
    });

    test('shares conversation history across turn generations', () {
      final adapter = _adapter();
      final firstOwner = _owner('conversation-a', 3);
      final nextOwner = _owner('conversation-a', 4);

      adapter.applyDelta(firstOwner, _delta(noProgressStreak: 2));

      expect(adapter.snapshotFor(nextOwner).noProgressStreak, 2);
    });

    test('isolates tracker history between conversations', () {
      final adapter = _adapter();

      adapter.applyDelta(
        _owner('conversation-a', 3),
        _delta(noProgressStreak: 2),
      );

      expect(
        adapter.snapshotFor(_owner('conversation-b', 3)).noProgressStreak,
        0,
      );
    });

    test('clears only the pending repair contract outcome', () {
      final adapter = _adapter();
      final owner = _owner('conversation-a', 3);
      adapter.applyDelta(
        owner,
        _delta(noProgressStreak: 2, pendingRepairContractOutcome: true),
      );

      final snapshot = adapter.clearPendingRepairContract(owner);

      expect(snapshot.pendingRepairContractOutcome, isFalse);
      expect(snapshot.noProgressStreak, 2);
    });

    test('presents a budget notice once per conversation', () {
      final adapter = _adapter();
      final firstOwner = _owner('conversation-a', 3);
      final nextOwner = _owner('conversation-a', 4);

      expect(adapter.markBudgetNoticePresented(firstOwner), isTrue);
      expect(adapter.markBudgetNoticePresented(nextOwner), isFalse);
    });

    test('removes conversation tracker history', () {
      final adapter = _adapter();
      final owner = _owner('conversation-a', 3);
      adapter.applyDelta(owner, _delta(noProgressStreak: 2));

      adapter.removeTracker(owner);

      expect(adapter.snapshotFor(owner).noProgressStreak, 0);
      expect(adapter.markBudgetNoticePresented(owner), isTrue);
    });
  });

  test('adapter has no presentation or callback dependency', () {
    final source = File(
      'lib/features/chat/application/runtime/'
      'turn_runtime_goal_tracker_adapter.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(contains('ChatState')));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('typedef ')));
    expect(source, isNot(contains('Function(')));
  });
}

TurnRuntimeGoalTrackerAdapter _adapter() => TurnRuntimeGoalTrackerAdapter(
  registry: GoalAutoContinueTrackerRegistry(
    replayIdFactory: (generation) => 'replay-$generation',
  ),
);

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

GoalAutoContinueTrackerDelta _delta({
  int? noProgressStreak,
  bool? pendingRepairContractOutcome,
}) => (
  consecutiveAutoContinuationsDelta: 0,
  diagnosticRepairContinuationsDelta: 0,
  diagnosticRepairExtensionUsed: null,
  noProgressStreak: noProgressStreak,
  consecutiveValidationMisses: null,
  failedVerificationObserved: null,
  previousEvidence: null,
  previousDiagnosticSignature: null,
  identicalDiagnosticSignatureStreak: null,
  pendingPostRepairReplayOutcome: null,
  pendingRepairContractOutcome: pendingRepairContractOutcome,
  repairNoMutationRetryUsed: null,
  completionElicitationMutationGeneration: null,
  markBudgetNoticePresented: false,
  removeTracker: false,
);
