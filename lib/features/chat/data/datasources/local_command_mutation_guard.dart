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
    for (final token in _tokens(_withoutHeredocBodies(command))) {
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

  /// [command] with heredoc bodies removed, keeping the shell operands.
  ///
  /// The operand tokenizer splits on whitespace, and a heredoc body is not
  /// operands: writing JavaScript through `cat > js/cave.js << 'EOF'` handed
  /// the fence the body's `//` comment markers, which read as absolute paths
  /// and denied an in-root write four times in session a0ca65b7. Only the
  /// operand pass drops the body -- [OutOfRootCommandPaths] still scans the
  /// whole command, so a `python3 << EOF` body naming an outside path is
  /// still seen.
  static String _withoutHeredocBodies(String command) {
    if (!command.contains('<<')) {
      return command;
    }
    final lines = command.split('\n');
    final kept = <String>[];
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      kept.add(line);
      index += 1;
      for (final redirect in _heredocRedirects(line)) {
        while (index < lines.length) {
          final raw = lines[index];
          index += 1;
          final candidate = redirect.allowsIndent
              ? raw.replaceFirst(RegExp(r'^[\t ]+'), '')
              : raw;
          if (candidate.trim() == redirect.delimiter) {
            break;
          }
        }
      }
    }
    return kept.join('\n');
  }

  /// Heredoc delimiters [line] opens, in order, ignoring quoted `<<` text.
  static List<({String delimiter, bool allowsIndent})> _heredocRedirects(
    String line,
  ) {
    final redirects = <({String delimiter, bool allowsIndent})>[];
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == r'\') {
        i += 1;
        continue;
      }
      if (char != '<' || i + 1 >= line.length || line[i + 1] != '<') {
        continue;
      }
      var cursor = i + 2;
      // `<<<` is a here-string: its operand stays on this line.
      if (cursor < line.length && line[cursor] == '<') {
        i = cursor;
        continue;
      }
      var allowsIndent = false;
      if (cursor < line.length && line[cursor] == '-') {
        allowsIndent = true;
        cursor += 1;
      }
      while (cursor < line.length &&
          (line[cursor] == ' ' || line[cursor] == '\t')) {
        cursor += 1;
      }
      final delimiter = StringBuffer();
      String? delimiterQuote;
      while (cursor < line.length) {
        final delimiterChar = line[cursor];
        if (delimiterQuote != null) {
          if (delimiterChar == delimiterQuote) {
            delimiterQuote = null;
          } else {
            delimiter.write(delimiterChar);
          }
          cursor += 1;
          continue;
        }
        if (delimiterChar == '"' || delimiterChar == "'") {
          delimiterQuote = delimiterChar;
          cursor += 1;
          continue;
        }
        if (delimiterChar == r'\') {
          cursor += 1;
          if (cursor < line.length) {
            delimiter.write(line[cursor]);
            cursor += 1;
          }
          continue;
        }
        if (delimiterChar == ' ' ||
            delimiterChar == '\t' ||
            delimiterChar == ';' ||
            delimiterChar == '&' ||
            delimiterChar == '|' ||
            delimiterChar == '<' ||
            delimiterChar == '>') {
          break;
        }
        delimiter.write(delimiterChar);
        cursor += 1;
      }
      final word = delimiter.toString();
      if (word.isNotEmpty) {
        redirects.add((delimiter: word, allowsIndent: allowsIndent));
      }
      i = cursor - 1;
    }
    return redirects;
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
