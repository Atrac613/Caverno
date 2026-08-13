import 'dart:convert';

import 'package:caverno/features/maintenance/data/ll37_objective_verdict_repository.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_verdict_record.dart';
import 'package:caverno/features/maintenance/domain/entities/ll37_objective_vote_identity.dart';
import 'package:caverno/features/maintenance/domain/services/ll37_verifier_fidelity_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persists a newest-first bounded verdict history', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = Ll37ObjectiveVerdictRepository(preferences);

    for (var index = 0; index < 55; index++) {
      await repository.record(
        _record(
          candidateId: 'candidate-$index',
          recordedAt: DateTime.utc(2026, 8, 13, 1, index),
        ),
      );
    }

    final records = repository.loadAll();
    expect(records, hasLength(Ll37ObjectiveVerdictRepository.maxRecords));
    expect(records.first.candidateId, 'candidate-54');
    expect(records.last.candidateId, 'candidate-5');
    final encoded = preferences.getString(
      Ll37ObjectiveVerdictRepository.storageKey,
    )!;
    expect(encoded, isNot(contains('changed file contents')));
  });

  test(
    'keeps valid neighbors while skipping malformed and unknown entries',
    () async {
      final valid = _record(candidateId: 'valid');
      SharedPreferences.setMockInitialValues({
        Ll37ObjectiveVerdictRepository.storageKey: jsonEncode([
          {'schemaVersion': 99},
          valid.toJson(),
          {'schemaVersion': 1, 'candidateId': ''},
        ]),
      });
      final preferences = await SharedPreferences.getInstance();

      final records = Ll37ObjectiveVerdictRepository(preferences).loadAll();

      expect(records.map((record) => record.candidateId), ['valid']);
    },
  );

  test('malformed roots fail closed to empty history', () async {
    SharedPreferences.setMockInitialValues({
      Ll37ObjectiveVerdictRepository.storageKey: '{not-json',
    });
    final preferences = await SharedPreferences.getInstance();

    expect(Ll37ObjectiveVerdictRepository(preferences).loadAll(), isEmpty);
  });

  test('duplicate candidates collapse to the newest valid record', () async {
    final older = _record(
      candidateId: 'duplicate',
      recordedAt: DateTime.utc(2026, 8, 13, 1),
      verdict: 'notRefuted',
    );
    final newer = _record(
      candidateId: 'duplicate',
      recordedAt: DateTime.utc(2026, 8, 13, 2),
      verdict: 'refuted',
      blocking: 'contradiction',
    );
    SharedPreferences.setMockInitialValues({
      Ll37ObjectiveVerdictRepository.storageKey: jsonEncode([
        older.toJson(),
        newer.toJson(),
      ]),
    });
    final preferences = await SharedPreferences.getInstance();

    final records = Ll37ObjectiveVerdictRepository(preferences).loadAll();

    expect(records, hasLength(1));
    expect(records.single.verdict, 'refuted');
    expect(records.single.recordedAt, DateTime.utc(2026, 8, 13, 2));
  });

  test(
    'record replaces the same vote and survives repository reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = Ll37ObjectiveVerdictRepository(preferences);
      await repository.record(_record(candidateId: 'candidate'));
      await repository.record(
        _record(
          candidateId: 'candidate',
          recordedAt: DateTime.utc(2026, 8, 14),
          verdict: 'unverifiable',
          blocking: 'unverifiable',
        ),
      );

      final reloaded = Ll37ObjectiveVerdictRepository(preferences).loadAll();

      expect(reloaded, hasLength(1));
      expect(reloaded.single.verdict, 'unverifiable');
    },
  );

  test('keeps multiple bounded votes for the same candidate', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = Ll37ObjectiveVerdictRepository(preferences);

    await repository.record(_record(candidateId: 'candidate', voteIndex: 1));
    await repository.record(
      _record(
        candidateId: 'candidate',
        voteIndex: 2,
        recordedAt: DateTime.utc(2026, 8, 13, 2),
        verdict: 'refuted',
        blocking: 'contradiction',
      ),
    );

    final records = repository.loadAll();
    expect(records, hasLength(2));
    expect(records.map((record) => record.voteIndex), [2, 1]);
    expect(records.map((record) => record.voteId).toSet(), hasLength(2));
  });

  test('loads schema-v1 history as vote one and rewrites schema v2', () async {
    final legacyJson = _record(candidateId: 'legacy').toJson()
      ..['schemaVersion'] = 1
      ..remove('voteId')
      ..remove('voteIndex');
    SharedPreferences.setMockInitialValues({
      Ll37ObjectiveVerdictRepository.storageKey: jsonEncode([legacyJson]),
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = Ll37ObjectiveVerdictRepository(preferences);

    final legacy = repository.loadAll().single;
    expect(legacy.voteIndex, 1);
    expect(
      legacy.voteId,
      Ll37ObjectiveVoteIdentity.build(
        candidateId: 'legacy',
        verifierProfileKey: legacy.verifierProfileKey,
        fidelityReportSha256: legacy.fidelityReportSha256,
        voteIndex: 1,
      ),
    );

    await repository.record(
      _record(
        candidateId: 'legacy',
        voteIndex: 2,
        recordedAt: DateTime.utc(2026, 8, 13, 2),
      ),
    );
    final stored =
        jsonDecode(
              preferences.getString(Ll37ObjectiveVerdictRepository.storageKey)!,
            )
            as List<dynamic>;
    expect(stored, hasLength(2));
    expect(
      stored.every(
        (item) =>
            (item as Map<String, dynamic>)['schemaVersion'] ==
            Ll37ObjectiveVerdictRecord.schemaVersion,
      ),
      isTrue,
    );
  });

  test(
    'rejects a record whose vote identity does not match its slot',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = Ll37ObjectiveVerdictRepository(preferences);
      final record = _record(candidateId: 'candidate');

      await expectLater(
        repository.record(
          _record(candidateId: 'other-candidate', voteId: record.voteId),
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects a route that does not own the requested vote slot', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = Ll37ObjectiveVerdictRepository(preferences);

    await expectLater(
      repository.record(
        _record(candidateId: 'candidate', voteIndex: 2, profileIndex: 0),
      ),
      throwsFormatException,
    );

    expect(repository.loadAll(), isEmpty);
  });
}

Ll37ObjectiveVerdictRecord _record({
  required String candidateId,
  DateTime? recordedAt,
  String verdict = 'notRefuted',
  String blocking = 'none',
  int voteIndex = 1,
  int? profileIndex,
  String? voteId,
}) {
  final profile = Ll37VerifierFidelityRegistry
      .acceptedProfiles[profileIndex ?? voteIndex - 1];
  return Ll37ObjectiveVerdictRecord(
    voteId:
        voteId ??
        Ll37ObjectiveVoteIdentity.build(
          candidateId: candidateId,
          verifierProfileKey: profile.profileKey,
          fidelityReportSha256: profile.reportSha256,
          voteIndex: voteIndex,
        ),
    voteIndex: voteIndex,
    candidateId: candidateId,
    sourceSurface: 'worktreeAgent',
    objective: 'Set the feature flag.',
    acceptanceCriteria: const ['The flag is true.'],
    changedFilePaths: const ['config.json'],
    implementationEvidence: const ['Verification result: passed'],
    verdict: verdict,
    confidence: 1,
    blocking: blocking,
    findings: verdict == 'refuted'
        ? const [
            Ll37ObjectiveVerdictFindingRecord(
              kind: 'unmet_criterion',
              location: 'config.json',
              detail: 'The flag remains false.',
            ),
          ]
        : const [],
    requestCount: 1,
    estimatedInputTokens: 20,
    estimatedOutputTokens: 10,
    verifierProvider: 'openAiCompatible',
    verifierBaseUrl: profile.baseUrl,
    verifierModel: profile.model,
    verifierProfileKey: profile.profileKey,
    fidelityReportSchemaVersion: profile.reportSchemaVersion,
    fidelityReportSha256: profile.reportSha256,
    recordedAt: recordedAt ?? DateTime.utc(2026, 8, 13),
  );
}
