import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persists user-attached files that are too large to inline into a chat
/// message.
///
/// Large files (e.g. 100MB+ logs) cannot be embedded as text in a [Message]
/// (which is JSON-serialized into Hive), so instead the file is copied into a
/// durable directory under the app support folder and the model references it
/// by a stable path via the read-only file tools.
///
/// The copy step is essential on mobile: the file picker's own path points into
/// a volatile cache that the OS may clear, whereas the app support directory
/// persists for the lifetime of the install.
class AttachmentStorageService {
  AttachmentStorageService._();

  static const String _dirName = 'attachments';
  static const Duration _retention = Duration(days: 7);

  /// Copies [sourcePath] into the durable attachments directory and returns the
  /// absolute destination path. The destination name is sanitized and prefixed
  /// with a timestamp to avoid collisions.
  static Future<String> persist({
    required String sourcePath,
    required String originalName,
  }) async {
    final dir = await _attachmentsDir();
    final safe = _safeName(originalName);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${dir.path}${Platform.pathSeparator}${stamp}_$safe';
    final dest = await File(sourcePath).copy(destPath);
    return dest.absolute.path;
  }

  /// Writes [bytes] into the durable attachments directory and returns the
  /// absolute destination path.
  static Future<String> persistBytes({
    required Uint8List bytes,
    required String originalName,
  }) async {
    final dir = await _attachmentsDir();
    final safe = _safeName(originalName);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${dir.path}${Platform.pathSeparator}${stamp}_$safe';
    final dest = File(destPath);
    await dest.writeAsBytes(bytes, flush: true);
    return dest.absolute.path;
  }

  /// Deletes attachment copies older than the retention window. Safe to call on
  /// app start; any failures (including a missing directory) are swallowed.
  static Future<void> sweepOldAttachments() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}$_dirName');
      if (!dir.existsSync()) return;
      final now = DateTime.now();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final age = now.difference((await entity.stat()).modified);
          if (age > _retention) await entity.delete();
        } catch (_) {
          // Ignore individual file errors and keep sweeping.
        }
      }
    } catch (_) {
      // Nothing to sweep, or storage unavailable.
    }
  }

  static Future<Directory> _attachmentsDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_dirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _safeName(String name) {
    final trimmed = name.trim();
    final base = trimmed.isEmpty ? 'attachment' : trimmed;
    final sanitized = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    // Keep the tail (extension is more useful than a long prefix).
    return sanitized.length > 80
        ? sanitized.substring(sanitized.length - 80)
        : sanitized;
  }
}
