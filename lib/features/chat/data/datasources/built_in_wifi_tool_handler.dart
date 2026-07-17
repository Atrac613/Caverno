import '../../../../core/services/wifi_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_tool_result_normalizer.dart';
import 'wifi_tools.dart';

/// Exposes and executes the built-in WiFi inspection tool family.
final class BuiltInWifiToolHandler {
  BuiltInWifiToolHandler({WifiService? wifiService})
    : _wifiService = wifiService;

  static const List<String> toolNames = <String>[
    'wifi_scan',
    'wifi_get_scan_results',
    'wifi_get_connection_info',
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};

  final WifiService? _wifiService;

  bool get isAvailable => _wifiService != null;

  List<Map<String, dynamic>> get definitions => WifiTools.allTools;

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown WiFi tool');
    }
    final wifi = _wifiService;
    if (wifi == null) {
      throw StateError('WiFi service is unavailable');
    }

    try {
      switch (name) {
        case 'wifi_scan':
          return _success(name, await wifi.startScan());

        case 'wifi_get_scan_results':
          final sortBy = arguments['sort_by'] as String?;
          return _success(name, wifi.getScanResults(sortBy: sortBy));

        case 'wifi_get_connection_info':
          return _success(name, await wifi.getConnectionInfo());
      }
      throw StateError('Unhandled WiFi tool: $name');
    } catch (error) {
      appLog('[McpToolService] WiFi tool error ($name): $error');
      return McpToolResultNormalizer.failure(
        toolName: name,
        errorMessage: error.toString(),
      );
    }
  }

  static McpToolResult _success(String toolName, String result) {
    return McpToolResultNormalizer.success(toolName: toolName, result: result);
  }
}
