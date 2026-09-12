import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

class _MockConversationBox extends Mock implements Box<String> {}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Conversation? getById(String id) => _store[id];

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

void main() {
  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
      ],
    );
  }

  ConversationsNotifier freshNotifier(ProviderContainer container) {
    final notifier = container.read(conversationsNotifierProvider.notifier);
    notifier.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-1',
    );
    return notifier;
  }

  Conversation current(ProviderContainer container) =>
      container.read(conversationsNotifierProvider).currentConversation!;

  test(
    'an acceptance is recorded with its rationale, evidence and premises',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = freshNotifier(container);

      final wrote = await notifier.recordTaskAcceptance(
        taskId: 'task-1',
        rationale: 'The CLI prints the counts the contract asks for.',
        evidence: ['python3 -m unittest passed', 'count.py'],
        premises: ['stdlib only'],
      );

      expect(wrote, isTrue);
      final acceptance = current(container).taskAcceptances.single;
      expect(acceptance.taskId, 'task-1');
      expect(acceptance.rationale, contains('counts the contract'));
      expect(acceptance.evidence, ['python3 -m unittest passed', 'count.py']);
      // Recorded so ANA2's contradiction policy can tell later whether the
      // premise this rested on has lapsed.
      expect(acceptance.premises, ['stdlib only']);
    },
  );

  test('accepting the same task twice leaves one acceptance', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = freshNotifier(container);

    await notifier.recordTaskAcceptance(taskId: 'task-1', rationale: 'first');
    await notifier.recordTaskAcceptance(taskId: 'task-1', rationale: 'second');

    // Two answers to "was this accepted, and on what" is the ambiguity the
    // single-writer rule exists to prevent.
    final acceptances = current(container).taskAcceptances;
    expect(acceptances, hasLength(1));
    expect(acceptances.single.rationale, 'second');
  });

  test('a blank task id writes nothing', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = freshNotifier(container);

    expect(await notifier.recordTaskAcceptance(taskId: '  '), isFalse);
    expect(current(container).taskAcceptances, isEmpty);
  });

  test(
    'empty rationale, evidence and premises are dropped, not stored',
    () async {
      final container = createContainer();
      addTearDown(container.dispose);
      final notifier = freshNotifier(container);

      await notifier.recordTaskAcceptance(
        taskId: 'task-1',
        evidence: ['', '  ', 'count.py'],
        premises: ['  '],
      );

      final acceptance = current(container).taskAcceptances.single;
      expect(acceptance.evidence, ['count.py']);
      expect(acceptance.premises, isEmpty);
    },
  );

  test('an acceptance survives a save and is reloaded from the store', () async {
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = freshNotifier(container);
    final conversationId = current(container).id;

    await notifier.recordTaskAcceptance(
      taskId: 'task-1',
      rationale: 'judged on the passing suite',
    );

    // The point of recording it at all: the next turn has to be able to see it
    // rather than starting over from the same files.
    final reloaded = container
        .read(conversationRepositoryProvider)
        .getById(conversationId);
    expect(reloaded!.taskAcceptances.single.rationale, contains('passing'));
  });
}
