import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
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
  }) => runtime.capture(
    generation: generation,
    settings: settings,
    projectTaskCommitScope: scope,
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
      await capture(runtime, 1, codeReview: false, prepare: true, scope: scope);
      await capture(runtime, 2, codeReview: false);
      expect(runtime.isProjectTaskCommitPreparation(1), isTrue);
      expect(runtime.isProjectTaskCommit(1), isFalse);
      expect(runtime.isProjectTaskTurn(1), isTrue);
      expect(runtime.commitScope(1), same(scope));
      expect(runtime.commitScope(2), isNull);
      runtime.release(1);
      expect(runtime.commitScope(1), isNull);
      expect(runtime.isProjectTaskCommitPreparation(1), isFalse);
      await capture(runtime, 1, codeReview: false, prepare: true, scope: scope);
      await capture(runtime, 1, codeReview: false);
      expect(runtime.commitScope(1), isNull);
      expect(runtime.isProjectTaskCommitPreparation(1), isFalse);
    },
  );

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
