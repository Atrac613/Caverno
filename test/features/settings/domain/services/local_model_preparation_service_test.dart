import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
import 'package:caverno/features/settings/domain/services/local_model_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalModelPreparationService', () {
    const service = LocalModelPreparationService();

    test('plans explicit primary role models without duplicates', () {
      final settings = AppSettings.defaults().copyWith(
        codingPrimaryModel: 'primary-quality',
        memoryExtractionModel: 'small-model',
        subagentModel: 'small-model',
        goalSuggestionModel: 'mesh-model',
        goalSuggestionEndpointId: 'http://mesh-box:1234/v1',
        approvalAutoReviewModel: 'review-model',
      );

      final plan = service.buildPrimaryRoleModelPlan(
        settings: settings,
        catalog: const LocalModelLifecycleCatalog.supported(
          models: [
            LocalManagedModel(
              id: 'primary-quality',
              state: LocalModelLifecycleState.unloaded,
              statusValue: 'unloaded',
            ),
            LocalManagedModel(
              id: 'small-model',
              state: LocalModelLifecycleState.unloaded,
              statusValue: 'unloaded',
            ),
            LocalManagedModel(
              id: 'review-model',
              state: LocalModelLifecycleState.loaded,
              statusValue: 'loaded',
            ),
            LocalManagedModel(
              id: 'mesh-model',
              state: LocalModelLifecycleState.unloaded,
              statusValue: 'unloaded',
            ),
          ],
        ),
      );

      expect(plan.targetModelIds, [
        'primary-quality',
        'small-model',
        'review-model',
      ]);
      expect(plan.loadableModelIds, ['primary-quality', 'small-model']);
      expect(plan.readyModelIds, ['review-model']);
      expect(plan.missingModelIds, isEmpty);
    });

    test('classifies in-progress and missing role models as skipped', () {
      final settings = AppSettings.defaults().copyWith(
        memoryExtractionModel: 'loading-model',
        subagentModel: 'missing-model',
      );

      final plan = service.buildPrimaryRoleModelPlan(
        settings: settings,
        catalog: const LocalModelLifecycleCatalog.supported(
          models: [
            LocalManagedModel(
              id: 'loading-model',
              state: LocalModelLifecycleState.loading,
              statusValue: 'loading',
            ),
          ],
        ),
      );

      expect(plan.loadableModelIds, isEmpty);
      expect(plan.inProgressModelIds, ['loading-model']);
      expect(plan.missingModelIds, ['missing-model']);
    });

    test('plans role models for a selected named endpoint', () {
      final meshEndpoint = LlmEndpoint(
        id: 'mesh-box',
        label: 'Mesh Box',
        baseUrl: 'http://mesh-box:1234/v1',
      ).normalizedForPersistence();
      final settings = AppSettings.defaults().copyWith(
        llmEndpoints: [meshEndpoint],
        codingPrimaryModel: 'mesh-primary',
        codingPrimaryEndpointId: meshEndpoint.id,
        memoryExtractionModel: 'primary-small',
        subagentModel: 'mesh-subagent',
        subagentEndpointId: meshEndpoint.id,
        approvalAutoReviewModel: 'mesh-review',
        approvalAutoReviewEndpointId: meshEndpoint.id,
        proReasoningModel: 'mesh-reasoning',
        proReasoningEndpointId: meshEndpoint.id,
      );

      final plan = service.buildRoleModelPlanForEndpoint(
        settings: settings,
        endpointId: meshEndpoint.id,
        catalog: const LocalModelLifecycleCatalog.supported(
          models: [
            LocalManagedModel(
              id: 'mesh-primary',
              state: LocalModelLifecycleState.loaded,
              statusValue: 'loaded',
            ),
            LocalManagedModel(
              id: 'mesh-subagent',
              state: LocalModelLifecycleState.unloaded,
              statusValue: 'unloaded',
            ),
            LocalManagedModel(
              id: 'mesh-review',
              state: LocalModelLifecycleState.loaded,
              statusValue: 'loaded',
            ),
            LocalManagedModel(
              id: 'primary-small',
              state: LocalModelLifecycleState.unloaded,
              statusValue: 'unloaded',
            ),
            LocalManagedModel(
              id: 'mesh-reasoning',
              state: LocalModelLifecycleState.unloaded,
              statusValue: 'unloaded',
            ),
          ],
        ),
      );

      expect(plan.targetModelIds, [
        'mesh-primary',
        'mesh-subagent',
        'mesh-review',
        'mesh-reasoning',
      ]);
      expect(plan.loadableModelIds, ['mesh-subagent', 'mesh-reasoning']);
      expect(plan.readyModelIds, ['mesh-primary', 'mesh-review']);
    });
  });
}
