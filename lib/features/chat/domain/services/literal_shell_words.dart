import 'literal_shell_word_parser.dart';

/// Parses literal shell words with explicit expansion and newline limits.
abstract final class LiteralShellWords {
  static List<String>? parse(
    String source, {
    bool allowPathGlobs = false,
    bool allowQuotedNewlines = false,
  }) => LiteralShellWordParser.parse(
    source,
    allowPathGlobs: allowPathGlobs,
    allowQuotedNewlines: allowQuotedNewlines,
  );

  static String quote(String word) =>
      RegExp(r'^[a-zA-Z0-9_./:=+-]+$').hasMatch(word)
      ? word
      : "'${word.replaceAll("'", "'\\''")}'";
}
