import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_artifact_metadata_backfill.dart';
import '../../tool/personal_eval_suite_report.dart';

void main() {
  test('backfills a legacy suite without changing scored outcomes', () async {
    final fixture = await _writeLegacyFixture();
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    final result = await backfillPersonalEvalArtifactMetadata(
      corpusFile: fixture.corpusFile,
      sourceSuiteDirectory: fixture.sourceSuiteDirectory,
      outputDirectory: fixture.outputDirectory,
      generatedAt: DateTime.utc(2026, 8, 12, 12),
    );

    expect(result.caseCount, 1);
    expect(result.executionCount, 4);
    final sourceReport = _readJson(
      File(
        '${fixture.sourceSuiteDirectory.path}/personal_eval_suite_report.json',
      ),
    );
    final report = _readJson(result.reportFile);
    expect(report['schemaVersion'], 7);
    expect(report['pairedStatistics'], sourceReport['pairedStatistics']);
    expect(report['tierCounts'], {'2': 1});
    expect(report['promptStyleCounts'], {'unguided': 1});
    expect(report['recommendation'], 'not_applicable');
    expect(
      (report['decisionEligibility'] as Map<String, dynamic>)['studyIntent'],
      'corpus_design',
    );

    final incumbent = _readJson(
      File('${fixture.outputDirectory.path}/incumbent_replay_run.json'),
    );
    expect(incumbent['schemaVersion'], 5);
    expect(
      (incumbent['cases'] as List).cast<Map<String, dynamic>>(),
      everyElement(containsPair('tier', 2)),
    );
    expect(
      (incumbent['cases'] as List).cast<Map<String, dynamic>>(),
      everyElement(containsPair('promptStyle', 'unguided')),
    );
    final sourceIncumbent = _readJson(
      File('${fixture.sourceSuiteDirectory.path}/incumbent_replay_run.json'),
    );
    expect((sourceIncumbent['cases'] as List).first, isNot(contains('tier')));
    final handoff = _readJson(
      File(
        '${fixture.outputDirectory.path}/personal_eval_profile_handoff.json',
      ),
    );
    expect(handoff['readyForProfileUpdate'], isFalse);
  });

  test('rejects metadata that conflicts with the authored corpus', () async {
    final fixture = await _writeLegacyFixture(manifestTier: 1);
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    await expectLater(
      backfillPersonalEvalArtifactMetadata(
        corpusFile: fixture.corpusFile,
        sourceSuiteDirectory: fixture.sourceSuiteDirectory,
        outputDirectory: fixture.outputDirectory,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Tier conflict'),
        ),
      ),
    );
  });

  test(
    'rejects a source report without validated protocol provenance',
    () async {
      final fixture = await _writeLegacyFixture(validatedProtocol: false);
      addTearDown(() => fixture.root.deleteSync(recursive: true));

      await expectLater(
        backfillPersonalEvalArtifactMetadata(
          corpusFile: fixture.corpusFile,
          sourceSuiteDirectory: fixture.sourceSuiteDirectory,
          outputDirectory: fixture.outputDirectory,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('validated protocol provenance'),
          ),
        ),
      );
    },
  );

  test('rejects overwriting the source suite directory', () async {
    final fixture = await _writeLegacyFixture();
    addTearDown(() => fixture.root.deleteSync(recursive: true));

    await expectLater(
      backfillPersonalEvalArtifactMetadata(
        corpusFile: fixture.corpusFile,
        sourceSuiteDirectory: fixture.sourceSuiteDirectory,
        outputDirectory: fixture.sourceSuiteDirectory,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('must differ'),
        ),
      ),
    );
  });
}

Future<_LegacyFixture> _writeLegacyFixture({
  int? manifestTier,
  bool validatedProtocol = true,
}) async {
  final root = Directory.systemTemp.createTempSync(
    'personal-eval-metadata-backfill-test-',
  );
  final sourceSuiteDirectory = Directory('${root.path}/source')
    ..createSync(recursive: true);
  final outputDirectory = Directory('${root.path}/output');
  final corpusFile = File('${root.path}/corpus.json');
  _writeJson(corpusFile, {
    'schemaName': 'caverno_personal_eval_authored_corpus',
    'schemaVersion': 1,
    'replay': {'seedRoot': 'seeds'},
    'tasks': [
      {
        'caseId': 'rebuild-case',
        'title': 'Rebuild behavior',
        'prompt': 'Repair the fixture.',
        'fixtureDirectory': 'fixtures/example',
        'verificationCommand': 'dart run bin/verify.dart',
        'split': 'heldOut',
        'tier': 2,
        'promptStyle': 'unguided',
        'objectiveFingerprint': 'example.rebuild.behavior',
      },
    ],
  });
  final manifestFile = File('${root.path}/source-case-manifest.json');
  _writeJson(manifestFile, {
    'schemaName': 'caverno_personal_eval_case_manifest',
    'schemaVersion': 1,
    'generatedAt': '2026-08-12T00:00:00.000Z',
    'caseId': 'rebuild-case',
    'title': 'Rebuild behavior',
    'readiness': 'ready',
    'origin': 'authored',
    'split': 'heldOut',
    'task': {
      'prompt': 'Repair the fixture.',
      'repoStateRef': '',
      'verificationCommand': 'dart run bin/verify.dart',
      'verificationResult': 'inconclusive',
      'workspaceMode': 'coding',
    },
    'consent': {'explicitUserConsent': false},
    'privacy': {'exportPolicy': 'shareable'},
  });
  final incumbentFile = File(
    '${sourceSuiteDirectory.path}/incumbent_replay_run.json',
  );
  final candidateFile = File(
    '${sourceSuiteDirectory.path}/candidate_replay_run.json',
  );
  _writeJson(
    incumbentFile,
    _runJson(
      label: 'incumbent',
      model: 'incumbent-model',
      baseUrl: 'http://localhost:1234/v1',
      manifestPath: manifestFile.path,
      results: const ['passed', 'failed'],
      startOffsetSeconds: 0,
    ),
  );
  _writeJson(
    candidateFile,
    _runJson(
      label: 'candidate',
      model: 'candidate-model',
      baseUrl: 'http://localhost:1235/v1',
      manifestPath: manifestFile.path,
      results: const ['failed', 'passed'],
      startOffsetSeconds: 1,
    ),
  );
  _writeJson(
    File('${sourceSuiteDirectory.path}/personal_eval_experiment_protocol.json'),
    {
      'schemaName': 'caverno_personal_eval_experiment_protocol',
      'schemaVersion': 1,
      'generatedAt': '2026-08-12T00:00:00.000Z',
      'label': 'Legacy reconstruction probe',
      'incumbent': _protocolModel(
        model: 'incumbent-model',
        baseUrl: 'http://localhost:1234/v1',
      ),
      'candidate': _protocolModel(
        model: 'candidate-model',
        baseUrl: 'http://localhost:1235/v1',
      ),
      'executionBudget': {
        'maxDurationMs': 900000,
        'maxTurns': 24,
        'maxToolCalls': 100,
      },
      'trialOrders': [
        {
          'caseId': 'rebuild-case',
          'trialId': 'trial-1',
          'first': 'incumbent',
          'second': 'candidate',
        },
        {
          'caseId': 'rebuild-case',
          'trialId': 'trial-2',
          'first': 'candidate',
          'second': 'incumbent',
        },
      ],
    },
  );
  final report = await buildPersonalEvalSuiteReport(
    manifestFiles: [manifestFile],
    incumbentResultFile: incumbentFile,
    candidateResultFile: candidateFile,
    generatedAt: DateTime.utc(2026, 8, 12),
  );
  final reportJson = report.toJson();
  if (validatedProtocol) {
    reportJson['experimentProtocol'] = {
      'path': 'legacy-protocol.json',
      'sha256': 'legacy-digest',
      'label': 'Legacy reconstruction probe',
      'validationStatus': 'validated',
      'validatedTrialCount': 2,
      'validatedExecutionEventCount': 4,
    };
  }
  _writeJson(
    File('${sourceSuiteDirectory.path}/personal_eval_suite_report.json'),
    reportJson,
  );
  if (manifestTier != null) {
    final manifest = _readJson(manifestFile)..['tier'] = manifestTier;
    _writeJson(manifestFile, manifest);
  }
  return _LegacyFixture(
    root: root,
    corpusFile: corpusFile,
    sourceSuiteDirectory: sourceSuiteDirectory,
    outputDirectory: outputDirectory,
  );
}

Map<String, dynamic> _runJson({
  required String label,
  required String model,
  required String baseUrl,
  required String manifestPath,
  required List<String> results,
  required int startOffsetSeconds,
}) {
  final cases = [
    for (var index = 0; index < results.length; index += 1)
      {
        'caseId': 'rebuild-case',
        'trialId': 'trial-${index + 1}',
        'executionOrder': index + 1,
        'startedAt': DateTime.utc(
          2026,
          8,
          12,
          0,
          0,
          index * 2 + startOffsetSeconds,
        ).toIso8601String(),
        'title': 'Rebuild behavior',
        'origin': 'authored',
        'split': 'heldOut',
        'logPath': '/tmp/$label-${index + 1}.jsonl',
        'verificationResult': results[index],
        'durationMs': 1000 + index,
        'toolCallCount': 2,
        'turnCount': 3,
        'summaryResult': 'completed',
        'warningCodes': <String>[],
      },
  ];
  return {
    'schemaName': 'caverno_personal_eval_replay_run',
    'schemaVersion': 4,
    'generatedAt': '2026-08-12T00:00:00.000Z',
    'label': label,
    'model': model,
    'baseUrl': baseUrl,
    'manifestPaths': [manifestPath],
    'caseCount': cases.length,
    'distinctCaseCount': 1,
    'trialCount': cases.length,
    'passedCount': 1,
    'failedCount': 1,
    'inconclusiveCount': 0,
    'totalDurationMs': 2001,
    'totalToolCallCount': 4,
    'cases': cases,
  };
}

Map<String, dynamic> _protocolModel({
  required String model,
  required String baseUrl,
}) => {
  'model': model,
  'baseUrl': baseUrl,
  'samplerSettings': {'temperature': 0.2, 'topP': 0.95, 'maxTokens': 8192},
  'warmup': {'completed': true, 'iterations': 1},
};

Map<String, dynamic> _readJson(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

void _writeJson(File file, Map<String, dynamic> value) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

final class _LegacyFixture {
  const _LegacyFixture({
    required this.root,
    required this.corpusFile,
    required this.sourceSuiteDirectory,
    required this.outputDirectory,
  });

  final Directory root;
  final File corpusFile;
  final Directory sourceSuiteDirectory;
  final Directory outputDirectory;
}
