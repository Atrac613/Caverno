import 'dart:convert';
import 'dart:io';

/// A file's leading bytes and what they say about its encoding.
///
/// Carries the sample alongside the verdict so a caller that needs to ask a
/// second question of the same bytes — is this a PDF? — does not pay for a
/// second read of the same prefix.
class BoundedFilePrefix {
  const BoundedFilePrefix({required this.bytes, required this.looksBinary});

  /// The sampled prefix, empty when the file could not be read.
  final List<int> bytes;

  final bool looksBinary;
}

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
  }) async => (await sniff(file, sniffBytes: sniffBytes)).looksBinary;

  /// Reads the bounded prefix of [file] and classifies it.
  static Future<BoundedFilePrefix> sniff(
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
      if (prefix.isEmpty) {
        return const BoundedFilePrefix(bytes: <int>[], looksBinary: false);
      }
      final sample = prefix.length > sniffBytes
          ? prefix.sublist(0, sniffBytes)
          : prefix;
      return BoundedFilePrefix(
        bytes: sample,
        looksBinary: _sampleLooksBinary(sample),
      );
    } on FileSystemException {
      return const BoundedFilePrefix(bytes: <int>[], looksBinary: false);
    }
  }

  static bool _sampleLooksBinary(List<int> sample) {
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
  }
}
