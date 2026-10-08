import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository_api.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/project_farm/domain/project_task_progress.dart';
import 'package:caverno/features/project_farm/presentation/providers/project_task_progress_provider.dart';
import 'package:caverno/features/project_farm/presentation/widgets/project_task_progress_section.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    ProjectTaskProgress? progress, {
    bool startedTask = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = _InMemoryConversationRepository();
    final now = DateTime(2026);
    if (startedTask) {
      await repository.save(
        Conversation(
          id: 'task',
          title: 'Task',
          messages: [
            Message(
              id: 'm',
              content: 'Earlier run.',
              role: MessageRole.assistant,
              timestamp: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
          goal: ConversationGoal(
            id: 'g',
            objective: 'Implement',
            projectTaskAutoReview: true,
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
    }
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        conversationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    if (progress != null) {
      container
          .read(projectTaskProgressProvider.notifier)
          .report('task', progress);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: ProjectTaskProgressSection(conversationId: 'task'),
          ),
        ),
      ),
    );
    return container;
  }

  Finder step(String label, String state) => find.byKey(
    ValueKey('project-task-step-project_task_progress.$label-$state'),
  );

  testWidgets('renders nothing for a thread without a workflow run', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.byKey(const ValueKey('project-task-progress')), findsNothing);
  });

  testWidgets('shows finished, current and remaining stages', (tester) async {
    await pump(
      tester,
      const ProjectTaskProgress(
        phase: ProjectTaskPhase.implement,
        subtaskIndex: 1,
        subtaskCount: 3,
      ),
    );

    expect(step('decompose', 'done'), findsOneWidget);
    expect(step('implement', 'active'), findsOneWidget);
    // One finished; the second is running.
    expect(find.text('project_task_progress.subtasks_done'), findsOneWidget);
    expect(step('review', 'pending'), findsOneWidget);
    expect(step('commit', 'pending'), findsOneWidget);
  });

  testWidgets('names the repair round on the review stage', (tester) async {
    await pump(
      tester,
      const ProjectTaskProgress(
        phase: ProjectTaskPhase.repair,
        subtaskIndex: 2,
        subtaskCount: 3,
        repairRound: 1,
      ),
    );

    expect(step('implement', 'done'), findsOneWidget);
    expect(find.text('project_task_progress.subtasks_done'), findsOneWidget);
    expect(step('review', 'active'), findsOneWidget);
    expect(find.text('project_task_progress.repair_round'), findsOneWidget);
  });

  testWidgets('marks the failed stage and shows why it stopped', (
    tester,
  ) async {
    await pump(
      tester,
      const ProjectTaskProgress(
        phase: ProjectTaskPhase.commit,
        outcome: ProjectTaskOutcome.stopped,
        stopReason: 'the commit turn recorded no new commit',
      ),
    );

    expect(step('review', 'done'), findsOneWidget);
    expect(step('commit', 'failed'), findsOneWidget);
    expect(find.text('the commit turn recorded no new commit'), findsOneWidget);
  });

  testWidgets('shows every stage done once committed', (tester) async {
    await pump(
      tester,
      const ProjectTaskProgress(
        phase: ProjectTaskPhase.commit,
        outcome: ProjectTaskOutcome.committed,
      ),
    );
    for (final label in ['decompose', 'implement', 'review', 'commit']) {
      expect(step(label, 'done'), findsOneWidget, reason: label);
    }
  });

  test('counts finished subtasks, not the running one', () {
    // Session 6f3ea3cf: the sidebar read "3/3" while the third subtask had
    // not finished and the workflow had stopped on it.
    const running = ProjectTaskProgress(
      phase: ProjectTaskPhase.implement,
      subtaskIndex: 2,
      subtaskCount: 3,
    );
    expect(running.completedSubtasks, 2);
    expect(
      running.copyWith(outcome: ProjectTaskOutcome.stopped).completedSubtasks,
      2,
    );
    expect(
      running.copyWith(phase: ProjectTaskPhase.review).completedSubtasks,
      3,
    );
    expect(
      const ProjectTaskProgress(
        phase: ProjectTaskPhase.decompose,
      ).completedSubtasks,
      0,
    );
  });

  group('resume', () {
    // The sidebar kept "findings remain" after manual fixes with no way to
    // continue the workflow.
    final resume = find.byKey(const ValueKey('project-task-resume'));
    for (final outcome in ProjectTaskOutcome.values) {
      testWidgets('offers resume only after a stop: ${outcome.name}', (
        tester,
      ) async {
        await pump(
          tester,
          ProjectTaskProgress(phase: ProjectTaskPhase.review, outcome: outcome),
        );
        expect(
          resume,
          outcome == ProjectTaskOutcome.findingsRemain ||
                  outcome == ProjectTaskOutcome.stopped
              ? findsOneWidget
              : findsNothing,
        );
      });
    }

    testWidgets('a started task offers resume after a restart', (tester) async {
      await pump(tester, null, startedTask: true);
      expect(resume, findsOneWidget);
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
