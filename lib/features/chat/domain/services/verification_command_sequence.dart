import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:path/path.dart' as path;

import 'literal_shell_words.dart';
import 'pytest_shell_invocation.dart';
import 'pytest_verification_identity.dart';

/// Verification after the last mutation in a literal, success-linked sequence.
/// This describes evidence only; approval still classifies the entire command.
final class VerificationCommandSequence {
  const VerificationCommandSequence._(this.command, this.directory, this.steps);

  final String command;
  final String directory;
  final List<String> steps;
  String get terminalCommand => steps.last;

  String get key =>
      jsonEncode([directory, for (final step in steps) _stepKey(step)]);

  String _stepKey(String step) {
    final pytest = PytestVerificationIdentity.parse(step, directory);
    if (pytest != null) return pytest.key;
    final words = LiteralShellWords.parse(step);
    if (words != null &&
        words.length >= 2 &&
        RegExp(
          r'^python(?:\d+(?:\.\d+)*)?$',
        ).hasMatch(path.basename(words.first)) &&
        !words[1].startsWith('-') &&
        words[1].endsWith('.py')) {
      // A working interpreter can replace the failed runtime, but the script
      // path, argument order, and every prerequisite must still match.
      return jsonEncode(['python-script', words.skip(1).toList()]);
    }
    return step;
  }

  PytestVerificationIdentity? get terminalPytest =>
      PytestVerificationIdentity.parse(terminalCommand, directory);

  static VerificationCommandSequence? parse(String command, String directory) {
    final unwrapped = PytestShellInvocation.withoutOutputWrapper(command);
    final segments = _segments(unwrapped);
    if (segments == null || segments.length < 2) return null;
    final suffix = <String>[];
    var hasVerification = false;
    const classifier = ToolCapabilityClassifier();
    for (var index = 0; index < segments.length; index++) {
      final words = LiteralShellWords.parse(segments[index]);
      if (words == null) return null;
      if (words.first == 'cd') {
        if (index != 0 ||
            words.length != 2 ||
            words[1].isEmpty ||
            words[1].startsWith('-') ||
            !path.isAbsolute(directory)) {
          return null;
        }
        directory = path.normalize(path.join(directory, words[1]));
        continue;
      }
      // A literal separator only formats output; a trailing echo is outside
      // this grammar so the final step still supplies verification evidence.
      if (words.first == 'echo') {
        if (index == segments.length - 1) return null;
        continue;
      }
      final literal = words.map(LiteralShellWords.quote).join(' ');
      final effect = classifier
          .classify('local_execute_command', arguments: {'command': literal})
          .commandEffect;
      if (effect == ToolCommandEffect.verification ||
          effect == ToolCommandEffect.inspection) {
        suffix.add(literal);
        hasVerification |= effect == ToolCommandEffect.verification;
      } else {
        suffix.clear();
        hasVerification = false;
      }
    }
    if (!hasVerification) return null;
    final sequence = VerificationCommandSequence._(
      suffix.join(' && '),
      directory,
      List.unmodifiable(suffix),
    );
    if (unwrapped != command.trim() && sequence.terminalPytest == null) {
      return null;
    }
    return sequence;
  }

  static List<String>? _segments(String command) {
    final segments = <String>[];
    var start = 0;
    String? quote;
    for (var index = 0; index < command.length; index++) {
      final char = command[index];
      if (quote != null) {
        if (char == quote) quote = null;
        continue;
      }
      if (char == "'" || char == '"') {
        quote = char;
      } else if (char == '&') {
        if (index + 1 >= command.length || command[index + 1] != '&') {
          return null;
        }
        final segment = command.substring(start, index).trim();
        if (segment.isEmpty) return null;
        segments.add(segment);
        start = ++index + 1;
      }
    }
    final last = command.substring(start).trim();
    if (quote != null || last.isEmpty) return null;
    segments.add(last);
    return segments;
  }
}
