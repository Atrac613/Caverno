import 'dart:convert';

import 'package:path/path.dart' as path;

import '../literal_shell_words.dart';

/// Keeps an inline verifier's checks fixed while its fixture can be repaired.
/// Unsupported shell or Python forms retain the full command's exact scope.
final class InlinePythonVerificationContract {
  InlinePythonVerificationContract._(
    this.directory,
    this.interpreter,
    Set<String> modules,
    this.checks,
  ) : modules = Set.unmodifiable(modules);

  final String directory;
  final String interpreter;
  final Set<String> modules;
  final String checks;

  String get key => jsonEncode([
    'inline-python-assertions',
    directory,
    interpreter,
    modules.toList()..sort(),
    checks,
  ]);

  bool covers(InlinePythonVerificationContract earlier) =>
      directory == earlier.directory &&
      interpreter == earlier.interpreter &&
      checks == earlier.checks &&
      modules.containsAll(earlier.modules);

  static InlinePythonVerificationContract? parse(
    String command,
    String directory,
  ) {
    if (!path.isAbsolute(directory)) return null;
    var invocation = command.trim().replaceFirst(RegExp(r'\s+2>&1$'), '');
    final cd = RegExp(
      r'^cd\s+(.+?)\s*&&\s*(.+)$',
      dotAll: true,
    ).firstMatch(invocation);
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
    final words = LiteralShellWords.parse(
      invocation,
      allowQuotedNewlines: true,
    );
    if (words == null ||
        words.length != 3 ||
        !RegExp(
          r'^python(?:\d+(?:\.\d+)*)?$',
        ).hasMatch(path.basename(words.first)) ||
        words[1] != '-c') {
      return null;
    }
    final script = words[2];
    // A line in a multiline string or a continued statement is not an assert.
    if (script.contains("'''") ||
        script.contains('"""') ||
        script.contains('\\\n')) {
      return null;
    }
    final assertion = RegExp(
      r'^assert\s+\S',
      multiLine: true,
    ).firstMatch(script);
    if (assertion == null) return null;
    final fixture = script.substring(0, assertion.start);
    if (RegExp(
      r'\bassert\b|\b(?:exec\w*|eval|__import__|exit|quit|_exit)\s*\('
      r'|\braise\s+SystemExit\b',
    ).hasMatch(fixture)) {
      return null;
    }
    final modules = <String>{};
    for (final line in const LineSplitter().convert(fixture)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('from ')) {
        final imported = RegExp(
          r'^from ([A-Za-z_]\w*(?:\.\w+)*) import [\w*, ]+$',
        ).firstMatch(trimmed);
        if (imported == null) return null;
        modules.add(imported[1]!);
      } else if (trimmed.startsWith('import ')) {
        for (final imported in trimmed.substring(7).split(',')) {
          final module = RegExp(
            r'^\s*([A-Za-z_]\w*(?:\.\w+)*)(?: as \w+)?\s*$',
          ).firstMatch(imported);
          if (module == null) return null;
          modules.add(module[1]!);
        }
      }
    }
    if (modules.isEmpty) return null;
    return InlinePythonVerificationContract._(
      path.normalize(directory),
      words.first,
      modules,
      // Preserve every check and everything after it, including whitespace
      // inside literals. Dropping or weakening a check changes the contract.
      script.substring(assertion.start),
    );
  }
}
