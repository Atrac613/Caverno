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

  test('app theme follows the persisted preference, defaulting to dark', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final settingsSource = File(
      'lib/features/settings/domain/entities/app_settings.dart',
    ).readAsStringSync();

    // Onboarding lets the user choose, so the hardcoded ThemeMode.dark is gone;
    // dark staying the entity default is what keeps existing installs looking
    // the same after the upgrade.
    expect(mainSource, contains('themeMode: themePreference.themeMode'));
    expect(
      settingsSource,
      contains('@Default(AppThemePreference.dark)'),
    );
  });
}
