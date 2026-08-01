import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/security/conversation_taint_state.dart';
import 'package:caverno/core/security/data_source_classifier.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';

void main() {
  group('ConversationTaintState', () {
    late ConversationTaintState state;
    late ChatTurnOwner owner;

    setUp(() {
      state = ConversationTaintState();
      owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 1,
      );
    });

    test('starts with an immutable empty owner snapshot', () {
      final snapshot = state.snapshot(owner: owner);

      expect(snapshot.influencingTrustLevels, isEmpty);
      expect(snapshot.hasUntrustedInfluence, isFalse);
      expect(
        () => snapshot.influencingTrustLevels.add(TrustLevel.untrusted),
        throwsUnsupportedError,
      );
      expect(state.influencingTrustLevels(owner: owner), isEmpty);
      expect(state.hasUntrustedInfluence(owner: owner), isFalse);
    });

    test('preserves insertion order and aggregates trust severity', () {
      state
        ..recordTrust(owner: owner, trust: TrustLevel.userTrusted)
        ..recordToolResult(owner: owner, toolName: 'read_file')
        ..recordToolResult(owner: owner, toolName: 'http_get')
        ..recordTrust(owner: owner, trust: TrustLevel.userTrusted);

      final snapshot = state.snapshot(owner: owner);
      expect(snapshot.influencingTrustLevels.toList(), [
        TrustLevel.userTrusted,
        TrustLevel.projectTrusted,
        TrustLevel.untrusted,
      ]);
      expect(snapshot.hasUntrustedInfluence, isTrue);
      expect(state.hasUntrustedInfluence(owner: owner), isTrue);
    });

    test('classifies external MCP results as untrusted', () {
      state.recordToolResult(
        owner: owner,
        toolName: 'third_party_tool',
        isMcpTool: true,
      );

      expect(state.influencingTrustLevels(owner: owner), {
        TrustLevel.untrusted,
      });
    });

    test('isolates conversations and generations with equal peer fields', () {
      final otherConversation = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: owner.interactionGeneration,
      );
      final otherGeneration = ChatTurnOwner(
        conversationId: owner.conversationId,
        interactionGeneration: owner.interactionGeneration + 1,
      );

      state
        ..recordTrust(owner: owner, trust: TrustLevel.userTrusted)
        ..recordTrust(
          owner: otherConversation,
          trust: TrustLevel.projectTrusted,
        )
        ..recordTrust(owner: otherGeneration, trust: TrustLevel.untrusted);

      expect(state.influencingTrustLevels(owner: owner), {
        TrustLevel.userTrusted,
      });
      expect(state.influencingTrustLevels(owner: otherConversation), {
        TrustLevel.projectTrusted,
      });
      expect(state.influencingTrustLevels(owner: otherGeneration), {
        TrustLevel.untrusted,
      });
    });

    test('terminal clear permanently rejects late owner records', () {
      final peer = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: owner.interactionGeneration,
      );
      state
        ..recordToolResult(owner: owner, toolName: 'http_get')
        ..recordTrust(owner: peer, trust: TrustLevel.projectTrusted)
        ..clearOwner(owner: owner)
        ..clearOwner(owner: owner)
        ..recordToolResult(owner: owner, toolName: 'http_get')
        ..recordTrust(owner: owner, trust: TrustLevel.untrusted);

      expect(state.snapshot(owner: owner).influencingTrustLevels, isEmpty);
      expect(state.influencingTrustLevels(owner: peer), {
        TrustLevel.projectTrusted,
      });
    });

    test('dispose is idempotent and rejects every late record', () {
      final peer = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: owner.interactionGeneration,
      );
      state
        ..recordTrust(owner: owner, trust: TrustLevel.untrusted)
        ..recordTrust(owner: peer, trust: TrustLevel.projectTrusted)
        ..dispose()
        ..dispose()
        ..recordTrust(owner: owner, trust: TrustLevel.untrusted)
        ..recordToolResult(owner: peer, toolName: 'http_get');

      expect(state.snapshot(owner: owner).influencingTrustLevels, isEmpty);
      expect(state.snapshot(owner: peer).influencingTrustLevels, isEmpty);
    });
  });
}
