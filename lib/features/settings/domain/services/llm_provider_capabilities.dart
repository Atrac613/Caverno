import '../entities/app_settings.dart';

class LlmProviderCapabilities {
  const LlmProviderCapabilities({
    required this.supportsNativeToolCalls,
    required this.supportsTextualToolBridge,
    required this.supportsLlmMemoryExtraction,
    required this.supportsAdvancedLiveToolDiagnostics,
  });

  final bool supportsNativeToolCalls;
  final bool supportsTextualToolBridge;
  final bool supportsLlmMemoryExtraction;
  final bool supportsAdvancedLiveToolDiagnostics;

  bool get supportsAnyToolBridge =>
      supportsNativeToolCalls || supportsTextualToolBridge;

  static const openAiCompatible = LlmProviderCapabilities(
    supportsNativeToolCalls: true,
    supportsTextualToolBridge: false,
    supportsLlmMemoryExtraction: true,
    supportsAdvancedLiveToolDiagnostics: true,
  );

  static const appleFoundationModels = LlmProviderCapabilities(
    supportsNativeToolCalls: false,
    supportsTextualToolBridge: true,
    supportsLlmMemoryExtraction: false,
    supportsAdvancedLiveToolDiagnostics: false,
  );
}

extension LlmProviderCapabilitiesX on LlmProvider {
  LlmProviderCapabilities get capabilities => switch (this) {
    LlmProvider.openAiCompatible => LlmProviderCapabilities.openAiCompatible,
    LlmProvider.appleFoundationModels =>
      LlmProviderCapabilities.appleFoundationModels,
  };
}

extension AppSettingsLlmCapabilitiesX on AppSettings {
  LlmProviderCapabilities get llmCapabilities => llmProvider.capabilities;
}
