import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:path/path.dart' as path;

import 'inline_python_verification_contract.dart';
import 'literal_environment_inspection_policy.dart';
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

  String _stepKey(String step, {bool repairRuntime = false}) {
    final pytest = PytestVerificationIdentity.parse(step, directory);
    if (pytest != null) return pytest.verificationKey;
    final words = LiteralShellWords.parse(step, allowQuotedNewlines: true);
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
    if (repairRuntime &&
        words != null &&
        InlinePythonVerificationContract.parse(step, directory) != null) {
      // Keep the complete program, including imports and fixture setup.
      return jsonEncode(['python-inline', words.skip(1).toList()]);
    }
    return step;
  }

  /// Only a pytest launch failure can use this alternate runtime identity.
  String? get runtimeRepairKey {
    if (leadingPytest == null ||
        path.basename(leadingPytest!.words.first) == 'pytest' ||
        !steps
            .skip(1)
            .every(
              (step) =>
                  InlinePythonVerificationContract.parse(step, directory) !=
                  null,
            )) {
      return null;
    }
    return jsonEncode([
      directory,
      for (final step in steps) _stepKey(step, repairRuntime: true),
    ]);
  }

  PytestVerificationIdentity? get leadingPytest =>
      PytestVerificationIdentity.parse(steps.first, directory);

  String repairRuntimeWith(String interpreter) => steps
      .map(
        (step) => step.replaceFirst(
          RegExp(r'''^(?:'[^']+'|"[^"]+"|\S+)'''),
          LiteralShellWords.quote(interpreter),
        ),
      )
      .join(' && ');

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
      // Every Caverno shell runs with pipefail (8730d1ed9), so trimming an
      // earlier step's output cannot hide its failure from `&&`. Session
      // d27e7528's `ensurepip 2>&1 | tail -2 && pip install pytest 2>&1 |
      // tail -3 && pytest -q` passed 61 tests, but the limiters kept it from
      // parsing, so it settled none of the earlier failed pytest runs.
      final words = LiteralShellWords.parse(
        index < segments.length - 1
            ? segments[index].replaceFirst(_outputLimiter, '')
            : segments[index],
        allowQuotedNewlines: true,
      );
      // An environment query such as `ls -d .venv` or `which pytest` only
      // decides whether the run can start; it asserts nothing about the
      // project, so it is not part of the verification's identity. In session
      // 016d4d5e `ls -d .venv 2>/dev/null && .venv/bin/python -m pytest -q`
      // failed on a missing venv, and no later pytest pass could settle it.
      if (words?.first != 'cd' &&
          index < segments.length - 1 &&
          LiteralEnvironmentInspectionPolicy.applies(segments[index])) {
        continue;
      }
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
        suffix.add(segments[index]);
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

  static final _outputLimiter = RegExp(
    r'(?:\s+2>&1)?(?:\s*\|\s*(?:head|tail)\s+-(?:n\s*)?[1-9]\d*)?\s*$',
  );

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
      } else if (char == '&' && index > 0 && command[index - 1] == '>') {
        // `2>&1` duplicates a descriptor; it is not a list operator.
        continue;
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
