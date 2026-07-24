import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/project_scoped_tool_argument_resolver.dart';

void main() {
  group('ProjectScopedToolArgumentResolver', () {
    test('defaults read-only directory tools to the current directory', () {
      for (final toolName in const [
        'list_directory',
        'find_files',
        'search_files',
      ]) {
        final resolved = ProjectScopedToolArgumentResolver.resolve(
          toolName: toolName,
          arguments: const <String, dynamic>{},
          loadProjectRoot: () => null,
        );

        expect(resolved['path'], '.');

        final projectResolved = ProjectScopedToolArgumentResolver.resolve(
          toolName: toolName,
          arguments: const <String, dynamic>{'path': '  '},
          loadProjectRoot: () => '/workspace/project',
        );

        expect(projectResolved['path'], '/workspace/project/');
      }
    });

    test('resolves every file tool path against the active project root', () {
      for (final toolName in const [
        'read_file',
        'inspect_file',
        'edit_file',
        'delete_file',
        'lsp_go_to_definition',
      ]) {
        final resolved = ProjectScopedToolArgumentResolver.resolve(
          toolName: toolName,
          arguments: const {'path': 'lib/main.dart'},
          loadProjectRoot: () => '/workspace/project',
        );

        expect(resolved['path'], '/workspace/project/lib/main.dart');
      }
    });

    test('uses dependency project path aliases', () {
      for (final key in const [
        'project_path',
        'path',
        'working_directory',
        'cwd',
      ]) {
        final resolved = ProjectScopedToolArgumentResolver.resolve(
          toolName: 'resolve_installed_dependency',
          arguments: {key: '/workspace/project'},
          loadProjectRoot: () => null,
        );

        expect(resolved['project_path'], '/workspace/project');
      }
    });

    test('resolves write_file and normalizes content aliases', () {
      final aliased = ProjectScopedToolArgumentResolver.resolve(
        toolName: 'write_file',
        arguments: const {'path': 'README.md', 'contents': '  # README  '},
        loadProjectRoot: () => '/workspace/project',
      );

      expect(aliased['path'], '/workspace/project/README.md');
      expect(aliased['content'], '# README');

      final explicit = ProjectScopedToolArgumentResolver.resolve(
        toolName: 'write_file',
        arguments: const {
          'path': '/workspace/project/README.md',
          'content': 'kept',
          'contents': 'ignored',
        },
        loadProjectRoot: () => null,
      );

      expect(explicit['content'], 'kept');
    });

    test('normalizes local commands and cwd aliases', () {
      for (final toolName in const ['local_execute_command', 'process_start']) {
        final resolved = ProjectScopedToolArgumentResolver.resolve(
          toolName: toolName,
          arguments: const {
            'command': '  dart test<|im_end|>  ',
            'cwd': '/workspace/project',
          },
          loadProjectRoot: () => null,
        );

        expect(resolved['command'], 'dart test');
        expect(resolved['working_directory'], '/workspace/project');
      }
    });

    test('resolves both git working directory and worktree path', () {
      for (final toolName in const [
        'git_execute_command',
        'git_finish_worktree_session',
      ]) {
        var projectRootLoads = 0;
        final resolved = ProjectScopedToolArgumentResolver.resolve(
          toolName: toolName,
          arguments: const {
            'cwd': '/workspace/project',
            'worktree_path': '/workspace/project-worktrees/task',
          },
          loadProjectRoot: () {
            projectRootLoads++;
            return null;
          },
        );

        expect(resolved['working_directory'], '/workspace/project');
        expect(resolved['worktree_path'], '/workspace/project-worktrees/task');
        expect(projectRootLoads, 1);
      }
    });

    test('leaves unknown tools untouched without loading project state', () {
      var projectRootLoads = 0;
      final arguments = <String, dynamic>{'value': 1};

      final resolved = ProjectScopedToolArgumentResolver.resolve(
        toolName: 'unknown_tool',
        arguments: arguments,
        loadProjectRoot: () {
          projectRootLoads++;
          return '/workspace/project';
        },
      );

      expect(identical(resolved, arguments), isTrue);
      expect(projectRootLoads, 0);
    });
  });
}
