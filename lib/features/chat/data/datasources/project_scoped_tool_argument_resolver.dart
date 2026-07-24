import 'filesystem_tools.dart';
import 'local_shell_tools.dart';

typedef ProjectRootLoader = String? Function();

class ProjectScopedToolArgumentResolver {
  ProjectScopedToolArgumentResolver._();

  static Map<String, dynamic> resolve({
    required String toolName,
    required Map<String, dynamic> arguments,
    required ProjectRootLoader loadProjectRoot,
  }) {
    String? projectRoot;
    var projectRootLoaded = false;

    String? resolveProjectRoot() {
      if (!projectRootLoaded) {
        projectRoot = loadProjectRoot();
        projectRootLoaded = true;
      }
      return projectRoot;
    }

    String? resolvePathArgument(
      String key, {
      bool allowEmpty = false,
      List<String> aliases = const [],
      String? fallbackWhenMissing,
    }) {
      String? rawValue = (arguments[key] as String?)?.trim();
      for (final alias in aliases) {
        if (rawValue != null && rawValue.isNotEmpty) {
          break;
        }
        rawValue = (arguments[alias] as String?)?.trim();
      }
      final hasExplicitValue = rawValue != null && rawValue.isNotEmpty;
      if (!hasExplicitValue && fallbackWhenMissing != null) {
        rawValue = fallbackWhenMissing;
      }
      if ((rawValue == null || rawValue.isEmpty) && !allowEmpty) {
        return null;
      }
      final resolved = FilesystemTools.resolvePath(
        rawValue,
        defaultRoot: resolveProjectRoot(),
      );
      if (resolved == null &&
          !hasExplicitValue &&
          fallbackWhenMissing != null) {
        return fallbackWhenMissing;
      }
      return resolved;
    }

    return switch (toolName) {
      'list_directory' || 'find_files' || 'search_files' => () {
        final resolvedPath = resolvePathArgument(
          'path',
          allowEmpty: true,
          fallbackWhenMissing: '.',
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedPath != null) {
          resolvedArguments['path'] = resolvedPath;
        }
        return resolvedArguments;
      }(),
      'resolve_installed_dependency' => () {
        final resolvedProjectPath = resolvePathArgument(
          'project_path',
          allowEmpty: true,
          aliases: const ['path', 'working_directory', 'cwd'],
          fallbackWhenMissing: '.',
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedProjectPath != null) {
          resolvedArguments['project_path'] = resolvedProjectPath;
        }
        return resolvedArguments;
      }(),
      'read_file' ||
      'inspect_file' ||
      'write_file' ||
      'edit_file' ||
      'delete_file' ||
      'lsp_go_to_definition' => () {
        final resolvedPath = resolvePathArgument('path');
        final resolvedArguments = toolName == 'write_file'
            ? normalizeWriteFileArguments(arguments)
            : <String, dynamic>{...arguments};
        if (resolvedPath != null) {
          resolvedArguments['path'] = resolvedPath;
        }
        return resolvedArguments;
      }(),
      'local_execute_command' || 'process_start' => () {
        final resolvedWorkingDirectory = resolvePathArgument(
          'working_directory',
          allowEmpty: true,
          aliases: const ['cwd'],
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        final command = (resolvedArguments['command'] as String?)?.trim();
        if (command != null && command.isNotEmpty) {
          resolvedArguments['command'] = LocalShellTools.normalizeCommand(
            command,
          );
        }
        if (resolvedWorkingDirectory != null) {
          resolvedArguments['working_directory'] = resolvedWorkingDirectory;
        }
        return resolvedArguments;
      }(),
      'git_execute_command' || 'git_finish_worktree_session' => () {
        final resolvedWorkingDirectory = resolvePathArgument(
          'working_directory',
          allowEmpty: true,
          aliases: const ['cwd'],
        );
        final resolvedWorktreePath = resolvePathArgument(
          'worktree_path',
          allowEmpty: true,
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedWorkingDirectory != null) {
          resolvedArguments['working_directory'] = resolvedWorkingDirectory;
        }
        if (resolvedWorktreePath != null) {
          resolvedArguments['worktree_path'] = resolvedWorktreePath;
        }
        return resolvedArguments;
      }(),
      _ => arguments,
    };
  }

  static Map<String, dynamic> normalizeWriteFileArguments(
    Map<String, dynamic> arguments,
  ) {
    final normalizedArguments = <String, dynamic>{...arguments};
    final content = (normalizedArguments['content'] as String?)?.trim();
    final contents = (normalizedArguments['contents'] as String?)?.trim();
    if ((content == null || content.isEmpty) &&
        contents != null &&
        contents.isNotEmpty) {
      normalizedArguments['content'] = contents;
    }
    return normalizedArguments;
  }
}
