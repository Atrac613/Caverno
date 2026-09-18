part of 'chat_domain_services_test.dart';

void _runToolResultTaintRecorder() {
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
