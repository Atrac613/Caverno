import 'dart:typed_data';

/// A mobile attachment waiting to be uploaded with the next Remote Coding
/// message.
class RemoteCodingAttachmentDraft {
  const RemoteCodingAttachmentDraft({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType.toLowerCase().startsWith('image/');
}

/// Shared limits and normalization for the Remote Coding attachment transfer.
///
/// The WebSocket still has a 256 KiB frame limit. Attachments therefore travel
/// as several small JSON messages rather than weakening the socket's resource
/// boundary for one large base64 payload.
abstract final class RemoteCodingAttachmentPolicy {
  static const int maxBytes = 4 * 1024 * 1024;
  static const int chunkBytes = 96 * 1024;
  static const int maxNameCharacters = 120;
  static const int maxMimeTypeCharacters = 128;

  static int chunkCount(int byteLength) {
    if (byteLength <= 0) return 1;
    return (byteLength + chunkBytes - 1) ~/ chunkBytes;
  }

  static String? validate({
    required String name,
    required String mimeType,
    required int byteLength,
  }) {
    if (name.trim().isEmpty) return 'Attachment name is required.';
    if (name.length > maxNameCharacters) {
      return 'Attachment name is too long.';
    }
    if (mimeType.trim().isEmpty || mimeType.length > maxMimeTypeCharacters) {
      return 'Attachment MIME type is invalid.';
    }
    if (byteLength < 0 || byteLength > maxBytes) {
      return 'Attachment exceeds the 4 MiB Remote Coding limit.';
    }
    return null;
  }

  /// Keeps a path supplied by an untrusted peer from becoming a path-like
  /// display name or a name with platform separators.
  static String normalizedName(String name) {
    final basename = name.trim().replaceAll('\\', '/').split('/').last;
    final sanitized = basename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final bounded = sanitized.length > maxNameCharacters
        ? sanitized.substring(0, maxNameCharacters)
        : sanitized;
    return bounded.isEmpty ? 'attachment' : bounded;
  }

  static String normalizedMimeType(String mimeType) {
    final normalized = mimeType.split(';').first.trim().toLowerCase();
    return normalized.isEmpty ? 'application/octet-stream' : normalized;
  }
}
