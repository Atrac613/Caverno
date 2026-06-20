import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/tool_approval_auto_review_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolApprovalAutoReviewService', () {
    test('parses allow decisions', () {
      final decision = ToolApprovalAutoReviewService.parseDecision(
        '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this scoped edit."}',
      );

      expect(decision, isNotNull);
      expect(decision!.isAllowed, isTrue);
      expect(decision.riskLevel, 'low');
      expect(decision.userAuthorization, 'high');
    });

    test('parses fenced deny decisions', () {
      final decision = ToolApprovalAutoReviewService.parseDecision(
        '```json\n{"outcome":"deny","riskLevel":"critical","userAuthorization":"unknown","rationale":"The command deletes unrelated files."}\n```',
      );

      expect(decision, isNotNull);
      expect(decision!.isAllowed, isFalse);
      expect(decision.rationale, 'The command deletes unrelated files.');
    });

    test('returns null for malformed decisions', () {
      expect(
        ToolApprovalAutoReviewService.parseDecision('allow this action'),
        isNull,
      );
      expect(
        ToolApprovalAutoReviewService.parseDecision(
          '{"outcome":"maybe","rationale":"unclear"}',
        ),
        isNull,
      );
    });

    test('builds visible conversation tail without system messages', () {
      final now = DateTime(2026, 5, 26);
      final tail = ToolApprovalAutoReviewService.buildConversationTail([
        Message(
          id: 'system',
          role: MessageRole.system,
          content: 'hidden',
          timestamp: now,
        ),
        Message(
          id: 'user',
          role: MessageRole.user,
          content: 'Please edit README.',
          timestamp: now,
        ),
        Message(
          id: 'assistant',
          role: MessageRole.assistant,
          content: 'I will update it.',
          timestamp: now,
        ),
      ]);

      expect(tail.map((entry) => entry.role), ['user', 'assistant']);
      expect(tail.map((entry) => entry.content), [
        'Please edit README.',
        'I will update it.',
      ]);
    });

    Map<String, dynamic> capabilityFor(String toolName) {
      final messages = ToolApprovalAutoReviewService.buildMessages(
        ToolApprovalAutoReviewRequest(
          actionKind: toolName,
          toolName: toolName,
          arguments: const {'command': 'rm -rf build'},
          conversationTail: const [],
        ),
      );
      final user = messages.firstWhere((m) => m.role == MessageRole.user);
      final packet = jsonDecode(user.content) as Map<String, dynamic>;
      return (packet['action'] as Map)['capability'] as Map<String, dynamic>;
    }

    test('embeds SEC1 capability context in the review packet', () {
      final capability = capabilityFor('local_execute_command');
      expect(capability['class'], 'shellExecution');
      expect(capability['risk'], 'high');
      expect(capability['mutatesState'], isTrue);
    });

    test('marks untrusted output for a network fetch', () {
      final capability = capabilityFor('http_get');
      expect(capability['producesUntrustedContent'], isTrue);
    });
  });
}
