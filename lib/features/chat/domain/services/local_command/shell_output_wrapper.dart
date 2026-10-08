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
}
