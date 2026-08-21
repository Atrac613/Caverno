import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/routines/data/routine_execution_service.dart';
import 'package:caverno/features/routines/domain/services/routine_tool_policy.dart';

void main() {
  group('RoutineToolPolicy', () {
    test('omits unclassified external MCP tools from the catalog', () {
      final filtered = RoutineToolPolicy.filterAllowedToolDefinitions([
        _builtIn('interface_info', 'Inspect local network interfaces'),
        _builtIn('get_dns_health', 'Summarize recent DNS health'),
        _external('router_health_snapshot', 'http://router-mcp.local:8765'),
        _external('get_dns_health__zeek_server', 'http://zeek-mcp.local:8765'),
        _builtIn('write_file', 'Write a file'),
      ]);

      expect(_names(filtered), ['interface_info', 'get_dns_health']);
    });

    test('keeps namespaced built-in tools that are not external MCP', () {
      final filtered = RoutineToolPolicy.filterAllowedToolDefinitions([
        _builtIn('get_dns_health__local', 'Local DNS health helper'),
      ]);

      expect(_names(filtered), ['get_dns_health__local']);
    });

    test('keeps routine extras and optional workspace writes', () {
      final filtered = RoutineToolPolicy.filterAllowedToolDefinitions(
        [_builtIn('write_file', 'Write a file')],
        allowWorkspaceWrites: true,
        extraDefinitions: [
          {
            'type': 'function',
            RoutineToolPolicy.routineToolDefinitionKey: true,
            'function': {
              'name': RoutineExecutionService.googleChatPostToolName,
              'description': 'Post to Google Chat',
              'parameters': const {'type': 'object', 'properties': {}},
            },
          },
        ],
      );

      expect(_names(filtered), [
        'write_file',
        RoutineExecutionService.googleChatPostToolName,
      ]);
    });

    test('denies external MCP with a distinct reason', () {
      final result = RoutineToolPolicy.buildExternalMcpDeniedResult(
        ToolCallInfo(
          id: 'tool-router',
          name: 'router_health_snapshot',
          arguments: const {'lookback_minutes': 15},
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('external MCP'));
      final payload = jsonDecode(result.result) as Map<String, dynamic>;
      expect(payload, containsPair('reason', 'routine_external_mcp_denied'));
      expect(payload, containsPair('code', 'permission_denied'));
    });
  });
}

Map<String, dynamic> _builtIn(String name, String description) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': const {'type': 'object', 'properties': {}},
  },
};

Map<String, dynamic> _external(String name, String sourceUrl) {
  return McpToolEntity(
    name: name,
    description: 'External MCP tool',
    inputSchema: const {'type': 'object', 'properties': {}},
    sourceUrl: sourceUrl,
  ).toOpenAiTool();
}

List<String> _names(List<Map<String, dynamic>> tools) {
  return tools
      .map((tool) => (tool['function'] as Map?)?['name'] as String?)
      .whereType<String>()
      .toList(growable: false);
}
