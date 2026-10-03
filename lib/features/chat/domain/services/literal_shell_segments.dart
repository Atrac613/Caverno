/// Splits literal command lists while keeping quoted program arguments intact.
abstract final class LiteralShellSegments {
  static List<String>? parse(String source) {
    final segments = <String>[];
    String? quote;
    var start = 0;
    for (var index = 0; index < source.length; index++) {
      final char = source[index];
      if (quote != null) {
        if (char == quote) quote = null;
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
      } else if (char == ';' ||
          char == '&' &&
              index + 1 < source.length &&
              source[index + 1] == '&') {
        final segment = source.substring(start, index).trim();
        if (segment.isEmpty) return null;
        segments.add(segment);
        if (char == '&') index++;
        start = index + 1;
      }
    }
    final last = source.substring(start).trim();
    if (quote != null || last.isEmpty) return null;
    return [...segments, last];
  }
}
