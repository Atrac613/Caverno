import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
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

  /// Starts a durable attachment write without buffering the whole payload in
  /// memory. The returned session writes a hidden staging file and atomically
  /// renames it to its final attachment name on [AttachmentStorageWriteSession
  /// .complete].
  static Future<AttachmentStorageWriteSession> beginWrite({
    required String originalName,
    Directory? directoryOverride,
  }) async {
    final dir = directoryOverride ?? await _attachmentsDir();
    if (!dir.existsSync()) await dir.create(recursive: true);
    final safe = _safeName(originalName);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final prefix = '${dir.path}${Platform.pathSeparator}${stamp}_$safe';
    final stagingPath =
        '${dir.path}${Platform.pathSeparator}.${stamp}_$safe.part';
    final finalPath = prefix;
    final sink = File(stagingPath).openWrite(mode: FileMode.writeOnly);
    return AttachmentStorageWriteSession._(
      stagingPath: stagingPath,
      finalPath: finalPath,
      sink: sink,
    );
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

  /// Deletes persisted attachment files referenced by a deleted conversation.
  ///
  /// Paths outside the managed attachment directory, including nested paths,
  /// are ignored. Individual failures are isolated so conversation deletion
  /// cannot fail after its persisted record has already been removed.
  static Future<void> deleteOwnedAttachments(
    Iterable<String> paths, {
    Directory? directoryOverride,
  }) async {
    try {
      final directory = directoryOverride ?? await _attachmentsDir();
      final managedDirectoryPath = p.normalize(p.absolute(directory.path));
      for (final rawPath in paths.toSet()) {
        final trimmedPath = rawPath.trim();
        if (trimmedPath.isEmpty) continue;
        final candidatePath = p.normalize(p.absolute(trimmedPath));
        if (!p.equals(p.dirname(candidatePath), managedDirectoryPath)) {
          continue;
        }
        try {
          final type = await FileSystemEntity.type(
            candidatePath,
            followLinks: false,
          );
          if (type == FileSystemEntityType.file) {
            await File(candidatePath).delete();
          }
        } catch (_) {
          // Keep deleting the remaining conversation attachments.
        }
      }
    } catch (_) {
      // Storage may be unavailable during shutdown or platform teardown.
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

/// A sequential write session for one managed attachment.
class AttachmentStorageWriteSession {
  AttachmentStorageWriteSession._({
    required this.stagingPath,
    required this.finalPath,
    required IOSink sink,
  }) : _sink = sink;

  final String stagingPath;
  final String finalPath;
  final IOSink _sink;
  bool _closed = false;
  String? _completedPath;

  /// Appends one chunk and waits until the sink has accepted it.
  Future<void> write(List<int> bytes) async {
    if (_closed) throw StateError('The attachment write session is closed.');
    _sink.add(bytes);
    await _sink.flush();
  }

  /// Closes the staging file and promotes it to the final attachment path.
  Future<String> complete() async {
    final completedPath = _completedPath;
    if (completedPath != null) return completedPath;
    await _closeSink();
    await File(stagingPath).rename(finalPath);
    _completedPath = finalPath;
    return finalPath;
  }

  /// Closes and removes an incomplete staging file.
  Future<void> discard() async {
    if (_completedPath != null) return;
    await _closeSink();
    try {
      await File(stagingPath).delete();
    } catch (_) {
      // Cleanup is best effort during disconnect or platform teardown.
    }
  }

  Future<void> _closeSink() async {
    if (_closed) return;
    _closed = true;
    await _sink.close();
  }
}
