import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_experiment_protocol.dart';

void main() {
  group('PersonalEvalExperimentProtocol', () {
    test('canonicalizes reproducible conditions and balanced trial order', () {
      final generatedAt = DateTime.utc(2026, 8, 12, 1, 2, 3);
      final protocol = PersonalEvalExperimentProtocol.fromJson(
        _validConfig(),
        generatedAt: generatedAt,
      );

      final json = protocol.toJson();
      expect(json['schemaName'], 'caverno_personal_eval_experiment_protocol');
      expect(json['schemaVersion'], 2);
      expect(json['generatedAt'], generatedAt.toIso8601String());
      expect(json['studyIntent'], 'model_selection');
      expect(json['decisionCriteria'], {
        'minimumEffectTaskCount': 20,
        'minimumHeldOutEffectTaskCount': 6,
      });
      expect((json['incumbent'] as Map<String, dynamic>)['samplerSettings'], {
        'temperature': 0.2,
        'topP': 0.95,
        'maxTokens': 8192,
      });
      expect((json['trialOrders'] as List).first, {
        'caseId': 'case-a',
        'trialId': 'trial-1',
        'first': 'incumbent',
        'second': 'candidate',
      });
      expect(
        protocol.toMarkdown(),
        contains('1 incumbent-first / 1 candidate-first'),
      );
      expect(protocol.toMarkdown(), contains('qwen3.6-27b-vision'));
      expect(
        protocol.toMarkdown(),
        contains('Study intent: `model_selection`'),
      );
      expect(protocol.toMarkdown(), contains('Minimum effect tasks: `20`'));
    });

    test('accepts corpus design without decision criteria', () {
      final config = _validConfig()
        ..['studyIntent'] = 'corpus_design'
        ..remove('decisionCriteria');

      final protocol = PersonalEvalExperimentProtocol.fromJson(config);

      expect(protocol.studyIntent, PersonalEvalStudyIntent.corpusDesign);
      expect(protocol.decisionCriteria, isNull);
      expect(protocol.toJson(), isNot(contains('decisionCriteria')));
    });

    test('requires intent-specific decision criteria', () {
      final missingIntent = _validConfig()..remove('studyIntent');
      final missingCriteria = _validConfig()..remove('decisionCriteria');
      final designWithCriteria = _validConfig()
        ..['studyIntent'] = 'corpus_design';

      expect(
        () => PersonalEvalExperimentProtocol.fromJson(missingIntent),
        throwsFormatException,
      );
      expect(
        () => PersonalEvalExperimentProtocol.fromJson(missingCriteria),
        throwsFormatException,
      );
      expect(
        () => PersonalEvalExperimentProtocol.fromJson(designWithCriteria),
        throwsFormatException,
      );
    });

    test('rejects a duplicate case and trial identity', () {
      final config = _validConfig();
      (config['trialOrders'] as List).add({
        'caseId': 'case-a',
        'trialId': 'trial-1',
        'first': 'candidate',
      });

      expect(
        () => PersonalEvalExperimentProtocol.fromJson(config),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Duplicate trial order: case-a#trial-1'),
          ),
        ),
      );
    });

    test('rejects globally unbalanced AB/BA order', () {
      final config = _validConfig();
      config['trialOrders'] = [
        {'caseId': 'case-a', 'trialId': 'trial-1', 'first': 'incumbent'},
        {'caseId': 'case-b', 'trialId': 'trial-1', 'first': 'incumbent'},
      ];

      expect(
        () => PersonalEvalExperimentProtocol.fromJson(config),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('AB/BA order is unbalanced for the experiment'),
          ),
        ),
      );
    });

    test('rejects incomplete warm-up and execution conditions', () {
      final missingWarmup = _validConfig();
      ((missingWarmup['candidate'] as Map<String, dynamic>)['warmup']
              as Map<String, dynamic>)['completed'] =
          false;
      expect(
        () => PersonalEvalExperimentProtocol.fromJson(missingWarmup),
        throwsFormatException,
      );

      final missingSampler = _validConfig();
      (missingSampler['candidate'] as Map<String, dynamic>)['samplerSettings'] =
          <String, dynamic>{};
      expect(
        () => PersonalEvalExperimentProtocol.fromJson(missingSampler),
        throwsFormatException,
      );

      final invalidBudget = _validConfig();
      (invalidBudget['executionBudget'] as Map<String, dynamic>)['maxTurns'] =
          0;
      expect(
        () => PersonalEvalExperimentProtocol.fromJson(invalidBudget),
        throwsFormatException,
      );
    });

    test('builds a canonical protocol from a config file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'personal-eval-protocol-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final configFile = File('${directory.path}/config.json');
      await configFile.writeAsString(jsonEncode(_validConfig()));
      final generatedAt = DateTime.utc(2026, 8, 12);

      final protocol = await buildPersonalEvalExperimentProtocol(
        configFile: configFile,
        generatedAt: generatedAt,
      );

      expect(protocol.generatedAt, generatedAt);
      expect(protocol.trialOrders, hasLength(2));
      expect(protocol.executionBudget.maxDurationMs, 900000);
    });
  });

  group('PersonalEvalExperimentProtocolOptions', () {
    test('parses the config and output directory', () {
      final options = PersonalEvalExperimentProtocolOptions.parse([
        '--config',
        'protocol.json',
        '--out-dir',
        'reports',
      ]);

      expect(options, isNotNull);
      expect(options!.configPath, 'protocol.json');
      expect(options.outDir, 'reports');
    });

    test('rejects missing and unknown options', () {
      expect(
        PersonalEvalExperimentProtocolOptions.parse(['--config', 'x.json']),
        isNull,
      );
      expect(
        PersonalEvalExperimentProtocolOptions.parse([
          '--config',
          'x.json',
          '--out-dir',
          'reports',
          '--unknown',
        ]),
        isNull,
      );
    });
  });
}

Map<String, dynamic> _validConfig() => {
  'schemaName': 'caverno_personal_eval_experiment_protocol',
  'schemaVersion': 2,
  'label': '27B vs 35B coding pilot',
  'studyIntent': 'model_selection',
  'decisionCriteria': {
    'minimumEffectTaskCount': 20,
    'minimumHeldOutEffectTaskCount': 6,
  },
  'incumbent': {
    'model': 'qwen3.6-35b-a3b-vision',
    'baseUrl': 'http://localhost:1234/v1',
    'samplerSettings': {'temperature': 0.2, 'topP': 0.95, 'maxTokens': 8192},
    'warmup': {'completed': true, 'iterations': 1},
  },
  'candidate': {
    'model': 'qwen3.6-27b-vision',
    'baseUrl': 'http://localhost:1234/v1',
    'samplerSettings': {'temperature': 0.2, 'topP': 0.95, 'maxTokens': 8192},
    'warmup': {'completed': true, 'iterations': 1},
  },
  'executionBudget': {
    'maxDurationMs': 900000,
    'maxTurns': 24,
    'maxToolCalls': 100,
  },
  'trialOrders': [
    {'caseId': 'case-a', 'trialId': 'trial-1', 'first': 'incumbent'},
    {'caseId': 'case-a', 'trialId': 'trial-2', 'first': 'candidate'},
  ],
};
