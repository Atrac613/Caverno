import '../../../settings/domain/entities/app_settings.dart';
import '../../data/datasources/mesh_secondary_completion_runner.dart';
import 'secondary_completion_route_snapshot.dart';

export 'secondary_completion_route_snapshot.dart';

// ChatNotifier decomposition collaborator: secondary-completion-router

typedef SecondaryCompletionOperation<D, T> =
    Future<T> Function(D dataSource, String model);

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

  /// Every secondary completion funnels through here, which makes it the one
  /// place that can stamp the usage role. Doing it per call site would be both
  /// repetitive and fragile: a role started with `unawaited(...)` from inside a
  /// chat turn otherwise inherits that turn's zone.
  Future<T> _run<T>({
    required D primaryDataSource,
    required SecondaryCompletionRouteSnapshot route,
    required String endpointId,
    required SecondaryCompletionOperation<D, T> operation,
  }) {
    return route.usageRole.runWith(
      () => _runRouted(
        primaryDataSource: primaryDataSource,
        route: route,
        endpointId: endpointId,
        operation: operation,
      ),
    );
  }

  Future<T> _runRouted<T>({
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
