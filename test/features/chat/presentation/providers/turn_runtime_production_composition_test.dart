import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime_conversation_goal_adapter.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime_goal_tracker_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_tracker_registry.dart';
import 'package:caverno/features/chat/presentation/providers/turn_runtime_production_composition.dart';
import 'package:test/test.dart';

void main() {
  group('TurnRuntimeProductionComposition', () {
    test('binds all five ports to one exact owner', () {
      final owner = _owner('conversation-a', 3);
      final conversation = _conversation('conversation-a');
      final lease = _OwnerLease(owner);
      final safeBoundary = _SafeBoundary();
      final composition = _composition(
        ownerLease: lease,
        conversationGoalStore: _GoalStore({'conversation-a': conversation}),
        safeBoundary: safeBoundary,
      );

      final scope = composition.create(
        owner: owner,
        loggingSettingsEnabled: false,
        loggingEnvironment: const {},
      );
      final runtime = scope.runtime;

      expect(runtime.owner, same(owner));
      expect(runtime.goalContinuation.ownerLease, same(lease));
      expect(
        runtime.goalContinuation.conversationGoal,
        isA<TurnRuntimeConversationGoalAdapter>(),
      );
      expect(
        runtime.goalContinuation.conversationGoal.conversationFor(owner),
        same(conversation),
      );
      expect(
        runtime.goalContinuation.tracker,
        isA<TurnRuntimeGoalTrackerAdapter>(),
      );
      expect(runtime.goalContinuation.safeBoundary, same(safeBoundary));
      expect(runtime.goalContinuation.log, isNotNull);
      expect(scope.loggingEnabled, isFalse);
    });

    test('shares tracker history but not turn-local scheduling state', () {
      final composition = _composition(
        ownerLease: _OwnerLease(_owner('conversation-a', 3)),
        conversationGoalStore: _GoalStore(const {}),
        safeBoundary: _SafeBoundary(),
      );
      final first = composition.create(
        owner: _owner('conversation-a', 3),
        loggingSettingsEnabled: false,
        loggingEnvironment: const {},
      );
      final next = composition.create(
        owner: _owner('conversation-a', 4),
        loggingSettingsEnabled: false,
        loggingEnvironment: const {},
      );

      first.runtime.goalContinuation.tracker.applyDelta(
        first.runtime.owner,
        _delta(noProgressStreak: 2),
      );
      expect(
        next.runtime.goalContinuation.tracker
            .snapshotFor(next.runtime.owner)
            .noProgressStreak,
        2,
      );

      expect(first.runtime.beginGoalContinuationScheduling(), isTrue);
      expect(next.runtime.isSchedulingGoalContinuation, isFalse);
      expect(next.runtime.beginGoalContinuationScheduling(), isTrue);
    });
  });

  test(
    'composition has no notifier, Riverpod, provider, or callback capture',
    () {
      final source = File(
        'lib/features/chat/presentation/providers/'
        'turn_runtime_production_composition.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('ChatNotifier')));
      expect(source, isNot(matches(RegExp(r'\bRef\b'))));
      expect(source, isNot(contains('flutter_riverpod')));
      expect(source, isNot(contains('Provider')));
      expect(source, isNot(contains('dynamic Function')));
    },
  );

  test('production wrapper constructs and consumes the owner scope', () {
    final continuationSource = File(
      'lib/features/chat/presentation/providers/'
      'chat_notifier_goal_auto_continue.dart',
    ).readAsStringSync();
    final reservedStart = continuationSource.indexOf(
      'Future<void> _maybeAutoContinueCurrentGoal(',
    );
    final reservedEnd = continuationSource.indexOf(
      'void _applyTurnRuntimeGoalUiEffect(',
      reservedStart,
    );
    final reservedPath = continuationSource.substring(
      reservedStart,
      reservedEnd,
    );

    expect(
      continuationSource,
      contains('ConversationsNotifierGoalRuntimeStore('),
    );
    expect(
      continuationSource,
      contains('_createGoalContinuationRuntimeScope(owner)'),
    );
    expect(reservedPath, contains('runtime.coordinateGoalContinuation('));
    expect(reservedPath, contains('runtime.applyGoalTrackerTransition('));
    expect(reservedPath, contains('runtime.finalizePersistedGoalBlock('));
    expect(
      reservedPath,
      contains('runtime.finalizeFailedGoalContinuationDispatch()'),
    );
    expect(reservedPath, isNot(contains('goalContinuation.tracker')));
    expect(reservedPath, contains('runtime.beginGoalContinuationDispatch('));
    expect(reservedPath, contains('_applyTurnRuntimeGoalUiEffect('));
    expect(reservedPath, contains('_dispatchTurnRuntimeHiddenTurn('));
    expect(
      continuationSource,
      contains('runtime.goalCompletionElicitationDispatch('),
    );
    expect(reservedPath, contains('runtime.clearGoalIndicator()'));
    expect(reservedPath, contains('runtime.showGoalNotice(noticeKey)'));
    expect(
      reservedPath,
      isNot(contains('sendHiddenPrompt(\n        continuationPrompt,')),
    );
    expect(reservedPath, isNot(contains('_goalAutoContinueTrackerRegistry')));
    expect(reservedPath, isNot(contains('.conversationFor(owner)')));
    expect(reservedPath, isNot(contains('.snapshotFor(owner)')));
    expect(reservedPath, isNot(contains('.applyDelta(')));
    expect(reservedPath, isNot(contains('.markBudgetNoticePresented(')));
    expect(reservedPath, isNot(contains('.removeTracker(')));
    expect(reservedPath, isNot(contains('.clearPendingRepairContract(')));
    expect(
      reservedPath,
      isNot(contains('GoalAutoContinueDecisionCoordinator().coordinate(')),
    );
    expect(reservedPath, isNot(contains('markCurrentGoalStatus(')));
    expect(reservedPath, isNot(contains('_clearGoalAutoContinueIndicator();')));
    expect(
      reservedPath,
      isNot(contains('state.copyWith(goalAutoContinueNotice: noticeKey)')),
    );
  });
}

TurnRuntimeProductionComposition _composition({
  required TurnRuntimeOwnerLeasePort ownerLease,
  required TurnRuntimeConversationGoalStore conversationGoalStore,
  required TurnRuntimeGoalSafeBoundaryPort safeBoundary,
}) => TurnRuntimeProductionComposition(
  ownerLease: ownerLease,
  conversationGoalStore: conversationGoalStore,
  trackerRegistry: GoalAutoContinueTrackerRegistry(
    replayIdFactory: (generation) => 'replay-$generation',
  ),
  safeBoundary: safeBoundary,
);

final class _OwnerLease implements TurnRuntimeOwnerLeasePort {
  const _OwnerLease(this.currentOwner);

  final ChatTurnOwner currentOwner;

  @override
  bool isCurrent(ChatTurnOwner owner) => owner == currentOwner;
}

final class _GoalStore implements TurnRuntimeConversationGoalStore {
  _GoalStore(this.conversations);

  final Map<String, Conversation> conversations;

  @override
  Conversation? conversationForId(String conversationId) =>
      conversations[conversationId];

  @override
  Future<void> markGoalStatus({
    required String conversationId,
    required ConversationGoalStatus status,
    String? blockedReason,
  }) async {}
}

final class _SafeBoundary implements TurnRuntimeGoalSafeBoundaryPort {
  @override
  GoalAutoContinueSafeBoundary capture(ChatTurnOwner owner) =>
      const GoalAutoContinueSafeBoundary(
        isLoading: false,
        hasQueuedUserInput: false,
        hasPendingSshConnect: false,
        hasPendingSshCommand: false,
        hasPendingGitCommand: false,
        hasPendingLocalCommand: false,
        hasPendingComputerUseAction: false,
        hasPendingBrowserAction: false,
        hasPendingFileOperation: false,
        hasPendingBleConnect: false,
        hasPendingSerialOpen: false,
        hasPendingParticipantToolApproval: false,
        hasPendingAskUserQuestion: false,
        hasPendingWorkflowDecision: false,
        hasParticipantTurnRuntime: false,
        hasError: false,
      );
}

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

Conversation _conversation(String id) => Conversation(
  id: id,
  title: id,
  messages: const [],
  createdAt: DateTime(2026, 8, 3),
  updatedAt: DateTime(2026, 8, 3),
  workspaceMode: WorkspaceMode.coding,
);

GoalAutoContinueTrackerDelta _delta({int? noProgressStreak}) => (
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
  pendingRepairContractOutcome: null,
  repairNoMutationRetryUsed: null,
  completionElicitationMutationGeneration: null,
  markBudgetNoticePresented: false,
  removeTracker: false,
);
