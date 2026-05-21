import '../entities/app_settings.dart';

class LocalCommandPermissionEvaluation {
  const LocalCommandPermissionEvaluation({required this.action, this.rule});

  final LocalCommandPermissionAction action;
  final LocalCommandPermissionRule? rule;

  bool get isAllowed => action == LocalCommandPermissionAction.allow;

  bool get isDenied => action == LocalCommandPermissionAction.deny;

  bool get requiresPrompt => action == LocalCommandPermissionAction.ask;
}

class LocalCommandRiskWarning {
  const LocalCommandRiskWarning({required this.title, required this.message});

  final String title;
  final String message;
}

class LocalCommandPermissionService {
  LocalCommandPermissionService._();

  static const Set<String> _broadAllowPrefixes = {
    'bash',
    'sh',
    'zsh',
    'fish',
    'python',
    'python3',
    'node',
    'ruby',
    'perl',
    'php',
    'dart',
    'flutter',
    'fvm',
    'npm',
    'npx',
    'yarn',
    'pnpm',
    'uv',
    'pip',
    'pip3',
    'curl',
    'wget',
    'ssh',
    'scp',
    'osascript',
    'open',
    'git',
    'rm',
    'sudo',
  };

  static String normalizePattern(String value) => value.trim();

  static LocalCommandPermissionEvaluation evaluate({
    required String command,
    required String workingDirectory,
    required Iterable<LocalCommandPermissionRule> rules,
  }) {
    final normalizedCommand = normalizePattern(command);
    if (normalizedCommand.isEmpty) {
      return const LocalCommandPermissionEvaluation(
        action: LocalCommandPermissionAction.ask,
      );
    }

    for (final rule in rules) {
      if (!rule.isUsable) continue;
      if (!_matchesWorkingDirectory(rule, workingDirectory)) continue;
      if (!_matches(rule, normalizedCommand)) continue;
      return LocalCommandPermissionEvaluation(action: rule.action, rule: rule);
    }

    return const LocalCommandPermissionEvaluation(
      action: LocalCommandPermissionAction.ask,
    );
  }

  static LocalCommandPermissionRule buildExactRule({
    required String id,
    required LocalCommandPermissionAction action,
    required String command,
    required String workingDirectory,
    DateTime? createdAt,
  }) {
    return LocalCommandPermissionRule(
      id: id,
      action: action,
      match: LocalCommandPermissionMatch.exact,
      pattern: normalizePattern(command),
      workingDirectory: normalizePattern(workingDirectory),
      createdAt: createdAt,
    );
  }

  static String? validateRule(LocalCommandPermissionRule rule) {
    final pattern = normalizePattern(rule.pattern);
    if (pattern.isEmpty) {
      return 'Command permission rules require a non-empty pattern.';
    }

    if (rule.action == LocalCommandPermissionAction.allow &&
        rule.match == LocalCommandPermissionMatch.prefix &&
        _isDangerousBroadAllowPrefix(pattern)) {
      return 'This allow rule is too broad. Use an exact command rule instead.';
    }

    return null;
  }

  static LocalCommandRiskWarning? riskWarningFor(String command) {
    for (final segment in _splitConditionalCommands(command)) {
      final args = _splitArgs(segment);
      if (args.isEmpty) continue;
      final executable = args.first.toLowerCase();
      final lowerSegment = segment.toLowerCase();

      if (executable == 'rm' && _looksLikeRecursiveForceRemoval(args)) {
        return const LocalCommandRiskWarning(
          title: 'Recursive file deletion',
          message:
              'This command can permanently remove files or directories. Review the target path before approving it.',
        );
      }

      if (executable == 'git' && args.length >= 2) {
        final subcommand = args[1].toLowerCase();
        if (subcommand == 'reset' && args.contains('--hard')) {
          return const LocalCommandRiskWarning(
            title: 'Hard git reset',
            message:
                'This command can discard uncommitted work in the repository.',
          );
        }
        if (subcommand == 'clean' && _hasAnyFlag(args, const ['-f', '-d'])) {
          return const LocalCommandRiskWarning(
            title: 'Git clean deletion',
            message:
                'This command can delete untracked files from the repository.',
          );
        }
        if (subcommand == 'push' &&
            (args.contains('--force') || args.contains('--force-with-lease'))) {
          return const LocalCommandRiskWarning(
            title: 'Forced git push',
            message:
                'This command can rewrite remote branch history for other collaborators.',
          );
        }
      }

      if (executable == 'terraform' && args.contains('destroy')) {
        return const LocalCommandRiskWarning(
          title: 'Infrastructure destruction',
          message: 'This command can destroy managed infrastructure resources.',
        );
      }

      if (executable == 'kubectl' && args.contains('delete')) {
        return const LocalCommandRiskWarning(
          title: 'Kubernetes delete',
          message:
              'This command can delete Kubernetes resources from the selected cluster.',
        );
      }

      if (executable == 'dropdb' ||
          lowerSegment.contains('drop database') ||
          lowerSegment.contains('drop schema')) {
        return const LocalCommandRiskWarning(
          title: 'Database destructive operation',
          message:
              'This command appears to drop database objects or data structures.',
        );
      }
    }

    return null;
  }

  static bool _matches(
    LocalCommandPermissionRule rule,
    String normalizedCommand,
  ) {
    final pattern = normalizePattern(rule.pattern);
    return switch (rule.match) {
      LocalCommandPermissionMatch.exact => normalizedCommand == pattern,
      LocalCommandPermissionMatch.prefix =>
        normalizedCommand == pattern ||
            normalizedCommand.startsWith('$pattern '),
    };
  }

  static bool _matchesWorkingDirectory(
    LocalCommandPermissionRule rule,
    String workingDirectory,
  ) {
    final ruleDirectory = normalizePattern(rule.workingDirectory);
    if (ruleDirectory.isEmpty) return true;
    return ruleDirectory == normalizePattern(workingDirectory);
  }

  static bool _isDangerousBroadAllowPrefix(String pattern) {
    final args = _splitArgs(pattern);
    if (args.isEmpty) return false;
    if (args.length > 1) return false;
    return _broadAllowPrefixes.contains(args.first.toLowerCase());
  }

  static bool _looksLikeRecursiveForceRemoval(List<String> args) {
    var hasRecursive = false;
    var hasForce = false;
    var hasDangerousTarget = false;

    for (final arg in args.skip(1)) {
      if (arg == '--') continue;
      if (arg.startsWith('-')) {
        if (arg == '--recursive') hasRecursive = true;
        if (arg == '--force') hasForce = true;
        if (!arg.startsWith('--')) {
          hasRecursive = hasRecursive || arg.contains('r') || arg.contains('R');
          hasForce = hasForce || arg.contains('f');
        }
        continue;
      }

      hasDangerousTarget =
          hasDangerousTarget ||
          arg == '/' ||
          arg == '~' ||
          arg == '.' ||
          arg == '..' ||
          arg == '*';
    }

    return (hasRecursive && hasForce) || hasDangerousTarget;
  }

  static bool _hasAnyFlag(List<String> args, List<String> flags) {
    for (final arg in args.skip(2)) {
      if (flags.contains(arg)) return true;
      if (!arg.startsWith('-') || arg.startsWith('--')) continue;
      for (final flag in flags) {
        final flagLetter = flag.replaceFirst('-', '');
        if (flagLetter.length == 1 && arg.contains(flagLetter)) return true;
      }
    }
    return false;
  }

  static List<String> _splitConditionalCommands(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        buffer.write(char);
        if (char == quoteChar) {
          quoteChar = null;
        }
        continue;
      }

      if (char == '"' || char == "'") {
        quoteChar = char;
        buffer.write(char);
        continue;
      }

      if (char == '&' && i + 1 < command.length && command[i + 1] == '&') {
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

  static List<String> _splitArgs(String command) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
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
