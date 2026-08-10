import 'dart:convert';

import 'package:caverno/features/remote_coding/data/remote_coding_notification_relay_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts credentials and payload identifiers recursively', () {
    final redacted = RemoteCodingRelayLogRedactor.redact({
      'operation': 'deliver',
      'deliveryHandle': 'delivery_handle_1',
      'headers': {
        'Authorization': 'Bearer provider-token',
        'X-Firebase-AppCheck': 'app-check-token',
        'X-Caverno-Relay-Key-Id': 'delivery-key-1',
        'X-Caverno-Relay-Nonce': 'nonce-1',
        'X-Caverno-Relay-Signature': 'signature-1',
      },
      'notification': {
        'eventId': 'event-1',
        'turnId': 'gen-1',
        'conversationId': 'conversation-1',
        'outcome': 'completed',
      },
      'credentials': [
        {'managementSecret': 'management-secret'},
        {'fcmRegistrationToken': 'fcm-registration-token'},
      ],
      'delegation': {
        'delegationId': 'delegation-1',
        'challengeId': 'challenge-1',
        'challengeDigest': 'challenge-digest-1',
        'challengeSecret': 'challenge-secret-1',
        'targetDeviceId': 'target-device-1',
        'idempotencyKey': 'idempotency-1',
      },
    });
    final encoded = jsonEncode(redacted);

    expect((redacted as Map<String, dynamic>)['operation'], 'deliver');
    expect(encoded, contains('completed'));
    for (final sensitiveValue in <String>[
      'delivery_handle_1',
      'provider-token',
      'app-check-token',
      'delivery-key-1',
      'nonce-1',
      'signature-1',
      'event-1',
      'gen-1',
      'conversation-1',
      'management-secret',
      'fcm-registration-token',
      'delegation-1',
      'challenge-1',
      'challenge-digest-1',
      'challenge-secret-1',
      'target-device-1',
      'idempotency-1',
    ]) {
      expect(encoded, isNot(contains(sensitiveValue)), reason: sensitiveValue);
    }
  });
}
