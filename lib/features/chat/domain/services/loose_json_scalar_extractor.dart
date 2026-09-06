import 'dart:convert';

final class LooseJsonScalarExtractor {
  const LooseJsonScalarExtractor._();

  static String? extract(String rawContent, {required List<String> keys}) {
    for (final key in keys) {
      final pattern = RegExp(
        """["']?${RegExp.escape(key)}["']?\\s*:\\s*(?:"((?:\\\\.|[^"\\\\])*)"|'((?:\\\\.|[^'\\\\])*)'|([A-Za-z_]+))""",
        caseSensitive: false,
        dotAll: true,
      );
      final match = pattern.firstMatch(rawContent);
      if (match == null) {
        continue;
      }

      final escapedJsonValue = match.group(1);
      String value;
      if (escapedJsonValue != null) {
        try {
          final decoded = jsonDecode('"$escapedJsonValue"');
          value = decoded is String ? decoded : '';
        } on FormatException {
          continue;
        }
      } else {
        value = match.group(2) ?? match.group(3) ?? '';
      }
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }
}
