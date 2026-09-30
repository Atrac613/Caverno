/// Parses literal shell words without expansion, comments, globbing or escapes.
abstract final class LiteralShellWords {
  static List<String>? parse(String source) {
    if (source.contains('\n') || source.contains('\r')) return null;
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
          if (RegExp(r'[;&|<>`()\$\\*?~#\[\]{}]').hasMatch(char)) {
            return null;
          }
          buffer.write(char);
        }
      }
      words.add(buffer.toString());
    }
    return words.isEmpty ? null : words;
  }

  static String quote(String word) =>
      RegExp(r'^[a-zA-Z0-9_./:=+-]+$').hasMatch(word)
      ? word
      : "'${word.replaceAll("'", "'\\''")}'";
}
