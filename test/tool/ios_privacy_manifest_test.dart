import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String manifest;

  setUpAll(() {
    manifest = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
  });

  test('declares the six app-owned collection categories', () {
    final declaredTypes = RegExp(
      r'<key>NSPrivacyCollectedDataType</key>\s*<string>([^<]+)</string>',
    ).allMatches(manifest).map((match) => match.group(1)).toSet();

    expect(declaredTypes, {
      'NSPrivacyCollectedDataTypeCustomerSupport',
      'NSPrivacyCollectedDataTypeOtherUserContent',
      'NSPrivacyCollectedDataTypePerformanceData',
      'NSPrivacyCollectedDataTypeOtherDiagnosticData',
      'NSPrivacyCollectedDataTypeDeviceID',
      'NSPrivacyCollectedDataTypeProductInteraction',
    });
  });

  test('feedback collection is unlinked and never used for tracking', () {
    for (final type in [
      'NSPrivacyCollectedDataTypeCustomerSupport',
      'NSPrivacyCollectedDataTypeOtherUserContent',
      'NSPrivacyCollectedDataTypePerformanceData',
      'NSPrivacyCollectedDataTypeOtherDiagnosticData',
    ]) {
      final entry = _entryFor(manifest, type);
      expect(entry, contains('<key>NSPrivacyCollectedDataTypeLinked</key>'));
      expect(entry, matches(RegExp(r'Linked</key>\s*<false\s*/>')));
      expect(entry, matches(RegExp(r'Tracking</key>\s*<false\s*/>')));
      expect(entry, contains('NSPrivacyCollectedDataTypePurposeAnalytics'));
    }
  });

  test('notification relay data is linked only for app functionality', () {
    for (final type in [
      'NSPrivacyCollectedDataTypeDeviceID',
      'NSPrivacyCollectedDataTypeProductInteraction',
    ]) {
      final entry = _entryFor(manifest, type);
      expect(entry, matches(RegExp(r'Linked</key>\s*<true\s*/>')));
      expect(entry, matches(RegExp(r'Tracking</key>\s*<false\s*/>')));
      expect(
        entry,
        contains('NSPrivacyCollectedDataTypePurposeAppFunctionality'),
      );
      expect(
        entry,
        isNot(contains('NSPrivacyCollectedDataTypePurposeAnalytics')),
      );
    }
  });

  test('keeps tracking disabled and required-reason declarations present', () {
    expect(
      manifest,
      matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false\s*/>')),
    );
    expect(
      manifest,
      matches(RegExp(r'<key>NSPrivacyTrackingDomains</key>\s*<array\s*/>')),
    );
    expect(manifest, contains('NSPrivacyAccessedAPICategoryUserDefaults'));
    expect(manifest, contains('NSPrivacyAccessedAPICategoryFileTimestamp'));
  });
}

String _entryFor(String manifest, String type) {
  final match = RegExp(
    '<dict>\\s*<key>NSPrivacyCollectedDataType</key>\\s*'
    '<string>${RegExp.escape(type)}</string>([\\s\\S]*?)</dict>',
  ).firstMatch(manifest);
  expect(match, isNotNull, reason: 'Missing privacy entry for $type.');
  return match!.group(0)!;
}
