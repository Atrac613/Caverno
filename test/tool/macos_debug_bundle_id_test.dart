import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS debug keeps the release bundle id for TCC', () {
    final xcodeProject = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();

    expect(
      appInfo,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.noguwo.apps.caverno'),
    );
    expect(
      xcodeProject,
      isNot(
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.noguwo.apps.caverno.debug;'),
      ),
    );
  });

  test('app always uses the dark theme', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains('themeMode: ThemeMode.dark'));
  });
}
