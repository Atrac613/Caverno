import '../../../../core/services/lan_scan_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'lan_scan_tools.dart';
import 'mcp_tool_result_normalizer.dart';

/// Exposes and executes the built-in local network scan tool family.
final class BuiltInLanScanToolHandler {
  BuiltInLanScanToolHandler({LanScanService? lanScanService})
    : _lanScanService = lanScanService;

  static const List<String> toolNames = <String>[
    'lan_scan',
    'lan_get_scan_results',
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};

  final LanScanService? _lanScanService;

  bool get isAvailable => _lanScanService != null;

  List<Map<String, dynamic>> get definitions => LanScanTools.allTools;

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      return _failure(name, 'Unknown LAN scan tool: $name');
    }
    final lanScan = _lanScanService;
    if (lanScan == null) {
      throw StateError('LAN scan service is unavailable');
    }

    try {
      switch (name) {
        case 'lan_scan':
          final subnet = (arguments['subnet'] as String?)?.trim();
          final ipVersion = (arguments['ip_version'] as String?)?.trim();
          final timeout = (arguments['timeout'] as num?)?.toInt() ?? 1000;
          final ports = (arguments['ports'] as List?)
              ?.map((entry) => (entry as num).toInt())
              .toList();
          final result = await lanScan.startScan(
            subnet: subnet,
            ipVersion: ipVersion,
            timeoutMs: timeout,
            ports: ports,
          );
          return _success(name, result);

        case 'lan_get_scan_results':
          final sortBy = arguments['sort_by'] as String?;
          return _success(name, lanScan.getScanResults(sortBy: sortBy));
      }
      return _failure(name, 'Unknown LAN scan tool: $name');
    } catch (error) {
      appLog('[McpToolService] LAN scan tool error ($name): $error');
      return _failure(name, error.toString());
    }
  }

  static McpToolResult _success(String toolName, String result) {
    return McpToolResultNormalizer.success(toolName: toolName, result: result);
  }

  static McpToolResult _failure(String toolName, String errorMessage) {
    return McpToolResultNormalizer.failure(
      toolName: toolName,
      errorMessage: errorMessage,
    );
  }
}
