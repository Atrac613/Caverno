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

  test('macOS app entitlements allow user-selected settings imports', () {
    final debugProfileEntitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    );
    final releaseEntitlements = File('macos/Runner/Release.entitlements');

    expect(debugProfileEntitlements.existsSync(), isTrue);
    expect(releaseEntitlements.existsSync(), isTrue);
    expect(
      debugProfileEntitlements.readAsStringSync(),
      contains('com.apple.security.files.user-selected.read-only'),
    );
    expect(
      releaseEntitlements.readAsStringSync(),
      contains('com.apple.security.files.user-selected.read-only'),
    );
  });
}
