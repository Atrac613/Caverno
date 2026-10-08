import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

/// Reads pytest's terminal runner summary, independently of assistant prose.
abstract final class PytestTestOutcomeParser {
  static ToolTestOutcome? parse(String output, String command) {
    final summary = RegExp(
      r'^=*\s*(\d+ (?:passed|failed|skipped|xfailed|xpassed|deselected|warnings?|errors?)'
      r'(?:, \d+ (?:passed|failed|skipped|xfailed|xpassed|deselected|warnings?|errors?))*)'
      r'(?: in [0-9.]+s)?\s*=*$',
    ).firstMatch(output.trim().split(RegExp(r'\r?\n')).last.trim());
    if (summary == null) return null;
    final counts = <String, int>{
      for (final match in RegExp(r'(\d+) (\w+)').allMatches(summary[1]!))
        match[2]!: int.parse(match[1]!),
    };
    return ToolTestOutcome(
      passedCount: counts['passed'] ?? 0,
      failedCount:
          (counts['failed'] ?? 0) + (counts['error'] ?? counts['errors'] ?? 0),
      skippedCount: (counts['skipped'] ?? 0) + (counts['xfailed'] ?? 0),
      command: command,
    );
  }
}
