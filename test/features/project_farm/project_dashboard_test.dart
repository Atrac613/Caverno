import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/project_farm/application/project_task_starter.dart';
import 'package:caverno/features/project_farm/data/project_git_status_reader.dart';
import 'package:caverno/features/project_farm/domain/entities/roadmap_snapshot.dart';
import 'package:caverno/features/project_farm/presentation/widgets/project_dashboard_sections.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _item = RoadmapItemSnapshot(
  id: 'RC1',
  title: 'Signed-device evidence',
  quote: 'Recommended next slice: RC1 signed-device evidence.',
  line: 97,
);

RoadmapSnapshot _snapshot({
  RoadmapSnapshotStatus status = RoadmapSnapshotStatus.verified,
  RoadmapItemSnapshot? recommended = _item,
}) => RoadmapSnapshot(
  projectId: 'p1',
  roadmapPath: 'docs/roadmap.md',
  contentSha256: 'sha',
  extractorVersion: 1,
  model: 'm',
  extractedAt: DateTime.utc(2026, 9, 26),
  status: status,
  recommended: recommended,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the task objective cites its source line and quote', () {
    expect(
      projectTaskObjective(_item, 'docs/roadmap.md'),
      'RC1: Signed-device evidence\n\n'
      'Source: docs/roadmap.md:97\n'
      '"Recommended next slice: RC1 signed-device evidence."',
    );
  });

  group('ProjectGitStatusReader', () {
    ProcessResult ok(String out) => ProcessResult(0, 0, out, '');

    test('reads branch, changes, ahead count and last commit', () async {
      final reader = ProjectGitStatusReader(
        run: (args, _) async => switch (args.first) {
          'rev-parse' => ok('feature/x\n'),
          'status' => ok(' M a.dart\n?? b.dart\n'),
          'rev-list' => ok('3\n'),
          _ => ok('abc123 feat: thing\n'),
        },
      );

      final status = await reader.read('/repo');

      expect(status!.branch, 'feature/x');
      expect(status.changedFiles, 2);
      expect(status.ahead, 3);
      expect(status.lastCommit, 'abc123 feat: thing');
    });

    test('reports no upstream as an unknown ahead count', () async {
      final reader = ProjectGitStatusReader(
        run: (args, _) async => args.first == 'rev-list'
            ? ProcessResult(0, 128, '', 'no upstream')
            : ok(args.first == 'rev-parse' ? 'main' : ''),
      );
      expect((await reader.read('/repo'))!.ahead, isNull);
    });

    test('returns null outside a git work tree', () async {
      final reader = ProjectGitStatusReader(
        run: (_, _) async => ProcessResult(0, 128, '', 'not a git repo'),
      );
      expect(await reader.read('/repo'), isNull);
    });
  });

  test('Start work creates a coding thread carrying the task goal', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = _InMemoryConversationRepository();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        conversationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final id = startProjectTask(
      conversations: container.read(conversationsNotifierProvider.notifier),
      projectId: 'p1',
      item: _item,
      roadmapPath: 'docs/roadmap.md',
    );

    final state = container.read(conversationsNotifierProvider);
    final created = state.conversations.singleWhere((c) => c.id == id);
    expect(
      state.currentConversationId,
      isNot(id),
      reason: 'the caller decides whether to open it',
    );
    expect(created.workspaceMode, WorkspaceMode.coding);
    expect(created.normalizedProjectId, 'p1');
    expect(created.messages, isEmpty, reason: 'nothing is sent');
    expect(created.goal!.status, ConversationGoalStatus.active);
    expect(created.goal!.objective, contains('docs/roadmap.md:97'));
    expect(repository.getById(id)?.goal, isNotNull);
  });

  test('a background thread is added without switching threads', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = _InMemoryConversationRepository();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        conversationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(conversationsNotifierProvider.notifier);
    notifier.createNewConversation(workspaceMode: WorkspaceMode.chat);
    final manager = container.read(conversationsNotifierProvider);

    final created = notifier.addBackgroundConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'p1',
      goal: projectTaskGoal(_item, 'docs/roadmap.md'),
    );

    final state = container.read(conversationsNotifierProvider);
    expect(state.currentConversationId, manager.currentConversationId);
    expect(state.activeWorkspaceMode, manager.activeWorkspaceMode);
    expect(state.conversations.first.id, created.id);
    expect(created.goal!.objective, contains('docs/roadmap.md:97'));
    expect(created.goal!.autoContinue, isFalse);
    expect(repository.getById(created.id), isNotNull);
  });

  group('NextTaskCard', () {
    Future<void> pump(
      WidgetTester tester,
      RoadmapSnapshot? snapshot, {
      bool hasRoadmap = true,
      ValueChanged<RoadmapSnapshot>? onStartWork,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NextTaskCard(
            snapshot: snapshot,
            hasRoadmap: hasRoadmap,
            refreshing: false,
            onStartWork: onStartWork ?? (_) {},
          ),
        ),
      ),
    );

    testWidgets('shows a verified task with Start work', (tester) async {
      RoadmapSnapshot? started;
      await pump(tester, _snapshot(), onStartWork: (s) => started = s);

      expect(
        find.byKey(const ValueKey('project-dashboard-verified')),
        findsOneWidget,
      );
      expect(find.text('docs/roadmap.md:97'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('project-dashboard-start-work')),
      );
      expect(started?.recommended?.id, 'RC1');
    });

    testWidgets('labels an unverified task', (tester) async {
      await pump(
        tester,
        _snapshot(
          status: RoadmapSnapshotStatus.unverified,
          recommended: _item.copyWith(verified: false, line: null),
        ),
      );
      expect(
        find.byKey(const ValueKey('project-dashboard-unverified')),
        findsOneWidget,
      );
      expect(find.text('docs/roadmap.md'), findsOneWidget);
    });

    testWidgets('says so when the roadmap names no task', (tester) async {
      await pump(
        tester,
        _snapshot(status: RoadmapSnapshotStatus.none, recommended: null),
      );
      expect(
        find.byKey(const ValueKey('project-dashboard-next-none')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('project-dashboard-start-work')),
        findsNothing,
      );
    });

    testWidgets('distinguishes a failed extraction and a missing roadmap', (
      tester,
    ) async {
      await pump(tester, _snapshot(status: RoadmapSnapshotStatus.failed));
      expect(
        find.byKey(const ValueKey('project-dashboard-next-failed')),
        findsOneWidget,
      );

      await pump(tester, null, hasRoadmap: false);
      expect(
        find.byKey(const ValueKey('project-dashboard-next-empty')),
        findsOneWidget,
      );
    });
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
