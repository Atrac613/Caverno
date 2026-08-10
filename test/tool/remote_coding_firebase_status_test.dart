import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/remote_coding_firebase_status.dart';

void main() {
  test('parses Firebase CLI success and error envelopes', () {
    final success = FirebaseCliEnvelope.parse(
      jsonEncode({'status': 'success', 'result': <Object>[]}),
    );
    final error = FirebaseCliEnvelope.parse(
      jsonEncode({'status': 'error', 'error': 'API disabled'}),
    );

    expect(success.success, isTrue);
    expect(success.result, isEmpty);
    expect(error.success, isFalse);
    expect(error.error, 'API disabled');
  });

  test('detects the default native Firestore database and location', () {
    final envelope = _success([
      {
        'name': 'projects/caverno/databases/(default)',
        'type': 'FIRESTORE_NATIVE',
        'locationId': 'asia-northeast1',
      },
    ]);

    expect(hasDefaultFirestoreDatabase(envelope), isTrue);
    expect(defaultFirestoreLocation(envelope), 'asia-northeast1');
  });

  test('detects the default Hosting URL', () {
    final envelope = _success({
      'sites': [
        {'type': 'DEFAULT_SITE', 'defaultUrl': 'https://caverno.web.app'},
      ],
    });

    expect(defaultHostingUrl(envelope), 'https://caverno.web.app');
  });

  test('requires the exact active notification relay deployment', () {
    final ready = _success([
      {
        'id': 'notificationRelay',
        'codebase': 'notification-relay',
        'region': 'asia-northeast1',
        'runtime': 'nodejs22',
        'state': 'ACTIVE',
      },
      {
        'id': 'retryNotificationDeliveries',
        'codebase': 'notification-relay',
        'region': 'asia-northeast1',
        'runtime': 'nodejs22',
        'state': 'ACTIVE',
      },
    ]);
    final wrongCodebase = _success([
      {
        'id': 'notificationRelay',
        'codebase': 'default',
        'region': 'asia-northeast1',
        'runtime': 'nodejs22',
        'state': 'ACTIVE',
      },
      {
        'id': 'retryNotificationDeliveries',
        'codebase': 'default',
        'region': 'asia-northeast1',
        'runtime': 'nodejs22',
        'state': 'ACTIVE',
      },
    ]);

    expect(hasActiveNotificationRelay(ready), isTrue);
    expect(hasActiveNotificationRelay(wrongCodebase), isFalse);
  });
}

FirebaseCliEnvelope _success(Object result) => FirebaseCliEnvelope.parse(
  jsonEncode({'status': 'success', 'result': result}),
);
