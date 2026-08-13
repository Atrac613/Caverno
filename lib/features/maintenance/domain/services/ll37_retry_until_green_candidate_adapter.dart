import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../chat/domain/services/retry_until_green_coordinator.dart';
import 'll37_objective_verification_panel.dart';

/// Converts complete bounded retry-until-green reports without rerunning them.
class Ll37RetryUntilGreenCandidateAdapter {
  const Ll37RetryUntilGreenCandidateAdapter();

  List<Ll37ObjectiveCandidate> adapt(Iterable<RetryUntilGreenReport> reports) {
    final ordered =
        reports
            .where((report) => report.objectiveEvidence != null)
            .toList(growable: false)
          ..sort((left, right) {
            final leftEvidence = left.objectiveEvidence!;
            final rightEvidence = right.objectiveEvidence!;
            final byCompletion = rightEvidence.completedAt.compareTo(
              leftEvidence.completedAt,
            );
            return byCompletion != 0
                ? byCompletion
                : leftEvidence.sourceId.compareTo(rightEvidence.sourceId);
          });
    final seenIds = <String>{};
    final candidates = <Ll37ObjectiveCandidate>[];
    for (final report in ordered) {
      final sourceId = report.objectiveEvidence!.sourceId.trim();
      if (sourceId.isEmpty) continue;
      final candidateId = 'retry-until-green:$sourceId';
      if (!seenIds.add(candidateId)) continue;
      final candidate = _adaptReport(report, candidateId: candidateId);
      if (candidate != null) candidates.add(candidate);
    }
    return List.unmodifiable(candidates);
  }

  Ll37ObjectiveCandidate? _adaptReport(
    RetryUntilGreenReport report, {
    required String candidateId,
  }) {
    final evidence = report.objectiveEvidence!;
    final objective = evidence.objective.trim();
    final criteria = _normalizedNonEmpty(evidence.acceptanceCriteria);
    final implementationEvidence = _normalizedNonEmpty(
      evidence.implementationEvidence,
    );
    if (!report.foundGreen ||
        report.hasResidueRisk ||
        !_hasConsistentWinner(report) ||
        evidence.attended ||
        objective.isEmpty ||
        criteria.isEmpty ||
        implementationEvidence.isEmpty ||
        !evidence.mechanicalVerification.passed ||
        evidence.changedFileEvidenceTruncated ||
        evidence.changedFiles.isEmpty) {
      return null;
    }
    final winningRound = report.winningRound!;

    final files = _validatedFiles(evidence.changedFiles);
    if (files == null) return null;
    return Ll37ObjectiveCandidate(
      id: candidateId,
      sourceSurface: Ll37ObjectiveSourceSurface.retryUntilGreen,
      attended: false,
      ll34OutcomeSettled: false,
      objective: objective,
      acceptanceCriteria: criteria,
      plan: evidence.plan.trim(),
      changedFiles: files,
      implementationEvidence: [
        'Mechanical verification: '
            '${evidence.mechanicalVerification.command.trim()} '
            '(exit ${evidence.mechanicalVerification.exitCode})',
        'Retry-until-green winner: round $winningRound of '
            '${report.roundCount}',
        ...implementationEvidence,
      ],
    );
  }

  bool _hasConsistentWinner(RetryUntilGreenReport report) {
    final winningRound = report.winningRound;
    if (winningRound == null ||
        winningRound < 0 ||
        winningRound >= report.rounds.length ||
        winningRound != report.rounds.length - 1 ||
        report.rounds.take(winningRound).any((round) => round.foundGreen)) {
      return false;
    }
    final round = report.rounds[winningRound];
    final winnerIndex = round.winnerIndex;
    if (winnerIndex == null) return false;
    final winners = round.attempts
        .where((attempt) => attempt.isWinner)
        .toList(growable: false);
    if (winners.length != 1) return false;
    final winner = winners.single;
    return winner.index == winnerIndex &&
        winner.generated &&
        winner.verified &&
        winner.passed;
  }

  List<Ll37ObjectiveChangedFile>? _validatedFiles(
    List<RetryUntilGreenChangedFileEvidence> source,
  ) {
    final seenPaths = <String>{};
    final files = <Ll37ObjectiveChangedFile>[];
    for (final file in source) {
      final path = _safeRelativePath(file.path);
      final bytes = utf8.encode(file.content);
      if (path == null ||
          !seenPaths.add(path) ||
          file.truncated ||
          file.byteSize != bytes.length ||
          file.contentHash.trim().toLowerCase() !=
              sha256.convert(bytes).toString()) {
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
