import 'dart:convert';

import '../../domain/services/dart_project_tooling.dart';
import 'project_mutation_path_fence.dart';

/// Blocks git repository relocation and out-of-root pathspecs.
///
/// SEC4.4d already fences the working directory. These escapes still move the
/// repository or name files outside that cwd: `-C`, `--git-dir`,
/// `--work-tree`, relocation environment variables, and pathspecs that are
/// absolute, home-relative, or contain `..`.
abstract final class GitCommandPathEscapeGuard {
  static const String relocationCode = 'git_repository_relocation_blocked';
  static const String relocationMessage =
      'git_execute_command does not accept -C, --git-dir, or --work-tree; '
      'run the command in the authorized working directory.';

  static const Set<String> _relocationEnvironmentKeys = {
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_COMMON_DIR',
    'GIT_OBJECT_DIRECTORY',
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_INDEX_FILE',
    'GIT_PREFIX',
  };

  static const Set<String> _globalsWithValue = {
    '-c',
    '--exec-path',
    '--namespace',
    '--super-prefix',
    '--config-env',
    '--attr-source',
    '--list-cmds',
  };

  static Map<String, String> sanitizedEnvironment(
    Map<String, String> environment,
  ) {
    return {
      for (final entry in environment.entries)
        if (!_relocationEnvironmentKeys.contains(entry.key))
          entry.key: entry.value,
    };
  }

  static Map<String, dynamic>? relocationPayload({
    required List<String> args,
    required String workingDirectory,
  }) {
    final relocation = relocationDenial(args);
    if (relocation == null) {
      return null;
    }
    return {
      'ok': false,
      'code': relocationCode,
      'error': relocationMessage,
      'option': relocation,
      'working_directory': workingDirectory,
      'exit_code': 2,
    };
  }

  static Future<Map<String, dynamic>?> evaluate({
    required List<String> args,
    required String toolName,
    required String? projectRoot,
    required String workingDirectory,
  }) async {
    final relocation = relocationPayload(
      args: args,
      workingDirectory: workingDirectory,
    );
    if (relocation != null) {
      return relocation;
    }

    for (final path in pathspecCandidates(args)) {
      final auth = await const ProjectMutationPathFence().authorize(
        toolName: toolName,
        projectRoot: projectRoot,
        rawPath: path,
      );
      if (!auth.isAllowed) {
        return jsonDecode(auth.deniedResult!.result) as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// Returns the relocating option text when it appears as a git global.
  static String? relocationDenial(List<String> args) {
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--' || !arg.startsWith('-') || arg == '-') {
        return null;
      }
      if (arg == '-C' || arg == '--git-dir' || arg == '--work-tree') {
        return arg;
      }
      if (arg.startsWith('--git-dir=') || arg.startsWith('--work-tree=')) {
        return arg.split('=').first;
      }
      if (_globalsWithValue.contains(arg) &&
          !arg.contains('=') &&
          i + 1 < args.length) {
        i += 1;
      }
    }
    return null;
  }

  static List<String> pathspecCandidates(List<String> args) {
    final subcommandIndex = _subcommandIndex(args);
    if (subcommandIndex < 0 || subcommandIndex + 1 >= args.length) {
      return const [];
    }
    final candidates = <String>[];
    var afterDoubleDash = false;
    for (var i = subcommandIndex + 1; i < args.length; i++) {
      final arg = args[i];
      if (!afterDoubleDash && arg == '--') {
        afterDoubleDash = true;
        continue;
      }
      if (afterDoubleDash) {
        if (arg.isNotEmpty) {
          candidates.add(arg);
        }
        continue;
      }
      if (arg.startsWith('-')) {
        continue;
      }
      if (_isEscapingPath(arg)) {
        candidates.add(arg);
      }
    }
    return candidates;
  }

  static int _subcommandIndex(List<String> args) {
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--' || !arg.startsWith('-') || arg == '-') {
        return i;
      }
      if (arg == '-C' ||
          arg == '--git-dir' ||
          arg == '--work-tree' ||
          arg.startsWith('--git-dir=') ||
          arg.startsWith('--work-tree=')) {
        return -1;
      }
      if (_globalsWithValue.contains(arg) &&
          !arg.contains('=') &&
          i + 1 < args.length) {
        i += 1;
      }
    }
    return -1;
  }

  static bool _isEscapingPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed == '~' ||
        trimmed.startsWith('~/') ||
        trimmed.startsWith(r'~\')) {
      return true;
    }
    if (trimmed
        .split(RegExp(r'[/\\]+'))
        .any((component) => component == '..')) {
      return true;
    }
    return DartProjectPath.isAbsolutePath(trimmed);
  }
}
