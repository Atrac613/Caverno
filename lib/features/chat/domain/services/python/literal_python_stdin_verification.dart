import 'package:path/path.dart' as path;

import '../local_command/environment_query_words_policy.dart';
import '../local_command/literal_shell_words.dart';
import 'pytest_verification_identity.dart';

/// Recognizes an executed literal Python stdin script for completion evidence.
/// This does not change command capabilities, containment, or approval policy.
abstract final class LiteralPythonStdinVerification {
  static bool applies(String command) {
    if (command.contains('\r')) return false;
    final lines = command
        .trimLeft()
        .replaceFirst(RegExp(r'\n+$'), '')
        .split('\n');
    if (lines.length < 3) return false;
    final header = RegExp(
      r'''^(.+?)[ \t]+<<[ \t]*(['"])([A-Za-z_]\w*)\2[ \t]*(?:2>&1[ \t]*)?$''',
    ).firstMatch(lines.first);
    if (header == null || lines.last != header[3]) return false;
    final body = lines.sublist(1, lines.length - 1);
    // An earlier terminator would expose the remaining body as shell commands.
    if (body.contains(header[3]) || body.every((line) => line.trim().isEmpty)) {
      return false;
    }
    var invocation = header[1]!;
    final cd = RegExp(
      r'^cd[ \t]+(.+?)[ \t]*&&[ \t]*(.+)$',
    ).firstMatch(invocation);
    if (cd != null) {
      final target = LiteralShellWords.parse(cd[1]!);
      if (target == null ||
          target.length != 1 ||
          target.single.isEmpty ||
          target.single.startsWith('-')) {
        return false;
      }
      invocation = cd[2]!;
    }
    // `pytest -q && python3 - <<'EOF'` runs the script only after the tests
    // pass. Read as a mutation, a failing assertion in it blocked nothing
    // (session 64bbc516 rec 52).
    final steps = invocation.split('&&').map((step) => step.trim()).toList();
    if (steps
        .take(steps.length - 1)
        .any((step) => PytestVerificationIdentity.parse(step, '/') == null)) {
      return false;
    }
    invocation = steps.last;
    final words = LiteralShellWords.parse(invocation);
    if (words == null ||
        words.length != 2 ||
        !RegExp(
          r'^python(?:\d+(?:\.\d+)*)?$',
        ).hasMatch(path.basename(words.first)) ||
        words[1] != '-') {
      return false;
    }
    final query = body
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('; ');
    return !EnvironmentQueryWordsPolicy.applies(
      [words.first, '-c', query],
      limited: false,
      allowPackageImports: true,
    );
  }
}
