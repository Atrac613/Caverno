import 'package:path/path.dart' as path;

import '../literal_shell_words.dart';
import '../shell_output_wrapper.dart';

/// Resolves a literal directory change, stderr merge, and output-only tail.
abstract final class PytestShellInvocation {
  static String withoutOutputWrapper(String command) =>
      ShellOutputWrapper.strip(command);

  static ({String directory, List<String> words})? parse(
    String command,
    String directory,
  ) {
    if (!path.isAbsolute(directory)) return null;
    var invocation = withoutOutputWrapper(command);
    final cd = RegExp(r'^cd\s+(.+?)\s*&&\s*(.+)$').firstMatch(invocation);
    if (cd != null) {
      final target = LiteralShellWords.parse(cd[1]!)?.singleOrNull;
      if (target == null || target.isEmpty || target.startsWith('-')) {
        return null;
      }
      directory = path.normalize(path.join(directory, target));
      invocation = cd[2]!;
    }
    final words = LiteralShellWords.parse(invocation);
    return words == null ? null : (directory: directory, words: words);
  }
}
