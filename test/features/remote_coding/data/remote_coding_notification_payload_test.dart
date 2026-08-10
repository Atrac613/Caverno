import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteCodingNotificationPayload', () {
    test('round-trips the allowlisted FCM data', () {
      final completedAt = DateTime.utc(2026, 8, 10, 12, 30);
      final payload = RemoteCodingNotificationPayload(
        eventId: 'event-1',
        turnId: 'gen-42',
        conversationId: 'conversation-7',
        outcome: RemoteCodingNotificationOutcome.completed,
        title: 'Remote coding completed',
        body: 'Open Caverno to review the result.',
        completedAt: completedAt,
      );

      final encoded = payload.toFcmData();
      expect(encoded, <String, String>{
        'kind': 'remote_coding_run_terminal',
        'schemaVersion': '1',
        'eventId': 'event-1',
        'turnId': 'gen-42',
        'conversationId': 'conversation-7',
        'outcome': 'completed',
        'title': 'Remote coding completed',
        'body': 'Open Caverno to review the result.',
        'completedAt': '2026-08-10T12:30:00.000Z',
      });
      expect(
        encoded.keys,
        isNot(anyOf(contains('prompt'), contains('content'), contains('tool'))),
      );

      final decoded = RemoteCodingNotificationPayload.fromFcmData(encoded);
      expect(decoded.eventId, payload.eventId);
      expect(decoded.turnId, payload.turnId);
      expect(decoded.conversationId, payload.conversationId);
      expect(decoded.outcome, payload.outcome);
      expect(decoded.title, payload.title);
      expect(decoded.body, payload.body);
      expect(decoded.completedAt, completedAt);
    });

    test('parses a failed terminal outcome', () {
      final payload = RemoteCodingNotificationPayload.fromFcmData(
        _validData(outcome: 'failed'),
      );

      expect(payload.outcome, RemoteCodingNotificationOutcome.failed);
    });

    test('rejects an unsupported kind', () {
      expect(
        () => RemoteCodingNotificationPayload.fromFcmData(
          _validData()..['kind'] = 'unknown',
        ),
        throwsFormatException,
      );
    });

    test('rejects an unsupported version', () {
      expect(
        () => RemoteCodingNotificationPayload.fromFcmData(
          _validData()..['schemaVersion'] = '2',
        ),
        throwsFormatException,
      );
    });

    test('rejects an unknown outcome', () {
      expect(
        () => RemoteCodingNotificationPayload.fromFcmData(
          _validData(outcome: 'cancelled'),
        ),
        throwsFormatException,
      );
    });

    test('rejects missing identifiers and invalid timestamps', () {
      for (final key in <String>['eventId', 'turnId', 'conversationId']) {
        expect(
          () => RemoteCodingNotificationPayload.fromFcmData(
            _validData()..remove(key),
          ),
          throwsFormatException,
          reason: key,
        );
      }
      expect(
        () => RemoteCodingNotificationPayload.fromFcmData(
          _validData()..['completedAt'] = 'not-a-timestamp',
        ),
        throwsFormatException,
      );
    });
  });
}

Map<String, dynamic> _validData({String outcome = 'completed'}) =>
    <String, dynamic>{
      'kind': 'remote_coding_run_terminal',
      'schemaVersion': '1',
      'eventId': 'event-1',
      'turnId': 'gen-42',
      'conversationId': 'conversation-7',
      'outcome': outcome,
      'title': 'Remote coding completed',
      'body': 'Open Caverno to review the result.',
      'completedAt': '2026-08-10T12:30:00.000Z',
    };
