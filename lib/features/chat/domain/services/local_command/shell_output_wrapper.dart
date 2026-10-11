/// Removes an output-only tail and stderr merge from a literal invocation.
abstract final class ShellOutputWrapper {
  static String strip(String command) => command
      .trim()
      .replaceFirst(
        RegExp(r'\s*(?:2>&1\s*)?\|\s*tail\s+-(?:n\s*)?[1-9]\d*\s*$'),
        '',
      )
      .replaceFirst(RegExp(r'\s+2>&1\s*$'), '')
      .trim();

  /// Removes a final `| grep ...` stage, which only filters what the model
  /// reads. Under pipefail grep exits 1 when nothing matched, and a passing
  /// test run prints no failure lines, so the filtered command could never
  /// pass and no unfiltered run of the same tests could settle it. Session
  /// 1fd1d58b: `pytest <test> 2>&1 | grep -A 30 "FAILED\|assert"` stayed
  /// failed while the test passed three times, until the repair turn ended.
  ///
  /// Unlike [strip] it changes the exit status, so only an identity that
  /// still requires a clean exit and parsed passing counts may use it.
  static String withoutGrepFilter(String command) {
    String? quote;
    var lastPipe = -1;
    var operatorAfterPipe = false;
    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (quote != null) {
        if (c == '\\' && quote == '"') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '\\') {
        i++;
      } else if (c == '|') {
        final orOperator =
            (i + 1 < command.length && command[i + 1] == '|') ||
            (i > 0 && command[i - 1] == '|');
        lastPipe = orOperator ? -1 : i;
        operatorAfterPipe = orOperator;
      } else if (';&<>`\$\n'.contains(c)) {
        operatorAfterPipe = true;
      }
    }
    if (quote != null || lastPipe < 0 || operatorAfterPipe) return command;
    final stage = command.substring(lastPipe + 1).trimLeft();
    if (!RegExp(r'^grep(?:\s|$)').hasMatch(stage)) return command;
    return command.substring(0, lastPipe).trimRight();
  }
}
