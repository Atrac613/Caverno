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
}
