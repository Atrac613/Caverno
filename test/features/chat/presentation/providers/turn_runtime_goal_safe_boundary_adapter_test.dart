import 'dart:async';
import 'dart:io';

import 'package:caverno/features/chat/application/runtime/turn_runtime_owner_lease_registry.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/pending_approval_summary.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/thread_scoped_chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/thread_scoped_message_queue.dart';
import 'package:caverno/features/chat/presentation/providers/turn_runtime_goal_safe_boundary_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('TurnRuntimeGoalSafeBoundaryAdapter', () {
    test('captures visible loading, error, queue, approval, and question', () {
      final fixture = _Fixture()..mountVisible('conversation-a');
      final owner = _owner('conversation-a');
      unawaited(fixture.queuedMessages.add(_queued('conversation-a')));
      fixture.pendingQuestions['conversation-a'] = _question('conversation-a');
      fixture.adapter.synchronizeVisibleState(
        ThreadScopedChatState(pendingLocalCommand: _local(owner)),
        isLoading: true,
        error: 'failed',
      );

      final boundary = fixture.adapter.captureFor(owner);

      expect(boundary.isLoading, isTrue);
      expect(boundary.hasError, isTrue);
      expect(boundary.hasQueuedUserInput, isTrue);
      expect(boundary.hasPendingLocalCommand, isTrue);
      expect(boundary.hasPendingAskUserQuestion, isTrue);
    });

    test(
      'uses stashed state and ignores visible status for detached owner',
      () {
        final fixture = _Fixture()..mountVisible('conversation-b');
        final detachedOwner = _owner('conversation-a');
        fixture.threadStates['conversation-a'] = ThreadScopedChatState(
          pendingLocalCommand: _local(detachedOwner),
        );
        fixture.adapter.synchronizeVisibleState(
          ThreadScopedChatState(
            pendingLocalCommand: _local(_owner('conversation-b')),
          ),
          isLoading: true,
          error: 'visible error',
        );

        final boundary = fixture.adapter.captureFor(detachedOwner);

        expect(boundary.hasPendingLocalCommand, isTrue);
        expect(boundary.isLoading, isFalse);
        expect(boundary.hasError, isFalse);
      },
    );

    test('every approval kind blocks continuation', () {
      // The adapter names the pending kinds one at a time, so it cannot be
      // exhaustive the way a sealed switch is — and it was not. ANA0's
      // assumption confirmation was added later and reached neither this
      // adapter nor the veto list behind it, so a goal with auto-continue on
      // would start another turn while the user was being asked to confirm the
      // assumption the last one was refused over. Driving every kind from
      // PendingApprovalKinds.all makes the next omission fail here.
      for (final kind in PendingApprovalKinds.all) {
        final fixture = _Fixture()..mountVisible('conversation-a');
        final owner = _owner('conversation-a');
        fixture.adapter.synchronizeVisibleState(
          _threadStateWith(kind, owner),
          isLoading: false,
          error: null,
        );

        final boundary = fixture.adapter.captureFor(owner);

        expect(
          boundary.firstVetoReason,
          isNotNull,
          reason: '$kind must stop a goal from continuing over it',
        );
      }
    });

    test('rejects an approval from another interaction generation', () {
      final fixture = _Fixture()..mountVisible('conversation-b');
      fixture.threadStates['conversation-a'] = ThreadScopedChatState(
        pendingLocalCommand: _local(_owner('conversation-a', generation: 2)),
      );

      final boundary = fixture.adapter.captureFor(_owner('conversation-a'));

      expect(boundary.hasPendingLocalCommand, isFalse);
    });

    test('returns an empty boundary when detached state is missing', () {
      final fixture = _Fixture()..mountVisible('conversation-b');

      final boundary = fixture.adapter.captureFor(_owner('conversation-a'));

      expect(boundary.isSafe, isTrue);
    });
  });

  test('adapter has no notifier, Riverpod, or callback dependency', () {
    final source = File(
      'lib/features/chat/presentation/providers/'
      'turn_runtime_goal_safe_boundary_adapter.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(contains('Function(')));
    expect(source, isNot(matches(RegExp(r'\bChatState\b'))));
  });

  test('chat notifier routes safe-boundary capture through the adapter', () {
    final notifierSource = File(
      'lib/features/chat/presentation/providers/chat_notifier.dart',
    ).readAsStringSync();
    final continuationSource = File(
      'lib/features/chat/presentation/providers/'
      'chat_notifier_goal_auto_continue.dart',
    ).readAsStringSync();

    expect(notifierSource, contains('TurnRuntimeGoalSafeBoundaryAdapter('));
    expect(
      continuationSource,
      contains('_turnRuntimeGoalSafeBoundary.synchronizeVisibleState('),
    );
    expect(
      continuationSource,
      contains('safeBoundary: _turnRuntimeGoalSafeBoundary,'),
    );
    expect(
      continuationSource,
      isNot(contains('GoalAutoContinuePendingState(')),
    );
  });
}

final class _Fixture {
  final ownerLease = TurnRuntimeOwnerLeaseRegistry();
  final queuedMessages = ThreadScopedMessageQueue();
  final threadStates = <String, ThreadScopedChatState>{};
  final pendingQuestions = <String, PendingAskUserQuestion>{};

  late final adapter = TurnRuntimeGoalSafeBoundaryAdapter(
    ownerLease: ownerLease,
    queuedMessages: queuedMessages,
    threadStates: threadStates,
    pendingQuestions: pendingQuestions,
  );

  void mountVisible(String conversationId) {
    ownerLease.mount(
      visibleConversationId: conversationId,
      selectedConversationId: conversationId,
    );
  }
}

ChatTurnOwner _owner(String conversationId, {int generation = 1}) =>
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    );

PendingLocalCommand _local(ChatTurnOwner owner) => PendingLocalCommand(
  owner: owner,
  id: 'command-${owner.interactionGeneration}',
  command: 'dart analyze',
  workingDirectory: '/workspace',
  reason: 'Verify the change',
  warningTitle: null,
  warningMessage: null,
  completer: Completer<LocalCommandApproval>(),
);

PendingAskUserQuestion _question(String conversationId) =>
    PendingAskUserQuestion(
      id: 'question-1',
      conversationId: conversationId,
      question: 'Continue?',
      help: '',
      options: const [],
      allowMultiple: false,
      allowOther: false,
      otherPlaceholder: '',
      completer: Completer<AskUserQuestionAnswer?>(),
    );

QueuedChatMessage _queued(String conversationId) => QueuedChatMessage(
  id: 'queued-1',
  content: 'User message',
  imageBase64: null,
  imageMimeType: null,
  languageCode: 'en',
  isVoiceMode: false,
  bypassPlanMode: false,
  conversationId: conversationId,
);

/// A thread blocked on exactly one approval [kind].
///
/// A switch rather than a map, so a kind added to [PendingApprovalKinds]
/// without a case here is a compile-time gap in the test rather than a silently
/// skipped iteration.
ThreadScopedChatState _threadStateWith(String kind, ChatTurnOwner owner) {
  return switch (kind) {
    PendingApprovalKinds.file => ThreadScopedChatState(
      pendingFileOperation: PendingFileOperation(
        owner: owner,
        id: 'file-1',
        operation: 'write',
        path: 'lib/main.dart',
        preview: '',
        reason: null,
        completer: Completer<bool>(),
      ),
    ),
    PendingApprovalKinds.localCommand => ThreadScopedChatState(
      pendingLocalCommand: _local(owner),
    ),
    PendingApprovalKinds.gitCommand => ThreadScopedChatState(
      pendingGitCommand: PendingGitCommand(
        owner: owner,
        id: 'git-1',
        command: 'status',
        workingDirectory: '/workspace',
        reason: null,
        completer: Completer<bool>(),
      ),
    ),
    PendingApprovalKinds.sshCommand => ThreadScopedChatState(
      pendingSshCommand: PendingSshCommand(
        owner: owner,
        id: 'ssh-command-1',
        command: 'uptime',
        reason: null,
        host: 'build-box',
        username: 'deploy',
        completer: Completer<bool>(),
      ),
    ),
    PendingApprovalKinds.sshConnect => ThreadScopedChatState(
      pendingSshConnect: PendingSshConnect(
        owner: owner,
        id: 'ssh-connect-1',
        host: 'build-box',
        port: 22,
        username: 'deploy',
        savedCredential: null,
        identityCandidates: const [],
        completer: Completer<SshConnectApproval?>(),
      ),
    ),
    PendingApprovalKinds.browserAction => ThreadScopedChatState(
      pendingBrowserAction: PendingBrowserAction(
        owner: owner,
        id: 'browser-1',
        toolName: 'browser_click',
        title: 'Click',
        riskLabel: 'low',
        warningMessage: '',
        approveLabel: 'Allow',
        summary: 'click',
        details: const [],
        targetSummary: null,
        sensitiveValuePreview: null,
        reason: null,
        completer: Completer<bool>(),
      ),
    ),
    PendingApprovalKinds.computerUse => ThreadScopedChatState(
      pendingComputerUseAction: PendingComputerUseAction(
        owner: owner,
        id: 'computer-use-1',
        toolName: 'computer_click',
        title: 'Click Send',
        riskCategory: 'input',
        riskLabel: 'High',
        warningMessage: '',
        approveLabel: 'Click',
        requiresUserApproval: true,
        requiresSmokeArming: true,
        emergencyStop: false,
        summary: 'Click at (10, 20)',
        details: const [],
        targetSummary: null,
        targetDetails: const [],
        exactTextPreview: null,
        exactTextLength: null,
        approvalBoundaries: const [],
        approvalBlockerCodes: const [],
        actionProposalNextAction: null,
        visionObservationSummary: null,
        visionObservationDetails: const [],
        reason: null,
        completer: Completer<ComputerUseActionApprovalDecision>(),
      ),
    ),
    PendingApprovalKinds.bleConnect => ThreadScopedChatState(
      pendingBleConnect: PendingBleConnect(
        owner: owner,
        id: 'ble-1',
        deviceId: 'AA:BB',
        deviceName: null,
        completer: Completer<bool>(),
      ),
    ),
    PendingApprovalKinds.serialOpen => ThreadScopedChatState(
      pendingSerialOpen: PendingSerialOpen(
        owner: owner,
        id: 'serial-1',
        portName: '/dev/tty',
        baudRate: 9600,
        completer: Completer<bool>(),
      ),
    ),
    PendingApprovalKinds.participantTool => ThreadScopedChatState(
      pendingParticipantToolApproval: PendingParticipantToolApproval(
        owner: owner,
        id: 'participant-1',
        participantId: 'p-1',
        participantName: 'Reviewer',
        participantRoleLabel: 'reviewer',
        toolName: 'read_file',
        arguments: const {},
        reason: null,
        completer: Completer<bool>(),
      ),
    ),
    PendingApprovalKinds.assumptionConfirmation => ThreadScopedChatState(
      pendingAssumptionConfirmation: PendingAssumptionConfirmation(
        owner: owner,
        id: 'assume-1',
        itemId: 'i-1',
        kind: ConversationContractItemKind.constraint,
        itemText: 'The port is free.',
        clarificationQuestion: null,
        toolName: 'write_file',
        completer: Completer<bool>(),
      ),
    ),
    _ => throw StateError(
      'No thread state for approval kind "$kind". Add one here, and check the '
      'adapter reports it, before the kind ships.',
    ),
  };
}
