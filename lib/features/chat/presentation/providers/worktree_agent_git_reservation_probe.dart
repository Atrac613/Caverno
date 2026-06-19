import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/worktree_agent_task.dart';
import 'coding_environment_snapshot_provider.dart';

class WorktreeAgentGitReservations {
  const WorktreeAgentGitReservations({
    required this.branchNames,
    required this.worktreePaths,
    this.errorMessage,
  });

  const WorktreeAgentGitReservations.empty()
    : branchNames = const <String>[],
      worktreePaths = const <String>[],
      errorMessage = null;

  final List<String> branchNames;
  final List<String> worktreePaths;
  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

final worktreeAgentGitReservationProbeProvider =
    Provider<WorktreeAgentGitReservationProbe>((ref) {
      return WorktreeAgentGitReservationProbe(
        runProcess: ref.watch(codingEnvironmentProcessRunnerProvider),
      );
    });

class WorktreeAgentGitReservationProbe {
  const WorktreeAgentGitReservationProbe({required this.runProcess});

  final CodingEnvironmentProcessRunner runProcess;

  Future<WorktreeAgentGitReservations> load(String projectRootPath) async {
    final rootPath = projectRootPath.trim();
    if (rootPath.isEmpty) {
      return const WorktreeAgentGitReservations(
        branchNames: [],
        worktreePaths: [],
        errorMessage: 'Project root path is required.',
      );
    }

    try {
      final repositoryResult = await runProcess('git', const [
        'rev-parse',
        '--show-toplevel',
      ], workingDirectory: rootPath);
      if (repositoryResult.exitCode != 0) {
        return WorktreeAgentGitReservations(
          branchNames: const [],
          worktreePaths: const [],
          errorMessage: _processErrorText(
            repositoryResult,
            fallback: 'Project is not a git repository.',
          ),
        );
      }

      final repositoryRoot = _stdoutText(repositoryResult).trim();
      final effectiveRoot = repositoryRoot.isEmpty ? rootPath : repositoryRoot;
      final branchResult = await runProcess('git', const [
        'for-each-ref',
        '--format=%(refname:short)',
        'refs/heads',
      ], workingDirectory: effectiveRoot);
      if (branchResult.exitCode != 0) {
        return WorktreeAgentGitReservations(
          branchNames: const [],
          worktreePaths: const [],
          errorMessage: _processErrorText(
            branchResult,
            fallback: 'Could not read git branches.',
          ),
        );
      }

      final worktreeResult = await runProcess('git', const [
        'worktree',
        'list',
        '--porcelain',
      ], workingDirectory: effectiveRoot);
      if (worktreeResult.exitCode != 0) {
        return WorktreeAgentGitReservations(
          branchNames: const [],
          worktreePaths: const [],
          errorMessage: _processErrorText(
            worktreeResult,
            fallback: 'Could not read git worktrees.',
          ),
        );
      }

      return WorktreeAgentGitReservations(
        branchNames: _parseBranchNames(_stdoutText(branchResult)),
        worktreePaths: _parseWorktreePaths(_stdoutText(worktreeResult)),
      );
    } on TimeoutException {
      return const WorktreeAgentGitReservations(
        branchNames: [],
        worktreePaths: [],
        errorMessage: 'Timed out while reading git worktree reservations.',
      );
    } catch (error) {
      return WorktreeAgentGitReservations(
        branchNames: const [],
        worktreePaths: const [],
        errorMessage: 'Could not read git worktree reservations: $error',
      );
    }
  }

  static List<String> _parseBranchNames(String output) {
    final branches =
        output
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return List.unmodifiable(branches);
  }

  static List<String> _parseWorktreePaths(String output) {
    final paths =
        output
            .split(RegExp(r'\r?\n'))
            .where((line) => line.startsWith('worktree '))
            .map((line) => line.substring('worktree '.length).trim())
            .map(WorktreeAgentTask.normalizeWorktreePath)
            .where((path) => path.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return List.unmodifiable(paths);
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
