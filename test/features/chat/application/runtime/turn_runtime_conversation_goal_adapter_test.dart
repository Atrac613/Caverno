import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime_conversation_goal_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:test/test.dart';

void main() {
  group('TurnRuntimeConversationGoalAdapter', () {
    test('reads the exact owner conversation', () {
      final conversation = _conversation('conversation-a');
      final store = _GoalStore({'conversation-a': conversation});

      expect(
        adapterFor(store, _owner('conversation-a')).conversation,
        conversation,
      );
      expect(adapterFor(store, _owner('conversation-b')).conversation, isNull);
    });

    test('writes status to the exact owner conversation', () async {
      final store = _GoalStore({
        'conversation-a': _conversation('conversation-a'),
        'conversation-b': _conversation('conversation-b'),
      });

      await adapterFor(store, _owner('conversation-a')).markGoalStatus(
        TurnRuntimeGoalStatusUpdate(
          status: ConversationGoalStatus.blocked,
          blockedReason: 'No progress',
        ),
      );

      expect(store.writes, [
        (
          conversationId: 'conversation-a',
          status: ConversationGoalStatus.blocked,
          blockedReason: 'No progress',
        ),
      ]);
    });

    test('suppresses a write for a missing conversation', () async {
      final store = _GoalStore(const {});

      await adapterFor(store, _owner('conversation-a')).markGoalStatus(
        TurnRuntimeGoalStatusUpdate(status: ConversationGoalStatus.blocked),
      );

      expect(store.writes, isEmpty);
    });

    test('rejects a mismatched conversation snapshot', () async {
      final store = _PoisonedGoalStore(_conversation('conversation-b'));

      final owner = _owner('conversation-a');

      expect(adapterFor(store, owner).conversation, isNull);
      await adapterFor(store, owner).markGoalStatus(
        TurnRuntimeGoalStatusUpdate(status: ConversationGoalStatus.blocked),
      );

      expect(store.writeCount, 0);
    });
  });

  test('adapter has no presentation or callback dependency', () {
    final source = _codeWithoutComments(
      'lib/features/chat/application/runtime/'
      'turn_runtime_conversation_goal_adapter.dart',
    );

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(contains('ChatState')));
    expect(source, isNot(contains('flutter_riverpod')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('typedef ')));
    expect(source, isNot(contains('Function(')));
  });

  test('production store has no notifier callback or Ref dependency', () {
    final source = File(
      'lib/features/chat/presentation/providers/'
      'conversations_notifier_goal_runtime_store.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ChatNotifier')));
    expect(source, isNot(contains('ChatState')));
    expect(source, isNot(matches(RegExp(r'\bRef\b'))));
    expect(source, isNot(contains('typedef ')));
    expect(source, isNot(contains('Function(')));
  });
}

typedef _GoalWrite = ({
  String conversationId,
  ConversationGoalStatus status,
  String? blockedReason,
});

final class _GoalStore implements TurnRuntimeConversationGoalStore {
  _GoalStore(this.conversations);

  final Map<String, Conversation> conversations;
  final List<_GoalWrite> writes = [];

  @override
  Conversation? conversationForId(String conversationId) =>
      conversations[conversationId];

  @override
  Future<void> markGoalStatus({
    required String conversationId,
    required ConversationGoalStatus status,
    String? blockedReason,
  }) async {
    writes.add((
      conversationId: conversationId,
      status: status,
      blockedReason: blockedReason,
    ));
  }
}

final class _PoisonedGoalStore implements TurnRuntimeConversationGoalStore {
  _PoisonedGoalStore(this.conversation);

  final Conversation conversation;
  int writeCount = 0;

  @override
  Conversation? conversationForId(String conversationId) => conversation;

  @override
  Future<void> markGoalStatus({
    required String conversationId,
    required ConversationGoalStatus status,
    String? blockedReason,
  }) async {
    writeCount += 1;
  }
}

ChatTurnOwner _owner(String conversationId) =>
    ChatTurnOwner(conversationId: conversationId, interactionGeneration: 3);

Conversation _conversation(String id) => Conversation(
  id: id,
  title: id,
  messages: const [],
  createdAt: DateTime(2026, 8, 3),
  updatedAt: DateTime(2026, 8, 3),
  workspaceMode: WorkspaceMode.coding,
  goal: ConversationGoal(
    id: 'goal-$id',
    objective: 'Complete $id',
    createdAt: DateTime(2026, 8, 3),
    updatedAt: DateTime(2026, 8, 3),
  ),
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

TurnRuntimeConversationGoalAdapter adapterFor(
  TurnRuntimeConversationGoalStore store,
  ChatTurnOwner owner,
) => TurnRuntimeConversationGoalAdapter(store: store, owner: owner);
