import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../../core/services/login_shell_environment.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/git_process_execution_contract.dart';
import '../../domain/services/git_tool_handler.dart';
import 'git_tools.dart';
import 'mcp_tool_result_normalizer.dart';

export '../../domain/services/git_process_execution_coordinator.dart';
export '../../domain/services/git_tool_handler.dart';

typedef GitRuntimeCommandRunner =
    Future<String> Function({
      required String command,
      required String workingDirectory,
      String? reason,
      GitProcessHandoff? beforeProcessStart,
    });

typedef GitRuntimeWorktreeRunner =
    Future<String> Function({
      required String worktreePath,
      String baseBranch,
      bool removeWorktree,
      String? mergeMessage,
      GitProcessHandoff? beforeProcessStart,
    });

typedef GitRuntimeStateInspector =
    Future<GitRepositoryInspection> Function(Iterable<String?> paths);

final class GitRepositoryInspection {
  GitRepositoryInspection({
    required this.available,
    required this.digest,
    required Iterable<String> worktreePaths,
    required Map<String, dynamic> evidence,
  }) : worktreePaths = List.unmodifiable(worktreePaths),
       evidence = freezeGitToolMap(evidence);

  factory GitRepositoryInspection.unavailable() => GitRepositoryInspection(
    available: false,
    digest: '',
    worktreePaths: const [],
    evidence: const {'available': false},
  );

  final bool available;
  final String digest;
  final List<String> worktreePaths;
  final Map<String, dynamic> evidence;

  bool hasSameState(GitRepositoryInspection other) =>
      available && other.available && digest == other.digest;
}

/// Captures non-secret repository facts for effect classification.
final class GitRepositoryStateInspector {
  const GitRepositoryStateInspector();

  static const _timeout = Duration(seconds: 5);
  static const _commands = <List<String>>[
    ['rev-parse', 'HEAD'],
    ['status', '--porcelain=v1', '-uall'],
    ['for-each-ref', '--format=%(refname)%00%(objectname)'],
    ['worktree', 'list', '--porcelain'],
    ['config', '--list', '--show-origin', '--show-scope'],
  ];

  Future<GitRepositoryInspection> inspect(Iterable<String?> paths) async {
    final environment = await LoginShellEnvironment.instance.environment();
    for (final rawPath in paths) {
      final path = rawPath?.trim() ?? '';
      if (path.isEmpty || !Directory(path).existsSync()) continue;
      final root = await _run(
        const ['rev-parse', '--show-toplevel'],
        path,
        environment,
      );
      if (root == null || root.exitCode != 0 || root.stdout.trim().isEmpty) {
        continue;
      }

      final snapshots = <String>[];
      var worktreeOutput = '';
      for (final command in _commands) {
        final result = await _run(command, path, environment);
        if (result == null) return GitRepositoryInspection.unavailable();
        final serialized = [
          command.join('\u0000'),
          result.exitCode,
          result.stdout,
          result.stderr,
        ].join('\u0001');
        snapshots.add(serialized);
        if (command.first == 'worktree') worktreeOutput = result.stdout;
      }
      final digest = sha256
          .convert(utf8.encode(snapshots.join('\u0002')))
          .toString();
      final worktrees = worktreeOutput
          .split('\n')
          .where((line) => line.startsWith('worktree '))
          .map((line) => line.substring('worktree '.length).trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      return GitRepositoryInspection(
        available: true,
        digest: digest,
        worktreePaths: worktrees,
        evidence: {
          'available': true,
          'repositoryRoot': root.stdout.trim(),
          'stateDigest': digest,
          'worktreePaths': worktrees,
        },
      );
    }
    return GitRepositoryInspection.unavailable();
  }

  Future<ProcessResult?> _run(
    List<String> arguments,
    String workingDirectory,
    Map<String, String> environment,
  ) async {
    try {
      return await Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      ).timeout(_timeout);
    } on Object {
      return null;
    }
  }
}

/// Production boundary between the owner-scoped handler and raw Git tools.
final class GitToolRuntimeAdapter
    implements GitExecutionPort, GitWorktreeSessionPort {
  GitToolRuntimeAdapter({
    GitRuntimeCommandRunner? commandRunner,
    GitRuntimeWorktreeRunner? worktreeRunner,
    GitRuntimeStateInspector? stateInspector,
  }) : _commandRunner = commandRunner ?? GitTools.execute,
       _worktreeRunner = worktreeRunner ?? GitTools.finishWorktreeSession,
       _stateInspector =
           stateInspector ?? const GitRepositoryStateInspector().inspect;

  final GitRuntimeCommandRunner _commandRunner;
  final GitRuntimeWorktreeRunner _worktreeRunner;
  final GitRuntimeStateInspector _stateInspector;

  @override
  Future<GitRawProcessCompletion> execute(
    GitCommandExecutionRequest request,
    GitProcessStartAuthorization authorization,
  ) async {
    final candidates = [
      request.workingDirectory,
      request.source.ownerRepositoryPath,
      request.source.ownerWorktreePath,
    ];
    final before = await _stateInspector(candidates);
    final payload = await _commandRunner(
      command: request.command,
      workingDirectory: request.workingDirectory,
      reason: request.reason,
      beforeProcessStart: authorization.beginProcessHandoff,
    );
    final result = McpToolResultNormalizer.fromCommandPayload(
      toolName: request.source.toolName,
      result: payload,
      toolLabel: 'Git command',
    );
    return _completion(
      authorization: authorization,
      result: result,
      before: before,
      afterCandidates: [...candidates, ...before.worktreePaths],
      readOnly: GitTools.isReadOnly(request.command),
    );
  }

  @override
  Future<GitRawProcessCompletion> finish(
    GitWorktreeSessionRequest request,
    GitProcessStartAuthorization authorization,
  ) async {
    final candidates = [
      request.source.ownerRepositoryPath,
      request.worktreePath,
      request.source.ownerWorktreePath,
    ];
    final before = await _stateInspector(candidates);
    final payload = await _worktreeRunner(
      worktreePath: request.worktreePath,
      baseBranch: request.baseBranch,
      removeWorktree: request.removeWorktree,
      mergeMessage: request.mergeMessage,
      beforeProcessStart: authorization.beginProcessHandoff,
    );
    final result = McpToolResultNormalizer.fromCommandPayload(
      toolName: request.source.toolName,
      result: payload,
      toolLabel: 'Finish worktree session',
    );
    return _completion(
      authorization: authorization,
      result: result,
      before: before,
      afterCandidates: [...candidates, ...before.worktreePaths],
      readOnly: false,
    );
  }

  Future<GitRawProcessCompletion> _completion({
    required GitProcessStartAuthorization authorization,
    required McpToolResult result,
    required GitRepositoryInspection before,
    required Iterable<String?> afterCandidates,
    required bool readOnly,
  }) async {
    if (!authorization.started && authorization.disposition == null) {
      throw GitProcessLaunchFailure(
        identity: authorization.identity,
        result: result,
      );
    }
    if (!authorization.started) {
      return GitRawProcessCompletion(
        identity: authorization.identity,
        result: result,
        effectKind: GitProcessEffectKind.noEffect,
      );
    }

    final after = await _stateInspector(afterCandidates);
    final unchanged = before.hasSameState(after);
    final effectKind = readOnly || (!result.isSuccess && unchanged)
        ? GitProcessEffectKind.noEffect
        : result.isSuccess && after.available
        ? GitProcessEffectKind.committed
        : GitProcessEffectKind.partialOrUnknown;
    return GitRawProcessCompletion(
      identity: authorization.identity,
      result: result,
      effectKind: effectKind,
      effectDetails: {
        'before': before.evidence,
        'after': after.evidence,
        'resultSucceeded': result.isSuccess,
      },
      reconciliation: after.available
          ? GitProcessReconciliationConfirmation(
              identity: authorization.identity,
              details: after.evidence,
            )
          : null,
    );
  }
}
