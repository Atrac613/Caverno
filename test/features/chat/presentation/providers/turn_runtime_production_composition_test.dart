import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime_goal_continuation_ports_factory.dart';
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
      // The composition binds the lease to this owner instead of passing the
      // long-lived binder through, so identity cannot vary per call.
      expect(runtime.goalContinuation.ownerLease.isCurrent, isTrue);
      expect(
        runtime.goalContinuation.conversationGoal,
        isA<TurnRuntimeConversationGoalAdapter>(),
      );
      expect(
        runtime.goalContinuation.conversationGoal.conversation,
        same(conversation),
      );
      expect(
        runtime.goalContinuation.tracker,
        isA<TurnRuntimeGoalTrackerAdapter>(),
      );
      expect(
        runtime.goalContinuation.safeBoundary,
        same(safeBoundary.boundaryFor(owner)),
      );
      expect(runtime.goalContinuation.log, isNotNull);
      expect(scope.loggingEnabled, isFalse);
    });

    test('shares tracker history and serializes active runtime scheduling', () {
      final lifecycle = TurnRuntimeGoalContinuationLifecycle();
      final composition = _composition(
        ownerLease: _OwnerLease(_owner('conversation-a', 3)),
        conversationGoalStore: _GoalStore(const {}),
        safeBoundary: _SafeBoundary(),
        goalContinuationLifecycle: lifecycle,
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
        _delta(noProgressStreak: 2),
      );
      expect(
        next.runtime.goalContinuation.tracker.snapshot.noProgressStreak,
        2,
      );

      expect(first.runtime.beginGoalContinuationScheduling(), isTrue);
      expect(first.claimGoalContinuationScheduling(), isTrue);
      expect(composition.isGoalContinuationScheduling, isTrue);
      expect(next.runtime.isSchedulingGoalContinuation, isFalse);
      expect(next.runtime.beginGoalContinuationScheduling(), isTrue);
      expect(next.claimGoalContinuationScheduling(), isFalse);
      expect(next.runtime.isSchedulingGoalContinuation, isFalse);

      first.releaseGoalContinuationScheduling();
      expect(composition.isGoalContinuationScheduling, isFalse);
      expect(first.runtime.isSchedulingGoalContinuation, isFalse);

      expect(next.runtime.beginGoalContinuationScheduling(), isTrue);
      expect(next.claimGoalContinuationScheduling(), isTrue);
      lifecycle.clear();
      expect(composition.isGoalContinuationScheduling, isFalse);
      expect(next.runtime.isSchedulingGoalContinuation, isFalse);
    });
  });

  test(
    'composition has no notifier, Riverpod, provider, or callback capture',
    () {
      final source = _codeWithoutComments(
        'lib/features/chat/presentation/providers/'
        'turn_runtime_production_composition.dart',
      );

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
    expect(
      reservedPath,
      contains('_turnRuntimeComposition.isGoalContinuationScheduling'),
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
    expect(
      reservedPath,
      contains('runtimeScope.claimGoalContinuationScheduling()'),
    );
    expect(
      reservedPath,
      contains('runtimeScope.releaseGoalContinuationScheduling()'),
    );
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
    expect(reservedPath, isNot(contains('conversationGoal.conversation;')));
    expect(reservedPath, isNot(contains('tracker.snapshot')));
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
    expect(reservedPath, isNot(contains('_isSchedulingGoalAutoContinue')));
  });

  test('legacy notifier reentrancy flag is absent from production', () {
    for (final path in [
      'lib/features/chat/presentation/providers/chat_notifier.dart',
      'lib/features/chat/presentation/providers/chat_notifier_cancellation.dart',
      'lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('_isSchedulingGoalAutoContinue')),
        reason: path,
      );
    }
  });
}

TurnRuntimeProductionComposition _composition({
  required TurnRuntimeOwnerLeaseBinder ownerLease,
  required TurnRuntimeConversationGoalStore conversationGoalStore,
  required TurnRuntimeGoalSafeBoundaryBinder safeBoundary,
  TurnRuntimeGoalContinuationLifecycle? goalContinuationLifecycle,
}) => TurnRuntimeProductionComposition(
  ownerLease: ownerLease,
  conversationGoalStore: conversationGoalStore,
  trackerRegistry: GoalAutoContinueTrackerRegistry(
    replayIdFactory: (generation) => 'replay-$generation',
  ),
  safeBoundary: safeBoundary,
  goalContinuationLifecycle:
      goalContinuationLifecycle ?? TurnRuntimeGoalContinuationLifecycle(),
);

final class _OwnerLease implements TurnRuntimeOwnerLeaseBinder {
  const _OwnerLease(this.currentOwner);

  final ChatTurnOwner currentOwner;

  @override
  TurnRuntimeOwnerLeasePort leaseFor(ChatTurnOwner owner) =>
      _BoundOwnerLease(isCurrent: owner == currentOwner);
}

final class _BoundOwnerLease implements TurnRuntimeOwnerLeasePort {
  const _BoundOwnerLease({required this.isCurrent});

  @override
  final bool isCurrent;
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

final class _SafeBoundary
    implements
        TurnRuntimeGoalSafeBoundaryBinder,
        TurnRuntimeGoalSafeBoundaryPort {
  @override
  TurnRuntimeGoalSafeBoundaryPort boundaryFor(ChatTurnOwner owner) => this;

  @override
  GoalAutoContinueSafeBoundary capture() => const GoalAutoContinueSafeBoundary(
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
