import 'dart:convert';
import 'dart:io';

/// Performs a bounded prefix check for binary or malformed UTF-8 content.
abstract final class BoundedTextFileClassifier {
  static const int defaultSniffBytes = 8192;

  /// Returns `true` for a NUL byte or malformed UTF-8 in the bounded prefix.
  ///
  /// A trailing partial UTF-8 rune is tolerated. I/O failures return `false`
  /// so the caller's subsequent read can surface the original filesystem
  /// error, preserving the existing filesystem-tool behavior.
  static Future<bool> looksBinary(
    File file, {
    int sniffBytes = defaultSniffBytes,
  }) async {
    if (sniffBytes <= 0) {
      throw ArgumentError.value(sniffBytes, 'sniffBytes', 'Must be positive.');
    }
    try {
      final prefix = <int>[];
      await for (final chunk in file.openRead(0, sniffBytes)) {
        prefix.addAll(chunk);
        if (prefix.length >= sniffBytes) break;
      }
      if (prefix.isEmpty) return false;
      final sample = prefix.length > sniffBytes
          ? prefix.sublist(0, sniffBytes)
          : prefix;
      if (sample.contains(0)) return true;
      for (var drop = 0; drop <= 3 && sample.length - drop > 0; drop++) {
        try {
          utf8.decode(
            sample.sublist(0, sample.length - drop),
            allowMalformed: false,
          );
          return false;
        } on FormatException {
          // A rune may cross the prefix boundary; retry without its tail.
        }
      }
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
