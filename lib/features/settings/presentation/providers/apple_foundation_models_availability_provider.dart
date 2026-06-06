import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/apple_foundation_models_platform_client.dart';
import '../../domain/entities/app_settings.dart';

final appleFoundationModelsClientProvider =
    Provider<AppleFoundationModelsClient>(
      (ref) => MethodChannelAppleFoundationModelsClient(),
    );

final appleFoundationModelsAvailabilityProvider =
    FutureProvider.autoDispose<AppleFoundationModelsAvailability>((ref) async {
      final client = ref.watch(appleFoundationModelsClientProvider);
      return client.checkAvailability();
    });

List<LlmProvider> selectableLlmProviders({
  required AppleFoundationModelsAvailability? appleFoundationModelsAvailability,
}) {
  return visibleLlmProviders(
        appleFoundationModelsAvailability: appleFoundationModelsAvailability,
      )
      .where((provider) {
        return isLlmProviderSelectable(
          provider: provider,
          appleFoundationModelsAvailability: appleFoundationModelsAvailability,
        );
      })
      .toList(growable: false);
}

List<LlmProvider> visibleLlmProviders({
  required AppleFoundationModelsAvailability? appleFoundationModelsAvailability,
}) {
  final providers = [LlmProvider.openAiCompatible];
  if (_shouldShowAppleFoundationModels(appleFoundationModelsAvailability)) {
    providers.add(LlmProvider.appleFoundationModels);
  }
  return providers;
}

bool isLlmProviderSelectable({
  required LlmProvider provider,
  required AppleFoundationModelsAvailability? appleFoundationModelsAvailability,
}) {
  return switch (provider) {
    LlmProvider.openAiCompatible => true,
    LlmProvider.appleFoundationModels =>
      appleFoundationModelsAvailability?.isAvailable == true,
  };
}

LlmProvider visibleLlmProviderSelection({
  required LlmProvider selectedProvider,
  required List<LlmProvider> selectableProviders,
}) {
  if (selectableProviders.contains(selectedProvider)) {
    return selectedProvider;
  }
  return LlmProvider.openAiCompatible;
}

bool _shouldShowAppleFoundationModels(
  AppleFoundationModelsAvailability? availability,
) {
  if (availability == null) {
    return false;
  }
  if (availability.isAvailable) {
    return true;
  }
  return switch (availability.reason) {
    'appleIntelligenceNotEnabled' || 'modelNotReady' => true,
    _ => false,
  };
}
