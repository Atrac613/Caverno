import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/worktree_agent_task.dart';
import 'coding_environment_snapshot_provider.dart';

class WorktreeAgentGitWorktreePrepareResult {
  const WorktreeAgentGitWorktreePrepareResult({
    required this.success,
    this.repositoryRoot = '',
    this.errorMessage,
  });

  const WorktreeAgentGitWorktreePrepareResult.succeeded({
    required String repositoryRoot,
  }) : this(success: true, repositoryRoot: repositoryRoot);

  const WorktreeAgentGitWorktreePrepareResult.failed(String errorMessage)
    : this(success: false, errorMessage: errorMessage);

  final bool success;
  final String repositoryRoot;
  final String? errorMessage;
}

typedef WorktreeParentDirectoryEnsurer = Future<void> Function(String path);

final worktreeAgentGitWorktreePreparerProvider =
    Provider<WorktreeAgentGitWorktreePreparer>((ref) {
      return WorktreeAgentGitWorktreePreparer(
        runProcess: ref.watch(codingEnvironmentProcessRunnerProvider),
      );
    });

class WorktreeAgentGitWorktreePreparer {
  WorktreeAgentGitWorktreePreparer({
    required this.runProcess,
    WorktreeParentDirectoryEnsurer? ensureParentDirectory,
  }) : _ensureParentDirectory =
           ensureParentDirectory ?? _defaultEnsureParentDirectory;

  final CodingEnvironmentProcessRunner runProcess;
  final WorktreeParentDirectoryEnsurer _ensureParentDirectory;

  Future<WorktreeAgentGitWorktreePrepareResult> prepare({
    required String projectRootPath,
    required WorktreeAgentTask task,
  }) async {
    final validationError = _validate(
      projectRootPath: projectRootPath,
      task: task,
    );
    if (validationError != null) {
      return WorktreeAgentGitWorktreePrepareResult.failed(validationError);
    }

    try {
      final repositoryResult = await runProcess('git', const [
        'rev-parse',
        '--show-toplevel',
      ], workingDirectory: projectRootPath.trim());
      if (repositoryResult.exitCode != 0) {
        return WorktreeAgentGitWorktreePrepareResult.failed(
          _processErrorText(
            repositoryResult,
            fallback: 'Project is not a git repository.',
          ),
        );
      }

      final repositoryRoot = _stdoutText(repositoryResult).trim();
      final effectiveRoot = repositoryRoot.isEmpty
          ? projectRootPath.trim()
          : repositoryRoot;
      final parentPath = _parentPath(task.normalizedWorktreePath);
      if (parentPath.isNotEmpty) {
        await _ensureParentDirectory(parentPath);
      }

      final worktreeResult = await runProcess('git', [
        'worktree',
        'add',
        '-b',
        task.branchName.trim(),
        task.normalizedWorktreePath,
        task.baseBranch.trim().isEmpty ? 'main' : task.baseBranch.trim(),
      ], workingDirectory: effectiveRoot);
      if (worktreeResult.exitCode != 0) {
        return WorktreeAgentGitWorktreePrepareResult.failed(
          _processErrorText(
            worktreeResult,
            fallback: 'Could not create git worktree.',
          ),
        );
      }

      return WorktreeAgentGitWorktreePrepareResult.succeeded(
        repositoryRoot: effectiveRoot,
      );
    } on TimeoutException {
      return const WorktreeAgentGitWorktreePrepareResult.failed(
        'Timed out while creating git worktree.',
      );
    } catch (error) {
      return WorktreeAgentGitWorktreePrepareResult.failed(
        'Could not create git worktree: $error',
      );
    }
  }

  String? _validate({
    required String projectRootPath,
    required WorktreeAgentTask task,
  }) {
    if (task.status != WorktreeAgentTaskStatus.queued) {
      return 'Only queued worktree-agent tasks can create a git worktree.';
    }
    if (projectRootPath.trim().isEmpty) {
      return 'Project root path is required.';
    }
    if (!_isSafeGitArgument(task.branchName)) {
      return 'Branch name is invalid.';
    }
    if (!_isSafePathArgument(task.normalizedWorktreePath)) {
      return 'Worktree path is invalid.';
    }
    if (!_isSafeGitArgument(
      task.baseBranch.trim().isEmpty ? 'main' : task.baseBranch,
    )) {
      return 'Base branch name is invalid.';
    }
    return null;
  }

  static bool _isSafeGitArgument(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty &&
        !normalized.startsWith('-') &&
        !normalized.contains('\u0000') &&
        !normalized.contains('\n') &&
        !normalized.contains('\r');
  }

  static bool _isSafePathArgument(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty &&
        !normalized.contains('\u0000') &&
        !normalized.contains('\n') &&
        !normalized.contains('\r');
  }

  static String _parentPath(String path) {
    final separator = path.contains('\\') && !path.contains('/') ? '\\' : '/';
    final index = path.lastIndexOf(separator);
    if (index <= 0) return '';
    return path.substring(0, index);
  }

  static Future<void> _defaultEnsureParentDirectory(String path) {
    return Directory(path).create(recursive: true);
  }

  static String _stdoutText(ProcessResult result) => result.stdout.toString();
}

String _processErrorText(ProcessResult result, {required String fallback}) {
  final stderr = result.stderr.toString().trim();
  if (stderr.isNotEmpty) {
    return stderr;
  }
  final stdout = result.stdout.toString().trim();
  if (stdout.isNotEmpty) {
    return stdout;
  }
  return fallback;
}
