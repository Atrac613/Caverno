import 'personal_eval_case.dart';
import 'personal_eval_replay_run.dart';

/// Per-case bake-off status, mirroring the offline
/// `tool/personal_eval_suite_report.dart` taxonomy.
enum PersonalEvalBakeOffStatus { regressed, watch, mixed, improved, unchanged }

/// The single model-swap recommendation a bake-off produces.
enum PersonalEvalBakeOffRecommendation { candidateReady, rejectCandidate }

/// One case compared between the incumbent and candidate replay runs.
class PersonalEvalBakeOffCaseEntry {
  const PersonalEvalBakeOffCaseEntry({
    required this.caseId,
    required this.title,
    required this.split,
    required this.status,
    required this.expectedToolCallCount,
    this.incumbent,
    this.candidate,
    this.hardRegressions = const [],
    this.watchSignals = const [],
    this.improvements = const [],
  });

  final String caseId;
  final String title;
  final PersonalEvalCaseSplit split;
  final PersonalEvalBakeOffStatus status;
  final int expectedToolCallCount;
  final PersonalEvalReplayCaseResult? incumbent;
  final PersonalEvalReplayCaseResult? candidate;
  final List<String> hardRegressions;
  final List<String> watchSignals;
  final List<String> improvements;

  bool get hasHardRegression => hardRegressions.isNotEmpty;
}

/// Aggregated incumbent/candidate scores for one held-in / held-out split.
/// Reported separately so an LL17 adoption can gate on non-regression of both
/// splits (Self-Harness protocol).
class PersonalEvalBakeOffSplitScore {
  const PersonalEvalBakeOffSplitScore({
    required this.split,
    required this.caseCount,
    required this.incumbentPassedCount,
    required this.candidatePassedCount,
    required this.hardRegressionCount,
  });

  final PersonalEvalCaseSplit split;
  final int caseCount;
  final int incumbentPassedCount;
  final int candidatePassedCount;
  final int hardRegressionCount;

  double get incumbentPassRate =>
      caseCount == 0 ? 0 : incumbentPassedCount / caseCount;

  double get candidatePassRate =>
      caseCount == 0 ? 0 : candidatePassedCount / caseCount;

  bool get nonRegressing => hardRegressionCount == 0;
}

/// LL19 bake-off: the comparison of a candidate model against the incumbent
/// over the recorded eval suite, producing a single swap recommendation.
class PersonalEvalBakeOffReport {
  const PersonalEvalBakeOffReport({
    required this.label,
    required this.entries,
    this.incumbentModel,
    this.candidateModel,
  });

  final String label;
  final List<PersonalEvalBakeOffCaseEntry> entries;
  final String? incumbentModel;
  final String? candidateModel;

  int get caseCount => entries.length;

  int get hardRegressionCount =>
      entries.fold(0, (sum, entry) => sum + entry.hardRegressions.length);

  int get watchSignalCount =>
      entries.fold(0, (sum, entry) => sum + entry.watchSignals.length);

  int get improvementCount =>
      entries.fold(0, (sum, entry) => sum + entry.improvements.length);

  /// The candidate is recommended only when it introduces no hard regression
  /// on any case, which also implies non-regression on both splits.
  bool get isSuccessful => hardRegressionCount == 0;

  PersonalEvalBakeOffRecommendation get recommendation => isSuccessful
      ? PersonalEvalBakeOffRecommendation.candidateReady
      : PersonalEvalBakeOffRecommendation.rejectCandidate;

  PersonalEvalBakeOffSplitScore splitScore(PersonalEvalCaseSplit split) {
    final splitEntries = entries
        .where((entry) => entry.split == split)
        .toList(growable: false);
    return PersonalEvalBakeOffSplitScore(
      split: split,
      caseCount: splitEntries.length,
      incumbentPassedCount: splitEntries
          .where((entry) => entry.incumbent?.isPassed ?? false)
          .length,
      candidatePassedCount: splitEntries
          .where((entry) => entry.candidate?.isPassed ?? false)
          .length,
      hardRegressionCount: splitEntries.fold(
        0,
        (sum, entry) => sum + entry.hardRegressions.length,
      ),
    );
  }

  PersonalEvalBakeOffSplitScore get heldIn =>
      splitScore(PersonalEvalCaseSplit.heldIn);

  PersonalEvalBakeOffSplitScore get heldOut =>
      splitScore(PersonalEvalCaseSplit.heldOut);
}
