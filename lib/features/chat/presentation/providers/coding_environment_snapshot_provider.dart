import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef CodingEnvironmentProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

const _gitSnapshotTimeout = Duration(seconds: 5);

final codingEnvironmentProcessRunnerProvider =
    Provider<CodingEnvironmentProcessRunner>((ref) => _defaultProcessRunner);

final codingEnvironmentSnapshotProvider = FutureProvider.autoDispose
    .family<CodingEnvironmentSnapshot, String>((ref, rootPath) async {
      final normalizedRootPath = rootPath.trim();
      if (normalizedRootPath.isEmpty) {
        return const CodingEnvironmentSnapshot.empty();
      }
      final runProcess = ref.watch(codingEnvironmentProcessRunnerProvider);
      return CodingEnvironmentSnapshot.load(
        rootPath: normalizedRootPath,
        runProcess: runProcess,
      );
    });

Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  ).timeout(_gitSnapshotTimeout);
}

class CodingEnvironmentSnapshot {
  const CodingEnvironmentSnapshot({
    required this.rootPath,
    required this.repositoryRoot,
    required this.isGitRepository,
    required this.branchName,
    required this.changedFileCount,
    required this.insertions,
    required this.deletions,
    this.errorMessage,
  });

  const CodingEnvironmentSnapshot.empty()
    : rootPath = '',
      repositoryRoot = null,
      isGitRepository = false,
      branchName = '',
      changedFileCount = 0,
      insertions = 0,
      deletions = 0,
      errorMessage = null;

  final String rootPath;
  final String? repositoryRoot;
  final bool isGitRepository;
  final String branchName;
  final int changedFileCount;
  final int insertions;
  final int deletions;
  final String? errorMessage;

  bool get hasChanges =>
      changedFileCount > 0 || insertions > 0 || deletions > 0;

  String get displayBranchName =>
      branchName.trim().isEmpty ? 'unknown' : branchName.trim();

  static Future<CodingEnvironmentSnapshot> load({
    required String rootPath,
    required CodingEnvironmentProcessRunner runProcess,
  }) async {
    if (!Directory(rootPath).existsSync()) {
      return CodingEnvironmentSnapshot(
        rootPath: rootPath,
        repositoryRoot: null,
        isGitRepository: false,
        branchName: '',
        changedFileCount: 0,
        insertions: 0,
        deletions: 0,
        errorMessage: 'Project folder is unavailable.',
      );
    }

    try {
      final repositoryResult = await runProcess('git', const [
        'rev-parse',
        '--show-toplevel',
      ], workingDirectory: rootPath);
      if (repositoryResult.exitCode != 0) {
        return CodingEnvironmentSnapshot(
          rootPath: rootPath,
          repositoryRoot: null,
          isGitRepository: false,
          branchName: '',
          changedFileCount: 0,
          insertions: 0,
          deletions: 0,
          errorMessage: 'Project is not a git repository.',
        );
      }

      final repositoryRoot = _stdoutText(repositoryResult).trim();
      final branchName = await _loadBranchName(
        rootPath: rootPath,
        runProcess: runProcess,
      );
      final statusResult = await runProcess('git', const [
        'status',
        '--short',
      ], workingDirectory: rootPath);
      final changedFileCount = statusResult.exitCode == 0
          ? _statusFileCount(_stdoutText(statusResult))
          : 0;
      final unstagedDiff = await _loadShortStat(
        rootPath: rootPath,
        runProcess: runProcess,
        arguments: const ['diff', '--shortstat'],
      );
      final stagedDiff = await _loadShortStat(
        rootPath: rootPath,
        runProcess: runProcess,
        arguments: const ['diff', '--cached', '--shortstat'],
      );

      return CodingEnvironmentSnapshot(
        rootPath: rootPath,
        repositoryRoot: repositoryRoot.isEmpty ? rootPath : repositoryRoot,
        isGitRepository: true,
        branchName: branchName,
        changedFileCount: changedFileCount,
        insertions: unstagedDiff.insertions + stagedDiff.insertions,
        deletions: unstagedDiff.deletions + stagedDiff.deletions,
      );
    } on TimeoutException {
      return CodingEnvironmentSnapshot(
        rootPath: rootPath,
        repositoryRoot: null,
        isGitRepository: false,
        branchName: '',
        changedFileCount: 0,
        insertions: 0,
        deletions: 0,
        errorMessage: 'Timed out while reading git state.',
      );
    } catch (error) {
      return CodingEnvironmentSnapshot(
        rootPath: rootPath,
        repositoryRoot: null,
        isGitRepository: false,
        branchName: '',
        changedFileCount: 0,
        insertions: 0,
        deletions: 0,
        errorMessage: 'Could not read git state: $error',
      );
    }
  }

  static Future<String> _loadBranchName({
    required String rootPath,
    required CodingEnvironmentProcessRunner runProcess,
  }) async {
    final branchResult = await runProcess('git', const [
      'branch',
      '--show-current',
    ], workingDirectory: rootPath);
    final branchName = _stdoutText(branchResult).trim();
    if (branchName.isNotEmpty) {
      return branchName;
    }
    final headResult = await runProcess('git', const [
      'rev-parse',
      '--short',
      'HEAD',
    ], workingDirectory: rootPath);
    return _stdoutText(headResult).trim();
  }

  static Future<_GitShortStat> _loadShortStat({
    required String rootPath,
    required CodingEnvironmentProcessRunner runProcess,
    required List<String> arguments,
  }) async {
    final result = await runProcess(
      'git',
      arguments,
      workingDirectory: rootPath,
    );
    if (result.exitCode != 0) {
      return const _GitShortStat();
    }
    return _GitShortStat.parse(_stdoutText(result));
  }

  static int _statusFileCount(String statusOutput) {
    return statusOutput
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .length;
  }

  static String _stdoutText(ProcessResult result) => result.stdout.toString();
}

class _GitShortStat {
  const _GitShortStat({this.insertions = 0, this.deletions = 0});

  final int insertions;
  final int deletions;

  static _GitShortStat parse(String value) {
    return _GitShortStat(
      insertions: _firstInt(value, RegExp(r'(\d+)\s+insertions?\(\+\)')),
      deletions: _firstInt(value, RegExp(r'(\d+)\s+deletions?\(-\)')),
    );
  }

  static int _firstInt(String value, RegExp pattern) {
    final match = pattern.firstMatch(value);
    if (match == null) {
      return 0;
    }
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }
}
