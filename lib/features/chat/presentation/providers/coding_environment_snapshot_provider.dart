import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/turn_diff.dart';
import '../../domain/services/turn_diff_service.dart';

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

final codingWorktreeDiffProvider = FutureProvider.autoDispose
    .family<TurnDiff?, String>((ref, rootPath) async {
      final normalizedRootPath = rootPath.trim();
      if (normalizedRootPath.isEmpty || !_isDesktopPlatform) {
        return null;
      }
      final runProcess = ref.watch(codingEnvironmentProcessRunnerProvider);
      return CodingWorktreeDiffLoader.load(
        rootPath: normalizedRootPath,
        runProcess: runProcess,
      );
    });

final codingGitBranchListProvider = FutureProvider.autoDispose
    .family<CodingGitBranchList, String>((ref, rootPath) async {
      final normalizedRootPath = rootPath.trim();
      if (normalizedRootPath.isEmpty || !_isDesktopPlatform) {
        return const CodingGitBranchList.empty();
      }
      final runProcess = ref.watch(codingEnvironmentProcessRunnerProvider);
      return CodingGitBranchList.load(
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

bool get _isDesktopPlatform =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;

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

class CodingGitBranchList {
  const CodingGitBranchList({required this.branches, this.errorMessage});

  const CodingGitBranchList.empty() : branches = const [], errorMessage = null;

  final List<String> branches;
  final String? errorMessage;

  bool get hasBranches => branches.isNotEmpty;

  static Future<CodingGitBranchList> load({
    required String rootPath,
    required CodingEnvironmentProcessRunner runProcess,
  }) async {
    if (!Directory(rootPath).existsSync()) {
      return const CodingGitBranchList(
        branches: [],
        errorMessage: 'Project folder is unavailable.',
      );
    }

    try {
      final repositoryResult = await runProcess('git', const [
        'rev-parse',
        '--show-toplevel',
      ], workingDirectory: rootPath);
      if (repositoryResult.exitCode != 0) {
        return const CodingGitBranchList(
          branches: [],
          errorMessage: 'Project is not a git repository.',
        );
      }

      final branchResult = await runProcess('git', const [
        'for-each-ref',
        '--format=%(refname:short)',
        'refs/heads',
      ], workingDirectory: rootPath);
      if (branchResult.exitCode != 0) {
        return CodingGitBranchList(
          branches: const [],
          errorMessage: _processErrorText(
            branchResult,
            fallback: 'Could not read git branches.',
          ),
        );
      }

      final branches =
          _stdoutText(branchResult)
              .split(RegExp(r'\r?\n'))
              .map((branch) => branch.trim())
              .where((branch) => branch.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      return CodingGitBranchList(branches: List.unmodifiable(branches));
    } on TimeoutException {
      return const CodingGitBranchList(
        branches: [],
        errorMessage: 'Timed out while reading git branches.',
      );
    } catch (error) {
      return CodingGitBranchList(
        branches: const [],
        errorMessage: 'Could not read git branches: $error',
      );
    }
  }

  static String _stdoutText(ProcessResult result) => result.stdout.toString();
}

class CodingGitBranchCheckoutResult {
  const CodingGitBranchCheckoutResult({
    required this.branchName,
    required this.success,
    this.errorMessage,
  });

  final String branchName;
  final bool success;
  final String? errorMessage;

  static CodingGitBranchCheckoutResult succeeded(String branchName) {
    return CodingGitBranchCheckoutResult(branchName: branchName, success: true);
  }

  static CodingGitBranchCheckoutResult failed(
    String branchName,
    String errorMessage,
  ) {
    return CodingGitBranchCheckoutResult(
      branchName: branchName,
      success: false,
      errorMessage: errorMessage,
    );
  }
}

class CodingGitBranchCheckout {
  CodingGitBranchCheckout._();

  static Future<CodingGitBranchCheckoutResult> checkout({
    required String rootPath,
    required String branchName,
    required CodingEnvironmentProcessRunner runProcess,
  }) async {
    final normalizedBranchName = branchName.trim();
    if (!_isValidBranchNameForCheckout(normalizedBranchName)) {
      return CodingGitBranchCheckoutResult.failed(
        normalizedBranchName,
        'Branch name is invalid.',
      );
    }
    if (!Directory(rootPath).existsSync()) {
      return CodingGitBranchCheckoutResult.failed(
        normalizedBranchName,
        'Project folder is unavailable.',
      );
    }

    final branchList = await CodingGitBranchList.load(
      rootPath: rootPath,
      runProcess: runProcess,
    );
    if (!branchList.branches.contains(normalizedBranchName)) {
      return CodingGitBranchCheckoutResult.failed(
        normalizedBranchName,
        branchList.errorMessage ?? 'Branch does not exist locally.',
      );
    }

    try {
      final checkoutResult = await runProcess('git', [
        'checkout',
        normalizedBranchName,
      ], workingDirectory: rootPath);
      if (checkoutResult.exitCode != 0) {
        return CodingGitBranchCheckoutResult.failed(
          normalizedBranchName,
          _processErrorText(
            checkoutResult,
            fallback: 'Could not switch git branches.',
          ),
        );
      }

      return CodingGitBranchCheckoutResult.succeeded(normalizedBranchName);
    } on TimeoutException {
      return CodingGitBranchCheckoutResult.failed(
        normalizedBranchName,
        'Timed out while switching git branches.',
      );
    } catch (error) {
      return CodingGitBranchCheckoutResult.failed(
        normalizedBranchName,
        'Could not switch git branches: $error',
      );
    }
  }

  static bool _isValidBranchNameForCheckout(String branchName) {
    return branchName.isNotEmpty &&
        !branchName.startsWith('-') &&
        !branchName.contains('\u0000') &&
        !branchName.contains('\n') &&
        !branchName.contains('\r');
  }
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

class CodingWorktreeDiffLoader {
  CodingWorktreeDiffLoader._();

  static Future<TurnDiff?> load({
    required String rootPath,
    required CodingEnvironmentProcessRunner runProcess,
  }) async {
    if (!Directory(rootPath).existsSync()) {
      return null;
    }

    try {
      final repositoryResult = await runProcess('git', const [
        'rev-parse',
        '--show-toplevel',
      ], workingDirectory: rootPath);
      if (repositoryResult.exitCode != 0) {
        return null;
      }

      final repositoryRoot = _stdoutText(repositoryResult).trim();
      final effectiveRoot = repositoryRoot.isEmpty ? rootPath : repositoryRoot;
      final trackedFiles = await _loadTrackedFiles(
        rootPath: rootPath,
        runProcess: runProcess,
      );
      final untrackedFiles = await _loadUntrackedFiles(
        rootPath: rootPath,
        repositoryRoot: effectiveRoot,
        runProcess: runProcess,
      );

      return TurnDiffService.buildTurnDiff(
        id: 'git_worktree:${effectiveRoot.hashCode}',
        assistantMessageId: 'git_worktree',
        userPrompt: 'Uncommitted changes (git diff HEAD)',
        timestamp: DateTime.now(),
        source: TurnDiffSource.git,
        files: [...trackedFiles, ...untrackedFiles],
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<TurnDiffFile>> _loadTrackedFiles({
    required String rootPath,
    required CodingEnvironmentProcessRunner runProcess,
  }) async {
    final numstatResult = await runProcess('git', const [
      'diff',
      '--numstat',
      'HEAD',
      '--',
    ], workingDirectory: rootPath);
    if (numstatResult.exitCode != 0) {
      return const [];
    }

    final patchResult = await runProcess('git', const [
      'diff',
      '--no-ext-diff',
      '--unified=3',
      'HEAD',
      '--',
    ], workingDirectory: rootPath);
    final patchOutput = patchResult.exitCode == 0
        ? _stdoutText(patchResult)
        : '';
    return TurnDiffService.buildGitFiles(
      numstatOutput: _stdoutText(numstatResult),
      patchOutput: patchOutput,
    );
  }

  static Future<List<TurnDiffFile>> _loadUntrackedFiles({
    required String rootPath,
    required String repositoryRoot,
    required CodingEnvironmentProcessRunner runProcess,
  }) async {
    final result = await runProcess('git', const [
      'ls-files',
      '--others',
      '--exclude-standard',
      '-z',
    ], workingDirectory: rootPath);
    if (result.exitCode != 0) {
      return const [];
    }

    final files = <TurnDiffFile>[];
    final paths =
        _stdoutText(result)
            .split('\u0000')
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false)
          ..sort();
    for (final path in paths) {
      final file = _fileFromGitPath(repositoryRoot, path);
      final entityType = FileSystemEntity.typeSync(file.path);
      if (entityType != FileSystemEntityType.file) {
        continue;
      }
      final fileLength = file.lengthSync();
      if (fileLength > TurnDiffService.maxTextFileBytes) {
        files.add(
          TurnDiffFile(
            filePath: path,
            isLargeFile: true,
            isUntracked: true,
            note: 'Untracked file is too large to render.',
          ),
        );
        continue;
      }

      try {
        final content = utf8.decode(await file.readAsBytes());
        final diff = TurnDiffService.buildFileDiff(
          filePath: path,
          oldContent: null,
          newContent: content,
          oldExists: false,
          newExists: true,
          isUntracked: true,
        )?.file;
        if (diff != null) {
          files.add(diff);
        }
      } on FormatException {
        files.add(
          TurnDiffFile(
            filePath: path,
            isBinary: true,
            isUntracked: true,
            note: 'Untracked file is not valid UTF-8 text.',
          ),
        );
      } on FileSystemException {
        continue;
      }
    }
    return files;
  }

  static File _fileFromGitPath(String repositoryRoot, String path) {
    final localPath = path
        .split('/')
        .where((part) => part.isNotEmpty)
        .join(Platform.pathSeparator);
    return File(
      '${Directory(repositoryRoot).absolute.path}${Platform.pathSeparator}$localPath',
    );
  }

  static String _stdoutText(ProcessResult result) => result.stdout.toString();
}
