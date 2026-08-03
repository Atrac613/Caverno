import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_tracker_registry.dart';
import 'package:caverno/features/chat/domain/services/goal_continuation_log_record_builder.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:test/test.dart';

void main() {
  group('TurnRuntime', () {
    test('owns one exact turn identity', () {
      final owner = _owner();
      final ports = _ports();

      final runtime = TurnRuntime(owner: owner, goalContinuation: ports);

      expect(runtime.owner, same(owner));
      expect(runtime.goalContinuation, same(ports));
    });

    test('rejects recursive continuation scheduling until released', () {
      final runtime = TurnRuntime(owner: _owner(), goalContinuation: _ports());

      expect(runtime.beginGoalContinuationScheduling(), isTrue);
      expect(runtime.isSchedulingGoalContinuation, isTrue);
      expect(runtime.beginGoalContinuationScheduling(), isFalse);

      runtime.endGoalContinuationScheduling();
      runtime.endGoalContinuationScheduling();

      expect(runtime.isSchedulingGoalContinuation, isFalse);
      expect(runtime.beginGoalContinuationScheduling(), isTrue);
    });

    test('returns owner-bound UI and hidden-turn dispatch effects', () {
      final owner = _owner();
      final runtime = TurnRuntime(owner: owner, goalContinuation: _ports());
      final allowedTools = <String>{'run_tests'};

      final dispatch = runtime.beginGoalContinuationDispatch(
        prompt: 'Continue the task',
        languageCode: 'en',
        evidence: const ToolResultCompletionEvidence(
          unresolvedErrorPaths: ['lib/main.dart'],
        ),
        count: 2,
        budget: 5,
        replayVerifierImmediatelyAfterMutation: true,
        verifierOnlyContinuation: false,
        allowedToolNames: allowedTools,
      );
      allowedTools.add('write_file');

      expect(dispatch, isNotNull);
      expect(dispatch!.uiEffect.owner, same(owner));
      expect(dispatch.uiEffect.count, 2);
      expect(dispatch.uiEffect.budget, 5);
      expect(dispatch.hiddenTurn.owner, same(owner));
      expect(dispatch.hiddenTurn.kind, TurnRuntimeHiddenTurnKind.continuation);
      expect(dispatch.hiddenTurn.prompt, 'Continue the task');
      expect(dispatch.hiddenTurn.evidence.unresolvedErrorPaths, [
        'lib/main.dart',
      ]);
      expect(
        dispatch.hiddenTurn.replayVerifierImmediatelyAfterMutation,
        isTrue,
      );
      expect(dispatch.hiddenTurn.verifierOnlyContinuation, isFalse);
      expect(dispatch.hiddenTurn.allowedToolNames, {'run_tests'});
      expect(
        runtime.beginGoalContinuationDispatch(
          prompt: 'Recursive continuation',
          languageCode: 'en',
          evidence: const ToolResultCompletionEvidence(),
          count: 3,
          budget: 5,
          replayVerifierImmediatelyAfterMutation: false,
          verifierOnlyContinuation: false,
        ),
        isNull,
      );
    });

    test('returns owner-bound completion elicitation effects', () {
      final owner = _owner();
      final runtime = TurnRuntime(owner: owner, goalContinuation: _ports());
      final paths = <String>['lib/main.dart'];

      final dispatch = runtime.goalCompletionElicitationDispatch(
        languageCode: 'ja',
        evidence: ToolResultCompletionEvidence(unresolvedErrorPaths: paths),
      );
      paths.add('lib/other.dart');

      expect(dispatch.uiEffect.owner, same(owner));
      expect(dispatch.hiddenTurn.owner, same(owner));
      expect(
        dispatch.hiddenTurn.kind,
        TurnRuntimeHiddenTurnKind.completionElicitation,
      );
      expect(dispatch.hiddenTurn.prompt, contains('update_goal'));
      expect(dispatch.hiddenTurn.prompt, contains('"ja"'));
      expect(dispatch.hiddenTurn.languageCode, 'ja');
      expect(dispatch.hiddenTurn.allowedToolNames, {'update_goal'});
      expect(dispatch.hiddenTurn.evidence.unresolvedErrorPaths, [
        'lib/main.dart',
      ]);
    });

    test('returns owner-bound clear and notice effects', () {
      final owner = _owner();
      final runtime = TurnRuntime(owner: owner, goalContinuation: _ports());

      final clear = runtime.clearGoalIndicator();
      final notice = runtime.showGoalNotice('goal-stopped');

      expect(clear.owner, same(owner));
      expect(notice.owner, same(owner));
      expect(notice.noticeKey, 'goal-stopped');
    });

    test('returns unavailable coordination without an owner conversation', () {
      final tracker = _GoalTrackerPort();
      final safeBoundary = _SafeBoundaryPort();
      final runtime = TurnRuntime(
        owner: _owner(),
        goalContinuation: _ports(tracker: tracker, safeBoundary: safeBoundary),
      );

      final result = runtime.coordinateGoalContinuation(_input());

      expect(result, isA<TurnRuntimeGoalCoordinationUnavailable>());
      expect(result.owner, same(runtime.owner));
      expect(tracker.snapshotCalls, 0);
      expect(safeBoundary.captureCalls, 0);
    });

    test('coordinates owner conversation, tracker, and safe boundary', () {
      final owner = _owner();
      final conversation = _conversation(owner.conversationId);
      final runtime = TurnRuntime(
        owner: owner,
        goalContinuation: _ports(conversation: conversation),
      );

      final result = runtime.coordinateGoalContinuation(_input());

      expect(result, isA<TurnRuntimeGoalCoordinationReady>());
      final ready = result as TurnRuntimeGoalCoordinationReady;
      expect(ready.owner, same(owner));
      expect(ready.conversation, same(conversation));
      expect(ready.tracker.noProgressStreak, 0);
      expect(ready.safeBoundary.isLoading, isFalse);
      expect(ready.plan.policyInput, isNotNull);
      expect(ready.plan.policyDecision.shouldContinue, isFalse);
    });
  });

  group('TurnRuntime goal continuation values', () {
    test('copies completion evidence collections', () {
      final paths = <String>['lib/first.dart'];
      final tools = <String>['run_tests'];
      final input = TurnRuntimeGoalContinuationInput(
        finalizedAssistantResponse: 'Working',
        languageCode: 'en',
        evidence: ToolResultCompletionEvidence(
          unresolvedErrorPaths: paths,
          unexecutedToolNames: tools,
        ),
        isVoiceMode: false,
      );

      paths.add('lib/second.dart');
      tools.add('write_file');

      expect(input.evidence.unresolvedErrorPaths, ['lib/first.dart']);
      expect(input.evidence.unexecutedToolNames, ['run_tests']);
      expect(
        () => input.evidence.unresolvedErrorPaths.add('lib/third.dart'),
        throwsUnsupportedError,
      );
    });

    test('copies a supplied hidden-turn allowlist', () {
      final allowed = <String>{'run_tests'};
      final request = TurnRuntimeHiddenTurnRequest(
        owner: _owner(),
        kind: TurnRuntimeHiddenTurnKind.continuation,
        prompt: 'Continue',
        languageCode: 'en',
        evidence: const ToolResultCompletionEvidence(),
        allowedToolNames: allowed,
      );

      allowed.add('write_file');

      expect(request.allowedToolNames, {'run_tests'});
      expect(
        () => request.allowedToolNames?.add('read_file'),
        throwsUnsupportedError,
      );
    });

    test('preserves a nullable hidden-turn allowlist', () {
      final request = TurnRuntimeHiddenTurnRequest(
        owner: _owner(),
        kind: TurnRuntimeHiddenTurnKind.completionElicitation,
        prompt: 'Report completion',
        languageCode: 'en',
        evidence: const ToolResultCompletionEvidence(),
      );

      expect(request.allowedToolNames, isNull);
    });

    test('binds status and returned effects to the exact owner', () {
      final owner = _owner();

      final status = TurnRuntimeGoalStatusUpdate(
        owner: owner,
        status: ConversationGoalStatus.blocked,
        blockedReason: 'No progress',
      );
      final clear = TurnRuntimeClearGoalIndicator(owner: owner);
      final progress = TurnRuntimeShowGoalProgress(
        owner: owner,
        count: 2,
        budget: 5,
      );
      final notice = TurnRuntimeShowGoalNotice(
        owner: owner,
        noticeKey: 'goal-stopped',
      );

      expect(status.owner, same(owner));
      expect(clear.owner, same(owner));
      expect(progress.owner, same(owner));
      expect(notice.owner, same(owner));
    });
  });

  test('runtime contract has no presentation or callback dependency', () {
    final source = File(
      'lib/features/chat/application/runtime/turn_runtime.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(contains('ChatState')));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('typedef ')));
    expect(source, isNot(contains('Function(')));
    expect(
      RegExp(r'abstract interface class TurnRuntime').allMatches(source),
      hasLength(5),
    );
  });
}

ChatTurnOwner _owner() =>
    ChatTurnOwner(conversationId: 'conversation-a', interactionGeneration: 7);

TurnRuntimeGoalContinuationInput _input() => TurnRuntimeGoalContinuationInput(
  finalizedAssistantResponse: 'Finished the current step.',
  languageCode: 'en',
  evidence: const ToolResultCompletionEvidence(),
  isVoiceMode: false,
);

Conversation _conversation(String id) => Conversation(
  id: id,
  title: id,
  messages: const [],
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  workspaceMode: WorkspaceMode.coding,
  goal: ConversationGoal(
    id: 'goal-1',
    objective: 'Finish the task',
    enabled: true,
    autoContinue: true,
    status: ConversationGoalStatus.active,
    turnBudget: 5,
    turnsUsed: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
);

TurnRuntimeGoalContinuationPorts _ports({
  Conversation? conversation,
  _GoalTrackerPort? tracker,
  _SafeBoundaryPort? safeBoundary,
}) => TurnRuntimeGoalContinuationPorts(
  ownerLease: _OwnerLeasePort(),
  conversationGoal: _ConversationGoalPort(conversation),
  tracker: tracker ?? _GoalTrackerPort(),
  safeBoundary: safeBoundary ?? _SafeBoundaryPort(),
  log: _ContinuationLogPort(),
);

final class _OwnerLeasePort implements TurnRuntimeOwnerLeasePort {
  @override
  bool isCurrent(ChatTurnOwner owner) => true;
}

final class _ConversationGoalPort implements TurnRuntimeConversationGoalPort {
  const _ConversationGoalPort(this.conversation);

  final Conversation? conversation;

  @override
  Conversation? conversationFor(ChatTurnOwner owner) => conversation;

  @override
  Future<void> markGoalStatus(TurnRuntimeGoalStatusUpdate update) async {}
}

final class _GoalTrackerPort implements TurnRuntimeGoalTrackerPort {
  int snapshotCalls = 0;

  @override
  GoalAutoContinueTrackerSnapshot applyDelta(
    ChatTurnOwner owner,
    GoalAutoContinueTrackerDelta delta,
  ) => snapshotFor(owner);

  @override
  bool markBudgetNoticePresented(ChatTurnOwner owner) => true;

  @override
  GoalAutoContinueTrackerSnapshot clearPendingRepairContract(
    ChatTurnOwner owner,
  ) => snapshotFor(owner);

  @override
  void removeTracker(ChatTurnOwner owner) {}

  @override
  GoalAutoContinueTrackerSnapshot snapshotFor(ChatTurnOwner owner) {
    snapshotCalls += 1;
    return (
      consecutiveAutoContinuations: 0,
      diagnosticRepairContinuations: 0,
      diagnosticRepairExtensionUsed: false,
      noProgressStreak: 0,
      consecutiveValidationMisses: 0,
      failedVerificationObserved: false,
      previousEvidence: null,
      previousDiagnosticSignature: '',
      identicalDiagnosticSignatureStreak: 0,
      pendingPostRepairReplayOutcome: false,
      pendingRepairContractOutcome: false,
      repairNoMutationRetryUsed: false,
      completionElicitationMutationGeneration: null,
      activeCommandDiagnosticRepairFocus: null,
      verifierReplayCandidate: null,
      replayedMutationGenerations: const <int>{},
      replayedInteractionGenerations: const <int>{},
      budgetNoticePresented: false,
    );
  }
}

final class _SafeBoundaryPort implements TurnRuntimeGoalSafeBoundaryPort {
  int captureCalls = 0;

  @override
  GoalAutoContinueSafeBoundary capture(ChatTurnOwner owner) {
    captureCalls += 1;
    return const GoalAutoContinueSafeBoundary(
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
}

final class _ContinuationLogPort implements TurnRuntimeGoalContinuationLogPort {
  @override
  Future<void> record(GoalAutoContinueLogRecord record) async {}
}
