import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// App Store screenshot target dimensions by device class.
/// Set the SCREENSHOT_DEVICE env var to 'ipad' for iPad sizing.
const _iphone = (width: 1284, height: 2778); // 6.7" iPhone
const _ipad = (width: 2048, height: 2732); // 12.9"/13" iPad
const _androidPhone = (width: 1080, height: 2400); // 20:9 Android Phone
const _androidTablet = (width: 1600, height: 2560); // 10:16 Android Tablet

Future<void> main() async {
  final deviceType =
      Platform.environment['SCREENSHOT_DEVICE']?.toLowerCase() ?? 'iphone';

  final (width: targetWidth, height: targetHeight) = switch (deviceType) {
    'ipad' => _ipad,
    'android_phone' => _androidPhone,
    'android_tablet' => _androidTablet,
    _ => _iphone,
  };

  final outDir = switch (deviceType) {
    'ipad' => 'screenshots/apple/ipad',
    'android_phone' => 'screenshots/android/phone',
    'android_tablet' => 'screenshots/android/tablet',
    _ => 'screenshots/apple/ios',
  };

  await integrationDriver(
    onScreenshot: (
      String screenshotName,
      List<int> screenshotBytes, [
      Map<String, Object?>? args,
    ]) async {
      final dir = Directory(outDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final path = '$outDir/$screenshotName.png';
      File(path).writeAsBytesSync(screenshotBytes);

      // Resize to target dimensions.
      await Process.run('sips', [
        '-z',
        '$targetHeight',
        '$targetWidth',
        path,
      ]);

      return true;
    },
  );
}
