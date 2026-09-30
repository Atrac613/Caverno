import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:path/path.dart' as path;

import 'literal_shell_words.dart';
import 'pytest_shell_invocation.dart';
import 'pytest_test_outcome_parser.dart';

/// A deliberately small command grammar; unsupported shell syntax stays unknown.
final class PytestVerificationIdentity {
  PytestVerificationIdentity._(
    this.key,
    this.command,
    this.directory,
    this.words,
  );

  final String key;
  final String command;
  final String directory;
  final List<String> words;

  String get replayCommand => words.map(LiteralShellWords.quote).join(' ');

  static PytestVerificationIdentity? parse(String command, String directory) {
    final invocation = PytestShellInvocation.parse(command, directory);
    if (invocation == null) return null;
    directory = invocation.directory;
    final words = invocation.words;
    final executable = path.basename(words.first);
    final arguments = switch (executable) {
      'pytest' => words.skip(1).toList(),
      _
          when RegExp(r'^python(?:\d+(?:\.\d+)*)?$').hasMatch(executable) &&
              words.length >= 3 &&
              words[1] == '-m' &&
              words[2] == 'pytest' =>
        words.skip(3).toList(),
      _ => null,
    };
    if (arguments == null) return null;
    return PytestVerificationIdentity._(
      jsonEncode([path.normalize(directory), 'pytest', arguments]),
      command,
      directory,
      words,
    );
  }

  /// Recognized runner counts, never inferred from assistant text or exit alone.
  ToolTestOutcome? counts(String output) {
    return PytestTestOutcomeParser.parse(output, command);
  }
}
