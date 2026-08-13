import 'package:caverno/features/maintenance/domain/entities/ll37_objective_verdict_record.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_vote_identity.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_verifier_fidelity_profile.dart';
import 'package:caverno/features/maintenance/presentation/providers/ll37_objective_verdict_history_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'records history and reloads it in a fresh provider container',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final first = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(first.dispose);

      final notifier = first.read(
        ll37ObjectiveVerdictHistoryNotifierProvider.notifier,
      );
      expect(notifier.recordsForCandidate('candidate-1'), isEmpty);
      await notifier.record(_record());
      expect(notifier.recordsForCandidate(' candidate-1 '), hasLength(1));
      expect(
        first.read(ll37ObjectiveVerdictHistoryNotifierProvider),
        hasLength(1),
      );

      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(second.dispose);

      final reloaded = second.read(ll37ObjectiveVerdictHistoryNotifierProvider);
      expect(reloaded.single.candidateId, 'candidate-1');
      expect(
        second
            .read(ll37ObjectiveVerdictHistoryNotifierProvider.notifier)
            .recordsForCandidate('candidate-1'),
        hasLength(1),
      );
    },
  );
}

Ll37ObjectiveVerdictRecord _record() {
  final profile = Ll37VerifierFidelityRegistry.acceptedProfiles.first;
  return Ll37ObjectiveVerdictRecord(
    voteId: Ll37ObjectiveVoteIdentity.build(
      candidateId: 'candidate-1',
      verifierProfileKey: profile.profileKey,
      fidelityReportSha256: profile.reportSha256,
      voteIndex: 1,
    ),
    voteIndex: 1,
    candidateId: 'candidate-1',
    sourceSurface: 'worktreeAgent',
    objective: 'Set the feature flag.',
    acceptanceCriteria: const ['The flag is true.'],
    changedFilePaths: const ['config.json'],
    implementationEvidence: const ['Verification result: passed'],
    verdict: 'notRefuted',
    confidence: 1,
    blocking: 'none',
    findings: const [],
    requestCount: 1,
    estimatedInputTokens: 20,
    estimatedOutputTokens: 10,
    verifierProvider: 'openAiCompatible',
    verifierBaseUrl: profile.baseUrl,
    verifierModel: profile.model,
    verifierProfileKey: profile.profileKey,
    fidelityReportSchemaVersion: profile.reportSchemaVersion,
    fidelityReportSha256: profile.reportSha256,
    recordedAt: DateTime.utc(2026, 8, 13),
  );
}
