import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/security/conversation_taint_state.dart';
import 'package:caverno/core/security/data_source_classifier.dart';

void main() {
  group('ConversationTaintState', () {
    test('starts clean', () {
      final state = ConversationTaintState();
      expect(state.influencingTrustLevels, isEmpty);
      expect(state.hasUntrustedInfluence, isFalse);
    });

    test('local reads keep the conversation untainted', () {
      final state = ConversationTaintState()
        ..recordToolResult('read_file')
        ..recordToolResult('list_directory')
        ..recordToolResult('ping');
      expect(state.hasUntrustedInfluence, isFalse);
      expect(state.influencingTrustLevels, contains(TrustLevel.projectTrusted));
    });

    test('a web fetch taints the conversation', () {
      final state = ConversationTaintState()
        ..recordToolResult('read_file')
        ..recordToolResult('http_get');
      expect(state.hasUntrustedInfluence, isTrue);
      expect(state.influencingTrustLevels, contains(TrustLevel.untrusted));
      expect(state.influencingTrustLevels, contains(TrustLevel.projectTrusted));
    });

    test('an MCP tool result taints the conversation', () {
      final state = ConversationTaintState()
        ..recordToolResult('third_party_tool', isMcpTool: true);
      expect(state.hasUntrustedInfluence, isTrue);
    });

    test('records an explicitly known trust level', () {
      final state = ConversationTaintState()
        ..recordTrust(TrustLevel.userTrusted);
      expect(state.influencingTrustLevels, {TrustLevel.userTrusted});
      expect(state.hasUntrustedInfluence, isFalse);
    });

    test('reset clears accumulated taint', () {
      final state = ConversationTaintState()..recordToolResult('http_get');
      expect(state.hasUntrustedInfluence, isTrue);
      state.reset();
      expect(state.influencingTrustLevels, isEmpty);
      expect(state.hasUntrustedInfluence, isFalse);
    });

    test('exposes an unmodifiable view', () {
      final state = ConversationTaintState()..recordToolResult('read_file');
      expect(
        () => state.influencingTrustLevels.add(TrustLevel.untrusted),
        throwsUnsupportedError,
      );
    });
  });
}
