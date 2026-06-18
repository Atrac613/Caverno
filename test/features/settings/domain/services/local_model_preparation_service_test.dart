import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
import 'package:caverno/features/settings/domain/services/local_model_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalModelPreparationService', () {
    const service = LocalModelPreparationService();

    test('plans explicit primary role models without duplicates', () {
      final settings = AppSettings.defaults().copyWith(
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

      expect(plan.targetModelIds, ['small-model', 'review-model']);
      expect(plan.loadableModelIds, ['small-model']);
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
      final meshEndpoint = NamedEndpoint(
        id: NamedEndpoint.buildId('http://mesh-box:1234/v1'),
        label: 'Mesh Box',
        baseUrl: 'http://mesh-box:1234/v1',
      ).normalizedForPersistence();
      final settings = AppSettings.defaults().copyWith(
        namedEndpoints: [meshEndpoint],
        memoryExtractionModel: 'primary-small',
        subagentModel: 'mesh-subagent',
        subagentEndpointId: meshEndpoint.id,
        approvalAutoReviewModel: 'mesh-review',
        approvalAutoReviewEndpointId: meshEndpoint.id,
      );

      final plan = service.buildRoleModelPlanForEndpoint(
        settings: settings,
        endpointId: meshEndpoint.id,
        catalog: const LocalModelLifecycleCatalog.supported(
          models: [
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
          ],
        ),
      );

      expect(plan.targetModelIds, ['mesh-subagent', 'mesh-review']);
      expect(plan.loadableModelIds, ['mesh-subagent']);
      expect(plan.readyModelIds, ['mesh-review']);
    });
  });
}
