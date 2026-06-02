import 'dart:io';

import 'package:caverno/core/services/macos_update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses Sparkle status payloads', () {
    final status = MacosUpdateStatus.fromMap(const <String, Object?>{
      'available': true,
      'configured': true,
      'feedURL':
          'https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos/appcast.xml',
      'publicKeyConfigured': true,
      'automaticallyChecksForUpdates': 'true',
      'automaticallyDownloadsUpdates': false,
      'scheduledCheckIntervalSeconds': '3600',
      'updateCheckIntervalSeconds': 3600,
      'bundleVersion': '13',
      'bundleShortVersion': '1.3.2',
    });

    expect(status.available, isTrue);
    expect(status.configured, isTrue);
    expect(status.publicKeyConfigured, isTrue);
    expect(status.automaticallyChecksForUpdates, isTrue);
    expect(status.automaticallyDownloadsUpdates, isFalse);
    expect(status.updateCheckIntervalSeconds, 3600);
    expect(status.displayVersion, '1.3.2+13');
  });

  test('reads Sparkle status from the platform channel on macOS', () async {
    if (!Platform.isMacOS) {
      return;
    }

    final channel = MethodChannel('test.caverno/sparkle_updates_status');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return <String, Object?>{
            'available': true,
            'configured': true,
            'feedURL':
                'https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos/appcast.xml',
            'publicKeyConfigured': true,
            'automaticallyChecksForUpdates': true,
            'automaticallyDownloadsUpdates': false,
            'scheduledCheckIntervalSeconds': 3600,
            'updateCheckIntervalSeconds': 3600,
            'bundleVersion': '13',
            'bundleShortVersion': '1.3.2',
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = MacosUpdateService(channel: channel);
    final status = await service.getStatus();

    expect(calls, ['getStatus']);
    expect(status.configured, isTrue);
    expect(status.feedUrl, contains('appcast.xml'));
  });

  test('starts a manual Sparkle update check on macOS', () async {
    if (!Platform.isMacOS) {
      return;
    }

    final channel = MethodChannel('test.caverno/sparkle_updates_check');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return <String, Object?>{
            'available': true,
            'configured': true,
            'feedURL':
                'https://caverno-macos-releases.s3.ap-northeast-1.amazonaws.com/caverno/macos/appcast.xml',
            'publicKeyConfigured': true,
            'automaticallyChecksForUpdates': true,
            'automaticallyDownloadsUpdates': false,
            'scheduledCheckIntervalSeconds': 3600,
            'updateCheckIntervalSeconds': 3600,
            'bundleVersion': '13',
            'bundleShortVersion': '1.3.2',
          };
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = MacosUpdateService(channel: channel);
    final status = await service.checkForUpdates();

    expect(calls, ['checkForUpdates']);
    expect(status.configured, isTrue);
  });
}
