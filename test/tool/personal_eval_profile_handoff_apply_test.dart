import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/settings/domain/entities/app_settings.dart';

import '../../tool/personal_eval_profile_handoff_apply.dart';

void main() {
  test('dry run builds an updated profile without writing settings', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-profile-apply-dry-run-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final settingsFile = File('${directory.path}/settings.json');
    final outputFile = File('${directory.path}/updated_settings.json');
    _writeJson(settingsFile, AppSettings.defaults().toJson());
    final handoffFile = _writeHandoff(directory);

    final result = await applyPersonalEvalProfileHandoff(
      handoffFile: handoffFile,
      settingsFile: settingsFile,
      outFile: outputFile,
    );

    expect(result.dryRun, isTrue);
    expect(result.wroteSettings, isFalse);
    expect(result.changed, isTrue);
    expect(result.createdProfile, isTrue);
    expect(outputFile.existsSync(), isFalse);
    expect(result.updatedSettings.modelCapabilityProfiles, hasLength(1));
    expect(
      result.updatedProfile.probeMetadata,
      containsPair('personalEval.lastRecommendation', 'candidate_ready'),
    );
    expect(result.toMarkdown(), contains('Mode: `dry_run`'));
  });

  test(
    'apply writes merged metadata while preserving profile capabilities',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'personal-eval-profile-apply-write-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final targetProfileId = _targetProfileId();
      final existingProfile = ModelCapabilityProfile(
        id: targetProfileId,
        baseUrl: 'http://localhost:1234/v1',
        model: 'candidate-model',
        toolCallStyle: ModelToolCallStyle.nativeToolCalls,
        structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
        editFormatPreference: ModelEditFormatPreference.unifiedDiff,
        probeMetadata: const {
          'keep': 'yes',
          'personalEval.lastRecommendation': 'old',
        },
      ).normalizedForPersistence();
      final settingsFile = File('${directory.path}/settings.json');
      final outputFile = File('${directory.path}/updated_settings.json');
      _writeJson(
        settingsFile,
        AppSettings.defaults()
            .copyWith(modelCapabilityProfiles: [existingProfile])
            .toJson(),
      );
      final handoffFile = _writeHandoff(
        directory,
        metadataPatch: const {
          'personalEval.lastRecommendation': 'candidate_ready',
          'personalEval.caseCount': '2',
        },
      );

      final result = await applyPersonalEvalProfileHandoff(
        handoffFile: handoffFile,
        settingsFile: settingsFile,
        outFile: outputFile,
        dryRun: false,
      );

      expect(result.wroteSettings, isTrue);
      expect(result.createdProfile, isFalse);
      expect(outputFile.existsSync(), isTrue);
      final updated = AppSettings.fromJson(
        jsonDecode(outputFile.readAsStringSync()) as Map<String, dynamic>,
      );
      expect(updated.modelCapabilityProfiles, hasLength(1));
      final profile = updated.modelCapabilityProfiles.single;
      expect(profile.toolCallStyle, ModelToolCallStyle.nativeToolCalls);
      expect(
        profile.structuredOutputSupport,
        ModelStructuredOutputSupport.jsonSchema,
      );
      expect(
        profile.editFormatPreference,
        ModelEditFormatPreference.unifiedDiff,
      );
      expect(profile.probeMetadata, containsPair('keep', 'yes'));
      expect(
        profile.probeMetadata,
        containsPair('personalEval.lastRecommendation', 'candidate_ready'),
      );
      expect(
        profile.probeMetadata,
        containsPair('personalEval.caseCount', '2'),
      );
    },
  );

  test('blocked handoff is refused without writing output', () async {
    final directory = Directory.systemTemp.createTempSync(
      'personal-eval-profile-apply-blocked-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final settingsFile = File('${directory.path}/settings.json');
    final outputFile = File('${directory.path}/updated_settings.json');
    _writeJson(settingsFile, AppSettings.defaults().toJson());
    final handoffFile = _writeHandoff(
      directory,
      ready: false,
      result: 'blocked',
      action: 'do_not_apply_profile_metadata',
      blockers: const ['suite recommendation is reject_candidate'],
    );

    expect(
      () => applyPersonalEvalProfileHandoff(
        handoffFile: handoffFile,
        settingsFile: settingsFile,
        outFile: outputFile,
        dryRun: false,
      ),
      throwsA(isA<PersonalEvalProfileHandoffApplyException>()),
    );
    expect(outputFile.existsSync(), isFalse);
  });

  test('parses explicit apply options and rejects unsafe combinations', () {
    final apply = PersonalEvalProfileHandoffApplyOptions.parse([
      '--handoff',
      '/tmp/handoff.json',
      '--settings',
      '/tmp/settings.json',
      '--apply',
      '--out',
      '/tmp/updated.json',
    ]);
    final dryRun = PersonalEvalProfileHandoffApplyOptions.parse([
      '--handoff',
      '/tmp/handoff.json',
      '--settings',
      '/tmp/settings.json',
      '--dry-run',
    ]);

    expect(apply, isNotNull);
    expect(apply!.dryRun, isFalse);
    expect(apply.outPath, '/tmp/updated.json');
    expect(dryRun, isNotNull);
    expect(dryRun!.dryRun, isTrue);
    expect(
      PersonalEvalProfileHandoffApplyOptions.parse([
        '--handoff',
        '/tmp/handoff.json',
        '--settings',
        '/tmp/settings.json',
        '--apply',
      ]),
      isNull,
    );
    expect(
      PersonalEvalProfileHandoffApplyOptions.parse([
        '--handoff',
        '/tmp/handoff.json',
        '--settings',
        '/tmp/settings.json',
        '--apply',
        '--dry-run',
        '--out',
        '/tmp/updated.json',
      ]),
      isNull,
    );
  });
}

File _writeHandoff(
  Directory directory, {
  bool ready = true,
  String result = 'ready',
  String action = 'apply_profile_metadata',
  List<String> blockers = const [],
  Map<String, String> metadataPatch = const {
    'personalEval.lastRecommendation': 'candidate_ready',
    'personalEval.caseCount': '1',
  },
}) {
  final file = File('${directory.path}/personal_eval_profile_handoff.json');
  _writeJson(file, {
    'schemaName': 'caverno_personal_eval_profile_handoff',
    'schemaVersion': 1,
    'generatedAt': '2026-06-15T01:02:03.000Z',
    'label': 'incumbent vs candidate',
    'suiteReportPath': '${directory.path}/personal_eval_suite_report.json',
    'result': result,
    'action': action,
    'readyForProfileUpdate': ready,
    'blockers': blockers,
    'target': {
      'provider': 'openAiCompatible',
      'baseUrl': 'http://localhost:1234/v1',
      'model': 'candidate-model',
      'profileId': _targetProfileId(),
    },
    'metrics': {'caseCount': 1},
    'probeMetadataPatch': metadataPatch,
    'watchSignals': const [],
    'improvements': const ['ping-cli: duration decreased 5000->3500 ms'],
  });
  return file;
}

String _targetProfileId() {
  return ModelCapabilityProfile.buildId(
    provider: LlmProvider.openAiCompatible,
    baseUrl: 'http://localhost:1234/v1',
    model: 'candidate-model',
  );
}

void _writeJson(File file, Map<String, dynamic> json) {
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}
