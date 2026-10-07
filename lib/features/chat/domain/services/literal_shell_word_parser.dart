/// Scans literal tokens without evaluating shell syntax.
abstract final class LiteralShellWordParser {
  static List<String>? parse(
    String source, {
    required bool allowPathGlobs,
    required bool allowQuotedNewlines,
  }) {
    if (source.contains('\r') ||
        (!allowQuotedNewlines && source.contains('\n'))) {
      return null;
    }
    final words = <String>[];
    var index = 0;
    while (index < source.length) {
      if (' \t'.contains(source[index])) {
        index++;
        continue;
      }
      final buffer = StringBuffer();
      while (index < source.length && !' \t'.contains(source[index])) {
        final char = source[index++];
        if (char == "'" || char == '"') {
          final end = source.indexOf(char, index);
          if (end < 0) return null;
          final literal = source.substring(index, end);
          if (char == '"' && RegExp(r'[\$`\\]').hasMatch(literal)) {
            return null;
          }
          buffer.write(literal);
          index = end + 1;
        } else {
          if (char == '\n') return null;
          if (RegExp(r'[;&|<>`()\$\\*?~#\[\]{}]').hasMatch(char) &&
              !(allowPathGlobs && '*?'.contains(char))) {
            return null;
          }
          buffer.write(char);
        }
      }
      words.add(buffer.toString());
    }
    return words.isEmpty ? null : words;
  }
}
