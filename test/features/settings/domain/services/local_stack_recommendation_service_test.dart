import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/local_host_resources.dart';
import 'package:caverno/features/settings/domain/entities/local_model_lifecycle.dart';
import 'package:caverno/features/settings/domain/services/local_stack_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = LocalStackRecommendationService();

  test('classifies router models with detected memory and stated budgets', () {
    final guidance = service.buildGuidance(
      hostProfile: const LocalHostResourceProfile.detected(
        totalMemoryBytes: 32 * localHostBytesPerGiB,
        appleSiliconUnifiedMemory: true,
        detectionMethod: 'test',
      ),
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'Qwen3-7B-Q4_K_M',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
            contextWindowTokens: 4096,
          ),
          LocalManagedModel(
            id: 'Huge-70B-Q8_0',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
            contextWindowTokens: 8192,
          ),
          LocalManagedModel(
            id: 'custom-chat-model',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
          ),
        ],
      ),
    );

    expect(guidance.hasDetectedMemory, isTrue);
    expect(guidance.safeBudgetBytes, 24051816857);
    expect(
      guidance.recommendationFor('Qwen3-7B-Q4_K_M')?.fit,
      LocalModelResourceFit.fits,
    );
    expect(
      guidance.recommendationFor('Huge-70B-Q8_0')?.fit,
      LocalModelResourceFit.tooLarge,
    );
    expect(
      guidance.recommendationFor('custom-chat-model')?.reason,
      LocalModelResourceReason.missingModelHints,
    );
    expect(guidance.fitCount, 1);
    expect(guidance.tooLargeCount, 1);
    expect(guidance.unknownCount, 1);
  });

  test('never marks models beyond detected memory as fitting', () {
    final guidance = service.buildGuidance(
      hostProfile: const LocalHostResourceProfile.detected(
        totalMemoryBytes: 8 * localHostBytesPerGiB,
        appleSiliconUnifiedMemory: true,
        detectionMethod: 'test',
      ),
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'Qwen3-32B-Q4_K_M',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
          ),
        ],
      ),
    );

    final recommendation = guidance.recommendationFor('Qwen3-32B-Q4_K_M');

    expect(recommendation?.estimatedMemoryBytes, isNotNull);
    expect(
      recommendation!.estimatedMemoryBytes!,
      greaterThan(guidance.hostProfile.totalMemoryBytes!),
    );
    expect(recommendation.fit, LocalModelResourceFit.tooLarge);
  });

  test('uses path hints when model ids omit size and quantization', () {
    final guidance = service.buildGuidance(
      hostProfile: const LocalHostResourceProfile.detected(
        totalMemoryBytes: 16 * localHostBytesPerGiB,
        appleSiliconUnifiedMemory: false,
        detectionMethod: 'test',
      ),
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'assistant',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
            path: '/models/Qwen3-Embedding-0.6B-Q8_0.gguf',
          ),
        ],
      ),
    );

    final recommendation = guidance.recommendationFor('assistant');

    expect(recommendation?.parameterBillion, 0.6);
    expect(recommendation?.quantization, LocalModelQuantizationHint.q8);
    expect(recommendation?.fit, LocalModelResourceFit.fits);
  });

  test('uses metadata hints when ids omit size and quantization', () {
    final guidance = service.buildGuidance(
      hostProfile: const LocalHostResourceProfile.detected(
        totalMemoryBytes: 64 * localHostBytesPerGiB,
        appleSiliconUnifiedMemory: true,
        detectionMethod: 'test',
      ),
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'google/gemma',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
            metadataHints: ['26B-A4B', 'Q4_K_M'],
          ),
        ],
      ),
    );

    final recommendation = guidance.recommendationFor('google/gemma');

    expect(recommendation?.parameterBillion, 26);
    expect(recommendation?.quantization, LocalModelQuantizationHint.q4);
    expect(recommendation?.fit, LocalModelResourceFit.fits);
  });

  test('returns unknown recommendations when host memory is unavailable', () {
    final guidance = service.buildGuidance(
      hostProfile: const LocalHostResourceProfile.unknown(),
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'Qwen3-7B-Q4_K_M',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
          ),
        ],
      ),
    );

    expect(guidance.hasDetectedMemory, isFalse);
    expect(
      guidance.recommendationFor('Qwen3-7B-Q4_K_M')?.reason,
      LocalModelResourceReason.missingHostMemory,
    );
  });

  test('recommends ngram and draft-model speedups for coding models', () {
    final guidance = service.buildSpeedupGuidance(
      settings: AppSettings.defaults().copyWith(
        model: 'Qwen3-Coder-30B-A3B-Q4_K_M',
      ),
      endpointId: '',
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'Qwen3-Coder-30B-A3B-Q4_K_M',
            state: LocalModelLifecycleState.loaded,
            statusValue: 'loaded',
          ),
          LocalManagedModel(
            id: 'Qwen3-Coder-Draft-1.5B-Q4_K_M',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
          ),
        ],
      ),
    );

    expect(
      guidance
          .recommendationFor(LocalStackSpeedupKind.ngramSpeculation)
          ?.status,
      LocalStackSpeedupStatus.recommended,
    );
    final draft = guidance.recommendationFor(
      LocalStackSpeedupKind.draftModelSpeculation,
    );
    expect(draft?.status, LocalStackSpeedupStatus.recommended);
    expect(draft?.targetModelId, 'Qwen3-Coder-30B-A3B-Q4_K_M');
    expect(draft?.draftModelId, 'Qwen3-Coder-Draft-1.5B-Q4_K_M');
  });

  test('detects already configured ngram speculation', () {
    final guidance = service.buildSpeedupGuidance(
      settings: AppSettings.defaults().copyWith(model: 'Qwen3-7B-Q4_K_M'),
      endpointId: '',
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'Qwen3-7B-Q4_K_M',
            state: LocalModelLifecycleState.loaded,
            statusValue: 'loaded',
            commandArguments: ['llama-server', '--spec-type', 'ngram-simple'],
          ),
        ],
      ),
    );

    expect(
      guidance
          .recommendationFor(LocalStackSpeedupKind.ngramSpeculation)
          ?.status,
      LocalStackSpeedupStatus.alreadyConfigured,
    );
  });

  test('uses selected endpoint subagent model for draft guidance', () {
    final settings = AppSettings.defaults().copyWith(
      subagentModel: 'Mesh-Coder-14B-Q4_K_M',
      subagentEndpointId: 'mesh-endpoint',
    );

    final guidance = service.buildSpeedupGuidance(
      settings: settings,
      endpointId: 'mesh-endpoint',
      catalog: const LocalModelLifecycleCatalog.supported(
        models: [
          LocalManagedModel(
            id: 'Mesh-Coder-14B-Q4_K_M',
            state: LocalModelLifecycleState.unloaded,
            statusValue: 'unloaded',
          ),
        ],
      ),
    );

    final draft = guidance.recommendationFor(
      LocalStackSpeedupKind.draftModelSpeculation,
    );
    expect(draft?.targetModelId, 'Mesh-Coder-14B-Q4_K_M');
    expect(draft?.status, LocalStackSpeedupStatus.needsDraftModel);
  });

  test('suggests smaller fit models for roles that use the main model', () {
    final catalog = const LocalModelLifecycleCatalog.supported(
      models: [
        LocalManagedModel(
          id: 'Qwen3-Coder-30B-A3B-Q4_K_M',
          state: LocalModelLifecycleState.loaded,
          statusValue: 'loaded',
        ),
        LocalManagedModel(
          id: 'Qwen3-1.7B-Q4_K_M',
          state: LocalModelLifecycleState.unloaded,
          statusValue: 'unloaded',
        ),
      ],
    );
    final resourceGuidance = _detectedGuidance(catalog);

    final guidance = service.buildRoleGuidance(
      settings: AppSettings.defaults().copyWith(
        model: 'Qwen3-Coder-30B-A3B-Q4_K_M',
      ),
      endpointId: '',
      catalog: catalog,
      resourceGuidance: resourceGuidance,
    );

    final memory = guidance.suggestionFor(LocalStackRoleKind.memoryExtraction);

    expect(memory?.status, LocalStackRoleSuggestionStatus.suggestSmallerModel);
    expect(memory?.usesMainModel, isTrue);
    expect(memory?.assignedModelId, 'Qwen3-Coder-30B-A3B-Q4_K_M');
    expect(memory?.suggestedModelId, 'Qwen3-1.7B-Q4_K_M');
  });

  test('uses selected endpoint role assignments for role suggestions', () {
    final settings = AppSettings.defaults().copyWith(
      subagentModel: 'Mesh-Coder-14B-Q4_K_M',
      subagentEndpointId: 'mesh-endpoint',
    );
    final catalog = const LocalModelLifecycleCatalog.supported(
      models: [
        LocalManagedModel(
          id: 'Mesh-Coder-14B-Q4_K_M',
          state: LocalModelLifecycleState.unloaded,
          statusValue: 'unloaded',
        ),
        LocalManagedModel(
          id: 'Mesh-Coder-3B-Q4_K_M',
          state: LocalModelLifecycleState.unloaded,
          statusValue: 'unloaded',
        ),
      ],
    );
    final resourceGuidance = _detectedGuidance(catalog);

    final guidance = service.buildRoleGuidance(
      settings: settings,
      endpointId: 'mesh-endpoint',
      catalog: catalog,
      resourceGuidance: resourceGuidance,
    );

    expect(guidance.suggestions, hasLength(1));
    final subagent = guidance.suggestionFor(LocalStackRoleKind.subagent);
    expect(
      subagent?.status,
      LocalStackRoleSuggestionStatus.suggestSmallerModel,
    );
    expect(subagent?.suggestedModelId, 'Mesh-Coder-3B-Q4_K_M');
  });

  test('does not suggest draft or embedding models as role candidates', () {
    final catalog = const LocalModelLifecycleCatalog.supported(
      models: [
        LocalManagedModel(
          id: 'Qwen3-Coder-30B-A3B-Q4_K_M',
          state: LocalModelLifecycleState.loaded,
          statusValue: 'loaded',
        ),
        LocalManagedModel(
          id: 'Qwen3-Embedding-0.6B-Q8_0',
          state: LocalModelLifecycleState.unloaded,
          statusValue: 'unloaded',
        ),
        LocalManagedModel(
          id: 'Qwen3-Draft-1.5B-Q4_K_M',
          state: LocalModelLifecycleState.unloaded,
          statusValue: 'unloaded',
        ),
      ],
    );
    final resourceGuidance = _detectedGuidance(catalog);

    final guidance = service.buildRoleGuidance(
      settings: AppSettings.defaults().copyWith(
        model: 'Qwen3-Coder-30B-A3B-Q4_K_M',
      ),
      endpointId: '',
      catalog: catalog,
      resourceGuidance: resourceGuidance,
    );

    final memory = guidance.suggestionFor(LocalStackRoleKind.memoryExtraction);
    expect(memory?.status, LocalStackRoleSuggestionStatus.noFitCandidate);
    expect(memory?.suggestedModelId, isNull);
  });
}

LocalStackResourceGuidance _detectedGuidance(
  LocalModelLifecycleCatalog catalog,
) {
  return const LocalStackRecommendationService().buildGuidance(
    hostProfile: const LocalHostResourceProfile.detected(
      totalMemoryBytes: 64 * localHostBytesPerGiB,
      appleSiliconUnifiedMemory: true,
      detectionMethod: 'test',
    ),
    catalog: catalog,
  );
}
