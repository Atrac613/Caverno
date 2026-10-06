import 'dart:typed_data';
import 'dart:ui' as ui;

/// The image payload sent to a vision-capable model.
class PreparedImageAttachment {
  const PreparedImageAttachment({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// Creates the bounded image payload used by local and Remote Coding chat.
///
/// The caller owns the original bytes separately. This service only prepares
/// the model-facing representation, keeping the display/storage copy and the
/// request copy on the same policy.
abstract final class ImageAttachmentPreparationService {
  static const int maxDimension = 1024;

  static Future<PreparedImageAttachment> prepareForModel({
    required Uint8List bytes,
    required String mimeType,
    required String filePath,
  }) async {
    final resized = await _resizeIfNeeded(bytes, mimeType: mimeType);
    return _normalizeFormat(
      bytes: resized.bytes,
      mimeType: resized.mimeType,
      filePath: filePath,
    );
  }

  static Future<PreparedImageAttachment> _resizeIfNeeded(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;

      if (image.width <= maxDimension && image.height <= maxDimension) {
        return PreparedImageAttachment(bytes: bytes, mimeType: mimeType);
      }

      final targetWidth = image.width >= image.height ? maxDimension : null;
      final targetHeight = image.height > image.width ? maxDimension : null;
      image.dispose();
      image = null;
      codec.dispose();
      codec = null;

      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final resizedFrame = await codec.getNextFrame();
      image = resizedFrame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return PreparedImageAttachment(bytes: bytes, mimeType: mimeType);
      }
      return PreparedImageAttachment(
        bytes: byteData.buffer.asUint8List(),
        mimeType: 'image/png',
      );
    } catch (_) {
      return PreparedImageAttachment(bytes: bytes, mimeType: mimeType);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Future<PreparedImageAttachment> _normalizeFormat({
    required Uint8List bytes,
    required String mimeType,
    required String filePath,
  }) async {
    final lowerMime = mimeType.toLowerCase();
    final lowerPath = filePath.toLowerCase();
    final isWebp = lowerMime == 'image/webp' || lowerPath.endsWith('.webp');
    final isTiff =
        lowerMime == 'image/tiff' ||
        lowerPath.endsWith('.tiff') ||
        lowerPath.endsWith('.tif');
    final isHeic =
        lowerMime == 'image/heic' ||
        lowerMime == 'image/heif' ||
        lowerPath.endsWith('.heic') ||
        lowerPath.endsWith('.heif');
    final isGif = lowerMime == 'image/gif' || lowerPath.endsWith('.gif');

    if (!isWebp && !isTiff && !isHeic && !isGif) {
      return PreparedImageAttachment(bytes: bytes, mimeType: mimeType);
    }

    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return PreparedImageAttachment(bytes: bytes, mimeType: mimeType);
      }
      return PreparedImageAttachment(
        bytes: byteData.buffer.asUint8List(),
        mimeType: 'image/png',
      );
    } catch (_) {
      return PreparedImageAttachment(bytes: bytes, mimeType: mimeType);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
