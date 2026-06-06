import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/python_input_staging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  final stagedDirs = <Directory>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('python_input_staging_');
    stagedDirs.clear();
  });

  tearDown(() async {
    for (final dir in stagedDirs) {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    }
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('stages original image file before upload image payload', () async {
    final original = File('${tempDir.path}${Platform.pathSeparator}photo.jpg');
    await original.writeAsBytes([1, 2, 3, 4]);

    final staged = await PythonInputStaging.stage(
      imageBase64: base64Encode([9, 8, 7]),
      imageMimeType: 'image/png',
      originalImagePath: original.path,
      originalImageMimeType: 'image/jpeg',
    );
    stagedDirs.add(Directory(staged.workingDirectory));

    expect(staged.inputs, hasLength(1));
    expect(staged.inputs.single['name'], 'attachment_0.jpg');
    expect(staged.inputs.single['mime'], 'image/jpeg');
    expect(await File(staged.inputs.single['path'] as String).readAsBytes(), [
      1,
      2,
      3,
      4,
    ]);
  });

  test(
    'falls back to upload image payload when original path is missing',
    () async {
      final staged = await PythonInputStaging.stage(
        imageBase64: base64Encode([9, 8, 7]),
        imageMimeType: 'image/png',
        originalImagePath:
            '${tempDir.path}${Platform.pathSeparator}missing-photo.jpg',
        originalImageMimeType: 'image/jpeg',
      );
      stagedDirs.add(Directory(staged.workingDirectory));

      expect(staged.inputs, hasLength(1));
      expect(staged.inputs.single['name'], 'attachment_0.png');
      expect(staged.inputs.single['mime'], 'image/png');
      expect(await File(staged.inputs.single['path'] as String).readAsBytes(), [
        9,
        8,
        7,
      ]);
    },
  );
}
