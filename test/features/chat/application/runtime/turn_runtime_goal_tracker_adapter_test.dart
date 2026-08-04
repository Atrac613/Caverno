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
      final registry = _registry();
      final owner = _owner('conversation-a', 3);
      const evidence = ToolResultCompletionEvidence(
        unresolvedErrorCount: 2,
        diagnosticSignature: 'diagnostic-a',
      );

      final snapshot = adapterFor(registry, owner).applyDelta((
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
      final registry = _registry();
      final firstOwner = _owner('conversation-a', 3);
      final nextOwner = _owner('conversation-a', 4);

      adapterFor(registry, firstOwner).applyDelta(_delta(noProgressStreak: 2));

      expect(adapterFor(registry, nextOwner).snapshot.noProgressStreak, 2);
    });

    test('isolates tracker history between conversations', () {
      final registry = _registry();
      adapterFor(
        registry,
        _owner('conversation-a', 3),
      ).applyDelta(_delta(noProgressStreak: 2));

      expect(
        adapterFor(
          registry,
          _owner('conversation-b', 3),
        ).snapshot.noProgressStreak,
        0,
      );
    });

    test('clears only the pending repair contract outcome', () {
      final registry = _registry();
      final owner = _owner('conversation-a', 3);
      adapterFor(registry, owner).applyDelta(
        _delta(noProgressStreak: 2, pendingRepairContractOutcome: true),
      );

      final snapshot = adapterFor(registry, owner).clearPendingRepairContract();

      expect(snapshot.pendingRepairContractOutcome, isFalse);
      expect(snapshot.noProgressStreak, 2);
    });

    test('presents a budget notice once per conversation', () {
      final registry = _registry();
      final firstOwner = _owner('conversation-a', 3);
      final nextOwner = _owner('conversation-a', 4);

      expect(
        adapterFor(registry, firstOwner).markBudgetNoticePresented(),
        isTrue,
      );
      expect(
        adapterFor(registry, nextOwner).markBudgetNoticePresented(),
        isFalse,
      );
    });

    test('removes conversation tracker history', () {
      final registry = _registry();
      final owner = _owner('conversation-a', 3);
      adapterFor(registry, owner).applyDelta(_delta(noProgressStreak: 2));

      adapterFor(registry, owner).removeTracker();

      expect(adapterFor(registry, owner).snapshot.noProgressStreak, 0);
      expect(adapterFor(registry, owner).markBudgetNoticePresented(), isTrue);
    });
  });

  test('adapter has no presentation or callback dependency', () {
    final source = _codeWithoutComments(
      'lib/features/chat/application/runtime/'
      'turn_runtime_goal_tracker_adapter.dart',
    );

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(contains('ChatState')));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('typedef ')));
    expect(source, isNot(contains('Function(')));
  });
}

GoalAutoContinueTrackerRegistry _registry() => GoalAutoContinueTrackerRegistry(
  replayIdFactory: (generation) => 'replay-$generation',
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

/// The decomposition audit requires a
/// `// ChatNotifier decomposition collaborator` marker in every
/// registered collaborator, so a bare substring search would read that
/// marker as the dependency it forbids. Strip comments first: the rule
/// is about code, not about what a comment names.
String _codeWithoutComments(String path) {
  final source = File(path).readAsStringSync();
  return source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .split('\n')
      .map((line) {
        final index = line.indexOf('//');
        return index == -1 ? line : line.substring(0, index);
      })
      .join('\n');
}

TurnRuntimeGoalTrackerAdapter adapterFor(
  GoalAutoContinueTrackerRegistry registry,
  ChatTurnOwner owner,
) => TurnRuntimeGoalTrackerAdapter(registry: registry, owner: owner);
