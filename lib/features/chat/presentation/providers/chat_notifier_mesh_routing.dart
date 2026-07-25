// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// LL8 LAN inference mesh: route secondary LLM calls to a role's assigned mesh
/// endpoint, degrading to the primary endpoint so an active turn never fails
/// when a mesh member is unreachable.
extension ChatNotifierMeshRouting on ChatNotifier {
  /// Run a secondary LLM [call] for a role, routing it to the role's assigned
  /// mesh endpoint (with primary fallback) when the active provider is
  /// OpenAI-compatible. Other providers always use the primary data source.
  Future<T> _runSecondaryCompletion<T>({
    required String endpointId,
    required String model,
    required Future<T> Function(ChatDataSource dataSource, String model) call,
  }) {
    final resolvedEndpointId =
        _settings.llmProvider == LlmProvider.openAiCompatible ? endpointId : '';
    return _meshRunner.run<T>(
      primary: _dataSource,
      primaryBaseUrl: _settings.baseUrl,
      primaryApiKey: _settings.apiKey,
      endpoints: _settings.enabledLlmEndpoints,
      endpointId: resolvedEndpointId,
      model: model,
      // The assigned model lives on the mesh host; fall back to the primary's
      // main model so a demotion never sends a mesh-only model to the primary.
      fallbackModel: _settings.model,
      call: call,
    );
  }

  /// Run a plan-drafting completion (workflow / task proposal) on the planning
  /// role's model and endpoint; an unassigned role keeps the main model. Logs
  /// the model each attempt ran on: a mid-call demotion to the primary would
  /// otherwise draft the plan on another model invisibly.
  Future<T> _runPlanningCompletion<T>(
    Future<T> Function(ChatDataSource dataSource, String model) call,
  ) {
    final endpointId = _settings.planningEndpointId.trim();
    final planner = _settings.effectivePlanningModel;
    final target = endpointId.isEmpty ? 'primary' : endpointId;
    return _runSecondaryCompletion<T>(
      endpointId: endpointId,
      model: planner,
      call: (dataSource, model) {
        appLog(
          '[Planning] plan_draft model=$model endpoint=$target '
          'fallback=${model != planner}',
        );
        return call(dataSource, model);
      },
    );
  }
}
