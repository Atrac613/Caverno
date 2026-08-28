import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/coding_project.dart';

import 'rag2_git_evidence_collector.dart';
import 'rag2_knowledge_object_replay.dart' show validateRag2RepoRelativePath;
import 'rag2_provenance_attestation_replay.dart';

const rag2BatchGitInventoryContract = 'rag2-batch-git-inventory-contract-v1';
const rag2BatchGitInventorySchema = 'caverno_rag2_batch_git_inventory';
const Duration rag2BatchGitCommandTimeout = Duration(seconds: 10);
const int rag2BatchGitCommandMaxOutputBytes = 4 * 1024 * 1024;
const int rag2BatchGitMaxCandidatePaths = 2048;

final class Rag2BatchGitInventoryCollector {
  Rag2BatchGitInventoryCollector({
    required this.project,
    Rag2GitProcessRunner processRunner = runRag2GitCommand,
    this.commandTimeout = rag2BatchGitCommandTimeout,
    this.maxCommandOutputBytes = rag2BatchGitCommandMaxOutputBytes,
  }) : _processRunner = processRunner;

  final CodingProject project;
  final Rag2GitProcessRunner _processRunner;
  final Duration commandTimeout;
  final int maxCommandOutputBytes;

  Future<Rag2BatchGitInventoryCollection> collect(
    Iterable<String> repoRelativePaths,
  ) async {
    final paths = repoRelativePaths.toList();
    if (project.id.trim().isEmpty) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'project_identity_unavailable',
        requestedPathCount: paths.length,
        commandCount: 0,
      );
    }
    if (paths.isEmpty) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'candidate_paths_unavailable',
        requestedPathCount: 0,
        commandCount: 0,
      );
    }
    if (paths.length > rag2BatchGitMaxCandidatePaths) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'candidate_file_count_exceeded',
        requestedPathCount: paths.length,
        commandCount: 0,
      );
    }
    try {
      for (final path in paths) {
        validateRag2RepoRelativePath(path);
        if (path.contains(RegExp(r'[\x00\r\n]'))) {
          throw const FormatException('Control characters are not supported.');
        }
      }
    } on FormatException {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'repo_relative_path_invalid',
        requestedPathCount: paths.length,
        commandCount: 0,
      );
    }
    if (paths.toSet().length != paths.length) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'candidate_paths_ambiguous',
        requestedPathCount: paths.length,
        commandCount: 0,
      );
    }
    paths.sort();

    var commandCount = 0;
    Future<Rag2GitCommandResult> run(List<String> arguments) async {
      commandCount++;
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

    late final String configuredRoot;
    try {
      configuredRoot = await Directory(
        project.normalizedRootPath,
      ).resolveSymbolicLinks();
    } on FileSystemException {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'project_root_unavailable',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }
    final preflight = await run(const <String>[
      '--literal-pathspecs',
      'rev-parse',
      '--show-toplevel',
    ]);
    final preflightFailure = _transportFailure(
      preflight,
      'batch_git_repository',
    );
    if (preflightFailure != null) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: preflightFailure,
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }
    if (preflight.exitCode != 0) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'batch_git_repository_unavailable',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }
    try {
      final reportedRoot = _decodeSingleLine(preflight.stdoutBytes);
      final canonicalReportedRoot = await Directory(
        reportedRoot,
      ).resolveSymbolicLinks();
      if (canonicalReportedRoot != configuredRoot) {
        return Rag2BatchGitInventoryCollection.rejected(
          reason: 'project_not_repository_root',
          requestedPathCount: paths.length,
          commandCount: commandCount,
        );
      }
    } on FormatException {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'batch_git_repository_output_ambiguous',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    } on FileSystemException {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'batch_git_repository_output_ambiguous',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }

    final statusResult = await run(const <String>[
      '--literal-pathspecs',
      'status',
      '--porcelain=v1',
      '-z',
      '--untracked-files=all',
    ]);
    final statusFailure = _transportFailure(statusResult, 'batch_git_status');
    if (statusFailure != null) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: statusFailure,
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }
    if (statusResult.exitCode != 0) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'batch_git_status_failed',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }

    late final _Rag2BatchStatus status;
    try {
      status = _parseStatus(statusResult.stdoutBytes);
    } on FormatException {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'batch_git_status_ambiguous',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }

    final indexResult = await run(const <String>[
      '--literal-pathspecs',
      'ls-files',
      '--stage',
      '-z',
    ]);
    final indexFailure = _transportFailure(indexResult, 'batch_git_index');
    if (indexFailure != null) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: indexFailure,
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }
    if (indexResult.exitCode != 0) {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'batch_git_index_failed',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }

    late final Map<String, List<_Rag2IndexEntry>> index;
    try {
      index = _parseIndex(indexResult.stdoutBytes);
    } on FormatException {
      return Rag2BatchGitInventoryCollection.rejected(
        reason: 'batch_git_index_ambiguous',
        requestedPathCount: paths.length,
        commandCount: commandCount,
      );
    }

    final evidenceByPath = <String, Rag2GitEvidence>{};
    for (final path in paths) {
      final entries = index[path] ?? const <_Rag2IndexEntry>[];
      final changed = status.changedPaths.contains(path);
      final untracked = status.untrackedPaths.contains(path);
      if (changed && untracked) {
        return Rag2BatchGitInventoryCollection.rejected(
          reason: 'batch_git_state_ambiguous',
          requestedPathCount: paths.length,
          commandCount: commandCount,
        );
      }
      if (entries.isEmpty) {
        if (!untracked || changed) {
          return Rag2BatchGitInventoryCollection.rejected(
            reason: 'batch_git_state_ambiguous',
            requestedPathCount: paths.length,
            commandCount: commandCount,
          );
        }
        evidenceByPath[path] = const Rag2GitEvidence(
          available: true,
          lsFilesExitCode: 1,
          statusPorcelain: '',
          collectedState: Rag2CollectedGitState.untracked,
        );
        continue;
      }
      if (entries.length != 1 || entries.single.stage != 0 || untracked) {
        return Rag2BatchGitInventoryCollection.rejected(
          reason: 'batch_git_state_ambiguous',
          requestedPathCount: paths.length,
          commandCount: commandCount,
        );
      }
      if (changed) {
        evidenceByPath[path] = const Rag2GitEvidence(
          available: true,
          lsFilesExitCode: 0,
          statusPorcelain: '',
          collectedState: Rag2CollectedGitState.modifiedTracked,
        );
        continue;
      }
      final blob = entries.single.blob;
      if (_isZeroObjectId(blob)) {
        return Rag2BatchGitInventoryCollection.rejected(
          reason: 'batch_git_revision_ambiguous',
          requestedPathCount: paths.length,
          commandCount: commandCount,
        );
      }
      evidenceByPath[path] = Rag2GitEvidence(
        available: true,
        lsFilesExitCode: 0,
        statusPorcelain: '',
        headBlobRevision: blob,
        collectedState: Rag2CollectedGitState.cleanTracked,
      );
    }
    return Rag2BatchGitInventoryCollection.collected(
      evidenceByPath: evidenceByPath,
      requestedPathCount: paths.length,
      commandCount: commandCount,
    );
  }
}

final class Rag2BatchGitInventoryCollection {
  const Rag2BatchGitInventoryCollection._({
    required this.decision,
    required this.requestedPathCount,
    required this.commandCount,
    required this.evidenceByPath,
    this.reason,
  });

  factory Rag2BatchGitInventoryCollection.collected({
    required Map<String, Rag2GitEvidence> evidenceByPath,
    required int requestedPathCount,
    required int commandCount,
  }) => Rag2BatchGitInventoryCollection._(
    decision: 'collected',
    requestedPathCount: requestedPathCount,
    commandCount: commandCount,
    evidenceByPath: Map.unmodifiable(evidenceByPath),
  );

  factory Rag2BatchGitInventoryCollection.rejected({
    required String reason,
    required int requestedPathCount,
    required int commandCount,
  }) => Rag2BatchGitInventoryCollection._(
    decision: 'rejected',
    requestedPathCount: requestedPathCount,
    commandCount: commandCount,
    evidenceByPath: const {},
    reason: reason,
  );

  final String decision;
  final String? reason;
  final int requestedPathCount;
  final int commandCount;
  final Map<String, Rag2GitEvidence> evidenceByPath;

  Map<String, Object?> toJson() {
    final stateCounts = <String, int>{
      for (final state in Rag2CollectedGitState.values) state.name: 0,
    };
    for (final evidence in evidenceByPath.values) {
      final state = evidence.collectedState;
      if (state != null) stateCounts[state.name] = stateCounts[state.name]! + 1;
    }
    return {
      'schemaName': rag2BatchGitInventorySchema,
      'schemaVersion': 1,
      'contract': rag2BatchGitInventoryContract,
      'contractDecision': decision == 'collected' ? 'go' : 'no_go',
      'inventoryDecision': decision,
      'manifestIntegrationDecision': 'not_evaluated',
      'storageDecision': 'not_evaluated',
      'productionDecision': 'no_go',
      'requestedPathCount': requestedPathCount,
      'collectedPathCount': evidenceByPath.length,
      'commandCount': commandCount,
      'stateCounts': stateCounts,
      if (reason != null) 'failureReason': reason,
    };
  }
}

final class _Rag2BatchStatus {
  const _Rag2BatchStatus({
    required this.changedPaths,
    required this.untrackedPaths,
  });

  final Set<String> changedPaths;
  final Set<String> untrackedPaths;
}

final class _Rag2IndexEntry {
  const _Rag2IndexEntry({required this.blob, required this.stage});

  final String blob;
  final int stage;
}

_Rag2BatchStatus _parseStatus(List<int> bytes) {
  if (bytes.isEmpty) {
    return const _Rag2BatchStatus(changedPaths: {}, untrackedPaths: {});
  }
  final output = utf8.decode(bytes, allowMalformed: false);
  if (!output.endsWith('\u0000')) {
    throw const FormatException('Status output must be NUL terminated.');
  }
  final records = output.split('\u0000')..removeLast();
  final changed = <String>{};
  final untracked = <String>{};
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    if (record.length < 4 || record.codeUnitAt(2) != 0x20) {
      throw const FormatException('Malformed porcelain status record.');
    }
    final code = record.substring(0, 2);
    final path = record.substring(3);
    if (path.isEmpty || code == '!!') {
      throw const FormatException('Unsupported porcelain status record.');
    }
    final isRenameOrCopy = code.contains('R') || code.contains('C');
    if (isRenameOrCopy) {
      if (++index >= records.length || records[index].isEmpty) {
        throw const FormatException('Rename source path is unavailable.');
      }
    }
    final target = code == '??' ? untracked : changed;
    if (!target.add(path) ||
        changed.contains(path) && untracked.contains(path)) {
      throw const FormatException('Status path is ambiguous.');
    }
  }
  return _Rag2BatchStatus(changedPaths: changed, untrackedPaths: untracked);
}

Map<String, List<_Rag2IndexEntry>> _parseIndex(List<int> bytes) {
  if (bytes.isEmpty) return const {};
  final output = utf8.decode(bytes, allowMalformed: false);
  if (!output.endsWith('\u0000')) {
    throw const FormatException('Index output must be NUL terminated.');
  }
  final result = <String, List<_Rag2IndexEntry>>{};
  final records = output.split('\u0000')..removeLast();
  final metadataPattern = RegExp(
    r'^[0-7]{6} ([0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?) ([0-3])$',
  );
  for (final record in records) {
    final tab = record.indexOf('\t');
    if (tab <= 0 || tab == record.length - 1) {
      throw const FormatException('Malformed index record.');
    }
    final metadata = metadataPattern.firstMatch(record.substring(0, tab));
    if (metadata == null) {
      throw const FormatException('Malformed index metadata.');
    }
    final path = record.substring(tab + 1);
    final entry = _Rag2IndexEntry(
      blob: metadata.group(1)!.toLowerCase(),
      stage: int.parse(metadata.group(2)!),
    );
    result.putIfAbsent(path, () => []).add(entry);
  }
  return result;
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

bool _isZeroObjectId(String value) =>
    value.codeUnits.every((unit) => unit == 48);
