import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../domain/entities/routine.dart';

typedef RoutineVerificationCommandRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

class RoutineObjectiveEvidenceCollection {
  const RoutineObjectiveEvidenceCollection({
    required this.verification,
    required this.changedFiles,
    required this.changedFileEvidenceTruncated,
    required this.implementationEvidence,
  });

  final RoutineRunMechanicalVerification verification;
  final List<RoutineRunChangedFileEvidence> changedFiles;
  final bool changedFileEvidenceTruncated;
  final List<String> implementationEvidence;
}

/// Captures bounded producer-owned evidence after a scheduled Routine run.
class RoutineObjectiveEvidenceCollector {
  RoutineObjectiveEvidenceCollector({
    RoutineVerificationCommandRunner? commandRunner,
    this.maxFileBytes = 64000,
    this.maxTotalBytes = 128000,
  }) : _commandRunner = commandRunner ?? _runCommand;

  final RoutineVerificationCommandRunner _commandRunner;
  final int maxFileBytes;
  final int maxTotalBytes;

  Future<RoutineObjectiveEvidenceCollection?> collect({
    required Routine routine,
    required List<RoutineRunToolCall> toolCalls,
    required String implementationOutput,
  }) async {
    final contract = routine.objectiveEvidenceContract;
    final workspace = routine.trimmedWorkspaceDirectory;
    if (contract == null ||
        workspace.isEmpty ||
        contract.objective.trim().isEmpty ||
        contract.acceptanceCriteria.isEmpty ||
        contract.verificationCommand.trim().isEmpty) {
      return null;
    }
    final args = _splitCommand(contract.verificationCommand);
    if (args.isEmpty || _hasControlOperator(contract.verificationCommand)) {
      return null;
    }

    ProcessResult verificationResult;
    try {
      verificationResult = await _commandRunner(
        args.first,
        args.skip(1).toList(growable: false),
        workspace,
      );
    } catch (error) {
      verificationResult = ProcessResult(0, 127, '', error.toString());
    }
    final captured = await _captureChangedFiles(workspace, toolCalls);
    final output = [
      verificationResult.stdout.toString().trim(),
      verificationResult.stderr.toString().trim(),
    ].where((part) => part.isNotEmpty).join('\n');
    final implementation = implementationOutput.trim();
    return RoutineObjectiveEvidenceCollection(
      verification: RoutineRunMechanicalVerification(
        command: contract.verificationCommand.trim(),
        exitCode: verificationResult.exitCode,
        output: _clip(output, 12000),
      ),
      changedFiles: captured.files,
      changedFileEvidenceTruncated: captured.truncated,
      implementationEvidence: [
        if (implementation.isNotEmpty) _clip(implementation, 4000),
        'Captured ${captured.files.length} workspace file(s) from '
            '${toolCalls.length} recorded tool call(s).',
      ],
    );
  }

  Future<({List<RoutineRunChangedFileEvidence> files, bool truncated})>
  _captureChangedFiles(
    String workspace,
    List<RoutineRunToolCall> toolCalls,
  ) async {
    final workspaceDirectory = Directory(workspace).absolute;
    final lexicalWorkspacePath = workspaceDirectory.path;
    String resolvedWorkspacePath;
    try {
      resolvedWorkspacePath = await workspaceDirectory.resolveSymbolicLinks();
    } catch (_) {
      return (files: const <RoutineRunChangedFileEvidence>[], truncated: true);
    }
    final paths = <String>{};
    for (final call in toolCalls) {
      if (call.name != 'write_file' && call.name != 'edit_file') continue;
      try {
        final decoded = jsonDecode(call.arguments);
        if (decoded is! Map || decoded['path'] is! String) continue;
        final raw = (decoded['path'] as String).trim();
        final absolute = path.isAbsolute(raw)
            ? File(raw).absolute.path
            : File(
                '$lexicalWorkspacePath/${raw.replaceAll('\\', '/')}',
              ).absolute.path;
        if (absolute == lexicalWorkspacePath ||
            !absolute.startsWith(
              '$lexicalWorkspacePath${Platform.pathSeparator}',
            )) {
          return (
            files: const <RoutineRunChangedFileEvidence>[],
            truncated: true,
          );
        }
        paths.add(absolute);
      } catch (_) {
        return (
          files: const <RoutineRunChangedFileEvidence>[],
          truncated: true,
        );
      }
    }

    var totalBytes = 0;
    var truncated = false;
    final files = <RoutineRunChangedFileEvidence>[];
    for (final absolute in paths.toList()..sort()) {
      final file = File(absolute);
      if (!await file.exists()) {
        truncated = true;
        continue;
      }
      String resolved;
      try {
        resolved = await file.resolveSymbolicLinks();
      } catch (_) {
        truncated = true;
        continue;
      }
      if (!resolved.startsWith(
        '$resolvedWorkspacePath${Platform.pathSeparator}',
      )) {
        truncated = true;
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxFileBytes ||
          totalBytes + bytes.length > maxTotalBytes) {
        truncated = true;
        continue;
      }
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        truncated = true;
        continue;
      }
      totalBytes += bytes.length;
      files.add(
        RoutineRunChangedFileEvidence(
          path: absolute
              .substring(lexicalWorkspacePath.length + 1)
              .replaceAll('\\', '/'),
          content: content,
          byteSize: bytes.length,
          contentHash: sha256.convert(bytes).toString(),
        ),
      );
    }
    return (
      files: List<RoutineRunChangedFileEvidence>.unmodifiable(files),
      truncated: truncated,
    );
  }

  static Future<ProcessResult> _runCommand(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    ).timeout(const Duration(seconds: 90));
  }

  bool _hasControlOperator(String command) =>
      RegExp(r'(?:&&|\|\||[;|<>`]|\$\()').hasMatch(command);

  List<String> _splitCommand(String command) {
    final matches = RegExp(
      r'''"([^"]*)"|'([^']*)'|(\S+)''',
    ).allMatches(command);
    return matches
        .map(
          (match) => match.group(1) ?? match.group(2) ?? match.group(3) ?? '',
        )
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  String _clip(String value, int limit) =>
      value.length <= limit ? value : '${value.substring(0, limit - 3)}...';
}
