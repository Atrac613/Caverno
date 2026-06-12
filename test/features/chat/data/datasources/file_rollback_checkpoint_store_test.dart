import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';

void main() {
  group('FileRollbackCheckpointStore', () {
    late Directory tempDir;
    late FileRollbackCheckpointStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'file_rollback_checkpoint_store_test_',
      );
      store = FileRollbackCheckpointStore();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    String tempPath(String name) {
      return '${tempDir.path}${Platform.pathSeparator}$name';
    }

    test('rolls back only files captured in the turn checkpoint', () async {
      final changed = File(tempPath('changed.txt'))
        ..writeAsStringSync('before\n');
      final createdPath = tempPath('created.txt');
      final untouched = File(tempPath('untouched.txt'))
        ..writeAsStringSync('untouched\n');

      store.beginFileTurnCheckpoint('turn-1');
      store.push(await FilesystemTools.captureTextSnapshot(changed.path));
      await changed.writeAsString('after\n');
      store.push(await FilesystemTools.captureTextSnapshot(createdPath));
      await File(createdPath).writeAsString('created\n');
      store.endFileTurnCheckpoint();

      final preview = await store.previewLastFileTurnCheckpoint();
      expect(preview, isNotNull);
      expect(preview!.turnId, 'turn-1');
      expect(preview.paths, [
        changed.absolute.path,
        File(createdPath).absolute.path,
      ]);

      final result = await store.rollbackLastFileTurnCheckpoint();

      expect(result.isSuccess, isTrue);
      expect(await changed.readAsString(), 'before\n');
      expect(File(createdPath).existsSync(), isFalse);
      expect(await untouched.readAsString(), 'untouched\n');
    });

    test(
      'restores the first snapshot when a turn edits a file twice',
      () async {
        final target = File(tempPath('target.txt'))
          ..writeAsStringSync('before\n');

        store.beginFileTurnCheckpoint('turn-repeated-file');
        store.push(await FilesystemTools.captureTextSnapshot(target.path));
        await target.writeAsString('after first\n');
        store.push(await FilesystemTools.captureTextSnapshot(target.path));
        await target.writeAsString('after second\n');
        store.endFileTurnCheckpoint();

        final preview = await store.previewLastFileTurnCheckpoint();
        expect(preview, isNotNull);
        expect(preview!.paths, [target.absolute.path]);

        final result = await store.rollbackLastFileTurnCheckpoint();

        expect(result.isSuccess, isTrue);
        expect(await target.readAsString(), 'before\n');
      },
    );

    test(
      'keeps turn checkpoint entries after individual rollback stack eviction',
      () async {
        final untouched = File(tempPath('untouched.txt'))
          ..writeAsStringSync('untouched\n');
        final changedFiles = <File>[];

        store.beginFileTurnCheckpoint('turn-overflow');
        for (var index = 0; index < 25; index += 1) {
          final file = File(tempPath('changed_$index.txt'))
            ..writeAsStringSync('before-$index\n');
          changedFiles.add(file);
          store.push(await FilesystemTools.captureTextSnapshot(file.path));
          await file.writeAsString('after-$index\n');
        }
        store.endFileTurnCheckpoint();

        final preview = await store.previewLastFileTurnCheckpoint();
        expect(preview, isNotNull);
        expect(preview!.paths, hasLength(25));

        final result = await store.rollbackLastFileTurnCheckpoint();

        expect(result.isSuccess, isTrue);
        for (var index = 0; index < changedFiles.length; index += 1) {
          expect(await changedFiles[index].readAsString(), 'before-$index\n');
        }
        expect(await untouched.readAsString(), 'untouched\n');
      },
    );

    test('retains only the latest ten completed turn checkpoints', () async {
      final files = <File>[];
      for (var index = 0; index < 12; index += 1) {
        final file = File(tempPath('turn_$index.txt'))
          ..writeAsStringSync('before-$index\n');
        files.add(file);

        store.beginFileTurnCheckpoint('turn-$index');
        store.push(await FilesystemTools.captureTextSnapshot(file.path));
        await file.writeAsString('after-$index\n');
        store.endFileTurnCheckpoint();
      }

      for (var expectedIndex = 11; expectedIndex >= 2; expectedIndex -= 1) {
        final result = await store.rollbackLastFileTurnCheckpoint();
        final decoded = jsonDecode(result.result) as Map<String, dynamic>;

        expect(result.isSuccess, isTrue);
        expect(decoded['turn_id'], 'turn-$expectedIndex');
        expect(
          await files[expectedIndex].readAsString(),
          'before-$expectedIndex\n',
        );
      }

      final exhausted = await store.rollbackLastFileTurnCheckpoint();

      expect(exhausted.isSuccess, isFalse);
      expect(await files[0].readAsString(), 'after-0\n');
      expect(await files[1].readAsString(), 'after-1\n');
    });

    test('closes the active checkpoint when a new turn starts', () async {
      final first = File(tempPath('first.txt'))
        ..writeAsStringSync('first before\n');
      final second = File(tempPath('second.txt'))
        ..writeAsStringSync('second before\n');

      store.beginFileTurnCheckpoint('turn-first');
      store.push(await FilesystemTools.captureTextSnapshot(first.path));
      await first.writeAsString('first after\n');

      store.beginFileTurnCheckpoint('turn-second');
      store.push(await FilesystemTools.captureTextSnapshot(second.path));
      await second.writeAsString('second after\n');
      store.endFileTurnCheckpoint();

      final secondRollback = await store.rollbackLastFileTurnCheckpoint();
      final firstRollback = await store.rollbackLastFileTurnCheckpoint();

      expect(secondRollback.isSuccess, isTrue);
      expect(firstRollback.isSuccess, isTrue);
      expect(await first.readAsString(), 'first before\n');
      expect(await second.readAsString(), 'second before\n');
    });

    test('keeps failed turn checkpoint available for retry', () async {
      final target = File(tempPath('target.txt'))
        ..writeAsStringSync('before\n');

      store.beginFileTurnCheckpoint('turn-retry');
      store.push(await FilesystemTools.captureTextSnapshot(target.path));
      await target.writeAsString('after\n');
      store.endFileTurnCheckpoint();

      target.deleteSync();
      Directory(target.path).createSync();

      final firstResult = await store.rollbackLastFileTurnCheckpoint();

      expect(firstResult.isSuccess, isFalse);
      expect(await store.previewLastFileTurnCheckpoint(), isNotNull);

      Directory(target.path).deleteSync();
      final secondResult = await store.rollbackLastFileTurnCheckpoint();

      expect(secondResult.isSuccess, isTrue);
      expect(await target.readAsString(), 'before\n');
    });
  });
}
