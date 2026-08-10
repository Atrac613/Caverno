import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/remote_coding_firebase_bootstrap.dart';

void main() {
  test('parses apps and selects the exact Caverno namespace', () {
    final apps = parseFirebaseAppsList(
      jsonEncode({
        'status': 'success',
        'result': [
          {
            'platform': 'IOS',
            'appId': 'ios-app',
            'namespace': remoteCodingFirebaseNamespace,
          },
          {
            'platform': 'ANDROID',
            'appId': 'android-app',
            'namespace': remoteCodingFirebaseNamespace,
          },
          {
            'platform': 'IOS',
            'appId': 'other-app',
            'namespace': 'com.example.other',
          },
        ],
      }),
    );

    final plan = buildRemoteCodingFirebaseBootstrapPlan(apps);

    expect(plan.requiresMutation, isFalse);
    expect(plan.iosApp?.appId, 'ios-app');
    expect(plan.androidApp?.appId, 'android-app');
  });

  test('reports only missing Firebase platforms', () {
    final plan = buildRemoteCodingFirebaseBootstrapPlan([
      const RemoteCodingFirebaseApp(
        platform: 'IOS',
        appId: 'ios-app',
        namespace: remoteCodingFirebaseNamespace,
      ),
    ]);

    expect(plan.requiresMutation, isTrue);
    expect(plan.missingPlatforms, ['ANDROID']);
  });

  test('rejects duplicate apps for the same namespace and platform', () {
    const app = RemoteCodingFirebaseApp(
      platform: 'IOS',
      appId: 'ios-app',
      namespace: remoteCodingFirebaseNamespace,
    );

    expect(
      () => buildRemoteCodingFirebaseBootstrapPlan([app, app]),
      throwsStateError,
    );
  });

  test('validates Firebase project IDs', () {
    expect(isValidFirebaseProjectId('caverno-notify-123'), isTrue);
    expect(isValidFirebaseProjectId('Caverno'), isFalse);
    expect(isValidFirebaseProjectId('short'), isFalse);
    expect(isValidFirebaseProjectId('contains_underscore'), isFalse);
  });
}
