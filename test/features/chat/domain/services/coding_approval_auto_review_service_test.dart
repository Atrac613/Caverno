import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/coding_approval_auto_review_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodingApprovalAutoReviewService', () {
    test('parses allow decisions', () {
      final decision = CodingApprovalAutoReviewService.parseDecision(
        '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this scoped edit."}',
      );

      expect(decision, isNotNull);
      expect(decision!.isAllowed, isTrue);
      expect(decision.riskLevel, 'low');
      expect(decision.userAuthorization, 'high');
    });

    test('parses fenced deny decisions', () {
      final decision = CodingApprovalAutoReviewService.parseDecision(
        '```json\n{"outcome":"deny","riskLevel":"critical","userAuthorization":"unknown","rationale":"The command deletes unrelated files."}\n```',
      );

      expect(decision, isNotNull);
      expect(decision!.isAllowed, isFalse);
      expect(decision.rationale, 'The command deletes unrelated files.');
    });

    test('returns null for malformed decisions', () {
      expect(
        CodingApprovalAutoReviewService.parseDecision('allow this action'),
        isNull,
      );
      expect(
        CodingApprovalAutoReviewService.parseDecision(
          '{"outcome":"maybe","rationale":"unclear"}',
        ),
        isNull,
      );
    });

    test('builds visible conversation tail without system messages', () {
      final now = DateTime(2026, 5, 26);
      final tail = CodingApprovalAutoReviewService.buildConversationTail([
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
  });
}
