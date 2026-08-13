import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../chat/domain/entities/worktree_agent_task.dart';
import 'll37_objective_verification_panel.dart';

/// Converts persisted LL13 completion evidence without reading its worktree.
class Ll37WorktreeAgentCandidateAdapter {
  const Ll37WorktreeAgentCandidateAdapter();

  List<Ll37ObjectiveCandidate> adapt(Iterable<WorktreeAgentTask> tasks) {
    final ordered = tasks.toList(growable: false)
      ..sort((left, right) {
        final byUpdate = right.updatedAt.compareTo(left.updatedAt);
        return byUpdate != 0 ? byUpdate : left.id.compareTo(right.id);
      });
    final seenTaskIds = <String>{};
    final candidates = <Ll37ObjectiveCandidate>[];
    for (final task in ordered) {
      final taskId = task.id.trim();
      if (taskId.isEmpty || !seenTaskIds.add(taskId)) {
        continue;
      }
      final candidate = _adaptTask(task, taskId: taskId);
      if (candidate != null) {
        candidates.add(candidate);
      }
    }
    return List.unmodifiable(candidates);
  }

  Ll37ObjectiveCandidate? _adaptTask(
    WorktreeAgentTask task, {
    required String taskId,
  }) {
    final objective = task.prompt.trim();
    final verificationCommand = task.verificationCommand.trim();
    final verificationSummary = task.verificationSummary.trim();
    final acceptanceCriteria = task.objectiveAcceptanceCriteria
        .map((criterion) => criterion.trim())
        .where((criterion) => criterion.isNotEmpty)
        .toList(growable: false);
    if (task.status != WorktreeAgentTaskStatus.completed ||
        !task.verifiedGreen ||
        task.changedFileEvidenceTruncated ||
        objective.isEmpty ||
        verificationCommand.isEmpty ||
        verificationSummary.isEmpty ||
        acceptanceCriteria.isEmpty ||
        task.changedFiles.isEmpty) {
      return null;
    }

    final changedFiles = <Ll37ObjectiveChangedFile>[];
    final seenPaths = <String>{};
    for (final file in task.changedFiles) {
      final normalizedPath = _safeRelativePath(file.path);
      if (normalizedPath == null ||
          !seenPaths.add(normalizedPath) ||
          file.truncated) {
        return null;
      }
      if (file.deleted) {
        if (file.content.isNotEmpty ||
            file.byteSize != 0 ||
            (file.contentHash?.trim().isNotEmpty ?? false)) {
          return null;
        }
      } else {
        final bytes = utf8.encode(file.content);
        final expectedHash = file.contentHash?.trim() ?? '';
        if (file.byteSize != bytes.length ||
            expectedHash.isEmpty ||
            sha256.convert(bytes).toString() != expectedHash) {
          return null;
        }
      }
      changedFiles.add(
        Ll37ObjectiveChangedFile(
          path: normalizedPath,
          content: file.deleted ? '' : file.content,
        ),
      );
    }

    final resultSummary = task.resultSummary.trim();
    return Ll37ObjectiveCandidate(
      id: 'worktree-agent:$taskId',
      sourceSurface: Ll37ObjectiveSourceSurface.worktreeAgent,
      attended: false,
      ll34OutcomeSettled: false,
      objective: objective,
      acceptanceCriteria: List.unmodifiable(acceptanceCriteria),
      changedFiles: List.unmodifiable(changedFiles),
      implementationEvidence: [
        'Verification result: $verificationSummary',
        if (resultSummary.isNotEmpty) 'Implementer summary: $resultSummary',
      ],
    );
  }

  String? _safeRelativePath(String rawPath) {
    final path = rawPath.trim().replaceAll('\\', '/');
    if (path.isEmpty ||
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(path)) {
      return null;
    }
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        return null;
      }
      segments.add(segment);
    }
    return segments.isEmpty ? null : segments.join('/');
  }
}

/// Prevents the same deterministic vote slot from running twice per session.
class Ll37ObjectiveAttemptLedger {
  final Set<String> _attemptedVoteIds = <String>{};

  bool contains(String candidateId) =>
      _attemptedVoteIds.contains(candidateId.trim());

  bool record(String candidateId) {
    final normalized = candidateId.trim();
    return normalized.isNotEmpty && _attemptedVoteIds.add(normalized);
  }

  int get length => _attemptedVoteIds.length;
}
