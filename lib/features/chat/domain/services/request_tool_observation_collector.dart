import '../entities/mcp_tool_entity.dart';
import 'immutable_json_snapshot.dart';

// ChatNotifier decomposition collaborator: request-tool-observation-collector

/// Immutable request-time snapshot of the available tool catalog.
final class RequestToolCatalogSnapshot {
  RequestToolCatalogSnapshot({
    required this.connectionStatus,
    required List<Map<String, dynamic>> toolDefinitions,
    required List<Map<String, dynamic>> externalToolDescriptors,
  }) : toolDefinitions = _freezeDefinitions(toolDefinitions),
       externalToolDescriptors = _freezeDefinitions(externalToolDescriptors);

  final McpConnectionStatus connectionStatus;
  final List<Map<String, dynamic>> toolDefinitions;
  final List<Map<String, dynamic>> externalToolDescriptors;
}

/// Immutable facts that control request tool observation.
final class RequestToolObservationInput {
  RequestToolObservationInput({
    required this.catalog,
    required this.hasToolNamesOverride,
    required Iterable<String> effectiveToolNames,
    required this.mcpEnabled,
    required this.hasTemporalReferenceContext,
  }) : effectiveToolNames = List<String>.unmodifiable(effectiveToolNames);

  /// Null when no tool service snapshot is available.
  final RequestToolCatalogSnapshot? catalog;
  final bool hasToolNamesOverride;
  final List<String> effectiveToolNames;
  final bool mcpEnabled;
  final bool hasTemporalReferenceContext;
}

/// Tool catalog facts observed for context-window accounting.
final class RequestToolObservation {
  const RequestToolObservation._({
    required this.definitions,
    required this.mcpNames,
  });

  const RequestToolObservation.empty()
    : definitions = const <Map<String, dynamic>>[],
      mcpNames = const <String>{};

  final List<Map<String, dynamic>> definitions;
  final Set<String> mcpNames;
}

/// Collects request tool observations without choosing advertised tools.
final class RequestToolObservationCollector {
  const RequestToolObservationCollector();

  RequestToolObservation collect(RequestToolObservationInput input) {
    final catalog = input.catalog;
    if (catalog == null ||
        !(input.hasToolNamesOverride ||
            input.mcpEnabled ||
            input.hasTemporalReferenceContext)) {
      return const RequestToolObservation.empty();
    }

    final mcpNames = _externalMcpToolNames(catalog);
    if (!input.hasToolNamesOverride) {
      return RequestToolObservation._(
        definitions: catalog.toolDefinitions,
        mcpNames: mcpNames,
      );
    }

    final effectiveNames = input.effectiveToolNames.toSet();
    final definitions = List<Map<String, dynamic>>.unmodifiable(
      catalog.toolDefinitions.where((definition) {
        final function = definition['function'];
        if (function is! Map) {
          return false;
        }
        final name = function['name'];
        return name is String && effectiveNames.contains(name);
      }),
    );
    return RequestToolObservation._(
      definitions: definitions,
      mcpNames: mcpNames,
    );
  }

  Set<String> _externalMcpToolNames(RequestToolCatalogSnapshot catalog) {
    if (catalog.connectionStatus != McpConnectionStatus.connected) {
      return const <String>{};
    }
    final names = <String>{};
    for (final descriptor in catalog.externalToolDescriptors) {
      final function = descriptor['function'];
      if (function is! Map) {
        continue;
      }
      final name = function['name'];
      if (name is String && name.isNotEmpty) {
        names.add(name);
      }
    }
    return Set<String>.unmodifiable(names);
  }
}

List<Map<String, dynamic>> _freezeDefinitions(
  List<Map<String, dynamic>> definitions,
) {
  return List<Map<String, dynamic>>.unmodifiable(
    definitions.map(ImmutableJsonSnapshot.freezeMap),
  );
}
