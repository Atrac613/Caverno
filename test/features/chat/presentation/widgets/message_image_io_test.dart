import 'dart:typed_data';

import 'package:caverno/features/chat/presentation/widgets/message_image_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() {
  test('maps image MIME types to file extensions', () {
    expect(messageImageExtensionForMime('image/png'), 'png');
    expect(messageImageExtensionForMime('image/jpeg'), 'jpg');
    expect(messageImageExtensionForMime('image/jpg'), 'jpg');
    expect(messageImageExtensionForMime('IMAGE/WEBP'), 'webp');
    expect(messageImageExtensionForMime(null), 'png');
    expect(messageImageExtensionForMime(''), 'png');
  });

  test('prefers the original path basename when it has an extension', () {
    expect(
      suggestedMessageImageFileName(
        originalImagePath: '/tmp/attachments/1234_photo.jpeg',
        mimeType: 'image/png',
      ),
      '1234_photo.jpeg',
    );
  });

  test('falls back to caverno-image plus MIME extension', () {
    expect(
      suggestedMessageImageFileName(mimeType: 'image/jpeg'),
      'caverno-image.jpg',
    );
  });

  test('selects the clipboard format for the MIME type', () {
    expect(messageImageClipboardFormat('image/png'), Formats.png);
    expect(messageImageClipboardFormat('image/jpeg'), Formats.jpeg);
    expect(messageImageClipboardFormat('image/gif'), Formats.gif);
    expect(messageImageClipboardFormat(null), Formats.png);
  });

  test('MessageImageIo.copy uses the injected callback', () async {
    Uint8List? copiedBytes;
    String? copiedMime;
    final io = MessageImageIo(
      copyImage: (bytes, mimeType) async {
        copiedBytes = bytes;
        copiedMime = mimeType;
      },
    );

    await io.copy(Uint8List.fromList([1, 2, 3]), 'image/png');

    expect(copiedBytes, Uint8List.fromList([1, 2, 3]));
    expect(copiedMime, 'image/png');
  });

  test('MessageImageIo.save uses the injected callback', () async {
    String? savedName;
    final io = MessageImageIo(
      saveImage:
          ({
            required bytes,
            required fileName,
            required mimeType,
            dialogTitle,
          }) async {
            savedName = fileName;
            return '/tmp/$fileName';
          },
    );

    final path = await io.save(
      bytes: Uint8List.fromList([1]),
      fileName: 'shot.png',
      mimeType: 'image/png',
    );

    expect(savedName, 'shot.png');
    expect(path, '/tmp/shot.png');
  });
}
