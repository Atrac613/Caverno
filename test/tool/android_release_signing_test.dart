import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String buildScript;

  setUpAll(() {
    buildScript = File('android/app/build.gradle.kts').readAsStringSync();
  });

  test('never assigns the debug signing configuration to release builds', () {
    expect(
      buildScript,
      isNot(contains('signingConfigs.getByName("debug")')),
    );
    expect(
      buildScript,
      contains('signingConfig = signingConfigs.findByName("release")'),
    );
  });

  test('requires every release signing property and the keystore file', () {
    for (final propertyName in [
      'keyAlias',
      'keyPassword',
      'storeFile',
      'storePassword',
    ]) {
      expect(buildScript, contains('"$propertyName"'));
    }

    expect(buildScript, contains('releaseStoreFile?.isFile == true'));
    expect(buildScript, contains('missingSigningProperties.isEmpty()'));
  });

  test('fails release artifact tasks with actionable guidance', () {
    expect(buildScript, contains('releaseBuildRequested && !releaseSigningReady'));
    expect(buildScript, contains('throw GradleException('));
    expect(buildScript, contains('Release signing is not configured:'));
    expect(buildScript, contains('assemble'));
    expect(buildScript, contains('bundle'));
  });
}
