import 'dart:async';
import 'dart:io';

import 'package:caverno/features/chat/application/runtime/turn_runtime_owner_lease_registry.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
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
