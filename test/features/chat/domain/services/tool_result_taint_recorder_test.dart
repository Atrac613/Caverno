import 'package:caverno/core/security/conversation_taint_state.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/tool_result_taint_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolResultTaintRecorder', () {
    test('records successful and failed external MCP results as untrusted', () {
      for (final result in const [
        McpToolResult(
          toolName: 'router_health',
          result: 'remote content',
          isSuccess: true,
          isExternalMcpResult: true,
        ),
        McpToolResult(
          toolName: 'router_health',
          result: '',
          isSuccess: false,
          errorMessage: 'remote error',
          isExternalMcpResult: true,
        ),
      ]) {
        final state = ConversationTaintState();

        ToolResultTaintRecorder.record(state, result);

        expect(state.hasUntrustedInfluence, isTrue);
      }
    });

    test('keeps local policy denials out of MCP taint', () {
      final state = ConversationTaintState();
      const result = McpToolResult(
        toolName: 'router_health',
        result: 'Planning mode denied this tool.',
        isSuccess: false,
      );

      ToolResultTaintRecorder.record(state, result);

      expect(state.hasUntrustedInfluence, isFalse);
    });
  });
}
