import 'package:caverno/features/chat/data/datasources/built_in_filesystem_operation_runner.dart';
import 'package:caverno/features/chat/data/datasources/built_in_filesystem_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/git_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'farm_completion_fixture.dart';

final class FarmCompletionTools extends McpToolService {
  factory FarmCompletionTools(FarmCompletionFixture fixture) {
    final scope = FarmCompletionScope(fixture);
    return FarmCompletionTools._(scope);
  }
  FarmCompletionTools._(this.scope)
    : super(
        filesystemToolHandler: BuiltInFilesystemToolHandler(
          snapshotReader: (path) {
            if (!scope.fixture.readable(path)) {
              throw StateError('Outside fixture snapshot scope');
            }
            return FilesystemTools.captureTextSnapshot(path);
          },
          operationResultRunner: ({required name, required arguments}) {
            final path = arguments['path'] as String? ?? '';
            final allowed = name == 'read_file'
                ? scope.fixture.readable(path)
                : ['write_file', 'edit_file'].contains(name) &&
                      scope.canWrite(path);
            if (!allowed) {
              throw StateError('Outside fixture file effect scope');
            }
            return runBuiltInFilesystemOperation(
              name: name,
              arguments: arguments,
            );
          },
        ),
      );
  final FarmCompletionScope scope;
  final nativeExecutions = <Map<String, dynamic>>[];
  final gitExecutions = <Map<String, dynamic>>[];
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}
  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    ...super.getOpenAiToolDefinitions().where(
      (tool) => [
        'read_file',
        'write_file',
        'edit_file',
        'local_execute_command',
        'git_execute_command',
        'update_goal',
      ].contains((tool['function'] as Map?)?['name']),
    ),
  ];
  @override
  Future<McpToolResult> executeProcessTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name != 'local_execute_command' ||
        arguments['command'] != farmCompletionVerify ||
        arguments['working_directory'] != scope.fixture.root.path ||
        arguments['workspace_command_containment'] != true) {
      throw StateError('Outside contained fixture verifier scope');
    }
    final result = await super.executeProcessTool(
      owner: owner,
      name: name,
      arguments: arguments,
    );
    nativeExecutions.add({
      'stage': scope.stage,
      'arguments': arguments,
      'result': result.result,
    });
    return result;
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name == 'read_file' &&
        scope.fixture.readable(arguments['path'] as String? ?? '')) {
      return super.executeTool(name: name, arguments: arguments);
    }
    if (name != 'git_execute_command' ||
        !scope.canGit(
          arguments['command'] as String? ?? '',
          arguments['working_directory'] as String? ?? '',
        )) {
      throw StateError('Outside fixture Git scope');
    }
    final result = await super.executeTool(name: name, arguments: arguments);
    gitExecutions.add({
      'stage': scope.stage,
      'mutation': !GitTools.isReadOnly(arguments['command'] as String),
      'arguments': arguments,
      'result': result.result,
    });
    return result;
  }
}

/// Git is a separate native authority route; approve each bounded write fresh.
final class FarmCompletionScope {
  FarmCompletionScope(this.fixture);
  final FarmCompletionFixture fixture;
  String stage = 'implementation';
  bool canWrite(String path) =>
      fixture.writable(path) &&
      (path.endsWith('/roadmap.md')
          ? stage == 'commit'
          : ['implementation', 'repair'].contains(stage));
  bool canGit(String command, String cwd) {
    if (cwd != fixture.root.path ||
        GitTools.firstShellControlOperator(command) != null) {
      return false;
    }
    final args = GitTools.splitArgs(GitTools.normalizeCommand(command));
    if (args.isEmpty) {
      return false;
    }
    const paths = {
      'fixture.py',
      'roadmap.md',
      'tool/verify.py',
      'unrelated.txt',
    };
    bool taskPath(String value) =>
        paths.contains(value) ||
        paths.any((relative) => value == '${fixture.root.path}/$relative');
    if (args.first == 'status') {
      return args.skip(1).every({'--short', '--porcelain'}.contains);
    }
    if (args.first == 'diff') {
      var afterSeparator = false;
      for (final arg in args.skip(1)) {
        if (arg == '--' && !afterSeparator) {
          afterSeparator = true;
          continue;
        }
        if (taskPath(arg)) {
          continue;
        }
        if (!afterSeparator &&
            {
              '--cached',
              '--staged',
              '--stat',
              '--no-ext-diff',
              '--unified=3',
              'HEAD',
            }.contains(arg)) {
          continue;
        }
        return false;
      }
      return true;
    }
    if (args.first == 'log') {
      return args.any({'-1', '-3'}.contains) &&
          args
              .skip(1)
              .every(
                {
                  '--oneline',
                  '-1',
                  '-3',
                  '--format=%B',
                  '--format=%s',
                  '--format=%H',
                }.contains,
              );
    }
    if (args.first == 'show') {
      return args
          .skip(1)
          .every(
            (arg) =>
                {
                  'HEAD',
                  '--stat',
                  '--oneline',
                  '--name-only',
                  '--format=%B',
                  '--no-ext-diff',
                  '--',
                }.contains(arg) ||
                taskPath(arg) ||
                paths.any((path) => arg == 'HEAD:$path'),
          );
    }
    if (args.join(' ') == 'rev-parse HEAD') return true;
    if (stage != 'commit') {
      return false;
    }
    if ((args.length == 3 || args.length == 4) &&
        args[0] == 'add' &&
        args[1] == '--' &&
        args
            .skip(2)
            .every(
              (value) => ['fixture.py', 'roadmap.md'].any(
                (path) =>
                    value == path || value == '${fixture.root.path}/$path',
              ),
            )) {
      return true;
    }
    return args.length == 5 &&
        args[0] == 'commit' &&
        args[1] == '-m' &&
        args[3] == '-m' &&
        RegExp(r'^(fix|test): [A-Za-z0-9 ,:.-]{1,60}$').hasMatch(args[2]) &&
        RegExp(r'^[A-Za-z0-9 ,:.-]{1,200}$').hasMatch(args[4]);
  }
}

final class FarmCompletionApprover {
  FarmCompletionApprover(
    ProviderContainer container,
    FarmCompletionTools tools,
  ) {
    subscription = container.listen<ChatState>(chatNotifierProvider, (
      previous,
      next,
    ) {
      final notifier = container.read(chatNotifierProvider.notifier);
      final local = next.pendingLocalCommand;
      if (local != null && previous?.pendingLocalCommand?.id != local.id) {
        final approved =
            local.command == farmCompletionVerify &&
            local.workingDirectory == tools.scope.fixture.root.path;
        decisions.add({
          'kind': 'local',
          'stage': tools.scope.stage,
          'command': local.command,
          'approved': approved,
        });
        notifier.resolveLocalCommand(
          id: local.id,
          approval: LocalCommandApproval(approved: approved),
        );
      }
      final file = next.pendingFileOperation;
      if (file != null && previous?.pendingFileOperation?.id != file.id) {
        final approved =
            ['Write File', 'Edit File'].contains(file.operation) &&
            tools.scope.canWrite(file.path);
        decisions.add({
          'kind': 'file',
          'stage': tools.scope.stage,
          'operation': file.operation,
          'path': file.path,
          'approved': approved,
        });
        notifier.resolveFileOperation(id: file.id, approved: approved);
      }
      final git = next.pendingGitCommand;
      if (git != null && previous?.pendingGitCommand?.id != git.id) {
        final approved = tools.scope.canGit(git.command, git.workingDirectory);
        decisions.add({
          'kind': 'git',
          'stage': tools.scope.stage,
          'command': git.command,
          'approved': approved,
        });
        notifier.resolveGitCommand(id: git.id, approved: approved);
      }
    });
  }
  late final ProviderSubscription<ChatState> subscription;
  final decisions = <Map<String, dynamic>>[];
  void dispose() => subscription.close();
}
