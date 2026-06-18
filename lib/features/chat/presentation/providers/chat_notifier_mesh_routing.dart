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
      endpoints: _settings.namedEndpoints,
      endpointId: resolvedEndpointId,
      model: model,
      call: call,
    );
  }
}
