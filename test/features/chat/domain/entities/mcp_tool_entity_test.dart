import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('McpToolResult execution provenance', () {
    test('defaults local results to non-MCP provenance', () {
      const result = McpToolResult(
        toolName: 'read_file',
        result: 'local content',
        isSuccess: true,
      );

      expect(result.isExternalMcpResult, isFalse);
    });

    test('keeps transient MCP provenance out of serialized JSON', () {
      const result = McpToolResult(
        toolName: 'router_health',
        result: 'remote content',
        isSuccess: true,
        isExternalMcpResult: true,
      );

      expect(result.toJson(), {
        'toolName': 'router_health',
        'result': 'remote content',
        'isSuccess': true,
        'errorMessage': null,
      });
      expect(
        McpToolResult.fromJson(result.toJson()).isExternalMcpResult,
        isFalse,
      );
    });
  });
}
