import 'environment_query_words_policy.dart';
import 'literal_shell_segments.dart';
import 'literal_shell_words.dart';

/// Recognizes literal environment queries without expansion or writable output.
abstract final class LiteralEnvironmentInspectionPolicy {
  static bool applies(String command, {bool allowPackageImports = true}) {
    final segments = LiteralShellSegments.parse(command, allowFallbacks: true);
    if (segments == null) return false;
    for (final segment in segments) {
      final query = segment.trim();
      final limiter = RegExp(r'\s*\|\s*(?:head|tail)\s+-(?:n\s*)?[1-9]\d*\s*$');
      final limited = limiter.hasMatch(query);
      final words = LiteralShellWords.parse(
        query
            .replaceFirst(limiter, '')
            .trim()
            .replaceFirst(RegExp(r'\s+(?:2>\s*/dev/null|2>&1)\s*$'), ''),
        allowPathGlobs: RegExp(r'^ls(?:\s|$)').hasMatch(query),
      );
      if (words == null) return false;
      if (!EnvironmentQueryWordsPolicy.applies(
        words,
        limited: limited,
        allowPackageImports: allowPackageImports,
      )) {
        return false;
      }
    }
    return true;
  }
}
