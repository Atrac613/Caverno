import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const domains = <String>[
    'root',
    'file',
    'database',
    'sharedpref',
    'external',
    'device_root',
    'device_file',
    'device_database',
    'device_sharedpref',
  ];

  test('manifest disables backup and references both rule formats', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('legacy rules exclude every app-private storage domain', () {
    final rules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();

    expect(rules, contains('<full-backup-content>'));
    for (final domain in domains) {
      expect(rules, contains('<exclude domain="$domain" path="." />'));
    }
    expect(rules, isNot(contains('<include ')));
  });

  test('modern rules exclude cloud and device transfer domains', () {
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
    for (final domain in domains) {
      final exclusion = '<exclude domain="$domain" path="." />';
      expect(exclusion.allMatches(rules), hasLength(2));
    }
    expect(rules, isNot(contains('<include ')));
  });
}
