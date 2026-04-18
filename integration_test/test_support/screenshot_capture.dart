import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:integration_test/integration_test.dart';

import 'package:caverno/core/utils/logger.dart';

Future<Uint8List> captureIntegrationScreenshot({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required GlobalKey repaintBoundaryKey,
  required String name,
  Directory? outputDirectory,
}) async {
  await _pumpUntilIdle(tester);

  try {
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    final bytes = await binding.takeScreenshot(name);
    return Uint8List.fromList(bytes);
  } on MissingPluginException {
    return _captureWithRepaintBoundary(
      binding: binding,
      tester: tester,
      repaintBoundaryKey: repaintBoundaryKey,
      name: name,
      outputDirectory:
          outputDirectory ?? Directory('build/integration_test_screenshots'),
    );
  }
}

Future<Uint8List> _captureWithRepaintBoundary({
  required IntegrationTestWidgetsFlutterBinding binding,
  required WidgetTester tester,
  required GlobalKey repaintBoundaryKey,
  required String name,
  required Directory outputDirectory,
}) async {
  final context = repaintBoundaryKey.currentContext;
  if (context == null) {
    throw StateError('Screenshot boundary is not attached for "$name".');
  }

  final renderObject = context.findRenderObject();
  if (renderObject == null) {
    throw StateError('Screenshot render object is missing for "$name".');
  }

  final boundary = renderObject as RenderRepaintBoundary;

  if (boundary.debugNeedsPaint) {
    await tester.pump();
  }

  final image = await boundary.toImage(
    pixelRatio: tester.view.devicePixelRatio,
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  if (byteData == null) {
    throw StateError('Failed to encode screenshot "$name" as PNG.');
  }

  final bytes = byteData.buffer.asUint8List();
  await outputDirectory.create(recursive: true);
  final outputFile = File('${outputDirectory.path}/$name.png');
  await outputFile.writeAsBytes(bytes, flush: true);

  binding.reportData ??= <String, dynamic>{};
  final screenshots =
      (binding.reportData!['screenshots'] as List<dynamic>?) ?? <dynamic>[];
  binding.reportData!['screenshots'] = screenshots;
  screenshots.add(<String, dynamic>{
    'screenshotName': name,
    'path': outputFile.path,
    'bytes': bytes,
    'source': 'repaint_boundary_fallback',
  });

  appLog(
    '[Screenshot] Saved "$name" via repaint boundary fallback to ${outputFile.path}',
  );

  return bytes;
}

Future<void> _pumpUntilIdle(
  WidgetTester tester, {
  Duration step = const Duration(milliseconds: 100),
  int maxPumps = 50,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(step);
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}
