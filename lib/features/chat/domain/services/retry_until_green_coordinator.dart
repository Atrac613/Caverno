import 'best_of_n_coordinator.dart';

class RetryUntilGreenMechanicalVerification {
  const RetryUntilGreenMechanicalVerification({
    required this.command,
    required this.exitCode,
    this.output = '',
  });

  final String command;
  final int exitCode;
  final String output;

  bool get passed => command.trim().isNotEmpty && exitCode == 0;

  factory RetryUntilGreenMechanicalVerification.fromJson(
    Map<String, dynamic> json,
  ) => RetryUntilGreenMechanicalVerification(
    command: json['command'] as String,
    exitCode: json['exitCode'] as int,
    output: json['output'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'command': command,
    'exitCode': exitCode,
    'output': output,
  };
}

class RetryUntilGreenChangedFileEvidence {
  const RetryUntilGreenChangedFileEvidence({
    required this.path,
    required this.content,
    required this.byteSize,
    required this.contentHash,
    this.truncated = false,
  });

  final String path;
  final String content;
  final int byteSize;
  final String contentHash;
  final bool truncated;

  factory RetryUntilGreenChangedFileEvidence.fromJson(
    Map<String, dynamic> json,
  ) => RetryUntilGreenChangedFileEvidence(
    path: json['path'] as String,
    content: json['content'] as String,
    byteSize: json['byteSize'] as int,
    contentHash: json['contentHash'] as String,
    truncated: json['truncated'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'content': content,
    'byteSize': byteSize,
    'contentHash': contentHash,
    'truncated': truncated,
  };
}

/// Frozen producer-owned evidence for the winning unattended result.
class RetryUntilGreenObjectiveEvidence {
  RetryUntilGreenObjectiveEvidence({
    required this.sourceId,
    required this.objective,
    required Iterable<String> acceptanceCriteria,
    required this.mechanicalVerification,
    required Iterable<RetryUntilGreenChangedFileEvidence> changedFiles,
    required Iterable<String> implementationEvidence,
    this.plan = '',
    this.attended = false,
    this.changedFileEvidenceTruncated = false,
    required this.completedAt,
  }) : acceptanceCriteria = List.unmodifiable(acceptanceCriteria),
       changedFiles = List.unmodifiable(changedFiles),
       implementationEvidence = List.unmodifiable(implementationEvidence);

  final String sourceId;
  final String objective;
  final List<String> acceptanceCriteria;
  final String plan;
  final bool attended;
  final RetryUntilGreenMechanicalVerification mechanicalVerification;
  final List<RetryUntilGreenChangedFileEvidence> changedFiles;
  final bool changedFileEvidenceTruncated;
  final List<String> implementationEvidence;
  final DateTime completedAt;

  factory RetryUntilGreenObjectiveEvidence.fromJson(
    Map<String, dynamic> json,
  ) => RetryUntilGreenObjectiveEvidence(
    sourceId: json['sourceId'] as String,
    objective: json['objective'] as String,
    acceptanceCriteria: (json['acceptanceCriteria'] as List<dynamic>).cast(),
    plan: json['plan'] as String? ?? '',
    attended: json['attended'] as bool? ?? false,
    mechanicalVerification: RetryUntilGreenMechanicalVerification.fromJson(
      Map<String, dynamic>.from(json['mechanicalVerification'] as Map),
    ),
    changedFiles: (json['changedFiles'] as List<dynamic>).map(
      (item) => RetryUntilGreenChangedFileEvidence.fromJson(
        Map<String, dynamic>.from(item as Map),
      ),
    ),
    changedFileEvidenceTruncated:
        json['changedFileEvidenceTruncated'] as bool? ?? false,
    implementationEvidence: (json['implementationEvidence'] as List<dynamic>)
        .cast(),
    completedAt: DateTime.parse(json['completedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'objective': objective,
    'acceptanceCriteria': acceptanceCriteria,
    'plan': plan,
    'attended': attended,
    'mechanicalVerification': mechanicalVerification.toJson(),
    'changedFiles': [for (final file in changedFiles) file.toJson()],
    'changedFileEvidenceTruncated': changedFileEvidenceTruncated,
    'implementationEvidence': implementationEvidence,
    'completedAt': completedAt.toUtc().toIso8601String(),
  };
}

/// Consolidated result of a bounded retry-until-green run: every Best-of-N round
/// plus the round that first produced a green candidate.
class RetryUntilGreenReport {
  const RetryUntilGreenReport({
    required this.rounds,
    required this.winningRound,
    this.objectiveEvidence,
  });

  final List<BestOfNReport> rounds;
  final int? winningRound;
  final RetryUntilGreenObjectiveEvidence? objectiveEvidence;

  bool get foundGreen => winningRound != null;
  int get roundCount => rounds.length;

  int get totalCandidates =>
      rounds.fold(0, (sum, round) => sum + round.candidateCount);

  /// True when any round left residue it could not discard.
  bool get hasResidueRisk => rounds.any((round) => round.hasResidueRisk);

  factory RetryUntilGreenReport.fromJson(Map<String, dynamic> json) {
    if (json['schemaName'] != 'caverno_retry_until_green_report') {
      throw const FormatException('invalid retry-until-green report schema');
    }
    final evidence = json['objectiveEvidence'];
    return RetryUntilGreenReport(
      rounds: (json['rounds'] as List<dynamic>)
          .map(
            (item) =>
                BestOfNReport.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false),
      winningRound: json['winningRound'] as int?,
      objectiveEvidence: evidence is Map
          ? RetryUntilGreenObjectiveEvidence.fromJson(
              Map<String, dynamic>.from(evidence),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_retry_until_green_report',
      'schemaVersion': 1,
      'foundGreen': foundGreen,
      'winningRound': ?winningRound,
      'roundCount': roundCount,
      'totalCandidates': totalCandidates,
      'hasResidueRisk': hasResidueRisk,
      'rounds': [for (final round in rounds) round.toJson()],
      if (objectiveEvidence != null)
        'objectiveEvidence': objectiveEvidence!.toJson(),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Overnight Retry-Until-Green Run')
      ..writeln()
      ..writeln('- Rounds run: `$roundCount`')
      ..writeln('- Candidates total: `$totalCandidates`')
      ..writeln(
        '- Result: ${foundGreen ? '`green` (round $winningRound)' : '`no green candidate`'}',
      );
    if (hasResidueRisk) {
      buffer.writeln('- ⚠️ Residue risk: a candidate failed to discard');
    }
    buffer
      ..writeln()
      ..writeln('| Round | candidates | result |')
      ..writeln('| ---: | ---: | --- |');
    for (var index = 0; index < rounds.length; index += 1) {
      final round = rounds[index];
      final result = round.foundGreen
          ? 'green (candidate ${round.winnerIndex})'
          : 'no green';
      buffer.writeln('| $index | ${round.candidateCount} | $result |');
    }
    return buffer.toString();
  }
}

/// LL7 overnight retry-until-green coordinator.
///
/// Repeats Best-of-N rounds until one yields a green candidate or the budget
/// (round count and an optional wall-clock deadline) is exhausted, then returns
/// a single consolidated report. Designed for unattended Routines runs: each
/// round's candidate generation goes through the non-interactive agent
/// (RoutineToolPolicy, no approval prompts), and non-winning candidates are
/// discarded by the runner, so a long overnight run never blocks on input and
/// never accumulates residue.
class RetryUntilGreenCoordinator {
  const RetryUntilGreenCoordinator({this.bestOfN = const BestOfNCoordinator()});

  final BestOfNCoordinator bestOfN;

  Future<RetryUntilGreenReport> run({
    required int maxRounds,
    required int candidatesPerRound,
    required BestOfNRunner runner,
    DateTime? deadline,
    DateTime Function() clock = DateTime.now,
  }) async {
    if (maxRounds <= 0) {
      throw ArgumentError.value(maxRounds, 'maxRounds', 'must be > 0');
    }
    if (candidatesPerRound <= 0) {
      throw ArgumentError.value(
        candidatesPerRound,
        'candidatesPerRound',
        'must be > 0',
      );
    }

    final rounds = <BestOfNReport>[];
    for (var round = 0; round < maxRounds; round += 1) {
      // Stop before a round if the wall-clock budget is exhausted.
      if (deadline != null && !clock().isBefore(deadline)) break;

      final report = await bestOfN.run(
        maxCandidates: candidatesPerRound,
        runner: runner,
      );
      rounds.add(report);
      if (report.foundGreen) {
        return RetryUntilGreenReport(rounds: rounds, winningRound: round);
      }
    }
    return RetryUntilGreenReport(rounds: rounds, winningRound: null);
  }
}
