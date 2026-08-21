import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/widgets/message_video_io.dart';

void main() {
  group('videoExtensionForName', () {
    test('takes the extension the file already has', () {
      expect(videoExtensionForName('IMG_8129.MOV'), 'mov');
      expect(videoExtensionForName('clip.webm'), 'webm');
    });

    test('falls back to mp4 when there is nothing to take', () {
      expect(videoExtensionForName('clip'), 'mp4');
      expect(videoExtensionForName('clip.'), 'mp4');
      expect(videoExtensionForName('.hidden'), 'mp4');
    });
  });

  group('save', () {
    test('uses the share sheet on mobile, never the save dialog', () async {
      var shared = 0;
      var saved = 0;
      final io = MessageVideoIo(
        isMobile: () => true,
        shareFile: ({required sourcePath, required mimeType}) async {
          shared++;
          return true;
        },
        saveFile: ({required sourcePath, required fileName, dialogTitle}) async {
          saved++;
          return '/tmp/out.mp4';
        },
      );

      final outcome = await io.save(
        sourcePath: '/tmp/in.mp4',
        fileName: 'in.mp4',
        mimeType: 'video/mp4',
      );

      expect(outcome, MessageVideoSaveOutcome.shared);
      expect(shared, 1);
      expect(saved, 0);
    });

    test('a dismissed share sheet is a cancellation, not a failure', () async {
      final io = MessageVideoIo(
        isMobile: () => true,
        shareFile: ({required sourcePath, required mimeType}) async => false,
      );

      expect(
        await io.save(
          sourcePath: '/tmp/in.mp4',
          fileName: 'in.mp4',
          mimeType: 'video/mp4',
        ),
        MessageVideoSaveOutcome.cancelled,
      );
    });

    test('uses the save dialog on desktop', () async {
      String? askedFileName;
      final io = MessageVideoIo(
        isMobile: () => false,
        saveFile: ({required sourcePath, required fileName, dialogTitle}) async {
          askedFileName = fileName;
          return '/tmp/out.mp4';
        },
      );

      final outcome = await io.save(
        sourcePath: '/tmp/in.mp4',
        fileName: 'clip.mov',
        mimeType: 'video/quicktime',
      );

      expect(outcome, MessageVideoSaveOutcome.saved);
      expect(askedFileName, 'clip.mov');
    });

    test('a cancelled save dialog reports cancelled', () async {
      final io = MessageVideoIo(
        isMobile: () => false,
        saveFile: ({required sourcePath, required fileName, dialogTitle}) async =>
            null,
      );

      expect(
        await io.save(
          sourcePath: '/tmp/in.mp4',
          fileName: 'in.mp4',
          mimeType: 'video/mp4',
        ),
        MessageVideoSaveOutcome.cancelled,
      );
    });
  });

  test('saveVideoWithFilePicker copies rather than buffering the file', () async {
    // The point of taking a path: a ten-megabyte video never has to sit in
    // memory to reach the destination the person chose.
    final dir = await Directory.systemTemp.createTemp('video_io_test');
    addTearDown(() => dir.delete(recursive: true));
    final source = File('${dir.path}/in.mp4');
    await source.writeAsBytes(List<int>.generate(2048, (i) => i % 256));
    final destination = '${dir.path}/out.mp4';

    // Exercised through the injectable seam; the real dialog needs a host.
    final io = MessageVideoIo(
      isMobile: () => false,
      saveFile: ({required sourcePath, required fileName, dialogTitle}) async {
        await File(sourcePath).copy(destination);
        return destination;
      },
    );
    await io.save(
      sourcePath: source.path,
      fileName: 'in.mp4',
      mimeType: 'video/mp4',
    );

    expect(await File(destination).readAsBytes(), await source.readAsBytes());
  });
}
