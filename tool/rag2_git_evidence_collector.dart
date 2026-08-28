import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';

import 'rag2_knowledge_object_replay.dart' show validateRag2RepoRelativePath;
import 'rag2_provenance_attestation_replay.dart';

const rag2GitEvidenceCollectorContract =
    'rag2-git-evidence-collector-contract-v1';
const Duration rag2GitCommandTimeout = Duration(seconds: 5);
const int rag2GitCommandMaxOutputBytes = 64 * 1024;

typedef Rag2GitProcessRunner =
    Future<Rag2GitCommandResult> Function({
      required List<String> arguments,
      required String workingDirectory,
      required Duration timeout,
      required int maxOutputBytes,
    });

final class Rag2GitCommandResult {
  const Rag2GitCommandResult({
    required this.started,
    required this.exitCode,
    required this.stdoutBytes,
    required this.stderrBytes,
    required this.timedOut,
    required this.outputLimitExceeded,
  });

  factory Rag2GitCommandResult.startFailed() => const Rag2GitCommandResult(
    started: false,
    exitCode: -1,
    stdoutBytes: <int>[],
    stderrBytes: <int>[],
    timedOut: false,
    outputLimitExceeded: false,
  );

  final bool started;
  final int exitCode;
  final List<int> stdoutBytes;
  final List<int> stderrBytes;
  final bool timedOut;
  final bool outputLimitExceeded;
}

Future<Rag2GitCommandResult> runRag2GitCommand({
  required List<String> arguments,
  required String workingDirectory,
  required Duration timeout,
  required int maxOutputBytes,
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
  }
  if (maxOutputBytes <= 0) {
    throw ArgumentError.value(
      maxOutputBytes,
      'maxOutputBytes',
      'Must be positive.',
    );
  }

  late final Process process;
  try {
    process = await Process.start(
      'git',
      arguments,
      workingDirectory: workingDirectory,
      environment: const {'LANG': 'C', 'LC_ALL': 'C'},
      includeParentEnvironment: true,
      runInShell: false,
    );
  } on ProcessException {
    return Rag2GitCommandResult.startFailed();
  }

  final stdout = BytesBuilder(copy: false);
  final stderr = BytesBuilder(copy: false);
  var storedBytes = 0;
  var outputLimitExceeded = false;

  Future<void> drain(Stream<List<int>> stream, BytesBuilder target) async {
    await for (final chunk in stream) {
      final remaining = maxOutputBytes - storedBytes;
      if (remaining > 0) {
        final retained = math.min(remaining, chunk.length);
        target.add(chunk.sublist(0, retained));
        storedBytes += retained;
      }
      if (chunk.length > remaining) {
        outputLimitExceeded = true;
        process.kill(ProcessSignal.sigkill);
      }
    }
  }

  final stdoutFuture = drain(process.stdout, stdout);
  final stderrFuture = drain(process.stderr, stderr);
  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  await Future.wait([stdoutFuture, stderrFuture]);
  return Rag2GitCommandResult(
    started: true,
    exitCode: exitCode,
    stdoutBytes: stdout.takeBytes(),
    stderrBytes: stderr.takeBytes(),
    timedOut: timedOut,
    outputLimitExceeded: outputLimitExceeded,
  );
}

final class Rag2GitEvidenceCollector {
  Rag2GitEvidenceCollector({
    required this.project,
    Rag2GitProcessRunner processRunner = runRag2GitCommand,
    this.commandTimeout = rag2GitCommandTimeout,
    this.maxCommandOutputBytes = rag2GitCommandMaxOutputBytes,
  }) : _processRunner = processRunner;

  final CodingProject project;
  final Rag2GitProcessRunner _processRunner;
  final Duration commandTimeout;
  final int maxCommandOutputBytes;
  Future<_Rag2RepositoryPreflight>? _preflight;

  Future<Rag2GitEvidenceCollection> collect(String repoRelativePath) async {
    if (project.id.trim().isEmpty) {
      return Rag2GitEvidenceCollection.rejected(
        reason: 'project_identity_unavailable',
      );
    }
    try {
      validateRag2RepoRelativePath(repoRelativePath);
      if (repoRelativePath.contains(RegExp(r'[\x00\r\n]'))) {
        throw const FormatException('Control characters are not supported.');
      }
    } on FormatException {
      return Rag2GitEvidenceCollection.rejected(
        reason: 'repo_relative_path_invalid',
      );
    }

    final preflight = await (_preflight ??= _runPreflight());
    if (!preflight.isReady) {
      return Rag2GitEvidenceCollection.rejected(reason: preflight.reason!);
    }

    final status = await _run(<String>[
      '--literal-pathspecs',
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
      '--',
      repoRelativePath,
    ]);
    final statusFailure = _transportFailure(status, 'git_status');
    if (statusFailure != null) {
      return Rag2GitEvidenceCollection.rejected(reason: statusFailure);
    }
    if (status.exitCode != 0) {
      return Rag2GitEvidenceCollection.rejected(reason: 'git_status_failed');
    }

    late final _Rag2GitPathStatus pathStatus;
    try {
      pathStatus = _parseStatus(status.stdoutBytes, repoRelativePath);
    } on FormatException {
      return Rag2GitEvidenceCollection.rejected(reason: 'git_status_ambiguous');
    }

    final tracked = await _run(<String>[
      '--literal-pathspecs',
      'ls-files',
      '-z',
      '--error-unmatch',
      '--',
      repoRelativePath,
    ]);
    final trackedFailure = _transportFailure(tracked, 'git_ls_files');
    if (trackedFailure != null) {
      return Rag2GitEvidenceCollection.rejected(reason: trackedFailure);
    }
    if (tracked.exitCode != 0 && tracked.exitCode != 1) {
      return Rag2GitEvidenceCollection.rejected(reason: 'git_ls_files_failed');
    }

    try {
      _validateTrackedOutput(
        tracked.stdoutBytes,
        repoRelativePath,
        isTracked: tracked.exitCode == 0,
      );
    } on FormatException {
      return Rag2GitEvidenceCollection.rejected(
        reason: 'git_ls_files_ambiguous',
      );
    }

    if (tracked.exitCode == 1) {
      if (pathStatus != _Rag2GitPathStatus.untracked) {
        return Rag2GitEvidenceCollection.rejected(
          reason: 'git_state_ambiguous',
        );
      }
      return Rag2GitEvidenceCollection.collected(
        state: Rag2CollectedGitState.untracked,
        evidence: const Rag2GitEvidence(
          available: true,
          lsFilesExitCode: 1,
          statusPorcelain: '',
          collectedState: Rag2CollectedGitState.untracked,
        ),
      );
    }

    if (pathStatus == _Rag2GitPathStatus.untracked) {
      return Rag2GitEvidenceCollection.rejected(reason: 'git_state_ambiguous');
    }
    if (pathStatus == _Rag2GitPathStatus.changed) {
      return Rag2GitEvidenceCollection.collected(
        state: Rag2CollectedGitState.modifiedTracked,
        evidence: const Rag2GitEvidence(
          available: true,
          lsFilesExitCode: 0,
          statusPorcelain: '',
          collectedState: Rag2CollectedGitState.modifiedTracked,
        ),
      );
    }

    final revision = await _run(<String>[
      '--literal-pathspecs',
      'rev-parse',
      '--verify',
      'HEAD:$repoRelativePath',
    ]);
    final revisionFailure = _transportFailure(revision, 'git_revision');
    if (revisionFailure != null) {
      return Rag2GitEvidenceCollection.rejected(reason: revisionFailure);
    }
    if (revision.exitCode != 0) {
      return Rag2GitEvidenceCollection.rejected(reason: 'git_revision_failed');
    }
    late final String blob;
    try {
      blob = _decodeSingleLine(revision.stdoutBytes);
    } on FormatException {
      return Rag2GitEvidenceCollection.rejected(
        reason: 'git_revision_ambiguous',
      );
    }
    if (!RegExp(r'^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$').hasMatch(blob)) {
      return Rag2GitEvidenceCollection.rejected(
        reason: 'git_revision_ambiguous',
      );
    }
    return Rag2GitEvidenceCollection.collected(
      state: Rag2CollectedGitState.cleanTracked,
      evidence: Rag2GitEvidence(
        available: true,
        lsFilesExitCode: 0,
        statusPorcelain: '',
        headBlobRevision: blob.toLowerCase(),
        collectedState: Rag2CollectedGitState.cleanTracked,
      ),
    );
  }

  Future<_Rag2RepositoryPreflight> _runPreflight() async {
    late final String configuredRoot;
    try {
      configuredRoot = await Directory(
        project.normalizedRootPath,
      ).resolveSymbolicLinks();
    } on FileSystemException {
      return const _Rag2RepositoryPreflight.rejected(
        'project_root_unavailable',
      );
    }
    final result = await _run(const <String>[
      '--literal-pathspecs',
      'rev-parse',
      '--show-toplevel',
    ]);
    final failure = _transportFailure(result, 'git_repository');
    if (failure != null) {
      return _Rag2RepositoryPreflight.rejected(failure);
    }
    if (result.exitCode != 0) {
      return const _Rag2RepositoryPreflight.rejected(
        'git_repository_unavailable',
      );
    }
    late final String reportedRoot;
    try {
      reportedRoot = _decodeSingleLine(result.stdoutBytes);
      final canonicalReportedRoot = await Directory(
        reportedRoot,
      ).resolveSymbolicLinks();
      if (canonicalReportedRoot != configuredRoot) {
        return const _Rag2RepositoryPreflight.rejected(
          'project_not_repository_root',
        );
      }
    } on FormatException {
      return const _Rag2RepositoryPreflight.rejected(
        'git_repository_output_ambiguous',
      );
    } on FileSystemException {
      return const _Rag2RepositoryPreflight.rejected(
        'git_repository_output_ambiguous',
      );
    }
    return const _Rag2RepositoryPreflight.ready();
  }

  Future<Rag2GitCommandResult> _run(List<String> arguments) async {
    try {
      return await _processRunner(
        arguments: arguments,
        workingDirectory: project.normalizedRootPath,
        timeout: commandTimeout,
        maxOutputBytes: maxCommandOutputBytes,
      );
    } on Object {
      return Rag2GitCommandResult.startFailed();
    }
  }
}

final class Rag2GitEvidenceCollection {
  const Rag2GitEvidenceCollection._({
    required this.decision,
    this.state,
    this.evidence,
    this.reason,
  });

  factory Rag2GitEvidenceCollection.collected({
    required Rag2CollectedGitState state,
    required Rag2GitEvidence evidence,
  }) => Rag2GitEvidenceCollection._(
    decision: 'collected',
    state: state,
    evidence: evidence,
  );

  factory Rag2GitEvidenceCollection.rejected({required String reason}) =>
      Rag2GitEvidenceCollection._(decision: 'rejected', reason: reason);

  final String decision;
  final Rag2CollectedGitState? state;
  final Rag2GitEvidence? evidence;
  final String? reason;
}

enum _Rag2GitPathStatus { clean, changed, untracked }

final class _Rag2RepositoryPreflight {
  const _Rag2RepositoryPreflight.ready() : isReady = true, reason = null;

  const _Rag2RepositoryPreflight.rejected(this.reason) : isReady = false;

  final bool isReady;
  final String? reason;
}

String? _transportFailure(Rag2GitCommandResult result, String command) {
  if (!result.started) return '${command}_unavailable';
  if (result.timedOut) return '${command}_timeout';
  if (result.outputLimitExceeded) return '${command}_output_exceeded';
  return null;
}

String _decodeSingleLine(List<int> bytes) {
  var value = utf8.decode(bytes, allowMalformed: false);
  if (value.endsWith('\n')) value = value.substring(0, value.length - 1);
  if (value.endsWith('\r')) value = value.substring(0, value.length - 1);
  if (value.isEmpty || value.contains(RegExp(r'[\x00\r\n]'))) {
    throw const FormatException('Expected exactly one output line.');
  }
  return value;
}

_Rag2GitPathStatus _parseStatus(List<int> bytes, String repoRelativePath) {
  if (bytes.isEmpty) return _Rag2GitPathStatus.clean;
  final output = utf8.decode(bytes, allowMalformed: false);
  if (!output.endsWith('\u0000')) {
    throw const FormatException('Status output must be NUL terminated.');
  }
  final records = output.split('\u0000')..removeLast();
  if (records.isEmpty || records.first.isEmpty) {
    throw const FormatException('Status contains an empty record.');
  }
  final first = records.removeAt(0);
  if (first.length < 4 || first.codeUnitAt(2) != 0x20) {
    throw const FormatException('Malformed porcelain status record.');
  }
  final code = first.substring(0, 2);
  if (first.substring(3) != repoRelativePath) {
    throw const FormatException('Status record targets another path.');
  }
  final isRenameOrCopy = code.contains('R') || code.contains('C');
  if (isRenameOrCopy) {
    if (records.isEmpty || records.removeAt(0).isEmpty) {
      throw const FormatException('Rename source path is unavailable.');
    }
  }
  if (records.isNotEmpty) {
    throw const FormatException('Status contains unexpected records.');
  }
  return code == '??'
      ? _Rag2GitPathStatus.untracked
      : _Rag2GitPathStatus.changed;
}

void _validateTrackedOutput(
  List<int> bytes,
  String repoRelativePath, {
  required bool isTracked,
}) {
  if (!isTracked) {
    if (bytes.isNotEmpty) {
      throw const FormatException('Untracked lookup returned output.');
    }
    return;
  }
  final output = utf8.decode(bytes, allowMalformed: false);
  if (output != '$repoRelativePath\u0000') {
    throw const FormatException('Tracked lookup targets another path.');
  }
}
