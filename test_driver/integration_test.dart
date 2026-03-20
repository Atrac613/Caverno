import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// App Store screenshot target dimensions by device class.
/// Set the SCREENSHOT_DEVICE env var to 'ipad' for iPad sizing.
const _iphone = (width: 1284, height: 2778); // 6.7" iPhone
const _ipad = (width: 2048, height: 2732); // 12.9"/13" iPad

Future<void> main() async {
  final isIpad =
      Platform.environment['SCREENSHOT_DEVICE']?.toLowerCase() == 'ipad';
  final target = isIpad ? _ipad : _iphone;
  final outDir = isIpad ? 'screenshots/ipad' : 'screenshots';

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

      // Resize to App Store dimensions.
      await Process.run('sips', [
        '-z',
        '${target.height}',
        '${target.width}',
        path,
      ]);

      return true;
    },
  );
}
