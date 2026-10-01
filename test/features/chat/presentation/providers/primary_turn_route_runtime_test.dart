import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/presentation/providers/primary_turn_route_runtime.dart';
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
  }) => runtime.capture(
    generation: generation,
    settings: settings,
    purpose: PrimaryTurnPurpose.of(
      codeReview: codeReview,
      projectTaskImplementation: implementation,
      projectTaskStep: step,
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
