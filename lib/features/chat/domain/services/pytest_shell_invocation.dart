import 'package:path/path.dart' as path;

import 'literal_shell_words.dart';

/// Resolves a literal directory change, stderr merge, and output-only tail.
abstract final class PytestShellInvocation {
  static String withoutOutputWrapper(String command) => command
      .trim()
      .replaceFirst(
        RegExp(r'\s*(?:2>&1\s*)?\|\s*tail\s+-(?:n\s*)?[1-9]\d*\s*$'),
        '',
      )
      .replaceFirst(RegExp(r'\s+2>&1\s*$'), '')
      .trim();

  static ({String directory, List<String> words})? parse(
    String command,
    String directory,
  ) {
    if (!path.isAbsolute(directory)) return null;
    var invocation = withoutOutputWrapper(command);
    final cd = RegExp(r'^cd\s+(.+?)\s*&&\s*(.+)$').firstMatch(invocation);
    if (cd != null) {
      final target = LiteralShellWords.parse(cd[1]!);
      if (target == null ||
          target.length != 1 ||
          target.single.isEmpty ||
          target.single.startsWith('-')) {
        return null;
      }
      directory = path.normalize(path.join(directory, target.single));
      invocation = cd[2]!;
    }
    final words = LiteralShellWords.parse(invocation);
    return words == null ? null : (directory: directory, words: words);
  }
}
