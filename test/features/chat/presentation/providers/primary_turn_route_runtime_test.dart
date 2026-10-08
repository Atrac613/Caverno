import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/services/project_task/project_task_review_verdict.dart';
import 'package:caverno/features/chat/domain/services/project_task/project_task_terminal_status.dart';
import 'package:caverno/features/chat/presentation/providers/primary_turn_route_runtime.dart';
import 'package:caverno/features/project_farm/domain/entities/project_task_commit_scope.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _MockChatDataSource extends Mock implements ChatDataSource {}

void main() {
  final settings = AppSettings.defaults().copyWith(
    demoMode: true,
    baseUrl: 'http://primary.example/v1',
    model: 'main-model',
    codeReviewModel: 'review-model',
    codeReviewEndpointId: 'review-host',
    llmEndpoints: const [
      LlmEndpoint(
        id: 'review-host',
        baseUrl: 'http://review.example/v1',
        model: 'review-model',
      ),
    ],
  );

  Future<void> capture(
    PrimaryTurnRouteRuntime runtime,
    int generation, {
    required bool codeReview,
    bool implementation = false,
    bool step = false,
    bool commit = false,
    bool prepare = false,
    ProjectTaskCommitScope? scope,
    String? promptId,
  }) => runtime.capture(
    generation: generation,
    settings: settings,
    projectTaskCommitScope: scope,
    taskCommitPromptId: promptId,
    purpose: prepare
        ? PrimaryTurnPurpose.projectTaskCommitPreparation
        : PrimaryTurnPurpose.of(
            codeReview: codeReview,
            projectTaskImplementation: implementation,
            projectTaskStep: step,
            projectTaskCommit: commit,
          ),
    assistantMode: AssistantMode.coding,
    primaryDataSource: _MockChatDataSource(),
    health: EndpointHealthTracker(),
    buildAssignedDataSource: (_) => _MockChatDataSource(),
    preparer: PrimaryRouteModelPreparer(
      serviceFactory: (_) => throw UnimplementedError(),
      logOutcome: (_) {},
      logError: (_, _) {},
    ),
    record: (_) async {},
  );

  test(
    'preparation scope is generation-owned and released or recaptured',
    () async {
      final runtime = PrimaryTurnRouteRuntime();
      final scope = ProjectTaskCommitScope(
        conversationId: 'task',
        projectRoot: '/repo',
        roadmapPath: '/repo/roadmap.md',
        reviewedPaths: ['/repo/task.txt'],
      );
      await capture(
        runtime,
        1,
        codeReview: false,
        prepare: true,
        scope: scope,
        promptId: 'phase-input',
      );
      expect(runtime.commitPromptStart(1), 'phase-input');
      await capture(runtime, 2, codeReview: false);
      expect(runtime.isProjectTaskCommitPreparation(1), isTrue);
      expect(runtime.isProjectTaskCommit(1), isFalse);
      expect(runtime.isProjectTaskTurn(1), isTrue);
      expect(runtime.commitScope(1), same(scope));
      expect(runtime.commitScope(2), isNull);
      runtime.release(1);
      expect(runtime.commitPromptStart(1), isNull);
      expect(runtime.commitScope(1), isNull);
      expect(runtime.isProjectTaskCommitPreparation(1), isFalse);
      await capture(runtime, 1, codeReview: false, prepare: true, scope: scope);
      await capture(runtime, 1, codeReview: false);
      expect(runtime.commitScope(1), isNull);
      expect(runtime.isProjectTaskCommitPreparation(1), isFalse);
    },
  );

  test(
    'commit terminal flags survive teardown and require the matching owner',
    () async {
      final runtime = PrimaryTurnRouteRuntime();
      await capture(runtime, 1, codeReview: false, prepare: true);
      runtime.recordCommitTerminal(1, 'task', true);
      runtime.release(1);
      expect(runtime.takeCommitTerminal(1, 'other'), isNull);
      expect(runtime.takeCommitTerminal(1, 'task')?.completedNormally, isTrue);
      expect(runtime.takeCommitTerminal(1, 'task'), isNull);
      await capture(runtime, 2, codeReview: false, commit: true);
      runtime.recordCommitTerminal(2, 'task', false);
      runtime.release(2);
      expect(runtime.takeCommitTerminal(2, 'task')?.completedNormally, isFalse);
    },
  );
  test(
    'ordinary turns and recaptured generations cannot supply stale flags',
    () async {
      final runtime = PrimaryTurnRouteRuntime();
      await capture(runtime, 1, codeReview: false);
      runtime.recordCommitTerminal(1, 'task', true);
      expect(runtime.takeCommitTerminal(1, 'task'), isNull);
      await capture(runtime, 2, codeReview: false, commit: true);
      runtime.recordCommitTerminal(2, 'task', true);
      await capture(runtime, 2, codeReview: false, prepare: true);
      expect(runtime.takeCommitTerminal(2, 'task'), isNull);
    },
  );
  test('unconsumed commit terminal flags have bounded retention', () async {
    final runtime = PrimaryTurnRouteRuntime();
    for (var generation = 1; generation <= 17; generation++) {
      await capture(runtime, generation, codeReview: false, commit: true);
      runtime.recordCommitTerminal(generation, 'task', true);
      runtime.release(generation);
    }
    expect(runtime.takeCommitTerminal(1, 'task'), isNull);
    expect(runtime.takeCommitTerminal(2, 'task')?.completedNormally, isTrue);
    expect(runtime.takeCommitTerminal(17, 'task')?.completedNormally, isTrue);
  });

  test('a subtask step is neither implementation nor review', () async {
    // Session 80dc7079: subtask turns lost the implementation turn's
    // exemption from prose continuation recovery, which forced an extra tool
    // call after a finished subtask.
    final runtime = PrimaryTurnRouteRuntime();
    await capture(runtime, 1, codeReview: false, step: true);
    expect(runtime.isProjectTaskStep(1), isTrue);
    expect(runtime.isProjectTaskImplementation(1), isFalse);
    expect(runtime.isCodeReview(1), isFalse);
    await capture(runtime, 1, codeReview: false);
    expect(runtime.isProjectTaskStep(1), isFalse);
    await capture(runtime, 2, codeReview: false, step: true);
    runtime.release(2);
    expect(runtime.isProjectTaskStep(2), isFalse);
  });
  test(
    'reviewed commit turns do not inherit subtask marker requirements',
    () async {
      final runtime = PrimaryTurnRouteRuntime();
      await capture(runtime, 1, codeReview: false, commit: true);
      expect(runtime.isProjectTaskTurn(1), isTrue);
      expect(runtime.isProjectTaskCommit(1), isTrue);
      expect(runtime.isProjectTaskStep(1), isFalse);
      expect(runtime.isProjectTaskImplementation(1), isFalse);
      await capture(runtime, 1, codeReview: false, step: true);
      expect(runtime.isProjectTaskCommit(1), isFalse);
      await capture(runtime, 2, codeReview: false, commit: true);
      runtime.release(2);
      expect(runtime.isProjectTaskCommit(2), isFalse);
    },
  );

  test(
    'implementation metadata cannot leak to review or a recaptured turn',
    () async {
      final runtime = PrimaryTurnRouteRuntime();
      await capture(runtime, 1, codeReview: false, implementation: true);
      await capture(runtime, 2, codeReview: true, implementation: true);
      expect(runtime.isProjectTaskImplementation(1), isTrue);
      expect(runtime.isProjectTaskImplementation(2), isFalse);
      await capture(runtime, 1, codeReview: false);
      expect(runtime.isProjectTaskImplementation(1), isFalse);
      await capture(runtime, 1, codeReview: false, implementation: true);
      runtime.release(1);
      expect(runtime.isProjectTaskImplementation(1), isFalse);
    },
  );

  test('subtask verdict survives teardown and is owner scoped', () async {
    final runtime = PrimaryTurnRouteRuntime();
    await capture(runtime, 7, codeReview: false, step: true);
    final status = ProjectTaskTerminalStatus.subtask(
      taskId: 'step',
      accepted: false,
      gaps: ['Required subtask tool actions remain unexecuted.'],
      gapCodes: ['unexecuted_actions'],
    );
    runtime.recordSubtaskTerminal(7, 'task', status);
    runtime.release(7);
    expect(runtime.takeSubtaskTerminal(7, 'other'), isNull);
    expect(runtime.takeSubtaskTerminal(7, 'task'), same(status));
    expect(runtime.takeSubtaskTerminal(7, 'task'), isNull);
    await capture(runtime, 8, codeReview: false, step: true);
    runtime.recordSubtaskTerminal(8, 'task', status);
    await capture(runtime, 8, codeReview: false);
    expect(runtime.takeSubtaskTerminal(8, 'task'), isNull);
  });

  test(
    'review verdict survives teardown and cannot be replaced or stolen',
    () async {
      final runtime = PrimaryTurnRouteRuntime();
      await capture(runtime, 31, codeReview: true);
      final findings = ProjectTaskReviewVerdict.fromResponse(
        'Fix Infinity.\nPROJECT_TASK_REVIEW_FINDINGS',
      );
      runtime.recordReviewTerminal(31, 'task', findings);
      runtime.recordReviewTerminal(
        31,
        'task',
        ProjectTaskReviewVerdict.fromResponse(
          'No findings.\nPROJECT_TASK_REVIEW_CLEAN',
        ),
      );
      runtime.release(31);
      expect(runtime.reviewTerminal(31, 'task'), same(findings));
      expect(runtime.reviewTerminal(31, 'other'), isNull);
      expect(runtime.takeReviewTerminal(31, 'other'), isNull);
      expect(runtime.takeReviewTerminal(31, 'task'), same(findings));
      expect(runtime.takeReviewTerminal(31, 'task'), isNull);
    },
  );

  test('remembers a review turn until its route is released', () async {
    final runtime = PrimaryTurnRouteRuntime();

    await capture(runtime, 1, codeReview: true);
    await capture(runtime, 2, codeReview: false);

    expect(runtime.isCodeReview(1), isTrue);
    expect(runtime.isCodeReview(2), isFalse);

    runtime.release(1);
    expect(runtime.isCodeReview(1), isFalse);
  });

  test('a recaptured generation drops a stale review flag', () async {
    final runtime = PrimaryTurnRouteRuntime();

    await capture(runtime, 1, codeReview: true);
    await capture(runtime, 1, codeReview: false);

    expect(runtime.isCodeReview(1), isFalse);
  });
}
