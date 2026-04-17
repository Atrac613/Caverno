import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';

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
  late _FakeConversationRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakeConversationRepository();
    container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'updateCurrentWorkflow persists workflow data for current thread',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Plan the next feature slice',
          constraints: ['Keep the first iteration small'],
          acceptanceCriteria: ['Prompt receives workflow context'],
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Persist tasks with the conversation',
            ),
          ],
        ),
      );

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(currentConversation, isNotNull);
      expect(
        currentConversation!.workflowStage,
        ConversationWorkflowStage.plan,
      );
      expect(
        currentConversation.workflowSpec,
        const ConversationWorkflowSpec(
          goal: 'Plan the next feature slice',
          constraints: ['Keep the first iteration small'],
          acceptanceCriteria: ['Prompt receives workflow context'],
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Persist tasks with the conversation',
            ),
          ],
        ),
      );

      final persisted = repository.getById(currentConversation.id);
      expect(persisted?.workflowStage, ConversationWorkflowStage.plan);
      expect(persisted?.workflowSpec?.goal, 'Plan the next feature slice');
      expect(
        persisted?.workflowSpec?.tasks.single.title,
        'Persist tasks with the conversation',
      );
    },
  );

  test(
    'updateCurrentConversation keeps the default title for image-only input',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);
      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(currentConversation, isNotNull);
      expect(currentConversation!.title, defaultConversationTitle);

      await notifier.updateCurrentConversation([
        Message(
          id: 'user-image',
          content: '',
          role: MessageRole.user,
          timestamp: DateTime(2026),
          imageBase64: 'image-data',
          imageMimeType: 'image/png',
        ),
      ]);

      final updatedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(updatedConversation, isNotNull);
      expect(updatedConversation!.title, defaultConversationTitle);
      expect(
        repository.getById(updatedConversation.id)?.title,
        defaultConversationTitle,
      );
    },
  );

  test(
    'updateCurrentConversation uses the first non-empty user text for title',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      await notifier.updateCurrentConversation([
        Message(
          id: 'user-image',
          content: '',
          role: MessageRole.user,
          timestamp: DateTime(2026),
          imageBase64: 'image-data',
          imageMimeType: 'image/png',
        ),
        Message(
          id: 'assistant-1',
          content: 'What should I focus on?',
          role: MessageRole.assistant,
          timestamp: DateTime(2026),
        ),
        Message(
          id: 'user-text',
          content: 'Summarize the attached dashboard metrics',
          role: MessageRole.user,
          timestamp: DateTime(2026),
        ),
      ]);

      final updatedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(updatedConversation, isNotNull);
      expect(updatedConversation!.title, 'Summarize the attached dashboa...');
      expect(
        repository.getById(updatedConversation.id)?.title,
        'Summarize the attached dashboa...',
      );
    },
  );

  test(
    'updateCurrentConversation trims and truncates long user titles',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      await notifier.updateCurrentConversation([
        Message(
          id: 'user-text',
          content:
              '   This title should trim leading spaces and stop after thirty visible chars   ',
          role: MessageRole.user,
          timestamp: DateTime(2026),
        ),
      ]);

      final updatedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(updatedConversation, isNotNull);
      expect(updatedConversation!.title, 'This title should trim leading...');
      expect(
        repository.getById(updatedConversation.id)?.title,
        'This title should trim leading...',
      );
    },
  );
}
