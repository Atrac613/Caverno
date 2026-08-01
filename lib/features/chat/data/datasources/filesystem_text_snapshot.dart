import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'file_mutation_path_fence.dart';

class TextFileSnapshot {
  const TextFileSnapshot({
    required this.path,
    required this.exists,
    this.content,
    this.error,
    this.resolvedPathKey,
    this.isPathAlias = false,
  });

  final String path;
  final bool exists;
  final String? content;
  final String? error;
  final String? resolvedPathKey;
  final bool isPathAlias;
}

/// Captures and fingerprints text files for mutation preconditions.
abstract final class FilesystemTextSnapshot {
  static Future<TextFileSnapshot> capture(String path) async {
    final absolutePath = File(path).absolute.path;
    final entityType = FileSystemEntity.typeSync(path, followLinks: false);
    final resolvedPathKey = await FileMutationPathFence.resolvePathKey(
      absolutePath,
    );
    final isPathAlias = entityType == FileSystemEntityType.link;

    if (isPathAlias) {
      return TextFileSnapshot(
        path: absolutePath,
        exists: entityType != FileSystemEntityType.notFound,
        error:
            'Aliased or symbolic-link-backed rollback targets are not '
            'supported.',
        resolvedPathKey: resolvedPathKey,
        isPathAlias: true,
      );
    }

    if (entityType == FileSystemEntityType.notFound) {
      return TextFileSnapshot(
        path: absolutePath,
        exists: false,
        resolvedPathKey: resolvedPathKey,
      );
    }

    if (entityType != FileSystemEntityType.file) {
      return TextFileSnapshot(
        path: absolutePath,
        exists: true,
        error: 'Path is not a regular text file.',
        resolvedPathKey: resolvedPathKey,
      );
    }

    final file = File(path);
    try {
      final rawBytes = await file.readAsBytes();
      final content = utf8.decode(rawBytes, allowMalformed: false);
      return TextFileSnapshot(
        path: file.absolute.path,
        exists: true,
        content: content,
        resolvedPathKey: resolvedPathKey,
      );
    } on FormatException {
      return TextFileSnapshot(
        path: file.absolute.path,
        exists: true,
        error:
            'File is not valid UTF-8 text. Diff preview is unavailable for '
            'binary or non-text files.',
        resolvedPathKey: resolvedPathKey,
      );
    } on FileSystemException catch (error) {
      return TextFileSnapshot(
        path: file.absolute.path,
        exists: true,
        error: error.toString(),
        resolvedPathKey: resolvedPathKey,
      );
    }
  }

  static Future<String> fingerprint(String path) async {
    return fingerprintSnapshot(await capture(path));
  }

  static String fingerprintSnapshot(TextFileSnapshot snapshot) {
    final payload = jsonEncode({
      'exists': snapshot.exists,
      'content': snapshot.content,
      'error': snapshot.error,
      'resolved_path': snapshot.resolvedPathKey,
      'path_alias': snapshot.isPathAlias,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}
