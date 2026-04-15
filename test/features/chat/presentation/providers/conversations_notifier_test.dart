import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
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
        ),
      );

      final persisted = repository.getById(currentConversation.id);
      expect(persisted?.workflowStage, ConversationWorkflowStage.plan);
      expect(persisted?.workflowSpec?.goal, 'Plan the next feature slice');
    },
  );
}
