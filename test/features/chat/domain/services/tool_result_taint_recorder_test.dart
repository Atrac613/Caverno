import 'package:caverno/core/security/conversation_taint_state.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/tool_result_taint_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolResultTaintRecorder', () {
    late ConversationTaintState state;
    late ChatTurnOwner owner;

    setUp(() {
      state = ConversationTaintState();
      owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 1,
      );
    });

    test('records successful and failed external results for one owner', () {
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
        ToolResultTaintRecorder.record(
          state: state,
          owner: owner,
          result: result,
        );
      }

      expect(state.hasUntrustedInfluence(owner: owner), isTrue);
    });

    test('keeps local policy denials out of MCP taint', () {
      ToolResultTaintRecorder.record(
        state: state,
        owner: owner,
        result: const McpToolResult(
          toolName: 'router_health',
          result: 'Planning mode denied this tool.',
          isSuccess: false,
        ),
      );

      expect(state.hasUntrustedInfluence(owner: owner), isFalse);
    });

    test('cannot taint a peer or resurrect a retired owner', () {
      final peer = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );
      state.clearOwner(owner: owner);

      ToolResultTaintRecorder.record(
        state: state,
        owner: owner,
        result: const McpToolResult(
          toolName: 'router_health',
          result: 'late remote content',
          isSuccess: true,
          isExternalMcpResult: true,
        ),
      );

      expect(state.hasUntrustedInfluence(owner: owner), isFalse);
      expect(state.hasUntrustedInfluence(owner: peer), isFalse);
    });
  });
}
