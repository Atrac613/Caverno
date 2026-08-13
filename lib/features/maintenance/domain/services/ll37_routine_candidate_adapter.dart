import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../routines/domain/entities/routine.dart';
import 'll37_objective_verification_panel.dart';

/// Converts complete persisted Routine evidence without executing the Routine.
class Ll37RoutineCandidateAdapter {
  const Ll37RoutineCandidateAdapter();

  List<Ll37ObjectiveCandidate> adapt(Iterable<Routine> routines) {
    final sources = <({Routine routine, RoutineRunRecord run})>[];
    for (final routine in routines) {
      for (final run in routine.runs) {
        sources.add((routine: routine, run: run));
      }
    }
    sources.sort((left, right) {
      final byFinish = right.run.finishedAt.compareTo(left.run.finishedAt);
      if (byFinish != 0) return byFinish;
      final byRoutine = left.routine.id.compareTo(right.routine.id);
      return byRoutine != 0 ? byRoutine : left.run.id.compareTo(right.run.id);
    });

    final seenIds = <String>{};
    final candidates = <Ll37ObjectiveCandidate>[];
    for (final source in sources) {
      final routineId = source.routine.id.trim();
      final runId = source.run.id.trim();
      if (routineId.isEmpty || runId.isEmpty) continue;
      final candidateId = 'routine:$routineId:$runId';
      if (!seenIds.add(candidateId)) continue;
      final candidate = _adaptRun(source.run, candidateId: candidateId);
      if (candidate != null) candidates.add(candidate);
    }
    return List.unmodifiable(candidates);
  }

  Ll37ObjectiveCandidate? _adaptRun(
    RoutineRunRecord run, {
    required String candidateId,
  }) {
    final objective = run.objective.trim();
    final criteria = _normalizedNonEmpty(run.objectiveAcceptanceCriteria);
    final implementationEvidence = _normalizedNonEmpty(
      run.implementationEvidence,
    );
    final verification = run.mechanicalVerification;
    if (run.status != RoutineRunStatus.completed ||
        run.trigger != RoutineRunTrigger.scheduled ||
        objective.isEmpty ||
        criteria.isEmpty ||
        implementationEvidence.isEmpty ||
        verification == null ||
        !verification.passed ||
        run.changedFileEvidenceTruncated ||
        run.changedFiles.isEmpty) {
      return null;
    }

    final files = _validatedFiles(run.changedFiles);
    if (files == null) return null;
    return Ll37ObjectiveCandidate(
      id: candidateId,
      sourceSurface: Ll37ObjectiveSourceSurface.routine,
      attended: false,
      ll34OutcomeSettled: false,
      objective: objective,
      acceptanceCriteria: criteria,
      plan: run.objectivePlan.trim(),
      changedFiles: files,
      implementationEvidence: [
        'Mechanical verification: ${verification.command.trim()} '
            '(exit ${verification.exitCode})',
        ...implementationEvidence,
      ],
    );
  }

  List<Ll37ObjectiveChangedFile>? _validatedFiles(
    List<RoutineRunChangedFileEvidence> source,
  ) {
    final seenPaths = <String>{};
    final files = <Ll37ObjectiveChangedFile>[];
    for (final file in source) {
      final path = _safeRelativePath(file.path);
      final bytes = utf8.encode(file.content);
      final hash = file.contentHash.trim().toLowerCase();
      if (path == null ||
          !seenPaths.add(path) ||
          file.truncated ||
          file.byteSize != bytes.length ||
          hash.isEmpty ||
          sha256.convert(bytes).toString() != hash) {
        return null;
      }
      files.add(Ll37ObjectiveChangedFile(path: path, content: file.content));
    }
    return List.unmodifiable(files);
  }

  List<String> _normalizedNonEmpty(Iterable<String> values) {
    final normalized = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return normalized.length == values.length
        ? List.unmodifiable(normalized)
        : const [];
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
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') return null;
      segments.add(segment);
    }
    return segments.isEmpty ? null : segments.join('/');
  }
}
