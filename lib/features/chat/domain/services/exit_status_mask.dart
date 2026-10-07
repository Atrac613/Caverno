/// Whether a command's exit status can hide a failure of the program it runs.
///
/// Exit 0 is the program's own verdict only when every top-level command is
/// joined by `&&`: an uncaught exception would then have made it non-zero. A
/// pipe without pipefail reports its last stage, and `;`, `||` or a newline
/// report whichever segment ran last, as `cmd; test $? -ne 0` and
/// `cmd || true` do.
///
/// Only a masked status lets a traceback or runtime-failure line judge the
/// run. Of the 16 such verdicts in the session corpus on 2026-10-01, all 11
/// correct ones were `... 2>&1 | tail` hiding a real failure, and all 5 on an
/// `&&`-only command were wrong: a script testing exc_info logging printed a
/// traceback on purpose and exited 0 (session 22d603f7).
final class ExitStatusMask {
  const ExitStatusMask();

  bool mayHide(String command) {
    String? quote;
    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == ';' || c == '\n') {
        return true;
      } else if (c == '|') {
        final orOperator =
            (i + 1 < command.length && command[i + 1] == '|') ||
            (i > 0 && command[i - 1] == '|');
        if (orOperator || !command.contains('pipefail')) return true;
      }
    }
    return false;
  }
}
