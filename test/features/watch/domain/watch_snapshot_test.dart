import 'dart:convert';

import 'package:caverno/features/watch/domain/watch_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('truncateForWatch', () {
    test('leaves short values untouched apart from trimming', () {
      expect(truncateForWatch('  hello  ', 10), 'hello');
    });

    test('marks the cut with an ellipsis', () {
      expect(truncateForWatch('abcdefghij', 4), 'abcd…');
    });

    test('counts runes, never splitting a surrogate pair', () {
      // Emoji are outside the BMP; cutting by code unit would leave half a
      // surrogate pair and produce JSON the Swift side cannot decode.
      const value = '👍👍👍👍';
      final truncated = truncateForWatch(value, 2);

      expect(truncated, '👍👍…');
      expect(() => jsonDecode(jsonEncode(truncated)), returnsNormally);
    });
  });

  group('WatchSnapshot encoding', () {
    WatchSnapshot maximal() => WatchSnapshot(
      sequence: 4242,
      generatedAt: DateTime.utc(2026, 9, 1, 12),
      conversationId: 'conversation-1',
      conversationTitle: 'T' * 4000,
      status: WatchTurnStatus.waitingApproval,
      lastAssistantText: 'A' * 40000,
      approval: WatchApproval(
        id: 'approval-1',
        kind: 'localCommand',
        title: 'C' * 4000,
        subtitle: 'S' * 4000,
        detail: 'D' * 40000,
        canResolveOnWatch: true,
      ),
      question: WatchQuestion(
        id: 'question-1',
        question: 'Q' * 4000,
        options: List.generate(
          40,
          (index) => WatchQuestionOption(id: 'o$index', label: 'L' * 400),
        ),
        allowMultiple: true,
        allowOther: true,
      ),
      elapsedSeconds: 91,
      queuedCount: 3,
      busyThreadCount: 2,
      error: 'E' * 4000,
    );

    test('stays inside the WatchConnectivity payload budget', () {
      final encoded = utf8.encode(jsonEncode(maximal().toJson()));

      expect(
        encoded.length,
        lessThan(watchSnapshotMaxEncodedBytes),
        reason:
            'WCSession rejects oversized dictionaries at runtime, so the '
            'projection must cap every unbounded field.',
      );
    });

    test('caps the question option list and says that it did', () {
      final json = maximal().toJson();
      final question = json['question']! as Map<String, dynamic>;

      expect(
        (question['options'] as List<dynamic>).length,
        watchSnapshotMaxQuestionOptions,
      );
      expect(question['optionsTruncated'], isTrue);
    });

    test('does not flag truncation when every option fits', () {
      const question = WatchQuestion(
        id: 'question-1',
        question: 'Which approach?',
        options: [
          WatchQuestionOption(id: 'a', label: 'Rewrite'),
          WatchQuestionOption(id: 'b', label: 'Patch'),
        ],
      );

      expect(question.toJson()['optionsTruncated'], isFalse);
    });

    test('round-trips through JSON', () {
      final original = WatchSnapshot(
        sequence: 7,
        generatedAt: DateTime.utc(2026, 9, 1, 12),
        conversationId: 'conversation-1',
        conversationTitle: 'Fix the parser',
        status: WatchTurnStatus.waitingQuestion,
        lastAssistantText: 'Reading the failing test.',
        question: const WatchQuestion(
          id: 'question-1',
          question: 'Which approach?',
          options: [WatchQuestionOption(id: 'a', label: 'Rewrite')],
        ),
        elapsedSeconds: 12,
        queuedCount: 1,
        busyThreadCount: 1,
      );

      final decoded = WatchSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.sequence, 7);
      expect(decoded.generatedAt, original.generatedAt);
      expect(decoded.conversationId, 'conversation-1');
      expect(decoded.status, WatchTurnStatus.waitingQuestion);
      expect(decoded.question!.options.single.label, 'Rewrite');
      expect(decoded.approval, isNull);
      expect(decoded.needsAttention, isTrue);
    });

    test('an unknown status decodes as idle rather than throwing', () {
      final decoded = WatchSnapshot.fromJson({
        'sequence': 1,
        'generatedAt': DateTime.utc(2026, 9, 1).toIso8601String(),
        'status': 'somethingNewerThanThisBuild',
      });

      expect(decoded.status, WatchTurnStatus.idle);
      expect(decoded.needsAttention, isFalse);
    });

    test('an unknown approval kind survives decoding', () {
      // A newer iPhone build may emit a kind the watch does not know. It must
      // still render as "open on iPhone" instead of vanishing.
      final decoded = WatchApproval.fromJson({
        'id': 'a-1',
        'kind': 'somethingNew',
        'title': 'New approval kind',
        'subtitle': '',
        'detail': '',
        'canResolveOnWatch': false,
      });

      expect(decoded.kind, 'somethingNew');
      expect(decoded.canResolveOnWatch, isFalse);
    });
  });
}
