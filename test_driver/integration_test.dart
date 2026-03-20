import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// App Store requires specific screenshot dimensions.
/// Resize to 1284x2778 (6.7" display, portrait).
const int _targetWidth = 1284;
const int _targetHeight = 2778;

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (
      String screenshotName,
      List<int> screenshotBytes, [
      Map<String, Object?>? args,
    ]) async {
      final dir = Directory('screenshots');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final path = 'screenshots/$screenshotName.png';
      File(path).writeAsBytesSync(screenshotBytes);

      // Resize to App Store dimensions.
      await Process.run('sips', [
        '-z',
        '$_targetHeight',
        '$_targetWidth',
        path,
      ]);

      return true;
    },
  );
}
