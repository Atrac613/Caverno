import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/services/apple_foundation_models_platform_client.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/apple_foundation_models_availability_provider.dart';

void main() {
  group('visibleLlmProviders', () {
    test('hides Apple Foundation Models when availability is unknown', () {
      final providers = visibleLlmProviders(
        appleFoundationModelsAvailability: null,
      );

      expect(providers, [LlmProvider.openAiCompatible]);
    });

    test('hides Apple Foundation Models when the device is not eligible', () {
      final providers = visibleLlmProviders(
        appleFoundationModelsAvailability:
            const AppleFoundationModelsAvailability(
              isAvailable: false,
              status: 'unavailable',
              reason: 'deviceNotEligible',
            ),
      );

      expect(providers, [LlmProvider.openAiCompatible]);
    });

    test(
      'shows Apple Foundation Models when Apple Intelligence is disabled',
      () {
        final providers = visibleLlmProviders(
          appleFoundationModelsAvailability:
              const AppleFoundationModelsAvailability(
                isAvailable: false,
                status: 'unavailable',
                reason: 'appleIntelligenceNotEnabled',
              ),
        );

        expect(providers, [
          LlmProvider.openAiCompatible,
          LlmProvider.appleFoundationModels,
        ]);
      },
    );

    test('shows Apple Foundation Models when the model is not ready', () {
      final providers = visibleLlmProviders(
        appleFoundationModelsAvailability:
            const AppleFoundationModelsAvailability(
              isAvailable: false,
              status: 'unavailable',
              reason: 'modelNotReady',
            ),
      );

      expect(providers, [
        LlmProvider.openAiCompatible,
        LlmProvider.appleFoundationModels,
      ]);
    });

    test('shows Apple Foundation Models when the device is available', () {
      final providers = visibleLlmProviders(
        appleFoundationModelsAvailability:
            const AppleFoundationModelsAvailability(
              isAvailable: true,
              status: 'available',
            ),
      );

      expect(providers, [
        LlmProvider.openAiCompatible,
        LlmProvider.appleFoundationModels,
      ]);
    });
  });

  group('selectableLlmProviders', () {
    test(
      'selects only OpenAI-compatible until Apple Foundation Models is ready',
      () {
        final providers = selectableLlmProviders(
          appleFoundationModelsAvailability:
              const AppleFoundationModelsAvailability(
                isAvailable: false,
                status: 'unavailable',
                reason: 'appleIntelligenceNotEnabled',
              ),
        );

        expect(providers, [LlmProvider.openAiCompatible]);
      },
    );

    test('selects Apple Foundation Models when it is available', () {
      final providers = selectableLlmProviders(
        appleFoundationModelsAvailability:
            const AppleFoundationModelsAvailability(
              isAvailable: true,
              status: 'available',
            ),
      );

      expect(providers, [
        LlmProvider.openAiCompatible,
        LlmProvider.appleFoundationModels,
      ]);
    });
  });

  group('isLlmProviderSelectable', () {
    test(
      'marks Apple Foundation Models unavailable until the model is ready',
      () {
        final isSelectable = isLlmProviderSelectable(
          provider: LlmProvider.appleFoundationModels,
          appleFoundationModelsAvailability:
              const AppleFoundationModelsAvailability(
                isAvailable: false,
                status: 'unavailable',
                reason: 'modelNotReady',
              ),
        );

        expect(isSelectable, isFalse);
      },
    );
  });

  group('visibleLlmProviderSelection', () {
    test(
      'falls back to OpenAI-compatible when selected provider is hidden',
      () {
        final visibleProvider = visibleLlmProviderSelection(
          selectedProvider: LlmProvider.appleFoundationModels,
          selectableProviders: const [LlmProvider.openAiCompatible],
        );

        expect(visibleProvider, LlmProvider.openAiCompatible);
      },
    );
  });
}
