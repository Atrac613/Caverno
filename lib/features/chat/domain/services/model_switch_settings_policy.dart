import '../../../settings/domain/entities/app_settings.dart';

// ChatNotifier decomposition collaborator: model-switch-settings-policy

final class ModelSwitchSettingsComparison {
  const ModelSwitchSettingsComparison({
    required this.previousRouteId,
    required this.nextRouteId,
    required this.routeChanged,
    required this.previousPrimaryModelForPreparation,
    required this.shouldRebuildDataSource,
  });

  final String previousRouteId;
  final String nextRouteId;
  final bool routeChanged;
  final String? previousPrimaryModelForPreparation;
  final bool shouldRebuildDataSource;
}

final class ModelSwitchSettingsPolicy {
  const ModelSwitchSettingsPolicy();

  ModelSwitchSettingsComparison compare({
    required AppSettings previous,
    required AppSettings next,
  }) {
    final previousRouteId = _routeId(previous);
    final nextRouteId = _routeId(next);
    return ModelSwitchSettingsComparison(
      previousRouteId: previousRouteId,
      nextRouteId: nextRouteId,
      routeChanged: previousRouteId != nextRouteId,
      previousPrimaryModelForPreparation: _previousModelForPreparation(
        previous,
        next,
      ),
      shouldRebuildDataSource: _shouldRebuildDataSource(previous, next),
    );
  }

  String _routeId(AppSettings settings) => ModelCapabilityProfile.buildId(
    provider: settings.llmProvider,
    baseUrl: settings.baseUrl,
    model: settings.effectiveModel,
  );

  String? _previousModelForPreparation(AppSettings previous, AppSettings next) {
    if (previous.llmProvider != LlmProvider.openAiCompatible ||
        next.llmProvider != LlmProvider.openAiCompatible ||
        previous.demoMode ||
        next.demoMode ||
        previous.baseUrl.trim() != next.baseUrl.trim() ||
        previous.apiKey.trim() != next.apiKey.trim()) {
      return null;
    }
    final previousModel = previous.model.trim();
    final nextModel = next.model.trim();
    return previousModel.isEmpty || previousModel == nextModel
        ? null
        : previousModel;
  }

  bool _shouldRebuildDataSource(AppSettings previous, AppSettings next) =>
      previous.demoMode != next.demoMode ||
      previous.llmProvider != next.llmProvider ||
      previous.baseUrl != next.baseUrl ||
      previous.apiKey != next.apiKey ||
      previous.reasoningEffort != next.reasoningEffort ||
      previous.enableLlmSessionLogs != next.enableLlmSessionLogs;
}
