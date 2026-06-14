import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_profile_handoff.dart';

void main() {
  test(
    'builds a ready LL3 profile handoff from a candidate-ready report',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'personal-eval-profile-handoff-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final report = _writeSuiteReport(
        directory: directory,
        recommendation: 'candidate_ready',
        hardRegressionCount: 0,
        candidateModel: 'candidate-model',
        candidateBaseUrl: 'http://localhost:1234/v1',
        entries: [
          _entry(
            caseId: 'ping-cli',
            improvements: ['duration decreased 5000->3500 ms'],
          ),
        ],
      );

      final handoff = await buildPersonalEvalProfileHandoff(
        suiteReportFile: report,
        generatedAt: DateTime.utc(2026, 6, 14, 3, 4, 5),
      );

      expect(handoff.schemaName, 'caverno_personal_eval_profile_handoff');
      expect(handoff.readyForProfileUpdate, isTrue);
      expect(handoff.action, 'apply_profile_metadata');
      expect(handoff.blockers, isEmpty);
      expect(
        handoff.target.profileId,
        'openAiCompatible|http://localhost:1234/v1|candidate-model',
      );
      expect(handoff.metrics.caseCount, 1);
      expect(handoff.metrics.candidatePassRate, 1.0);
      expect(handoff.improvements, [
        'ping-cli: duration decreased 5000->3500 ms',
      ]);
      expect(
        handoff.metadataPatch,
        containsPair('personalEval.lastRecommendation', 'candidate_ready'),
      );
      expect(
        handoff.metadataPatch,
        containsPair('personalEval.candidateModel', 'candidate-model'),
      );
      expect(
        handoff.toJson()['probeMetadataPatch'],
        containsPair('personalEval.lastReportPath', report.path),
      );
      expect(
        handoff.toMarkdown(),
        contains('Ready for profile update: `true`'),
      );
      expect(handoff.toMarkdown(), contains('apply_profile_metadata'));
    },
  );

  test('blocks profile updates when the suite rejects the candidate', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-profile-handoff-reject-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final report = _writeSuiteReport(
      directory: directory,
      result: 'failed',
      recommendation: 'reject_candidate',
      hardRegressionCount: 1,
      candidateModel: 'candidate-model',
      candidateBaseUrl: 'http://localhost:1234/v1',
      entries: [
        _entry(
          caseId: 'ping-cli',
          watchSignals: ['duration increased 1000->3000 ms'],
        ),
      ],
    );

    final handoff = await buildPersonalEvalProfileHandoff(
      suiteReportFile: report,
      generatedAt: DateTime.utc(2026, 6, 14),
    );

    expect(handoff.readyForProfileUpdate, isFalse);
    expect(handoff.action, 'do_not_apply_profile_metadata');
    expect(
      handoff.blockers,
      containsAll([
        'suite recommendation is reject_candidate',
        'suite has 1 hard regression(s)',
      ]),
    );
    expect(handoff.watchSignals, [
      'ping-cli: duration increased 1000->3000 ms',
    ]);
    expect(
      handoff.toMarkdown(),
      contains('suite recommendation is reject_candidate'),
    );
  });

  test(
    'blocks profile updates when the target profile is incomplete',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'personal-eval-profile-handoff-target-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final report = _writeSuiteReport(
        directory: directory,
        recommendation: 'candidate_ready',
        hardRegressionCount: 0,
        candidateModel: null,
        candidateBaseUrl: null,
      );

      final blocked = await buildPersonalEvalProfileHandoff(
        suiteReportFile: report,
      );
      final overridden = await buildPersonalEvalProfileHandoff(
        suiteReportFile: report,
        targetBaseUrl: 'http://127.0.0.1:4321/v1',
        targetModel: 'override-model',
      );

      expect(blocked.readyForProfileUpdate, isFalse);
      expect(blocked.target.profileId, isNull);
      expect(
        blocked.blockers,
        contains('candidate profile target is incomplete'),
      );
      expect(overridden.readyForProfileUpdate, isTrue);
      expect(
        overridden.target.profileId,
        'openAiCompatible|http://127.0.0.1:4321/v1|override-model',
      );
    },
  );

  test('parses CLI options and validates report schema', () async {
    final options = PersonalEvalProfileHandoffOptions.parse([
      '--suite-report',
      '/tmp/report.json',
      '--out-dir',
      '/tmp/out',
      '--label',
      'handoff',
      '--target-profile-id',
      'profile-id',
      '--target-provider',
      'openAiCompatible',
      '--target-base-url',
      'http://localhost:1234/v1',
      '--target-model',
      'model',
    ]);

    expect(options, isNotNull);
    expect(options!.suiteReportPath, '/tmp/report.json');
    expect(options.outDir, '/tmp/out');
    expect(options.targetProfileId, 'profile-id');
    expect(PersonalEvalProfileHandoffOptions.parse(['--suite-report']), isNull);

    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-profile-handoff-schema-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final invalid = File('${directory.path}/invalid.json')
      ..writeAsStringSync(jsonEncode({'schemaName': 'wrong'}));

    expect(
      () => buildPersonalEvalProfileHandoff(suiteReportFile: invalid),
      throwsFormatException,
    );
  });
}

File _writeSuiteReport({
  required Directory directory,
  String result = 'passed',
  required String recommendation,
  required int hardRegressionCount,
  String? candidateModel,
  String? candidateBaseUrl,
  List<Map<String, Object?>> entries = const [],
}) {
  final file = File('${directory.path}/personal_eval_suite_report.json');
  final candidate = <String, Object?>{'passRate': 1.0};
  if (candidateModel != null) {
    candidate['model'] = candidateModel;
  }
  if (candidateBaseUrl != null) {
    candidate['baseUrl'] = candidateBaseUrl;
  }
  file.writeAsStringSync(
    jsonEncode({
      'schemaName': 'caverno_personal_eval_suite_report',
      'schemaVersion': 1,
      'generatedAt': '2026-06-14T02:03:04.000Z',
      'label': 'incumbent vs candidate',
      'result': result,
      'recommendation': recommendation,
      'hardRegressionCount': hardRegressionCount,
      'watchSignalCount': entries.fold<int>(
        0,
        (sum, entry) => sum + ((entry['watchSignals'] as List?)?.length ?? 0),
      ),
      'improvementCount': entries.fold<int>(
        0,
        (sum, entry) => sum + ((entry['improvements'] as List?)?.length ?? 0),
      ),
      'incumbent': {'passRate': 0.5},
      'candidate': candidate,
      'entries': entries,
    }),
  );
  return file;
}

Map<String, Object?> _entry({
  required String caseId,
  List<String> watchSignals = const [],
  List<String> improvements = const [],
}) {
  return {
    'caseId': caseId,
    'watchSignals': watchSignals,
    'improvements': improvements,
  };
}
