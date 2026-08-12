import 'dart:convert';
import 'dart:io';

import 'personal_eval_case_manifest.dart';
import 'personal_eval_paired_statistics.dart';

const _schemaName = 'caverno_personal_eval_suite_report';
const _schemaVersion = 7;
const _runSchemaName = 'caverno_personal_eval_replay_run';

Future<void> main(List<String> args) async {
  final options = PersonalEvalSuiteReportOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_suite_report.dart '
      '--manifest PATH [--manifest PATH ...] '
      '--incumbent PATH --candidate PATH --out-dir PATH [--label LABEL]',
    );
    exitCode = 64;
    return;
  }

  final PersonalEvalSuiteReport report;
  try {
    report = await buildPersonalEvalSuiteReport(
      manifestFiles: options.manifestPaths.map(File.new).toList(),
      incumbentResultFile: File(options.incumbentPath),
      candidateResultFile: File(options.candidatePath),
      label: options.label,
    );
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
    return;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
    return;
  }

  final outputDirectory = Directory(options.outDir);
  outputDirectory.createSync(recursive: true);
  final jsonFile = File(
    '${outputDirectory.path}/personal_eval_suite_report.json',
  );
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  final markdownFile = File(
    '${outputDirectory.path}/personal_eval_suite_report.md',
  );
  await markdownFile.writeAsString(report.toMarkdown());

  stdout.writeln('Personal eval suite report written to ${jsonFile.path}');
  stdout.writeln(report.toMarkdown());

  if (!report.isSuccessful) {
    exitCode = 1;
  }
}

Future<PersonalEvalSuiteReport> buildPersonalEvalSuiteReport({
  required List<File> manifestFiles,
  required File incumbentResultFile,
  required File candidateResultFile,
  String? label,
  DateTime? generatedAt,
  PersonalEvalExperimentProtocolProvenance? experimentProtocol,
}) async {
  if (manifestFiles.isEmpty) {
    throw const FormatException('At least one eval case manifest is required.');
  }

  final manifests = <PersonalEvalCaseManifestRecord>[];
  final seenCaseIds = <String>{};
  for (final file in manifestFiles) {
    final manifest = PersonalEvalCaseManifestRecord.fromJson(
      await _readJsonObject(file),
      path: file.path,
    );
    if (!seenCaseIds.add(manifest.caseId)) {
      throw FormatException('Duplicate eval case id: ${manifest.caseId}');
    }
    manifests.add(manifest);
  }

  final incumbent = PersonalEvalReplayRun.fromJson(
    await _readJsonObject(incumbentResultFile),
    path: incumbentResultFile.path,
  );
  final candidate = PersonalEvalReplayRun.fromJson(
    await _readJsonObject(candidateResultFile),
    path: candidateResultFile.path,
  );
  _validateReplayProvenance(
    manifests: manifests,
    run: incumbent,
    role: 'incumbent',
  );
  _validateReplayProvenance(
    manifests: manifests,
    run: candidate,
    role: 'candidate',
  );

  final entries = <PersonalEvalSuiteReportEntry>[
    for (final manifest in manifests)
      PersonalEvalSuiteReportEntry.compare(
        manifest: manifest,
        incumbentTrials: incumbent.trialsByCaseId[manifest.caseId] ?? const [],
        candidateTrials: candidate.trialsByCaseId[manifest.caseId] ?? const [],
      ),
  ];
  final observationsByCaseId = {
    for (final manifest in manifests)
      manifest.caseId: _pairedTaskObservation(
        manifest.caseId,
        incumbent.trialsByCaseId[manifest.caseId] ?? const [],
        candidate.trialsByCaseId[manifest.caseId] ?? const [],
      ),
  };
  final statistics = PersonalEvalPairedStatistics.calculateTasks(
    observationsByCaseId.values.toList(growable: false),
  );
  final strata = _buildStrata(manifests, observationsByCaseId);
  final heldOutEffectTaskCount = manifests.where((manifest) {
    if (manifest.split != 'heldOut') return false;
    return _hasBinaryTrialPair(
      incumbent.trialsByCaseId[manifest.caseId] ?? const [],
      candidate.trialsByCaseId[manifest.caseId] ?? const [],
    );
  }).length;
  final decisionEligibility = PersonalEvalDecisionEligibility.evaluate(
    experimentProtocol: experimentProtocol,
    effectTaskCount: statistics.effectTaskCount,
    heldOutEffectTaskCount: heldOutEffectTaskCount,
  );

  return PersonalEvalSuiteReport(
    schemaName: _schemaName,
    schemaVersion: _schemaVersion,
    generatedAt: generatedAt ?? DateTime.now(),
    label: label ?? '${incumbent.label} vs ${candidate.label}',
    manifestPaths: manifestFiles.map((file) => file.path).toList(),
    incumbentPath: incumbentResultFile.path,
    candidatePath: candidateResultFile.path,
    incumbent: PersonalEvalRunSummary.fromRun(incumbent, manifests),
    candidate: PersonalEvalRunSummary.fromRun(candidate, manifests),
    experimentProtocol: experimentProtocol,
    decisionEligibility: decisionEligibility,
    statistics: statistics,
    strata: strata,
    entries: entries,
  );
}

final class PersonalEvalSuiteReportOptions {
  const PersonalEvalSuiteReportOptions({
    required this.manifestPaths,
    required this.incumbentPath,
    required this.candidatePath,
    required this.outDir,
    this.label,
  });

  final List<String> manifestPaths;
  final String incumbentPath;
  final String candidatePath;
  final String outDir;
  final String? label;

  static PersonalEvalSuiteReportOptions? parse(List<String> args) {
    final manifests = <String>[];
    String? incumbentPath;
    String? candidatePath;
    String? outDir;
    String? label;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--manifest':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          manifests.add(value);
        case '--incumbent':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          incumbentPath = value;
        case '--candidate':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          candidatePath = value;
        case '--out-dir':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          outDir = value;
        case '--label':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          label = value;
        default:
          return null;
      }
    }

    if (manifests.isEmpty ||
        incumbentPath == null ||
        candidatePath == null ||
        outDir == null) {
      return null;
    }
    return PersonalEvalSuiteReportOptions(
      manifestPaths: List.unmodifiable(manifests),
      incumbentPath: incumbentPath,
      candidatePath: candidatePath,
      outDir: outDir,
      label: label,
    );
  }

  static String? _nextValue(List<String> args, int index) {
    if (index >= args.length) {
      return null;
    }
    final value = args[index];
    return value.startsWith('--') ? null : value;
  }
}

final class PersonalEvalSuiteReport {
  const PersonalEvalSuiteReport({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.label,
    required this.manifestPaths,
    required this.incumbentPath,
    required this.candidatePath,
    required this.incumbent,
    required this.candidate,
    required this.experimentProtocol,
    required this.decisionEligibility,
    required this.statistics,
    required this.strata,
    required this.entries,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String label;
  final List<String> manifestPaths;
  final String incumbentPath;
  final String candidatePath;
  final PersonalEvalRunSummary incumbent;
  final PersonalEvalRunSummary candidate;
  final PersonalEvalExperimentProtocolProvenance? experimentProtocol;
  final PersonalEvalDecisionEligibility decisionEligibility;
  final PersonalEvalPairedStatistics statistics;
  final List<PersonalEvalSuiteStratum> strata;
  final List<PersonalEvalSuiteReportEntry> entries;

  int get hardRegressionCount =>
      entries.fold(0, (sum, entry) => sum + entry.hardRegressions.length);

  int get watchSignalCount =>
      entries.fold(0, (sum, entry) => sum + entry.watchSignals.length);

  int get improvementCount =>
      entries.fold(0, (sum, entry) => sum + entry.improvements.length);

  bool get isSuccessful => hardRegressionCount == 0;

  List<String> get evidenceOrigins =>
      entries.map((entry) => entry.origin).toSet().toList()..sort();

  Map<String, int> get splitCounts => {
    for (final split in const ['heldIn', 'heldOut'])
      split: entries.where((entry) => entry.split == split).length,
  };

  Map<String, int> get tierCounts => _dimensionCounts(
    entries.map((entry) => entry.tier?.toString() ?? 'unclassified'),
  );

  Map<String, int> get promptStyleCounts => _dimensionCounts(
    entries.map((entry) => entry.promptStyle ?? 'unclassified'),
  );

  /// Whether the run itself is usable. Kept separate from [recommendation] and
  /// still the exit-code signal: a run that establishes no difference is a
  /// valid, informative result, not a failed run.
  String get result => isSuccessful ? 'passed' : 'failed';

  /// What the evidence licenses.
  ///
  /// Previously this returned `candidate_ready` whenever no case hard-regressed,
  /// which ignored the statistics printed beside it. The 2026-08-12 re-run is
  /// the case in point: zero discordant pairs, an undefined exact test, and a
  /// 95% interval of [0.000, +0.115] — no difference established — and the
  /// report still said `candidate_ready`. The verdict is what an operator acts
  /// on, so it now reads the interval.
  String get recommendation {
    if (decisionEligibility.studyIntent == 'corpus_design') {
      return 'not_applicable';
    }
    if (!decisionEligibility.isEligible) {
      return 'insufficient_evidence';
    }
    if (!isSuccessful) {
      return 'reject_candidate';
    }
    final interval = statistics.passRateDifference95Ci;
    if (interval == null) {
      // Nothing was measured, so nothing is established.
      return 'no_difference_established';
    }
    if (interval.lower > 0) {
      return 'candidate_ready';
    }
    if (interval.upper < 0) {
      // Measurably worse, even without a case-level hard regression.
      return 'reject_candidate';
    }
    return 'no_difference_established';
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'label': label,
      'result': result,
      'recommendation': recommendation,
      'manifestPaths': manifestPaths,
      'incumbentPath': incumbentPath,
      'candidatePath': candidatePath,
      'hardRegressionCount': hardRegressionCount,
      'watchSignalCount': watchSignalCount,
      'improvementCount': improvementCount,
      'evidenceOrigins': evidenceOrigins,
      'splitCounts': splitCounts,
      'tierCounts': tierCounts,
      'promptStyleCounts': promptStyleCounts,
      'incumbent': incumbent.toJson(),
      'candidate': candidate.toJson(),
      'experimentProtocol':
          experimentProtocol?.toJson() ??
          const {'validationStatus': 'not_provided'},
      'decisionEligibility': decisionEligibility.toJson(),
      'pairedStatistics': statistics.toJson(),
      'strata': strata
          .map((stratum) => stratum.toJson())
          .toList(growable: false),
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Personal Eval Suite Report')
      ..writeln()
      ..writeln('- Label: `$label`')
      ..writeln('- Result: `$result`')
      ..writeln('- Recommendation: `$recommendation`')
      ..writeln('- Decision eligible: `${decisionEligibility.isEligible}`')
      ..writeln('- Cases: `${entries.length}`')
      ..writeln(
        '- Pass rate: `${_percent(incumbent.passRate)}` incumbent, '
        '`${_percent(candidate.passRate)}` candidate',
      )
      ..writeln('- Hard regressions: `$hardRegressionCount`')
      ..writeln('- Watch signals: `$watchSignalCount`')
      ..writeln('- Improvements: `$improvementCount`')
      ..writeln('- Evidence origins: `${evidenceOrigins.join(', ')}`')
      ..writeln(
        '- Splits: `${splitCounts['heldIn']} held-in, '
        '${splitCounts['heldOut']} held-out`',
      )
      ..writeln('- Tiers: `${_dimensionSummary(tierCounts)}`')
      ..writeln('- Prompt styles: `${_dimensionSummary(promptStyleCounts)}`')
      ..writeln(
        '- Experiment protocol: '
        '`${experimentProtocol?.validationStatus ?? 'not_provided'}`',
      );
    if (experimentProtocol != null) {
      buffer
        ..writeln('- Protocol path: `${experimentProtocol!.path}`')
        ..writeln('- Protocol SHA-256: `${experimentProtocol!.sha256}`')
        ..writeln(
          '- Validated trials: `${experimentProtocol!.validatedTrialCount}`',
        )
        ..writeln(
          '- Validated execution events: '
          '`${experimentProtocol!.validatedExecutionEventCount}`',
        );
    }
    if (decisionEligibility.blockers.isNotEmpty) {
      buffer
        ..writeln('- Decision blockers:')
        ..writeAll(
          decisionEligibility.blockers.map((blocker) => '  - $blocker\n'),
        );
    }
    buffer
      ..writeln()
      ..writeln('## Paired Statistics')
      ..writeln()
      ..writeln(
        '- Effect tasks: `${statistics.effectTaskCount}` '
        '(`${statistics.repeatedTaskCount}` with repeated trials)',
      )
      ..writeln(
        '- Trial pairs: `${statistics.pairedTrialCount}` '
        '(`${statistics.excludedBinaryTrialPairCount}` excluded from the '
        'pass effect)',
      )
      ..writeln(
        '- Exact-test tasks: `${statistics.binaryPairCount}` '
        '(`${statistics.excludedBinaryPairCount}` excluded)',
      )
      ..writeln(
        '- Pass-rate difference (candidate - incumbent): '
        '`${_signedPercent(statistics.passRateDifference)}`',
      )
      ..writeln(
        '- Hierarchical paired task-bootstrap 95% CI: '
        '`${_confidenceInterval(statistics.passRateDifference95Ci)}`',
      )
      ..writeln(
        '- Discordant pairs: `${statistics.candidateOnlyPassedCount}` '
        'candidate-only, `${statistics.incumbentOnlyPassedCount}` '
        'incumbent-only',
      )
      ..writeln(
        '- Two-sided exact McNemar p-value: '
        '`${_pValue(statistics.mcnemarExactPValue)}`',
      )
      ..writeln(
        '- Median paired duration difference: '
        '`${_signedNumber(statistics.medianDurationDifferenceMs, 'ms')}`',
      )
      ..writeln(
        '- Median paired turn difference: '
        '`${_signedNumber(statistics.medianTurnCountDifference, 'turns')}`',
      )
      ..writeln(
        '- Median paired tool-call difference: '
        '`${_signedNumber(statistics.medianToolCallCountDifference, 'calls')}`',
      )
      ..writeln()
      ..writeln('## Stratified Statistics')
      ..writeln()
      ..writeln(
        '| Dimension | Value | Cases | Effect Tasks | Pass-rate Difference | 95% CI |',
      )
      ..writeln(
        '|-----------|-------|-------|--------------|----------------------|--------|',
      );

    for (final stratum in strata) {
      buffer.writeln(
        '| `${stratum.dimension}` '
        '| `${stratum.value}` '
        '| `${stratum.caseCount}` '
        '| `${stratum.statistics.effectTaskCount}` '
        '| `${_signedPercent(stratum.statistics.passRateDifference)}` '
        '| `${_confidenceInterval(stratum.statistics.passRateDifference95Ci)}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Origin | Split | Tier | Prompt Style | Status | Incumbent | Candidate | Hard Regressions | Watch Signals | Improvements |',
      )
      ..writeln(
        '|------|--------|-------|------|--------------|--------|-----------|-----------|------------------|---------------|--------------|',
      );

    for (final entry in entries) {
      buffer.writeln(
        '| ${_tableCell(entry.caseId)} '
        '| `${entry.origin}` '
        '| `${entry.split}` '
        '| `${entry.tier?.toString() ?? 'unclassified'}` '
        '| `${entry.promptStyle ?? 'unclassified'}` '
        '| `${entry.status}` '
        '| ${_tableCell(entry.incumbentSummary)} '
        '| ${_tableCell(entry.candidateSummary)} '
        '| ${_listCell(entry.hardRegressions)} '
        '| ${_listCell(entry.watchSignals)} '
        '| ${_listCell(entry.improvements)} |',
      );
    }

    return buffer.toString();
  }
}

void _validateReplayProvenance({
  required List<PersonalEvalCaseManifestRecord> manifests,
  required PersonalEvalReplayRun run,
  required String role,
}) {
  final manifestByCaseId = {
    for (final manifest in manifests) manifest.caseId: manifest,
  };
  for (final trial in run.cases) {
    final manifest = manifestByCaseId[trial.caseId];
    if (manifest == null) continue;
    if (trial.origin != manifest.origin ||
        trial.split != manifest.split ||
        trial.tier != manifest.tier ||
        trial.promptStyle != manifest.promptStyle) {
      throw FormatException(
        '$role replay provenance mismatch for '
        '${trial.caseId}#${trial.trialId}: expected '
        '${manifest.origin}/${manifest.split}/'
        '${manifest.tier ?? 'unclassified'}/'
        '${manifest.promptStyle ?? 'unclassified'}, got '
        '${trial.origin}/${trial.split}/'
        '${trial.tier ?? 'unclassified'}/'
        '${trial.promptStyle ?? 'unclassified'}.',
      );
    }
  }
}

List<PersonalEvalSuiteStratum> _buildStrata(
  List<PersonalEvalCaseManifestRecord> manifests,
  Map<String, PersonalEvalPairedTaskObservation> observationsByCaseId,
) {
  final strata = <PersonalEvalSuiteStratum>[];
  for (final dimension in const ['tier', 'promptStyle']) {
    final grouped = <String, List<PersonalEvalPairedTaskObservation>>{};
    for (final manifest in manifests) {
      final value = switch (dimension) {
        'tier' => manifest.tier?.toString() ?? 'unclassified',
        'promptStyle' => manifest.promptStyle ?? 'unclassified',
        _ => throw StateError('Unsupported stratum dimension $dimension.'),
      };
      grouped
          .putIfAbsent(value, () => [])
          .add(observationsByCaseId[manifest.caseId]!);
    }
    final values = grouped.keys.toList()..sort();
    for (final value in values) {
      final observations = grouped[value]!;
      strata.add(
        PersonalEvalSuiteStratum(
          dimension: dimension,
          value: value,
          caseCount: observations.length,
          statistics: PersonalEvalPairedStatistics.calculateTasks(observations),
        ),
      );
    }
  }
  return List.unmodifiable(strata);
}

Map<String, int> _dimensionCounts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return Map.unmodifiable(counts);
}

String _dimensionSummary(Map<String, int> counts) =>
    counts.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');

final class PersonalEvalSuiteStratum {
  const PersonalEvalSuiteStratum({
    required this.dimension,
    required this.value,
    required this.caseCount,
    required this.statistics,
  });

  final String dimension;
  final String value;
  final int caseCount;
  final PersonalEvalPairedStatistics statistics;

  Map<String, dynamic> toJson() => {
    'dimension': dimension,
    'value': value,
    'caseCount': caseCount,
    'pairedStatistics': statistics.toJson(),
  };
}

final class PersonalEvalExperimentProtocolProvenance {
  const PersonalEvalExperimentProtocolProvenance({
    required this.path,
    required this.sha256,
    required this.label,
    required this.validationStatus,
    required this.studyIntent,
    required this.minimumEffectTaskCount,
    required this.minimumHeldOutEffectTaskCount,
    required this.validatedTrialCount,
    required this.validatedExecutionEventCount,
  });

  final String path;
  final String sha256;
  final String label;
  final String validationStatus;
  final String studyIntent;
  final int? minimumEffectTaskCount;
  final int? minimumHeldOutEffectTaskCount;
  final int validatedTrialCount;
  final int validatedExecutionEventCount;

  Map<String, dynamic> toJson() => {
    'path': path,
    'sha256': sha256,
    'label': label,
    'validationStatus': validationStatus,
    'studyIntent': studyIntent,
    if (minimumEffectTaskCount != null)
      'minimumEffectTaskCount': minimumEffectTaskCount,
    if (minimumHeldOutEffectTaskCount != null)
      'minimumHeldOutEffectTaskCount': minimumHeldOutEffectTaskCount,
    'validatedTrialCount': validatedTrialCount,
    'validatedExecutionEventCount': validatedExecutionEventCount,
  };
}

final class PersonalEvalDecisionEligibility {
  const PersonalEvalDecisionEligibility({
    required this.studyIntent,
    required this.isEligible,
    required this.effectTaskCount,
    required this.heldOutEffectTaskCount,
    required this.blockers,
  });

  final String? studyIntent;
  final bool isEligible;
  final int effectTaskCount;
  final int heldOutEffectTaskCount;
  final List<String> blockers;

  factory PersonalEvalDecisionEligibility.evaluate({
    required PersonalEvalExperimentProtocolProvenance? experimentProtocol,
    required int effectTaskCount,
    required int heldOutEffectTaskCount,
  }) {
    final blockers = <String>[];
    final studyIntent = experimentProtocol?.studyIntent;
    if (experimentProtocol == null ||
        experimentProtocol.validationStatus != 'validated') {
      blockers.add(
        'a validated experiment protocol with a pre-registered study intent '
        'is required',
      );
    } else if (studyIntent == 'corpus_design') {
      blockers.add('corpus_design studies do not authorize model selection');
    } else if (studyIntent == 'model_selection') {
      final minimumEffectTaskCount = experimentProtocol.minimumEffectTaskCount;
      final minimumHeldOutEffectTaskCount =
          experimentProtocol.minimumHeldOutEffectTaskCount;
      if (minimumEffectTaskCount == null ||
          minimumHeldOutEffectTaskCount == null) {
        blockers.add(
          'model_selection requires pre-registered decision criteria',
        );
        return PersonalEvalDecisionEligibility(
          studyIntent: studyIntent,
          isEligible: false,
          effectTaskCount: effectTaskCount,
          heldOutEffectTaskCount: heldOutEffectTaskCount,
          blockers: List.unmodifiable(blockers),
        );
      }
      if (effectTaskCount < minimumEffectTaskCount) {
        blockers.add(
          'effect task count $effectTaskCount is below the pre-registered '
          'minimum $minimumEffectTaskCount',
        );
      }
      if (heldOutEffectTaskCount < minimumHeldOutEffectTaskCount) {
        blockers.add(
          'held-out effect task count $heldOutEffectTaskCount is below the '
          'pre-registered minimum $minimumHeldOutEffectTaskCount',
        );
      }
    } else {
      blockers.add('study intent is missing or unsupported');
    }
    return PersonalEvalDecisionEligibility(
      studyIntent: studyIntent,
      isEligible: blockers.isEmpty,
      effectTaskCount: effectTaskCount,
      heldOutEffectTaskCount: heldOutEffectTaskCount,
      blockers: List.unmodifiable(blockers),
    );
  }

  Map<String, dynamic> toJson() => {
    if (studyIntent != null) 'studyIntent': studyIntent,
    'isEligible': isEligible,
    'effectTaskCount': effectTaskCount,
    'heldOutEffectTaskCount': heldOutEffectTaskCount,
    'blockers': blockers,
  };
}

bool _hasBinaryTrialPair(
  List<PersonalEvalReplayCaseResult> incumbentTrials,
  List<PersonalEvalReplayCaseResult> candidateTrials,
) {
  final incumbentByTrial = {
    for (final trial in incumbentTrials) trial.trialId: trial,
  };
  for (final candidate in candidateTrials) {
    final incumbent = incumbentByTrial[candidate.trialId];
    if (_binaryPass(incumbent) != null && _binaryPass(candidate) != null) {
      return true;
    }
  }
  return false;
}

PersonalEvalPairedTaskObservation _pairedTaskObservation(
  String caseId,
  List<PersonalEvalReplayCaseResult> incumbentTrials,
  List<PersonalEvalReplayCaseResult> candidateTrials,
) {
  final incumbentByTrial = {
    for (final trial in incumbentTrials) trial.trialId: trial,
  };
  final candidateByTrial = {
    for (final trial in candidateTrials) trial.trialId: trial,
  };
  final trialIds = {...incumbentByTrial.keys, ...candidateByTrial.keys}.toList()
    ..sort();
  if (trialIds.isEmpty) trialIds.add('trial-1');
  return PersonalEvalPairedTaskObservation(
    taskId: caseId,
    trials: [
      for (final trialId in trialIds)
        _pairedObservation(
          incumbentByTrial[trialId],
          candidateByTrial[trialId],
        ),
    ],
  );
}

PersonalEvalPairedObservation _pairedObservation(
  PersonalEvalReplayCaseResult? incumbent,
  PersonalEvalReplayCaseResult? candidate,
) {
  return PersonalEvalPairedObservation(
    incumbentPassed: _binaryPass(incumbent),
    candidatePassed: _binaryPass(candidate),
    incumbentDurationMs: incumbent?.durationMs,
    candidateDurationMs: candidate?.durationMs,
    incumbentTurnCount: incumbent?.turnCount,
    candidateTurnCount: candidate?.turnCount,
    incumbentToolCallCount: incumbent?.toolCallCount,
    candidateToolCallCount: candidate?.toolCallCount,
  );
}

bool? _binaryPass(PersonalEvalReplayCaseResult? result) {
  if (result == null) return null;
  return switch (result.verificationResult) {
    PersonalEvalVerificationResult.passed => true,
    PersonalEvalVerificationResult.failed => false,
    PersonalEvalVerificationResult.inconclusive => null,
  };
}

final class PersonalEvalRunSummary {
  const PersonalEvalRunSummary({
    required this.label,
    required this.model,
    required this.baseUrl,
    required this.caseCount,
    required this.missingCaseCount,
    required this.passedCount,
    required this.failedCount,
    required this.inconclusiveCount,
    required this.totalDurationMs,
    required this.totalToolCallCount,
    required this.averageToolCallDelta,
  });

  final String label;
  final String? model;
  final String? baseUrl;
  final int caseCount;
  final int missingCaseCount;
  final int passedCount;
  final int failedCount;
  final int inconclusiveCount;
  final int totalDurationMs;
  final int totalToolCallCount;
  final double averageToolCallDelta;

  double get passRate => caseCount == 0 ? 0 : passedCount / caseCount;

  double get averageDurationMs =>
      caseCount == 0 ? 0 : totalDurationMs / caseCount;

  factory PersonalEvalRunSummary.fromRun(
    PersonalEvalReplayRun run,
    List<PersonalEvalCaseManifestRecord> manifests,
  ) {
    var missing = 0;
    var passed = 0;
    var failed = 0;
    var inconclusive = 0;
    var duration = 0;
    var toolCalls = 0;
    var toolDelta = 0;
    for (final manifest in manifests) {
      final result = run.caseById[manifest.caseId];
      if (result == null) {
        missing += 1;
        continue;
      }
      switch (result.verificationResult) {
        case PersonalEvalVerificationResult.passed:
          passed += 1;
        case PersonalEvalVerificationResult.failed:
          failed += 1;
        case PersonalEvalVerificationResult.inconclusive:
          inconclusive += 1;
      }
      duration += result.durationMs;
      toolCalls += result.toolCallCount;
      toolDelta += (result.toolCallCount - manifest.sourceToolCallCount).abs();
    }
    final caseCount = manifests.length;
    return PersonalEvalRunSummary(
      label: run.label,
      model: run.model,
      baseUrl: run.baseUrl,
      caseCount: caseCount,
      missingCaseCount: missing,
      passedCount: passed,
      failedCount: failed,
      inconclusiveCount: inconclusive,
      totalDurationMs: duration,
      totalToolCallCount: toolCalls,
      averageToolCallDelta: caseCount == 0 ? 0 : toolDelta / caseCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      if (model != null) 'model': model,
      if (baseUrl != null) 'baseUrl': baseUrl,
      'caseCount': caseCount,
      'missingCaseCount': missingCaseCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'inconclusiveCount': inconclusiveCount,
      'passRate': passRate,
      'totalDurationMs': totalDurationMs,
      'averageDurationMs': averageDurationMs,
      'totalToolCallCount': totalToolCallCount,
      'averageToolCallDelta': averageToolCallDelta,
    };
  }
}

final class PersonalEvalSuiteReportEntry {
  const PersonalEvalSuiteReportEntry({
    required this.caseId,
    required this.title,
    required this.origin,
    required this.split,
    required this.tier,
    required this.promptStyle,
    required this.status,
    required this.expectedToolCallCount,
    required this.incumbentTrialCount,
    required this.candidateTrialCount,
    required this.incumbent,
    required this.candidate,
    required this.hardRegressions,
    required this.watchSignals,
    required this.improvements,
  });

  final String caseId;
  final String title;
  final String origin;
  final String split;
  final int? tier;
  final String? promptStyle;
  final String status;
  final int expectedToolCallCount;
  final int incumbentTrialCount;
  final int candidateTrialCount;
  final PersonalEvalReplayCaseResult? incumbent;
  final PersonalEvalReplayCaseResult? candidate;
  final List<String> hardRegressions;
  final List<String> watchSignals;
  final List<String> improvements;

  String get incumbentSummary => _resultSummary(incumbent);

  String get candidateSummary => _resultSummary(candidate);

  factory PersonalEvalSuiteReportEntry.compare({
    required PersonalEvalCaseManifestRecord manifest,
    required List<PersonalEvalReplayCaseResult> incumbentTrials,
    required List<PersonalEvalReplayCaseResult> candidateTrials,
  }) {
    final hardRegressions = <String>[];
    final watchSignals = <String>[];
    final improvements = <String>[];

    if (incumbentTrials.isEmpty) {
      hardRegressions.add('missing incumbent result');
    }
    if (candidateTrials.isEmpty) {
      hardRegressions.add('missing candidate result');
    }

    final incumbentByTrial = {
      for (final trial in incumbentTrials) trial.trialId: trial,
    };
    final candidateByTrial = {
      for (final trial in candidateTrials) trial.trialId: trial,
    };
    if (incumbentTrials.isNotEmpty && candidateTrials.isNotEmpty) {
      for (final trialId in incumbentByTrial.keys) {
        if (!candidateByTrial.containsKey(trialId)) {
          hardRegressions.add('missing candidate trial $trialId');
        }
      }
      for (final trialId in candidateByTrial.keys) {
        if (!incumbentByTrial.containsKey(trialId)) {
          hardRegressions.add('missing incumbent trial $trialId');
        }
      }
    }

    final incumbent = _aggregateTaskResults(incumbentTrials);
    final candidate = _aggregateTaskResults(candidateTrials);

    if (incumbent != null && candidate != null) {
      _compareVerificationResult(
        incumbent: incumbent,
        candidate: candidate,
        hardRegressions: hardRegressions,
        improvements: improvements,
      );
      _compareDuration(
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
      _compareTurns(
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
      _compareToolCallFidelity(
        expectedToolCallCount: manifest.sourceToolCallCount,
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
    }

    return PersonalEvalSuiteReportEntry(
      caseId: manifest.caseId,
      title: manifest.title,
      origin: manifest.origin,
      split: manifest.split,
      tier: manifest.tier,
      promptStyle: manifest.promptStyle,
      status: _entryStatus(hardRegressions, watchSignals, improvements),
      expectedToolCallCount: manifest.sourceToolCallCount,
      incumbentTrialCount: incumbentTrials.length,
      candidateTrialCount: candidateTrials.length,
      incumbent: incumbent,
      candidate: candidate,
      hardRegressions: List.unmodifiable(hardRegressions),
      watchSignals: List.unmodifiable(watchSignals),
      improvements: List.unmodifiable(improvements),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caseId': caseId,
      'title': title,
      'origin': origin,
      'split': split,
      if (tier != null) 'tier': tier,
      if (promptStyle != null) 'promptStyle': promptStyle,
      'status': status,
      'expectedToolCallCount': expectedToolCallCount,
      'incumbentTrialCount': incumbentTrialCount,
      'candidateTrialCount': candidateTrialCount,
      'incumbent': incumbent?.toJson(),
      'candidate': candidate?.toJson(),
      'hardRegressions': hardRegressions,
      'watchSignals': watchSignals,
      'improvements': improvements,
    };
  }

  static String _resultSummary(PersonalEvalReplayCaseResult? result) {
    if (result == null) {
      return 'missing';
    }
    return '${result.verificationResult.name}, '
        '${result.durationMs} ms, '
        '${result.toolCallCount} tools, '
        '${result.turnCount} turns';
  }
}

final class PersonalEvalCaseManifestRecord {
  const PersonalEvalCaseManifestRecord({
    required this.path,
    required this.caseId,
    required this.title,
    required this.readiness,
    required this.expectedVerificationResult,
    required this.sourceToolCallCount,
    required this.origin,
    required this.split,
    required this.tier,
    required this.promptStyle,
  });

  final String path;
  final String caseId;
  final String title;
  final String readiness;
  final PersonalEvalVerificationResult expectedVerificationResult;
  final int sourceToolCallCount;
  final String origin;
  final String split;
  final int? tier;
  final String? promptStyle;

  factory PersonalEvalCaseManifestRecord.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final schemaName = _asString(json['schemaName']);
    if (schemaName != 'caverno_personal_eval_case_manifest') {
      throw FormatException('Invalid personal eval manifest schema in $path.');
    }
    final task = _asStringMap(json['task']);
    final source = _asStringMap(json['source']);
    final summary = _asStringMap(source?['sessionLogSummary']);
    final verificationResult = PersonalEvalVerificationResult.parse(
      _asString(task?['verificationResult']) ?? '',
    );
    final origin = _asString(json['origin']) ?? 'recorded';
    if (origin != 'recorded' && origin != 'authored') {
      throw FormatException('Invalid personal eval origin in $path.');
    }
    final split = _asString(json['split']) ?? 'heldIn';
    if (split != 'heldIn' && split != 'heldOut') {
      throw FormatException('Invalid personal eval split in $path.');
    }
    if (task == null ||
        verificationResult == null ||
        (origin == 'recorded' && summary == null)) {
      throw FormatException('Incomplete personal eval manifest in $path.');
    }
    return PersonalEvalCaseManifestRecord(
      path: path,
      caseId: _requiredString(json, 'caseId', path),
      title: _requiredString(json, 'title', path),
      readiness: _asString(json['readiness']) ?? 'unknown',
      expectedVerificationResult: verificationResult,
      sourceToolCallCount: _asInt(summary?['toolCallCount']) ?? 0,
      origin: origin,
      split: split,
      tier: _optionalTier(json['tier'], path),
      promptStyle: _optionalPromptStyle(json['promptStyle'], path),
    );
  }
}

final class PersonalEvalReplayRun {
  const PersonalEvalReplayRun({
    required this.label,
    required this.model,
    required this.baseUrl,
    required this.cases,
    required this.path,
  });

  final String label;
  final String? model;
  final String? baseUrl;
  final List<PersonalEvalReplayCaseResult> cases;
  final String path;

  Map<String, List<PersonalEvalReplayCaseResult>> get trialsByCaseId {
    final result = <String, List<PersonalEvalReplayCaseResult>>{};
    for (final trial in cases) {
      result.putIfAbsent(trial.caseId, () => []).add(trial);
    }
    return {
      for (final entry in result.entries)
        entry.key: List.unmodifiable(entry.value),
    };
  }

  Map<String, PersonalEvalReplayCaseResult> get caseById => {
    for (final entry in trialsByCaseId.entries)
      entry.key: _aggregateTaskResults(entry.value)!,
  };

  factory PersonalEvalReplayRun.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final schemaName = _asString(json['schemaName']);
    if (schemaName != _runSchemaName) {
      throw FormatException(
        'Invalid personal eval replay run schema in $path.',
      );
    }
    final rawCases = _asList(json['cases']);
    final cases = <PersonalEvalReplayCaseResult>[];
    final seenTrialKeys = <String>{};
    for (final rawCase in rawCases) {
      final caseJson = _asStringMap(rawCase);
      if (caseJson == null) {
        throw FormatException('Invalid replay case entry in $path.');
      }
      final result = PersonalEvalReplayCaseResult.fromJson(
        caseJson,
        path: path,
      );
      final trialKey = '${result.caseId}#${result.trialId}';
      if (!seenTrialKeys.add(trialKey)) {
        throw FormatException(
          'Duplicate replay result for trial $trialKey in $path.',
        );
      }
      cases.add(result);
    }
    return PersonalEvalReplayRun(
      label: _asString(json['label']) ?? 'unnamed',
      model: _asString(json['model']),
      baseUrl: _asString(json['baseUrl']),
      cases: List.unmodifiable(cases),
      path: path,
    );
  }
}

final class PersonalEvalReplayCaseResult {
  const PersonalEvalReplayCaseResult({
    required this.caseId,
    required this.trialId,
    required this.executionOrder,
    required this.origin,
    required this.split,
    required this.tier,
    required this.promptStyle,
    required this.verificationResult,
    required this.durationMs,
    required this.toolCallCount,
    required this.turnCount,
    required this.error,
  });

  final String caseId;
  final String trialId;
  final int executionOrder;
  final String origin;
  final String split;
  final int? tier;
  final String? promptStyle;
  final PersonalEvalVerificationResult verificationResult;
  final int durationMs;
  final int toolCallCount;
  final int turnCount;
  final String? error;

  factory PersonalEvalReplayCaseResult.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final verificationResult = PersonalEvalVerificationResult.parse(
      _asString(json['verificationResult']) ?? '',
    );
    if (verificationResult == null) {
      throw FormatException('Invalid verification result in $path.');
    }
    final origin = _asString(json['origin']) ?? 'recorded';
    if (origin != 'recorded' && origin != 'authored') {
      throw FormatException('Invalid replay origin in $path.');
    }
    final split = _asString(json['split']) ?? 'heldIn';
    if (split != 'heldIn' && split != 'heldOut') {
      throw FormatException('Invalid replay split in $path.');
    }
    return PersonalEvalReplayCaseResult(
      caseId: _requiredString(json, 'caseId', path),
      trialId: _asString(json['trialId']) ?? 'trial-1',
      executionOrder: _asNonNegativeInt(json['executionOrder']) ?? 0,
      origin: origin,
      split: split,
      tier: _optionalTier(json['tier'], path),
      promptStyle: _optionalPromptStyle(json['promptStyle'], path),
      verificationResult: verificationResult,
      durationMs: _asNonNegativeInt(json['durationMs']) ?? 0,
      toolCallCount: _asNonNegativeInt(json['toolCallCount']) ?? 0,
      turnCount: _asNonNegativeInt(json['turnCount']) ?? 0,
      error: _asString(json['error']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caseId': caseId,
      'trialId': trialId,
      'executionOrder': executionOrder,
      'origin': origin,
      'split': split,
      if (tier != null) 'tier': tier,
      if (promptStyle != null) 'promptStyle': promptStyle,
      'verificationResult': verificationResult.name,
      'durationMs': durationMs,
      'toolCallCount': toolCallCount,
      'turnCount': turnCount,
      if (error != null) 'error': error,
    };
  }
}

PersonalEvalReplayCaseResult? _aggregateTaskResults(
  List<PersonalEvalReplayCaseResult> trials,
) {
  if (trials.isEmpty) return null;
  final verificationResult =
      trials.any(
        (trial) =>
            trial.verificationResult == PersonalEvalVerificationResult.failed,
      )
      ? PersonalEvalVerificationResult.failed
      : trials.any(
          (trial) =>
              trial.verificationResult ==
              PersonalEvalVerificationResult.inconclusive,
        )
      ? PersonalEvalVerificationResult.inconclusive
      : PersonalEvalVerificationResult.passed;
  return PersonalEvalReplayCaseResult(
    caseId: trials.first.caseId,
    trialId: trials.length == 1 ? trials.first.trialId : 'aggregate',
    executionOrder: 0,
    origin: trials.first.origin,
    split: trials.first.split,
    tier: trials.first.tier,
    promptStyle: trials.first.promptStyle,
    verificationResult: verificationResult,
    durationMs: _roundedMedian(trials.map((trial) => trial.durationMs)),
    toolCallCount: _roundedMedian(trials.map((trial) => trial.toolCallCount)),
    turnCount: _roundedMedian(trials.map((trial) => trial.turnCount)),
    error: trials.map((trial) => trial.error).nonNulls.firstOrNull,
  );
}

int _roundedMedian(Iterable<int> values) {
  final sorted = values.toList()..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return ((sorted[middle - 1] + sorted[middle]) / 2).round();
}

void _compareVerificationResult({
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> hardRegressions,
  required List<String> improvements,
}) {
  final incumbentRank = _verificationRank(incumbent.verificationResult);
  final candidateRank = _verificationRank(candidate.verificationResult);
  if (candidateRank < incumbentRank) {
    hardRegressions.add(
      'verification result regressed '
      '${incumbent.verificationResult.name}->${candidate.verificationResult.name}',
    );
  } else if (candidateRank > incumbentRank) {
    improvements.add(
      'verification result improved '
      '${incumbent.verificationResult.name}->${candidate.verificationResult.name}',
    );
  }
}

void _compareDuration({
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> watchSignals,
  required List<String> improvements,
}) {
  if (incumbent.durationMs <= 0 || candidate.durationMs <= 0) {
    return;
  }
  final increase = candidate.durationMs - incumbent.durationMs;
  if (increase > 1000 && candidate.durationMs > incumbent.durationMs * 1.1) {
    watchSignals.add(
      'duration increased ${incumbent.durationMs}->${candidate.durationMs} ms',
    );
  } else if (candidate.durationMs < incumbent.durationMs) {
    improvements.add(
      'duration decreased ${incumbent.durationMs}->${candidate.durationMs} ms',
    );
  }
}

void _compareTurns({
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> watchSignals,
  required List<String> improvements,
}) {
  if (candidate.turnCount > incumbent.turnCount + 1) {
    watchSignals.add(
      'turn count increased ${incumbent.turnCount}->${candidate.turnCount}',
    );
  } else if (candidate.turnCount < incumbent.turnCount) {
    improvements.add(
      'turn count decreased ${incumbent.turnCount}->${candidate.turnCount}',
    );
  }
}

void _compareToolCallFidelity({
  required int expectedToolCallCount,
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> watchSignals,
  required List<String> improvements,
}) {
  final incumbentDelta = (incumbent.toolCallCount - expectedToolCallCount)
      .abs();
  final candidateDelta = (candidate.toolCallCount - expectedToolCallCount)
      .abs();
  if (candidateDelta > incumbentDelta) {
    watchSignals.add(
      'tool-call fidelity delta increased $incumbentDelta->$candidateDelta',
    );
  } else if (candidateDelta < incumbentDelta) {
    improvements.add(
      'tool-call fidelity delta decreased $incumbentDelta->$candidateDelta',
    );
  }
}

int _verificationRank(PersonalEvalVerificationResult result) {
  return switch (result) {
    PersonalEvalVerificationResult.failed => 0,
    PersonalEvalVerificationResult.inconclusive => 1,
    PersonalEvalVerificationResult.passed => 2,
  };
}

String _entryStatus(
  List<String> hardRegressions,
  List<String> watchSignals,
  List<String> improvements,
) {
  if (hardRegressions.isNotEmpty) {
    return 'regressed';
  }
  if (watchSignals.isNotEmpty) {
    return improvements.isEmpty ? 'watch' : 'mixed';
  }
  if (improvements.isNotEmpty) {
    return 'improved';
  }
  return 'unchanged';
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  final object = _asStringMap(decoded);
  if (object == null) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return object;
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String? _asString(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

int? _asNonNegativeInt(Object? value) {
  final parsed = _asInt(value);
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

int? _optionalTier(Object? value, String path) {
  if (value == null) return null;
  if (value is! int || value < 1 || value > 3) {
    throw FormatException('Invalid personal eval tier in $path.');
  }
  return value;
}

String? _optionalPromptStyle(Object? value, String path) {
  if (value == null) return null;
  if (value != 'guided' && value != 'unguided') {
    throw FormatException('Invalid personal eval promptStyle in $path.');
  }
  return value as String;
}

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = _asString(json[key])?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('Missing `$key` in $path.');
  }
  return value;
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _signedPercent(double? value) {
  if (value == null) return 'unavailable';
  final percent = value * 100;
  return '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)} pp';
}

String _confidenceInterval(PersonalEvalConfidenceInterval? interval) {
  if (interval == null) return 'unavailable';
  return '[${_signedPercent(interval.lower)}, '
      '${_signedPercent(interval.upper)}]';
}

String _pValue(double? value) {
  if (value == null) return 'unavailable (no discordant pairs)';
  return value.toStringAsFixed(6);
}

String _signedNumber(double? value, String unit) {
  if (value == null) return 'unavailable';
  final rendered = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '${value >= 0 ? '+' : ''}$rendered $unit';
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _listCell(List<String> values) {
  if (values.isEmpty) {
    return '';
  }
  return values.map(_tableCell).join('<br>');
}
