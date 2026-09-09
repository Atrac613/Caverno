import 'dart:async';

import 'package:caverno/features/remote_coding/data/remote_coding_mobile_notification_gateway.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'failed concurrent initialization can retry and cache success',
    () async {
      var attempts = 0;
      final firstAttempt = Completer<void>();
      final gateway = FirebaseRemoteCodingMobileNotificationGateway.forTesting(
        messaging: _Messaging(),
        initializeFirebase: () async {
          attempts++;
          if (attempts == 1) await firstAttempt.future;
        },
      );
      final first = expectLater(gateway.initialize(), throwsStateError);
      final second = expectLater(gateway.initialize(), throwsStateError);
      expect(attempts, 1);
      firstAttempt.completeError(StateError('Firebase initialization failed'));
      await Future.wait([first, second]);
      final recovered = await Future.wait([
        gateway.initialize(),
        gateway.initialize(),
      ]);
      expect(
        recovered,
        everyElement(RemoteCodingNotificationPermission.authorized),
      );
      expect(attempts, 2);
      await gateway.initialize();
      expect(attempts, 2);
    },
  );

  test(
    'settings failure does not restart successful Firebase initialization',
    () async {
      var attempts = 0;
      final messaging = _Messaging()..failSettings = true;
      final gateway = FirebaseRemoteCodingMobileNotificationGateway.forTesting(
        messaging: messaging,
        initializeFirebase: () async {
          attempts++;
        },
      );
      await expectLater(gateway.initialize(), throwsStateError);
      messaging.failSettings = false;
      expect(
        await gateway.initialize(),
        RemoteCodingNotificationPermission.authorized,
      );
      expect(attempts, 1);
    },
  );
}

class _Messaging implements FirebaseMessaging {
  bool failSettings = false;

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    if (failSettings) throw StateError('Notification settings unavailable');
    return _Settings();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements NotificationSettings {
  @override
  AuthorizationStatus get authorizationStatus => AuthorizationStatus.authorized;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
