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
    bool syncBase = true,
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
      final localBaseRef = task.baseBranch.trim().isEmpty
          ? 'main'
          : task.baseBranch.trim();
      final baseRef = syncBase
          ? await _resolveBaseRef(
              repositoryRoot: effectiveRoot,
              baseBranch: localBaseRef,
            )
          : localBaseRef;
      final parentPath = _parentPath(task.normalizedWorktreePath);
      if (parentPath.isNotEmpty) {
        await _ensureParentDirectory(parentPath);
      }

      var worktreeResult = await _addWorktree(
        repositoryRoot: effectiveRoot,
        task: task,
        baseRef: baseRef,
      );
      if (worktreeResult.exitCode != 0 && baseRef != localBaseRef) {
        worktreeResult = await _addWorktree(
          repositoryRoot: effectiveRoot,
          task: task,
          baseRef: localBaseRef,
        );
      }
      if (worktreeResult.exitCode != 0) {
        return WorktreeAgentGitWorktreePrepareResult.failed(
          _processErrorText(
            worktreeResult,
            fallback: 'Could not create git worktree.',
          ),
        );
      }
      await _lockWorktree(repositoryRoot: effectiveRoot, task: task);

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

  Future<String> _resolveBaseRef({
    required String repositoryRoot,
    required String baseBranch,
  }) async {
    final upstreamResult = await runProcess('git', [
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '$baseBranch@{upstream}',
    ], workingDirectory: repositoryRoot);
    final upstreamRef = _stdoutText(upstreamResult).trim();
    if (upstreamResult.exitCode == 0 &&
        _isSafeGitArgument(upstreamRef) &&
        upstreamRef.contains('/')) {
      await _fetchRemoteRef(repositoryRoot: repositoryRoot, ref: upstreamRef);
      return upstreamRef;
    }

    final remoteRef = _remoteTrackingRefForBase(baseBranch);
    if (remoteRef != null &&
        await _fetchRemoteRef(repositoryRoot: repositoryRoot, ref: remoteRef)) {
      return remoteRef;
    }
    return baseBranch;
  }

  Future<bool> _fetchRemoteRef({
    required String repositoryRoot,
    required String ref,
  }) async {
    final slashIndex = ref.indexOf('/');
    if (slashIndex <= 0 || slashIndex == ref.length - 1) {
      return false;
    }
    final result = await runProcess('git', [
      'fetch',
      ref.substring(0, slashIndex),
      ref.substring(slashIndex + 1),
    ], workingDirectory: repositoryRoot);
    return result.exitCode == 0;
  }

  Future<ProcessResult> _addWorktree({
    required String repositoryRoot,
    required WorktreeAgentTask task,
    required String baseRef,
  }) {
    return runProcess('git', [
      'worktree',
      'add',
      '-b',
      task.branchName.trim(),
      task.normalizedWorktreePath,
      baseRef,
    ], workingDirectory: repositoryRoot);
  }

  Future<void> _lockWorktree({
    required String repositoryRoot,
    required WorktreeAgentTask task,
  }) async {
    try {
      await runProcess('git', [
        'worktree',
        'lock',
        '--reason',
        'caverno task=${task.id}',
        task.normalizedWorktreePath,
      ], workingDirectory: repositoryRoot);
    } catch (_) {
      // Worktree locks are best-effort; a lock failure should not block coding.
    }
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

  static String? _remoteTrackingRefForBase(String baseBranch) {
    if (baseBranch.startsWith('refs/')) return null;
    if (baseBranch.contains('/')) return baseBranch;
    return 'origin/$baseBranch';
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
