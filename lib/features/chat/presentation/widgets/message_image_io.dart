import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../../../core/utils/logger.dart';

/// Copy, save, and original-file loading for the message image viewer.
///
/// Tests inject fakes; production uses clipboard + save-file dialogs.
class MessageImageIo {
  const MessageImageIo({
    this.copyImage,
    this.saveImage,
    this.readFileBytes,
  });

  final Future<void> Function(Uint8List bytes, String mimeType)? copyImage;
  final Future<String?> Function({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? dialogTitle,
  })?
  saveImage;
  final Future<Uint8List?> Function(String path)? readFileBytes;

  Future<void> copy(Uint8List bytes, String mimeType) {
    return (copyImage ?? copyImageToClipboard)(bytes, mimeType);
  }

  Future<String?> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? dialogTitle,
  }) {
    return (saveImage ?? saveImageWithFilePicker)(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      dialogTitle: dialogTitle,
    );
  }

  Future<Uint8List?> readOriginal(String path) {
    return (readFileBytes ?? readImageFileBytes)(path);
  }
}

String messageImageExtensionForMime(String? mimeType) {
  return switch (_normalizedMime(mimeType)) {
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    'image/tiff' => 'tiff',
    'image/bmp' => 'bmp',
    _ => 'png',
  };
}

String suggestedMessageImageFileName({
  String? originalImagePath,
  String? mimeType,
}) {
  final fromPath = messageImageBasename(originalImagePath);
  if (fromPath != null && fromPath.contains('.')) {
    return fromPath;
  }
  final stem = fromPath == null || fromPath.isEmpty
      ? 'caverno-image'
      : fromPath;
  return '$stem.${messageImageExtensionForMime(mimeType)}';
}

String? messageImageBasename(String? path) {
  if (path == null) {
    return null;
  }
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final normalized = trimmed.replaceAll('\\', '/');
  final parts = normalized.split('/');
  final name = parts.isEmpty ? '' : parts.last.trim();
  return name.isEmpty ? null : name;
}

SimpleFileFormat messageImageClipboardFormat(String? mimeType) {
  return switch (_normalizedMime(mimeType)) {
    'image/jpeg' => Formats.jpeg,
    'image/gif' => Formats.gif,
    'image/webp' => Formats.webp,
    'image/heic' => Formats.heic,
    'image/heif' => Formats.heif,
    'image/tiff' => Formats.tiff,
    'image/bmp' => Formats.bmp,
    _ => Formats.png,
  };
}

Future<void> copyImageToClipboard(Uint8List bytes, String mimeType) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    throw StateError('Clipboard is not available on this platform.');
  }
  final item = DataWriterItem();
  item.add(messageImageClipboardFormat(mimeType)(bytes));
  await clipboard.write([item]);
}

Future<String?> saveImageWithFilePicker({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? dialogTitle,
}) {
  final extension = messageImageExtensionForMime(mimeType);
  return FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: bytes,
  );
}

Future<Uint8List?> readImageFileBytes(String path) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final file = File(trimmed);
    if (!await file.exists()) {
      return null;
    }
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  } catch (error) {
    appLog('[MessageImageIo] Failed to read original image: $error');
    return null;
  }
}

String _normalizedMime(String? mimeType) {
  final trimmed = mimeType?.trim().toLowerCase() ?? '';
  if (trimmed == 'image/jpg') {
    return 'image/jpeg';
  }
  return trimmed;
}
