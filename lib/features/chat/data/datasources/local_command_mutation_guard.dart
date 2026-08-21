import 'package:path/path.dart' as p;

import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/out_of_root_command_paths.dart';
import 'project_mutation_path_fence.dart';
import 'turn_project_root.dart';

/// Blocks local-command writes that escape the authorized project.
///
/// SEC4.4a already fences approval-free internal reads. Native-shell writes
/// still used a lexical cwd check, so a symlink working directory or a `~` /
/// `..` / absolute operand could mutate files beside the selected project.
abstract final class LocalCommandMutationGuard {
  static const String _unmatchableRoot =
      '/__caverno_unmatchable_project_root__';

  static const Set<String> _commandSeparators = {'&&', '||', '|', ';', '&'};

  /// Explicit `projectRoot`, otherwise the turn-scoped root. Empty when
  /// general-mode chat has no selected project and the fence must not run.
  static String? authorizedProjectRoot(String? projectRoot) {
    final explicit = projectRoot?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final scoped = TurnProjectRoot.current?.rootPath.trim();
    if (scoped != null && scoped.isNotEmpty) {
      return scoped;
    }
    return null;
  }

  static Future<ProjectMutationPathAuthorization> authorizeWorkingDirectory({
    required String toolName,
    required String? projectRoot,
    required String workingDirectory,
  }) {
    return const ProjectMutationPathFence().authorize(
      toolName: toolName,
      projectRoot: projectRoot,
      rawPath: workingDirectory,
    );
  }

  static Future<ProjectMutationPathAuthorization?> authorizeWritePaths({
    required String toolName,
    required String? projectRoot,
    required String command,
    required String workingDirectory,
  }) async {
    const fence = ProjectMutationPathFence();
    for (final path in writePathCandidates(command)) {
      final authorization = await fence.authorize(
        toolName: toolName,
        projectRoot: projectRoot,
        rawPath: _resolveAgainstWorkingDirectory(path, workingDirectory),
      );
      if (!authorization.isAllowed) {
        return authorization;
      }
    }
    return null;
  }

  /// Escaping operands a write command names, excluding the executable.
  static List<String> writePathCandidates(String command) {
    final candidates = <String>[];
    final skippedCommands = <String>[];

    void consider(String raw) {
      final path = _stripRedirectPrefix(raw.trim());
      if (path.isEmpty || candidates.contains(path)) {
        return;
      }
      if (_isDeviceFile(path)) {
        return;
      }
      if (!_isEscapingPath(path)) {
        return;
      }
      candidates.add(path);
    }

    var nextIsCommand = true;
    for (final token in _tokens(command)) {
      if (_commandSeparators.contains(token)) {
        nextIsCommand = true;
        continue;
      }
      if (nextIsCommand) {
        skippedCommands.add(token);
        nextIsCommand = false;
        continue;
      }
      if (token.startsWith('-')) {
        continue;
      }
      consider(token);
    }

    for (final mentioned in const OutOfRootCommandPaths().scan(
      command: command,
      projectRoot: _unmatchableRoot,
    )) {
      if (skippedCommands.contains(mentioned)) {
        continue;
      }
      consider(mentioned);
    }
    return List<String>.unmodifiable(candidates);
  }

  static String _resolveAgainstWorkingDirectory(
    String path,
    String workingDirectory,
  ) {
    final trimmed = path.trim();
    if (trimmed.isEmpty ||
        trimmed == '~' ||
        trimmed.startsWith('~/') ||
        trimmed.startsWith(r'~\') ||
        DartProjectPath.isAbsolutePath(trimmed)) {
      return trimmed;
    }
    return p.normalize(p.join(workingDirectory, trimmed));
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

  static bool _isDeviceFile(String path) =>
      path == '/dev/null' ||
      path == '/dev/zero' ||
      path == '/dev/random' ||
      path == '/dev/urandom' ||
      path == '/dev/stdin' ||
      path == '/dev/stdout' ||
      path == '/dev/stderr' ||
      path == '/dev/tty' ||
      path == '/dev/console' ||
      path.startsWith('/dev/fd/');

  static String _stripRedirectPrefix(String token) {
    var value = token;
    if (RegExp(r'^\d+').hasMatch(value)) {
      value = value.replaceFirst(RegExp(r'^\d+'), '');
    }
    while (value.startsWith('>') || value.startsWith('<')) {
      value = value.substring(1);
    }
    return value;
  }

  static List<String> _tokens(String command) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;

    void flush() {
      if (buffer.isEmpty) {
        return;
      }
      tokens.add(buffer.toString());
      buffer.clear();
    }

    for (var i = 0; i < command.length; i++) {
      final char = command[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == ' ' || char == '\t' || char == '\n') {
        flush();
        continue;
      }
      if (char == ';') {
        flush();
        tokens.add(';');
        continue;
      }
      if (char == '&' || char == '|') {
        final doubled = i + 1 < command.length && command[i + 1] == char
            ? '$char$char'
            : char;
        flush();
        tokens.add(doubled);
        if (doubled.length == 2) {
          i += 1;
        }
        continue;
      }
      buffer.write(char);
    }
    flush();
    return tokens;
  }
}
