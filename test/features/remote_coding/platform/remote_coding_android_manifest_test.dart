import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest does not globally permit cleartext traffic', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');

    expect(manifest.existsSync(), isTrue);
    expect(
      manifest.readAsStringSync(),
      isNot(contains('android:usesCleartextTraffic="true"')),
    );
  });

  test('Android FCM uses the pre-created Remote Coding channel', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('com.google.firebase.messaging.default_notification_channel_id'),
    );
    expect(manifest, contains('android:value="remote_coding_completion"'));
  });

  test('iOS declares local networking for LAN Remote Coding', () {
    final plist = File('ios/Runner/Info.plist');

    expect(plist.existsSync(), isTrue);
    final content = plist.readAsStringSync();
    expect(content, contains('NSAllowsLocalNetworking'));
    expect(content, contains('NSLocalNetworkUsageDescription'));
  });

  test('macOS release entitlements allow LAN host sockets', () {
    final entitlements = File('macos/Runner/Release.entitlements');

    expect(entitlements.existsSync(), isTrue);
    final content = entitlements.readAsStringSync();
    expect(content, contains('com.apple.security.network.client'));
    expect(content, contains('com.apple.security.network.server'));
  });

  test('macOS app entitlements allow user-selected project directories', () {
    final project = File('macos/Runner.xcodeproj/project.pbxproj');
    final entitlementsFiles = [
      File('macos/Runner/DebugProfile.entitlements'),
      File('macos/Runner/Release.entitlements'),
    ];

    expect(project.existsSync(), isTrue);
    final projectContent = project.readAsStringSync();
    expect(
      projectContent,
      contains('CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements;'),
    );
    expect(
      projectContent,
      contains('CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;'),
    );

    for (final entitlements in entitlementsFiles) {
      expect(entitlements.existsSync(), isTrue);
      expect(
        entitlements.readAsStringSync(),
        contains('com.apple.security.files.user-selected.read-write'),
      );
    }
  });

  test('macOS app entitlements allow user-selected settings imports', () {
    final entitlementsFiles = [
      File('macos/Runner/DebugProfile.entitlements'),
      File('macos/Runner/Release.entitlements'),
    ];

    for (final entitlements in entitlementsFiles) {
      expect(entitlements.existsSync(), isTrue);
      final content = entitlements.readAsStringSync();
      expect(
        content.contains('com.apple.security.files.user-selected.read-only') ||
            content.contains(
              'com.apple.security.files.user-selected.read-write',
            ),
        isTrue,
      );
    }
  });

  test('macOS disables Firebase Messaging auto-init', () {
    // firebase_messaging calls registerForRemoteNotifications at plugin
    // load when auto-init is on. macOS is not an FCM receive target, and
    // Debug signing does not include aps-environment, so that call logs
    // OSStatus 13 ("The operation couldn't be completed.") during
    // `flutter run -d macos`.
    final info = File('macos/Runner/Info.plist').readAsStringSync();
    expect(info, contains('FirebaseMessagingAutoInitEnabled'));
    expect(
      info.contains('<key>FirebaseMessagingAutoInitEnabled</key>\n\t<false/>'),
      isTrue,
    );
  });

  test('macOS debug entitlements allow the debugger to attach', () {
    // Signing.xcconfig sets CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO so
    // Xcode will not add get-task-allow for us. Without it, debugserver
    // reports "Not allowed to attach to process".
    final debugEntitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    final releaseEntitlements = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final runnerDebugStart = project.indexOf(
      '33CC10FC2044A3C60003C045 /* Debug */',
    );
    final runnerDebugEnd = project.indexOf('name = Debug;', runnerDebugStart);
    final runnerDebug = project.substring(runnerDebugStart, runnerDebugEnd);

    expect(debugEntitlements, contains('com.apple.security.get-task-allow'));
    expect(debugEntitlements, contains('com.apple.security.cs.allow-jit'));
    expect(releaseEntitlements, isNot(contains('get-task-allow')));
    expect(runnerDebug, isNot(contains('ENABLE_HARDENED_RUNTIME = YES;')));
    expect(runnerDebug, contains('ENABLE_APP_SANDBOX = NO;'));
  });

  test('macOS entitlements grant the keychain access secure storage needs', () {
    // flutter_secure_storage holds the relay delivery credential and the SSH
    // credentials. Without this entitlement the macOS keychain answers
    // errSecMissingEntitlement (-34018) and every write fails at runtime while
    // the build stays green.
    final entitlementsFiles = [
      File('macos/Runner/DebugProfile.entitlements'),
      File('macos/Runner/Release.entitlements'),
    ];

    for (final entitlements in entitlementsFiles) {
      expect(entitlements.existsSync(), isTrue);
      final content = entitlements.readAsStringSync();
      expect(content, contains('keychain-access-groups'));
      expect(
        content,
        contains(r'$(AppIdentifierPrefix)com.noguwo.apps.caverno'),
      );
    }
  });
}
