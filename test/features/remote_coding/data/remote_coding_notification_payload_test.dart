import 'package:caverno/features/remote_coding/data/remote_coding_notification_payload.dart';
import 'package:caverno/features/remote_coding/domain/remote_coding_grant_kinds.dart';
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

  group('RemoteCodingApprovalNotificationPayload', () {
    RemoteCodingApprovalNotificationPayload build({
      String approvalKind = 'localCommand',
      bool hasWarning = false,
      String hostName = "Osamu's MacBook Pro",
    }) => RemoteCodingApprovalNotificationPayload.forApproval(
      eventId: 'event-9',
      approvalId: 'approval-3',
      conversationId: 'conversation-7',
      approvalKind: approvalKind,
      hasWarning: hasWarning,
      hostName: hostName,
      requestedAt: DateTime.utc(2026, 9, 9, 4, 15),
    );

    test('round-trips the allowlisted FCM data', () {
      final encoded = build().toFcmData();

      expect(encoded, <String, String>{
        'kind': 'remote_coding_approval_requested',
        'schemaVersion': '1',
        'eventId': 'event-9',
        'approvalId': 'approval-3',
        'conversationId': 'conversation-7',
        'approvalKind': 'localCommand',
        'hasWarning': 'false',
        'title': 'Caverno needs your approval',
        'body': "Osamu's MacBook Pro is waiting on a shell command.",
        'requestedAt': '2026-09-09T04:15:00.000Z',
      });

      final decoded = RemoteCodingApprovalNotificationPayload.fromFcmData(
        encoded,
      );
      expect(decoded.approvalId, 'approval-3');
      expect(decoded.approvalKind, 'localCommand');
      expect(decoded.hasWarning, isFalse);
      expect(decoded.requestedAt, DateTime.utc(2026, 9, 9, 4, 15));
    });

    test('carries no request detail, whatever the request said', () {
      // The privacy boundary this payload exists to hold. A lock screen is the
      // least private surface the app has, and the relay is the only place
      // Caverno data leaves the machine, so the encoded form must be a pure
      // function of the kind, the flag, and the host name — never of the
      // command, its target, or the warning prose.
      final encoded = build(hasWarning: true).toFcmData();
      final wire = encoded.values.join(' ');

      for (final secret in const <String>[
        'rm -rf /Users/dev/scratch',
        '/Users/dev/caverno',
        'Recursive file deletion',
        'This command can permanently remove files or directories.',
      ]) {
        expect(
          wire,
          isNot(contains(secret)),
          reason: 'the wire must not carry $secret',
        );
      }
      expect(
        encoded.keys.toSet(),
        <String>{
          'kind',
          'schemaVersion',
          'eventId',
          'approvalId',
          'conversationId',
          'approvalKind',
          'hasWarning',
          'title',
          'body',
          'requestedAt',
        },
        reason: 'a new key here is a privacy-boundary change',
      );
    });

    test('says to review the request when a warning is attached', () {
      expect(build(hasWarning: true).body, contains('Review it'));
      expect(build().body, isNot(contains('Review it')));
    });

    test('names the host, and clamps one that would not fit', () {
      expect(build(hostName: '   ').body, startsWith('Your Mac is waiting'));
      final long = build(hostName: 'M' * 80).body;
      expect(long, contains('\u2026'));
      expect(long.length, lessThan(80));
    });

    test('phrases every kind the desktop may grant', () {
      // A kind with no phrase would read "is waiting on an approval", which
      // says less than the sheet the person is being asked to open.
      for (final kind in RemoteCodingGrantKinds.all) {
        expect(
          build(approvalKind: kind).body,
          isNot(contains('is waiting on an approval')),
          reason: '$kind has no phrase',
        );
      }
    });

    test('refuses a kind the desktop cannot grant, in both directions', () {
      expect(
        () => build(approvalKind: 'somethingElse'),
        throwsA(isA<FormatException>()),
      );
      final encoded = build().toFcmData();
      expect(
        () => RemoteCodingApprovalNotificationPayload.fromFcmData({
          ...encoded,
          'approvalKind': 'somethingElse',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses a warning flag that is not a boolean', () {
      final encoded = build().toFcmData();
      expect(
        () => RemoteCodingApprovalNotificationPayload.fromFcmData({
          ...encoded,
          'hasWarning': 'maybe',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('parseRemoteCodingRelayNotification', () {
    test('dispatches on kind and names an unknown one', () {
      final terminal = RemoteCodingNotificationPayload(
        eventId: 'event-1',
        turnId: 'gen-42',
        conversationId: 'conversation-7',
        outcome: RemoteCodingNotificationOutcome.failed,
        title: 'Remote coding failed',
        body: 'Open Caverno to review the failure.',
        completedAt: DateTime.utc(2026, 8, 10),
      );
      final approval = RemoteCodingApprovalNotificationPayload.forApproval(
        eventId: 'event-9',
        approvalId: 'approval-3',
        conversationId: 'conversation-7',
        approvalKind: 'askUserQuestion',
        hasWarning: false,
        hostName: 'Mac',
        requestedAt: DateTime.utc(2026, 9, 9),
      );

      expect(
        parseRemoteCodingRelayNotification(terminal.toFcmData()),
        isA<RemoteCodingNotificationPayload>(),
      );
      expect(
        parseRemoteCodingRelayNotification(approval.toFcmData()),
        isA<RemoteCodingApprovalNotificationPayload>(),
      );
      expect(
        () => parseRemoteCodingRelayNotification(<String, dynamic>{
          'kind': 'remote_coding_something_new',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('remote_coding_something_new'),
          ),
        ),
      );
    });
  });

  group('RemoteCodingApprovalWithdrawalPayload', () {
    test('carries an id and nothing about the request', () {
      final data = RemoteCodingApprovalWithdrawalPayload(
        eventId: 'event-9',
        approvalId: 'approval-77',
        conversationId: 'conversation-7',
        resolvedAt: DateTime.utc(2026, 9, 9, 14),
      ).toFcmData();

      // The privacy boundary, pinned. This shape rides the same lock screen as
      // the request it withdraws, so it must never grow a field describing what
      // the approval was for -- and it has no title or body at all, because it
      // is delivered silently and displays nothing.
      expect(data.keys.toSet(), <String>{
        'kind',
        'schemaVersion',
        'eventId',
        'approvalId',
        'conversationId',
        'resolvedAt',
      });
      expect(data['kind'], 'remote_coding_approval_resolved');
      expect(data['approvalId'], 'approval-77');
    });

    test('round-trips through the parser', () {
      final decoded = parseRemoteCodingRelayNotification(<String, dynamic>{
        'kind': 'remote_coding_approval_resolved',
        'schemaVersion': '1',
        'eventId': 'event-9',
        'approvalId': 'approval-77',
        'conversationId': 'conversation-7',
        'resolvedAt': '2026-09-09T14:00:00.000Z',
      });

      expect(decoded, isA<RemoteCodingApprovalWithdrawalPayload>());
      final withdrawal = decoded as RemoteCodingApprovalWithdrawalPayload;
      expect(withdrawal.approvalId, 'approval-77');
      expect(withdrawal.resolvedAt, DateTime.utc(2026, 9, 9, 14));
      expect(withdrawal.title, isEmpty);
      expect(withdrawal.body, isEmpty);
    });

    test('rejects a payload missing the approval it withdraws', () {
      expect(
        () => parseRemoteCodingRelayNotification(<String, dynamic>{
          'kind': 'remote_coding_approval_resolved',
          'schemaVersion': '1',
          'eventId': 'event-9',
          'conversationId': 'conversation-7',
          'resolvedAt': '2026-09-09T14:00:00.000Z',
        }),
        throwsA(isA<FormatException>()),
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
