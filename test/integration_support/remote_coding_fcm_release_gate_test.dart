import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/remote_coding_fcm_release_gate.dart';

void main() {
  test('current repository blocks only missing environment evidence', () {
    final result = buildRemoteCodingFcmReleaseGate(
      repoRoot: Directory.current,
      generatedAt: DateTime.utc(2026, 8, 10, 12),
    );

    expect(result.status, 'blocked');
    expect(
      result.gates
          .singleWhere((gate) => gate.id == 'platform_capabilities')
          .isReady,
      isTrue,
    );
    expect(
      result.gates
          .singleWhere((gate) => gate.id == 'relay_and_mobile_implementation')
          .isReady,
      isTrue,
    );
    // The Firebase app files are environment-owned and gitignored, so this
    // gate depends on whether the current machine has installed them.
    final hasFirebaseAppFiles =
        File('ios/Runner/GoogleService-Info.plist').existsSync() &&
        File('android/app/google-services.json').existsSync();
    expect(
      result.blockedGateIds.contains('firebase_app_configuration'),
      !hasFirebaseAppFiles,
    );
    expect(result.blockedGateIds, contains('firebase_deployment'));
    expect(result.blockedGateIds, contains('physical_device_delivery_matrix'));
    expect(
      result.blockedGateIds,
      contains('release_signing_push_entitlements'),
    );
  });

  test('passes with matching app files and complete manual evidence', () {
    final root = Directory.systemTemp.createTempSync('fcm_release_gate_');
    addTearDown(() => root.deleteSync(recursive: true));
    _writeStaticFixture(root);
    final checklist = _markAllBooleansReady(
      remoteCodingFcmManualChecklistTemplate(
        generatedAt: DateTime.utc(2026, 8, 10, 12),
      ),
    );
    final checklistFile = File('${root.path}/checklist.json')
      ..writeAsStringSync(jsonEncode(checklist));

    final result = buildRemoteCodingFcmReleaseGate(
      repoRoot: root,
      manualChecklistFile: checklistFile,
      generatedAt: DateTime.utc(2026, 8, 10, 12),
    );

    expect(result.status, 'ready_for_remote_coding_fcm_release');
    expect(result.blockedGateIds, isEmpty);
    expect(result.toJson()['schemaName'], 'remote_coding_fcm_release_gate');
    expect(result.toMarkdown(), contains('physical_device_delivery_matrix'));
  });

  test('template covers deployment, device, and signing evidence', () {
    final template = remoteCodingFcmManualChecklistTemplate();

    expect(template['firebaseDeployment'], isA<Map<String, Object>>());
    expect(template['physicalDeviceMatrix'], isA<Map<String, Object>>());
    expect(template['releaseSigning'], isA<Map<String, Object>>());
  });
}

void _writeStaticFixture(Directory root) {
  final files = <String, String>{
    'ios/Runner/Info.plist':
        'remote-notification FirebaseMessagingAutoInitEnabled',
    'ios/Runner/Runner.entitlements': 'aps-environment',
    'ios/Podfile':
        "platform :ios, '15.0' IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'",
    'ios/Runner.xcodeproj/project.pbxproj':
        'com.apple.Push com.apple.BackgroundModes Copy Firebase Configuration',
    'ios/Runner/GoogleService-Info.plist': 'com.noguwo.apps.caverno',
    'android/app/src/main/AndroidManifest.xml':
        'POST_NOTIFICATIONS firebase_messaging_auto_init_enabled '
        'com.google.firebase.messaging.default_notification_channel_id '
        'remote_coding_completion',
    'android/settings.gradle.kts': 'com.google.gms.google-services',
    'android/app/build.gradle.kts': 'google-services.json',
    'android/app/google-services.json': 'com.noguwo.apps.caverno',
    'tool/bootstrap_remote_coding_firebase.dart': 'bootstrap',
    'tool/remote_coding_firebase_status.dart': 'functions:list',
    'firebase.json': 'notification-relay',
    'services/notification_relay/src/relay_service.js': 'deliver',
    'lib/features/remote_coding/data/remote_coding_mobile_notification_gateway.dart':
        'getLimitedUseToken setAutoInitEnabled',
  };
  for (final entry in files.entries) {
    final file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
}

Object _markAllBooleansReady(Object value) {
  if (value is bool) {
    return true;
  }
  if (value is Map<String, Object>) {
    return value.map(
      (key, child) => MapEntry(key, _markAllBooleansReady(child)),
    );
  }
  return value;
}
