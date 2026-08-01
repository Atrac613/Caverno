import '../../data/datasources/mesh_secondary_completion_runner.dart';
import '../../../settings/domain/entities/app_settings.dart';

// ChatNotifier decomposition collaborator: secondary-completion-router

typedef SecondaryCompletionOperation<D, T> =
    Future<T> Function(D dataSource, String model);

/// Immutable routing facts captured before a secondary completion starts.
final class SecondaryCompletionRouteSnapshot {
  SecondaryCompletionRouteSnapshot({
    required this.provider,
    required this.primaryBaseUrl,
    required this.primaryApiKey,
    required this.primaryModel,
    required List<LlmEndpoint> enabledEndpoints,
    required this.selectedEndpointId,
    required this.selectedModel,
    String? fallbackModel,
  }) : enabledEndpoints = List<LlmEndpoint>.unmodifiable(enabledEndpoints),
       fallbackModel = fallbackModel ?? primaryModel;

  final LlmProvider provider;
  final String primaryBaseUrl;
  final String primaryApiKey;
  final String primaryModel;
  final List<LlmEndpoint> enabledEndpoints;
  final String selectedEndpointId;
  final String selectedModel;
  final String fallbackModel;
}

/// One planning-completion route attempt exposed for narrow logging.
final class SecondaryCompletionRouteMetadata {
  const SecondaryCompletionRouteMetadata({
    required this.model,
    required this.endpoint,
    required this.isFallback,
  });

  final String model;
  final String endpoint;
  final bool isFallback;
}

abstract interface class SecondaryCompletionLogPort {
  void recordPlanningAttempt(SecondaryCompletionRouteMetadata metadata);
}

typedef SecondaryCompletionLogCallback =
    void Function(SecondaryCompletionRouteMetadata metadata);

/// Adapts an existing planning log sink to the narrow metadata boundary.
final class CallbackSecondaryCompletionLogPort
    implements SecondaryCompletionLogPort {
  const CallbackSecondaryCompletionLogPort(this._record);

  final SecondaryCompletionLogCallback _record;

  @override
  void recordPlanningAttempt(SecondaryCompletionRouteMetadata metadata) =>
      _record(metadata);
}

/// Routes secondary completions without reading notifier or provider state.
final class SecondaryCompletionRouter<D> {
  const SecondaryCompletionRouter({
    required MeshSecondaryCompletionRunner<D> meshRunner,
    SecondaryCompletionLogPort? logPort,
  }) : _meshRunner = meshRunner,
       _logPort = logPort;

  final MeshSecondaryCompletionRunner<D> _meshRunner;
  final SecondaryCompletionLogPort? _logPort;

  Future<T> run<T>({
    required D primaryDataSource,
    required SecondaryCompletionRouteSnapshot route,
    required SecondaryCompletionOperation<D, T> operation,
  }) {
    return _run(
      primaryDataSource: primaryDataSource,
      route: route,
      endpointId: route.selectedEndpointId,
      operation: operation,
    );
  }

  Future<T> runPlanning<T>({
    required D primaryDataSource,
    required SecondaryCompletionRouteSnapshot route,
    required SecondaryCompletionOperation<D, T> operation,
  }) {
    final endpointId = route.selectedEndpointId.trim();
    final endpoint = endpointId.isEmpty ? 'primary' : endpointId;
    return _run(
      primaryDataSource: primaryDataSource,
      route: route,
      endpointId: endpointId,
      operation: (dataSource, model) {
        try {
          _logPort?.recordPlanningAttempt(
            SecondaryCompletionRouteMetadata(
              model: model,
              endpoint: endpoint,
              isFallback: model != route.selectedModel,
            ),
          );
        } catch (_) {}
        return operation(dataSource, model);
      },
    );
  }

  Future<T> _run<T>({
    required D primaryDataSource,
    required SecondaryCompletionRouteSnapshot route,
    required String endpointId,
    required SecondaryCompletionOperation<D, T> operation,
  }) {
    final resolvedEndpointId = route.provider == LlmProvider.openAiCompatible
        ? endpointId
        : '';
    return _meshRunner.run<T>(
      primary: primaryDataSource,
      primaryBaseUrl: route.primaryBaseUrl,
      primaryApiKey: route.primaryApiKey,
      endpoints: route.enabledEndpoints,
      endpointId: resolvedEndpointId,
      model: route.selectedModel,
      fallbackModel: route.fallbackModel,
      call: operation,
    );
  }
}
