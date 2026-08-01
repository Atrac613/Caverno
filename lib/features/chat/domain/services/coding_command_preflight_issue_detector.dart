class CodingCommandPreflightIssue {
  const CodingCommandPreflightIssue({
    required this.code,
    required this.command,
    required this.workingDirectory,
    required this.segment,
    required this.summary,
    required this.instruction,
    required this.targets,
  });

  final String code;
  final String command;
  final String workingDirectory;
  final String segment;
  final String summary;
  final String instruction;
  final List<String> targets;

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'command': command,
      'working_directory': workingDirectory,
      'segment': segment,
      'summary': summary,
      'instruction': instruction,
      'targets': targets,
    };
  }
}

/// Detects command-shape problems before or after command execution.
class CodingCommandPreflightIssueDetector {
  const CodingCommandPreflightIssueDetector();

  static const Set<String> _dartCreateOptionsWithValue = {
    '-t',
    '--template',
    '--type',
    '--sample',
    '--description',
    '--project-name',
  };

  static final RegExp _maskedExitStatusPattern = RegExp(
    r'^(?:'
    r'true|:'
    r'|exit\s+0'
    r'|echo\b[^|]*\$\?'
    r'|(?:test|\[)\s+\$\?\s*(?:-ne|!=)\s*0\s*\]?'
    r')$',
    caseSensitive: false,
  );

  CodingCommandPreflightIssue? detect({
    required String toolName,
    required String command,
    required String workingDirectory,
  }) {
    final normalizedToolName = toolName.trim().toLowerCase();
    if (normalizedToolName != 'local_execute_command' &&
        normalizedToolName != 'process_start') {
      return null;
    }
    final normalizedCommand = command.trim();
    if (normalizedCommand.isEmpty) {
      return null;
    }
    return _detectMalformedDartCreateCommand(
      command: normalizedCommand,
      workingDirectory: workingDirectory,
    );
  }

  /// Detects a chain whose exit status cannot report what the chain did.
  ///
  /// A shell chain reports the status of its last segment. A non-failing final
  /// segment can therefore hide an earlier failure. A single command followed
  /// by a negative assertion remains valid because that assertion is the check.
  CodingCommandPreflightIssue? detectMaskedExitStatusIssue({
    required String command,
    String workingDirectory = '',
  }) {
    final normalizedCommand = command.trim();
    if (normalizedCommand.isEmpty) return null;
    final segments = _splitShellSegments(normalizedCommand);
    if (segments.length < 3) return null;

    final last = segments.last.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!_maskedExitStatusPattern.hasMatch(last)) return null;

    return CodingCommandPreflightIssue(
      code: 'masked_exit_status',
      command: normalizedCommand,
      workingDirectory: workingDirectory,
      segment: segments.last,
      summary:
          'The command ends with "$last", so its exit status reports that '
          'segment instead of whether the earlier commands succeeded. This '
          'result is not evidence that the chain passed.',
      instruction:
          'Re-run the checks so a failure propagates: drop the trailing '
          '"$last", or assert an expected failure in its own command, such as '
          '"! <command that must fail>".',
      targets: const [],
    );
  }

  CodingCommandPreflightIssue? _detectMalformedDartCreateCommand({
    required String command,
    required String workingDirectory,
  }) {
    for (final segment in _splitShellSegments(command)) {
      final args = _splitArgs(segment);
      final createArgs = _dartCreateArgs(args);
      if (createArgs == null) {
        continue;
      }
      final targets = _dartCreateTargets(createArgs);
      final unsupportedOption = _unsupportedDartCreateOption(createArgs);
      if (unsupportedOption != null) {
        final value = unsupportedOption.value;
        final replacement = value == null || value.isEmpty
            ? '"--template <template>"'
            : '"--template $value"';
        final original = value == null || value.isEmpty
            ? '"${unsupportedOption.option}"'
            : '"${unsupportedOption.option} $value"';
        return CodingCommandPreflightIssue(
          code: 'dart_create_unsupported_option',
          command: command,
          workingDirectory: workingDirectory,
          segment: segment,
          summary:
              'Dart create does not support the "${unsupportedOption.option}" option.',
          instruction: 'Replace $original with $replacement.',
          targets: targets,
        );
      }
      if (targets.length <= 1) {
        continue;
      }
      return CodingCommandPreflightIssue(
        code: 'dart_create_multiple_targets',
        command: command,
        workingDirectory: workingDirectory,
        segment: segment,
        summary: 'Dart create command specifies multiple target directories.',
        instruction:
            'Run dart create with exactly one target directory. Use '
            '"dart create --force prime_numbers_pkg" from the parent '
            'directory, or create the directory first and run '
            '"dart create --force ." inside it.',
        targets: targets,
      );
    }
    return null;
  }

  List<String>? _dartCreateArgs(List<String> args) {
    if (args.length >= 2 && args[0] == 'dart' && args[1] == 'create') {
      return args.skip(2).toList(growable: false);
    }
    if (args.length >= 3 &&
        args[0] == 'fvm' &&
        args[1] == 'dart' &&
        args[2] == 'create') {
      return args.skip(3).toList(growable: false);
    }
    return null;
  }

  List<String> _dartCreateTargets(List<String> args) {
    final targets = <String>[];
    var consumeNextAsOptionValue = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (consumeNextAsOptionValue) {
        consumeNextAsOptionValue = false;
        continue;
      }
      if (arg == '--') {
        targets.addAll(
          args
              .skip(i + 1)
              .map((target) => target.trim())
              .where((target) => target.isNotEmpty),
        );
        break;
      }
      if (arg.startsWith('-')) {
        consumeNextAsOptionValue = _dartCreateOptionConsumesNext(arg);
        continue;
      }
      targets.add(arg);
    }
    return targets;
  }

  _UnsupportedDartCreateOption? _unsupportedDartCreateOption(
    List<String> args,
  ) {
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--') {
        return null;
      }
      if (arg == '--type') {
        final value = i + 1 < args.length ? args[i + 1] : null;
        return _UnsupportedDartCreateOption(option: arg, value: value);
      }
      if (arg.startsWith('--type=')) {
        return _UnsupportedDartCreateOption(
          option: '--type',
          value: arg.substring('--type='.length),
        );
      }
      if (_dartCreateOptionConsumesNext(arg)) {
        i += 1;
      }
    }
    return null;
  }

  bool _dartCreateOptionConsumesNext(String arg) {
    if (arg.contains('=')) {
      return false;
    }
    return _dartCreateOptionsWithValue.contains(arg);
  }

  List<String> _splitShellSegments(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        if (char == '\\' && i + 1 < command.length) {
          i += 1;
          buffer.write(command[i]);
          continue;
        }
        if (char == quoteChar) {
          quoteChar = null;
        } else {
          buffer.write(char);
        }
        continue;
      }

      if (char == '"' || char == "'") {
        quoteChar = char;
        continue;
      }

      if (char == '\\' && i + 1 < command.length) {
        i += 1;
        buffer.write(command[i]);
        continue;
      }

      if (char == ';' || char == '\n') {
        final segment = buffer.toString().trim();
        if (segment.isNotEmpty) {
          segments.add(segment);
        }
        buffer.clear();
        continue;
      }

      if ((char == '&' || char == '|') &&
          i + 1 < command.length &&
          command[i + 1] == char) {
        final segment = buffer.toString().trim();
        if (segment.isNotEmpty) {
          segments.add(segment);
        }
        buffer.clear();
        i += 1;
        continue;
      }

      buffer.write(char);
    }

    final trailing = buffer.toString().trim();
    if (trailing.isNotEmpty) {
      segments.add(trailing);
    }
    return segments;
  }

  List<String> _splitArgs(String command) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        if (char == '\\' && i + 1 < command.length) {
          i += 1;
          buffer.write(command[i]);
          continue;
        }
        if (char == quoteChar) {
          quoteChar = null;
        } else {
          buffer.write(char);
        }
        continue;
      }

      if (char == '"' || char == "'") {
        quoteChar = char;
        continue;
      }

      if (char == '\\' && i + 1 < command.length) {
        i += 1;
        buffer.write(command[i]);
        continue;
      }

      if (char == ' ' || char == '\t') {
        if (buffer.isNotEmpty) {
          args.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }
    return args;
  }
}

class _UnsupportedDartCreateOption {
  const _UnsupportedDartCreateOption({
    required this.option,
    required this.value,
  });

  final String option;
  final String? value;
}
