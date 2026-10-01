import 'package:caverno/features/project_farm/domain/project_task_progress.dart';
import 'package:caverno/features/project_farm/presentation/providers/project_task_progress_provider.dart';
import 'package:caverno/features/project_farm/presentation/widgets/project_task_progress_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    ProjectTaskProgress? progress,
  ) async {
    final container = ProviderContainer();
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
    expect(find.text('2/3'), findsOneWidget);
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
    expect(find.text('3/3'), findsOneWidget);
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
}
