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
import 'package:caverno/features/project_farm/presentation/widgets/roadmap_path_dialog.dart';
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
  RoadmapRecommendationSource recommendationSource =
      RoadmapRecommendationSource.explicit,
}) => RoadmapSnapshot(
  projectId: 'p1',
  roadmapPath: 'docs/roadmap.md',
  contentSha256: 'sha',
  extractorVersion: 1,
  model: 'm',
  extractedAt: DateTime.utc(2026, 9, 26),
  status: status,
  recommended: recommended,
  recommendationSource: recommendationSource,
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

    test('reads HEAD and the status of only the task files', () async {
      final calls = <List<String>>[];
      final reader = ProjectGitStatusReader(
        run: (args, _) async {
          calls.add(args);
          return args.first == 'rev-parse' ? ok('abc\n') : ok(' M a.dart\n');
        },
      );

      final state = await reader.readTaskState('/repo', ['a.dart']);

      expect(state!.head, 'abc');
      expect(state.dirtyPaths, hasLength(1));
      expect(calls.last, ['status', '--porcelain', '--', 'a.dart']);
    });

    test('reports no task state when git rejects a path', () async {
      final reader = ProjectGitStatusReader(
        run: (args, _) async => args.first == 'rev-parse'
            ? ok('abc')
            : ProcessResult(0, 128, '', 'outside repository'),
      );
      expect(await reader.readTaskState('/repo', ['/elsewhere/a']), isNull);
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
    expect(created.goal!.projectTaskAutoReview, isFalse);
    // Named after the roadmap item, not the workflow's generic first prompt.
    expect(created.title, 'RC1: Signed-device evidence');
    expect(repository.getById(id)?.goal, isNotNull);
  });

  test('dashboard start opts into automatic review', () async {
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
    final id = startProjectTask(
      conversations: container.read(conversationsNotifierProvider.notifier),
      projectId: 'p1',
      item: _item,
      roadmapPath: 'docs/roadmap.md',
      autoReview: true,
    );
    final created = container
        .read(conversationsNotifierProvider)
        .conversationForId(id)!;
    expect(created.goal!.projectTaskAutoReview, isTrue);
    expect(
      ConversationGoal.fromJson(created.goal!.toJson()).projectTaskAutoReview,
      isTrue,
    );
    expect(created.messages, isEmpty);
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

    testWidgets('labels a priority-based suggestion', (tester) async {
      await pump(
        tester,
        _snapshot(recommendationSource: RoadmapRecommendationSource.priority),
      );
      expect(
        find.byKey(const ValueKey('project-dashboard-priority-suggestion')),
        findsOneWidget,
      );
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

  testWidgets('shows upcoming tasks in priority order beside status groups', (
    tester,
  ) async {
    final snapshot = _snapshot().copyWith(
      upcoming: const [
        RoadmapItemSnapshot(
          id: '',
          title: 'Retry requests',
          quote: 'Retry requests',
          line: 19,
        ),
        RoadmapItemSnapshot(
          id: '',
          title: 'Add tests',
          quote: 'Add tests',
          line: 21,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RoadmapItemsCard(snapshot: snapshot)),
      ),
    );

    expect(find.text('1. Retry requests'), findsOneWidget);
    expect(find.text('2. Add tests'), findsOneWidget);
    expect(find.text('docs/roadmap.md:19'), findsOneWidget);
    expect(find.text('docs/roadmap.md:21'), findsOneWidget);
    expect(find.text('RC1 · Signed-device evidence'), findsNothing);
  });

  testWidgets('labels a pinned next task', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NextTaskCard(
            snapshot: _snapshot().copyWith(pinned: true),
            hasRoadmap: true,
            refreshing: false,
            onStartWork: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('project-dashboard-pinned')),
      findsOneWidget,
    );
  });

  testWidgets('the roadmap path dialog refuses paths outside the project', (
    tester,
  ) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<String>(
              context: context,
              builder: (_) => const RoadmapPathDialog(
                projectRoot: '/repo',
                initialPath: '',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('roadmap-path-field'));
    final save = find.byKey(const ValueKey('roadmap-path-save'));

    await tester.enterText(field, '../secrets.md');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, 'unset', reason: 'the dialog stays open');

    await tester.enterText(field, 'PLAN.md');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, 'PLAN.md');
  });

  group('ProjectThreadsCard paging', () {
    Conversation thread(int n, {int minutesAgo = 0}) => Conversation(
      id: 't$n',
      title: 'Thread $n',
      messages: const [],
      createdAt: DateTime.utc(2026, 9, 26),
      updatedAt: DateTime.utc(
        2026,
        9,
        26,
        12,
      ).subtract(Duration(minutes: minutesAgo)),
      workspaceMode: WorkspaceMode.coding,
      projectId: 'p1',
    );

    test('orders threads needing approval, then running, then newest', () {
      final threads = [
        thread(1, minutesAgo: 1),
        thread(2, minutesAgo: 50),
        thread(3, minutesAgo: 30),
        thread(4, minutesAgo: 5),
      ];
      final sorted = sortThreadsForDashboard(
        threads,
        isBusy: (id) => id == 't3',
        needsApproval: (id) => id == 't2',
      );
      expect(sorted.map((t) => t.id), ['t2', 't3', 't1', 't4']);
    });

    Future<void> pump(WidgetTester tester, List<Conversation> threads) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProjectThreadsCard(
                  threads: threads,
                  isBusy: (_) => false,
                  needsApproval: (_) => false,
                  onOpen: (_) {},
                  pageSize: 3,
                ),
              ),
            ),
          ),
        );

    testWidgets('pages through threads and clamps when the list shrinks', (
      tester,
    ) async {
      final threads = [for (var n = 1; n <= 7; n++) thread(n, minutesAgo: n)];
      const next = ValueKey('project-dashboard-thread-next');
      const prev = ValueKey('project-dashboard-thread-prev');
      Finder row(int n) => find.byKey(ValueKey('project-dashboard-thread-t$n'));

      await pump(tester, threads);
      expect(row(1), findsOneWidget);
      expect(row(4), findsNothing);

      await tester.tap(find.byKey(next));
      await tester.pump();
      expect(row(4), findsOneWidget);
      expect(row(1), findsNothing);

      await tester.tap(find.byKey(next));
      await tester.pump();
      expect(row(7), findsOneWidget);

      // Only four threads left: page 3 no longer exists, so page 2 shows.
      await pump(tester, threads.take(4).toList());
      expect(row(4), findsOneWidget);

      await tester.tap(find.byKey(prev));
      await tester.pump();
      expect(row(1), findsOneWidget);
    });

    testWidgets('shows no paging controls for a single page', (tester) async {
      await pump(tester, [thread(1), thread(2)]);
      expect(
        find.byKey(const ValueKey('project-dashboard-thread-next')),
        findsNothing,
      );
    });
  });

  testWidgets(
    'puts roadmap progress beside threads when wide, stacked when narrow',
    (tester) async {
      const left = ValueKey('left');
      const right = ValueKey('right');
      Future<void> pumpAt(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: const DashboardSplit(
                    leading: SizedBox(key: left, height: 40),
                    trailing: SizedBox(key: right, height: 40),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await pumpAt(1000);
      expect(
        tester.getTopLeft(find.byKey(right)).dy,
        tester.getTopLeft(find.byKey(left)).dy,
      );
      expect(
        tester.getTopLeft(find.byKey(right)).dx,
        greaterThan(tester.getTopLeft(find.byKey(left)).dx),
      );

      await pumpAt(500);
      expect(
        tester.getTopLeft(find.byKey(right)).dy,
        greaterThan(tester.getTopLeft(find.byKey(left)).dy),
      );
    },
  );
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
