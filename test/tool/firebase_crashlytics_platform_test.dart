import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String pubspec;
  late String mainSource;
  late String androidSettings;
  late String androidApp;
  late String androidDebugManifest;
  late String iosProject;
  late String macosProject;
  late String proguard;
  late String macosRegistrant;

  setUpAll(() {
    pubspec = File('pubspec.yaml').readAsStringSync();
    mainSource = File('lib/main.dart').readAsStringSync();
    androidSettings = File('android/settings.gradle.kts').readAsStringSync();
    androidApp = File('android/app/build.gradle.kts').readAsStringSync();
    androidDebugManifest = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();
    iosProject = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    macosProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    proguard = File('android/app/proguard-rules.pro').readAsStringSync();
    macosRegistrant = File(
      'macos/Flutter/GeneratedPluginRegistrant.swift',
    ).readAsStringSync();
  });

  test('GUI startup installs Crashlytics after the CLI frontend exits', () {
    expect(pubspec, contains('firebase_crashlytics:'));
    expect(
      File('.gitignore').readAsStringSync(),
      contains('/macos/Runner/GoogleService-Info.plist'),
    );
    expect(mainSource, contains('installCavernoCrashlytics()'));
    expect(
      mainSource.indexOf('looksLikeCliInvocation'),
      lessThan(mainSource.indexOf('installCavernoCrashlytics()')),
    );
  });

  test('Android applies Crashlytics only with google-services.json', () {
    expect(androidSettings, contains('id("com.google.firebase.crashlytics")'));
    expect(
      androidApp,
      contains('apply(plugin = "com.google.firebase.crashlytics")'),
    );

    final optionalFirebaseBlock = RegExp(
      r'if \(file\("google-services\.json"\)\.exists\(\)\) \{[^}]+\}',
      dotAll: true,
    ).firstMatch(androidApp);
    expect(optionalFirebaseBlock, isNotNull);
    expect(
      optionalFirebaseBlock!.group(0),
      contains('com.google.gms.google-services'),
    );
    expect(
      optionalFirebaseBlock.group(0),
      contains('com.google.firebase.crashlytics'),
    );
    expect(proguard, contains('SourceFile,LineNumberTable'));
  });

  test('Android debug builds disable native Crashlytics collection', () {
    expect(
      androidDebugManifest,
      contains('firebase_crashlytics_collection_enabled'),
    );
    expect(androidDebugManifest, contains('android:value="false"'));
  });

  test('iOS uploads dSYMs only when Firebase configuration is present', () {
    expect(iosProject, contains('Upload Crashlytics dSYMs'));
    expect(iosProject, contains('Skipping Crashlytics dSYM upload for Debug.'));
    expect(
      iosProject,
      contains(
        'GoogleService-Info.plist is absent; skipping Crashlytics dSYM upload.',
      ),
    );
    expect(iosProject, contains('FirebaseCrashlytics/run'));
    expect(
      iosProject,
      contains(
        'GoogleService-Info.plist is absent; Firebase Messaging and Crashlytics stay disabled in this build.',
      ),
    );
    expect(macosRegistrant, contains('FirebaseCrashlyticsPlugin.register'));
  });

  test('macOS copies Firebase config and uploads dSYMs when present', () {
    expect(macosProject, contains('Copy Firebase Configuration'));
    expect(macosProject, contains('Upload Crashlytics dSYMs'));
    expect(macosProject, contains('../ios/Runner/GoogleService-Info.plist'));
    expect(
      macosProject,
      contains(
        'GoogleService-Info.plist is absent; Firebase Crashlytics stays disabled in this macOS build.',
      ),
    );
    expect(
      macosProject,
      contains('Skipping Crashlytics dSYM upload for Debug.'),
    );
    expect(macosProject, contains('FirebaseCrashlytics/run'));
    expect(
      File('tool/bootstrap_remote_coding_firebase.dart').readAsStringSync(),
      contains('copyIosFirebaseConfigToMacos'),
    );
  });
}
