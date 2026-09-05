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
    WatchSnapshot maximal({String fill = 'A'}) => WatchSnapshot(
      sequence: 4242,
      generatedAt: DateTime.utc(2026, 9, 1, 12),
      sourceInstanceId: 'source-1',
      sourceStartedAtMicros: 1788264000000000,
      conversationId: 'conversation-1',
      conversationTitle: fill * 4000,
      workspaceMode: 'coding',
      goal: WatchGoal(
        objective: fill * 4000,
        status: 'awaitingConfirmation',
        completionSummary: fill * 4000,
        blockedReason: fill * 4000,
      ),
      status: WatchTurnStatus.waitingApproval,
      lastAssistantText: fill * 40000,
      approval: WatchApproval(
        id: 'approval-1',
        kind: 'localCommand',
        title: fill * 4000,
        subtitle: fill * 4000,
        detail: fill * 40000,
        canResolveOnWatch: true,
      ),
      question: WatchQuestion(
        id: 'question-1',
        question: fill * 4000,
        options: List.generate(
          40,
          (index) => WatchQuestionOption(id: 'o\$index', label: fill * 400),
        ),
        allowMultiple: true,
        allowOther: true,
      ),
      messages: List.generate(
        40,
        (index) => WatchMessage(
          id: 'm\$index',
          role: index.isEven
              ? WatchMessageRole.user
              : WatchMessageRole.assistant,
          text: fill * 4000,
          timestamp: DateTime.utc(2026, 9, 1, 11, index),
        ),
      ),
      elapsedSeconds: 91,
      queuedCount: 3,
      busyThreadCount: 2,
      conversations: List.generate(
        40,
        (index) => WatchConversation(
          id: 'c\$index',
          title: fill * 4000,
          mode: 'coding',
        ),
      ),
      error: fill * 4000,
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

    test('stays inside the budget in every script width', () {
      // Every cap counts runes, so the same frame costs one byte per rune in
      // English, three in Japanese and four in emoji. Sized by runes alone a
      // maximal frame reaches 116% of the budget in the widest case, and
      // WatchConnectivity refuses an oversized dictionary rather than clipping
      // it — the watch then sits on stale state with only an NSLog to say why.
      for (final fill in const ['A', '日', '👍']) {
        final encoded = utf8.encode(jsonEncode(maximal(fill: fill).toJson()));

        expect(
          encoded.length,
          lessThanOrEqualTo(watchSnapshotMaxEncodedBytes),
          reason: 'a maximal frame filled with "$fill" overran the budget',
        );
      }
    });

    test('sheds the thread picker before the transcript', () {
      // The frame exists to answer a blocked turn. Thread switching is
      // navigation, and `conversationsTruncated` already tells the watch to
      // point at the iPhone, so it is the cheapest thing to give up.
      final json = maximal(fill: '👍').toJson();

      expect(json['conversations'], isEmpty);
      expect(json['conversationsTruncated'], isTrue);
      expect(json['messages'], isNotEmpty);
      expect(json['approval'], isNotNull);
      expect(json['question'], isNotNull);
    });

    test('keeps the full projection when the frame already fits', () {
      final json = maximal().toJson();

      expect(
        (json['conversations']! as List<dynamic>).length,
        watchSnapshotMaxConversations,
      );
      expect(
        (json['messages']! as List<dynamic>).length,
        watchSnapshotMaxMessages,
      );
      expect(json['lastAssistantText'], isNotNull);
    });

    test('fits the budget even when one bubble is the whole frame', () {
      // A single message long enough to blow the budget on its own has no
      // thread list or scrollback left to shed, so this is the rung that
      // proves the ladder bottoms out inside the budget rather than merely
      // shrinking.
      final snapshot = WatchSnapshot(
        sequence: 1,
        generatedAt: DateTime.utc(2026, 9, 1, 12),
        conversationTitle: '👍' * 4000,
        status: WatchTurnStatus.waitingApproval,
        lastAssistantText: '👍' * 40000,
        approval: WatchApproval(
          id: 'approval-1',
          kind: 'localCommand',
          title: '👍' * 4000,
          subtitle: '👍' * 4000,
          detail: '👍' * 40000,
          canResolveOnWatch: true,
        ),
        messages: [
          WatchMessage(
            id: 'm0',
            role: WatchMessageRole.assistant,
            text: '👍' * 40000,
            timestamp: DateTime.utc(2026, 9, 1, 11),
          ),
        ],
        error: '👍' * 4000,
      );

      final encoded = utf8.encode(jsonEncode(snapshot.toJson()));

      expect(encoded.length, lessThanOrEqualTo(watchSnapshotMaxEncodedBytes));
      // Shrinking must not cost the decision itself.
      expect(snapshot.toJson()['approval'], isNotNull);
    });

    test('caps the thread list and says that it did', () {
      final json = maximal().toJson();

      expect(
        (json['conversations'] as List<dynamic>).length,
        watchSnapshotMaxConversations,
      );
      expect(json['conversationsTruncated'], isTrue);
    });

    test('does not flag truncation when every thread fits', () {
      final snapshot = WatchSnapshot(
        sequence: 1,
        generatedAt: DateTime.utc(2026, 9, 1),
        conversations: const [
          WatchConversation(id: 'a', title: 'Fix the parser'),
        ],
      );

      expect(snapshot.toJson()['conversationsTruncated'], isFalse);
    });

    test('caps the transcript and says that it did', () {
      final json = maximal().toJson();

      expect(
        (json['messages'] as List<dynamic>).length,
        watchSnapshotMaxMessages,
      );
      expect(json['messagesTruncated'], isTrue);
    });

    test('the newest bubble gets the larger text allowance', () {
      // The last bubble is the one being read; clipping it to scrollback
      // length would truncate the answer the person came to the wrist for.
      final messages = maximal().toJson()['messages']! as List<dynamic>;
      final scrollback = messages.first as Map<String, dynamic>;
      final newest = messages.last as Map<String, dynamic>;

      expect(
        (scrollback['text']! as String).runes.length,
        watchSnapshotMessageTextLimit + 1,
      );
      expect(
        (newest['text']! as String).runes.length,
        watchSnapshotLastMessageTextLimit + 1,
      );
    });

    test('does not flag truncation when the whole thread fits', () {
      final snapshot = WatchSnapshot(
        sequence: 1,
        generatedAt: DateTime.utc(2026, 9, 1),
        messages: [
          WatchMessage(
            id: 'm-1',
            role: WatchMessageRole.user,
            text: 'Run the tests',
            timestamp: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      expect(snapshot.toJson()['messagesTruncated'], isFalse);
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
        sourceInstanceId: 'source-1',
        sourceStartedAtMicros: 1788264000000000,
        conversationId: 'conversation-1',
        conversationTitle: 'Fix the parser',
        status: WatchTurnStatus.waitingQuestion,
        lastAssistantText: 'Reading the failing test.',
        question: const WatchQuestion(
          id: 'question-1',
          question: 'Which approach?',
          options: [WatchQuestionOption(id: 'a', label: 'Rewrite')],
        ),
        messages: [
          WatchMessage(
            id: 'm-1',
            role: WatchMessageRole.user,
            text: 'Run the tests',
            timestamp: DateTime.utc(2026, 9, 1, 11, 59),
          ),
          WatchMessage(
            id: 'm-2',
            role: WatchMessageRole.assistant,
            text: 'Reading the failing test.',
            timestamp: DateTime.utc(2026, 9, 1, 12),
            isStreaming: true,
          ),
        ],
        elapsedSeconds: 12,
        queuedCount: 1,
        busyThreadCount: 1,
      );

      final decoded = WatchSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.sequence, 7);
      expect(decoded.generatedAt, original.generatedAt);
      expect(decoded.sourceInstanceId, 'source-1');
      expect(decoded.sourceStartedAtMicros, 1788264000000000);
      expect(decoded.conversationId, 'conversation-1');
      expect(decoded.status, WatchTurnStatus.waitingQuestion);
      expect(decoded.question!.options.single.label, 'Rewrite');
      expect(decoded.approval, isNull);
      expect(decoded.needsAttention, isTrue);
      expect(decoded.messages.first.role, WatchMessageRole.user);
      expect(
        decoded.messages.first.timestamp,
        DateTime.utc(2026, 9, 1, 11, 59),
      );
      expect(decoded.messages.last.isStreaming, isTrue);
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

    test('source identity is optional for an older phone build', () {
      final decoded = WatchSnapshot.fromJson({
        'sequence': 1,
        'generatedAt': DateTime.utc(2026, 9, 1).toIso8601String(),
      });

      expect(decoded.sourceInstanceId, isEmpty);
      expect(decoded.sourceStartedAtMicros, 0);
    });

    test('an unknown message role decodes as assistant', () {
      // Same reasoning as the status enum: the watch may be running an older
      // build than the phone, and a role it does not know must degrade to a
      // bubble rather than fail the whole frame.
      final decoded = WatchMessage.fromJson({
        'id': 'm-1',
        'role': 'toolSomethingNewer',
        'text': 'hello',
        'timestamp': DateTime.utc(2026, 9, 1).toIso8601String(),
      });

      expect(decoded.role, WatchMessageRole.assistant);
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

  group('goal projection', () {
    test('caps every goal field and keeps the status verbatim', () {
      final json = WatchGoal(
        objective: 'o' * 500,
        status: 'awaitingConfirmation',
        completionSummary: 's' * 500,
        blockedReason: 'b' * 500,
      ).toJson();

      expect(
        (json['objective']! as String).runes.length,
        watchSnapshotGoalTextLimit + 1,
      );
      expect(json['status'], 'awaitingConfirmation');
      expect(
        (json['completionSummary']! as String).runes.length,
        watchSnapshotGoalTextLimit + 1,
      );
      expect(
        (json['blockedReason']! as String).runes.length,
        watchSnapshotGoalTextLimit + 1,
      );
    });

    test('omits the fields it has nothing to say about', () {
      final json = const WatchGoal(
        objective: 'Ship it',
        status: 'active',
      ).toJson();

      expect(json.containsKey('completionSummary'), isFalse);
      expect(json.containsKey('blockedReason'), isFalse);
    });

    test('an unknown status survives rather than dropping the goal', () {
      // ConversationGoalStatus gains members, and the two apps ship as one
      // bundle without being guaranteed to be the same build at runtime.
      final goal = WatchGoal.fromJson(const {
        'objective': 'Ship it',
        'status': 'somethingNewer',
      });

      expect(goal.objective, 'Ship it');
      expect(goal.status, 'somethingNewer');
    });

    test('a frame from a phone without a goal decodes as no goal', () {
      final snapshot = WatchSnapshot.fromJson(const {
        'sequence': 1,
        'status': 'idle',
      });

      expect(snapshot.goal, isNull);
      expect(snapshot.workspaceMode, '');
      expect(snapshot.needsAttention, isFalse);
    });

    test('awaitingGoalConfirmation is an attention state', () {
      final snapshot = WatchSnapshot(
        sequence: 1,
        generatedAt: DateTime.utc(2026, 9, 5),
        status: WatchTurnStatus.awaitingGoalConfirmation,
      );

      expect(snapshot.needsAttention, isTrue);
      expect(snapshot.toJson()['status'], 'awaitingGoalConfirmation');
      expect(
        WatchSnapshot.fromJson(snapshot.toJson()).status,
        WatchTurnStatus.awaitingGoalConfirmation,
      );
    });
  });

}
