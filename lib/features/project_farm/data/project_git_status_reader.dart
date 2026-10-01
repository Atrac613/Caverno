import 'dart:io';

import '../domain/entities/project_task_git_state.dart';

/// A read-only glance at a project's git state for the dashboard.
final class ProjectGitStatus {
  const ProjectGitStatus({
    required this.branch,
    required this.changedFiles,
    required this.ahead,
    required this.lastCommit,
  });

  final String branch;
  final int changedFiles;

  /// Commits ahead of the upstream, or null when there is no upstream.
  final int? ahead;
  final String lastCommit;
}

typedef GitRunner =
    Future<ProcessResult> Function(List<String> args, String workingDirectory);

/// Reads git state with fixed, read-only commands the app itself issues.
///
/// These are not model tool calls, so they do not pass through the tool
/// approval gate; every argument is a literal, never model- or user-supplied.
final class ProjectGitStatusReader {
  const ProjectGitStatusReader({GitRunner? run}) : _run = run ?? _defaultRun;

  final GitRunner _run;

  static Future<ProcessResult> _defaultRun(
    List<String> args,
    String workingDirectory,
  ) => Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
  ).timeout(const Duration(seconds: 5));

  /// Returns null when [projectRoot] is not a git work tree or git fails.
  Future<ProjectGitStatus?> read(String projectRoot) async {
    try {
      final branch = await _output([
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ], projectRoot);
      if (branch == null) return null;
      final status =
          await _output(['status', '--porcelain'], projectRoot) ?? '';
      final ahead = await _output([
        'rev-list',
        '--count',
        '@{upstream}..HEAD',
      ], projectRoot);
      final lastCommit =
          await _output(['log', '-1', '--format=%h %s'], projectRoot) ?? '';
      return ProjectGitStatus(
        branch: branch,
        changedFiles: status
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .length,
        ahead: ahead == null ? null : int.tryParse(ahead),
        lastCommit: lastCommit,
      );
    } on Object {
      return null;
    }
  }

  /// HEAD and the porcelain status of [paths], for checking that a project
  /// task's commit landed. Returns null when git fails, including for a path
  /// outside the work tree.
  Future<ProjectTaskGitState?> readTaskState(
    String projectRoot,
    List<String> paths,
  ) async {
    try {
      final head = await _output(['rev-parse', 'HEAD'], projectRoot);
      if (head == null) return null;
      final status = paths.isEmpty
          ? ''
          : await _output([
              'status',
              '--porcelain',
              '--',
              ...paths,
            ], projectRoot);
      if (status == null) return null;
      return ProjectTaskGitState(
        head: head,
        dirtyPaths: status
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList(),
      );
    } on Object {
      return null;
    }
  }

  Future<String?> _output(List<String> args, String projectRoot) async {
    final result = await _run(args, projectRoot);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }
}
