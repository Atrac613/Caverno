import 'dart:io';

import 'package:caverno/core/services/attachment_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late Directory attachmentsDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('caverno_attachments_');
    attachmentsDir = Directory('${tempDir.path}/attachments')..createSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'deletes only direct files in the managed attachment directory',
    () async {
      final owned = File('${attachmentsDir.path}/owned.txt')
        ..writeAsStringSync('owned');
      final outside = File('${tempDir.path}/outside.txt')
        ..writeAsStringSync('outside');
      final nestedDirectory = Directory('${attachmentsDir.path}/nested')
        ..createSync();
      final nested = File('${nestedDirectory.path}/nested.txt')
        ..writeAsStringSync('nested');

      await AttachmentStorageService.deleteOwnedAttachments([
        owned.path,
        outside.path,
        nested.path,
        owned.path,
      ], directoryOverride: attachmentsDir);

      expect(owned.existsSync(), isFalse);
      expect(outside.existsSync(), isTrue);
      expect(nested.existsSync(), isTrue);
    },
  );

  test('ignores missing files and empty paths', () async {
    await expectLater(
      AttachmentStorageService.deleteOwnedAttachments([
        '',
        '${attachmentsDir.path}/missing.txt',
      ], directoryOverride: attachmentsDir),
      completes,
    );
  });

  test(
    'writes chunks to a staging file before promoting the attachment',
    () async {
      final writer = await AttachmentStorageService.beginWrite(
        originalName: 'large.bin',
        directoryOverride: attachmentsDir,
      );

      await writer.write(<int>[1, 2]);
      await writer.write(<int>[3, 4]);
      final path = await writer.complete();

      expect(File(path).readAsBytesSync(), [1, 2, 3, 4]);
      expect(
        attachmentsDir.listSync().whereType<File>().any(
          (file) => file.path.endsWith('.part'),
        ),
        isFalse,
      );
    },
  );

  test('discards an incomplete staging file', () async {
    final writer = await AttachmentStorageService.beginWrite(
      originalName: 'partial.bin',
      directoryOverride: attachmentsDir,
    );

    await writer.write(<int>[1, 2, 3]);
    final stagingPath = writer.stagingPath;
    await writer.discard();

    expect(File(stagingPath).existsSync(), isFalse);
  });
}
