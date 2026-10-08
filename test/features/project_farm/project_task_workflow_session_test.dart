import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/project_farm/application/project_task_starter.dart';
import 'package:caverno/features/project_farm/application/project_task_workflow_session.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _item = RoadmapItemSnapshot(
  id: 'CLI5',
  title: 'Headless Project Farm',
  quote: 'Run the Project Farm task workflow headless.',
  line: 12,
);

void main() {
  // The session is driven through a bare ProviderContainer here, the way the
  // terminal frontend reads providers, so no widget tree is involved.
  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        conversationRepositoryProvider.overrideWithValue(
          _InMemoryConversationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  String start(ProviderContainer container, {required bool autoReview}) =>
      startProjectTask(
        conversations: container.read(conversationsNotifierProvider.notifier),
        projectId: 'p1',
        item: _item,
        roadmapPath: 'docs/roadmap.md',
        autoReview: autoReview,
      );

  test('skips a thread that did not opt into the workflow', () async {
    final c = await container();
    final outcome = await ProjectTaskWorkflowSession().run(
      read: c.read,
      conversationId: start(c, autoReview: false),
      languageCode: 'en',
      isActive: () => true,
    );
    expect(outcome, isA<ProjectTaskWorkflowSkipped>());
  });

  test('resume skips a thread with no earlier run', () async {
    final c = await container();
    final outcome = await ProjectTaskWorkflowSession().run(
      read: c.read,
      conversationId: start(c, autoReview: true),
      languageCode: 'en',
      isActive: () => true,
      resume: true,
    );
    expect(outcome, isA<ProjectTaskWorkflowSkipped>());
  });

  test('reports a missing review route instead of showing a message, and '
      'releases the thread for a later run', () async {
    final c = await container();
    final session = ProjectTaskWorkflowSession();
    final id = start(c, autoReview: true);
    for (var attempt = 0; attempt < 2; attempt++) {
      final outcome = await session.run(
        read: c.read,
        conversationId: id,
        languageCode: 'en',
        isActive: () => true,
      );
      expect(outcome, isA<ProjectTaskWorkflowUnavailable>());
    }
  });
}

class _InMemoryConversationRepository implements ConversationRepositoryApi {
  final Map<String, Conversation> _conversations = {};

  @override
  List<Conversation> getAll() => _conversations.values.toList(growable: false);

  @override
  Conversation? getById(String id) => _conversations[id];

  @override
  Future<Conversation?> refresh(String id) async => _conversations[id];

  @override
  Future<void> save(Conversation conversation) async {
    _conversations[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _conversations.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _conversations.clear();
  }

  @override
  Future<List<Conversation>> search(String query) async => getAll();
}
