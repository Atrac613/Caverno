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
}
