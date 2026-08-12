import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/personal_eval_authored_operator.dart';
import '../../tool/personal_eval_experiment_protocol.dart';

void main() {
  late Directory temporary;
  late File protocolFile;
  late String corpusPath;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('authored_operator_');
    corpusPath = File('tool/personal_eval_corpus/corpus.json').absolute.path;
    protocolFile = File('${temporary.path}/protocol.json')
      ..writeAsStringSync(jsonEncode(_protocolConfig()));
  });

  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test(
    'dry run writes the locked four-event AB/BA plan without ports',
    () async {
      final ports = _FakePorts();
      final operator = await PersonalEvalAuthoredOperator.load(
        options: _operatorOptions(
          protocolFile: protocolFile,
          corpusPath: corpusPath,
          outDir: '${temporary.path}/dry-run',
        ),
        ports: ports,
      );

      final result = await operator.run();
      final plan = jsonDecode(result.planFile.readAsStringSync());
      final checkpoint = jsonDecode(result.checkpointFile.readAsStringSync());

      expect(result.totalEvents, 4);
      expect((plan['events'] as List).map((item) => item['role']), [
        'incumbent',
        'candidate',
        'candidate',
        'incumbent',
      ]);
      expect(checkpoint['completedCount'], 0);
      expect(ports.preparedModels, isEmpty);
      expect(ports.executedEvents, isEmpty);
    },
  );

  test('resume skips completed events and retries the failed event', () async {
    final outDir = '${temporary.path}/resume';
    final firstPorts = _FakePorts(
      failEventId: '2-authored_textkit_trailing_run-trial-1-candidate',
    );
    final first = await PersonalEvalAuthoredOperator.load(
      options: _operatorOptions(
        protocolFile: protocolFile,
        corpusPath: corpusPath,
        outDir: outDir,
        execute: true,
      ),
      ports: firstPorts,
    );

    await expectLater(
      first.run(),
      throwsA(isA<PersonalEvalOperatorException>()),
    );
    final firstCheckpoint =
        jsonDecode(File('$outDir/operator_checkpoint.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(firstCheckpoint['completedCount'], 1);
    expect(firstPorts.restoredModels, ['qwen3.6-27b-vision']);

    final resumedPorts = _FakePorts(
      failEventId: '4-authored_textkit_trailing_run-trial-2-incumbent',
    );
    final resumed = await PersonalEvalAuthoredOperator.load(
      options: _operatorOptions(
        protocolFile: protocolFile,
        corpusPath: corpusPath,
        outDir: outDir,
        execute: true,
        resume: true,
      ),
      ports: resumedPorts,
    );

    await expectLater(
      resumed.run(),
      throwsA(isA<PersonalEvalOperatorException>()),
    );
    expect(resumedPorts.executedEvents, [
      '2-authored_textkit_trailing_run-trial-1-candidate',
      '3-authored_textkit_trailing_run-trial-2-candidate',
      '4-authored_textkit_trailing_run-trial-2-incumbent',
    ]);
    final resumedCheckpoint =
        jsonDecode(File('$outDir/operator_checkpoint.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(resumedCheckpoint['completedCount'], 3);
    final resumedEvents = (resumedCheckpoint['events'] as List)
        .cast<Map<String, dynamic>>();
    expect(resumedEvents[0]['attempt'], 1);
    expect(resumedEvents[1]['attempt'], 2);
  });

  test('execute refuses an existing checkpoint without resume', () async {
    final outDir = '${temporary.path}/existing';
    final dryRun = await PersonalEvalAuthoredOperator.load(
      options: _operatorOptions(
        protocolFile: protocolFile,
        corpusPath: corpusPath,
        outDir: outDir,
      ),
      ports: _FakePorts(),
    );
    await dryRun.run();
    final execute = await PersonalEvalAuthoredOperator.load(
      options: _operatorOptions(
        protocolFile: protocolFile,
        corpusPath: corpusPath,
        outDir: outDir,
        execute: true,
      ),
      ports: _FakePorts(),
    );

    await expectLater(
      execute.run(),
      throwsA(
        isA<PersonalEvalOperatorException>().having(
          (error) => error.message,
          'message',
          contains('--resume'),
        ),
      ),
    );
  });

  test('the committed pilot plans two balanced trials for all cases', () async {
    final operator = await PersonalEvalAuthoredOperator.load(
      options: PersonalEvalAuthoredOperatorOptions(
        protocolPath: File(
          'tool/personal_eval_corpus/protocol_config.json',
        ).absolute.path,
        corpusPath: corpusPath,
        outDir: '${temporary.path}/committed-pilot',
        execute: false,
        resume: false,
        apiKey: 'no-key',
        maxEvents: null,
      ),
      ports: _FakePorts(),
    );

    final result = await operator.run();
    final plan = jsonDecode(result.planFile.readAsStringSync());
    final events = (plan['events'] as List).cast<Map<String, dynamic>>();

    expect(events, hasLength(104));
    expect(events.map((event) => event['caseId']).toSet(), hasLength(26));
    for (final caseId in events.map((event) => event['caseId']).toSet()) {
      final caseEvents = events.where((event) => event['caseId'] == caseId);
      expect(caseEvents, hasLength(4), reason: '$caseId event count');
      expect(
        caseEvents.map((event) => event['role']).toSet(),
        {'incumbent', 'candidate'},
        reason: '$caseId role balance',
      );
    }
  });

  test('a completed run feeds the existing suite pipeline', () async {
    final outDir = '${temporary.path}/complete';
    final operator = await PersonalEvalAuthoredOperator.load(
      options: _operatorOptions(
        protocolFile: protocolFile,
        corpusPath: corpusPath,
        outDir: outDir,
        execute: true,
      ),
      ports: _FakePorts(),
    );

    final result = await operator.run();

    expect(result.completedEvents, 4);
    expect(
      File('$outDir/suite/personal_eval_suite_report.json').existsSync(),
      isTrue,
    );
    expect(
      File('$outDir/suite/personal_eval_suite_report.md').existsSync(),
      isTrue,
    );
  });

  test(
    'a bounded pilot restores state and resumes into the full suite',
    () async {
      final outDir = '${temporary.path}/bounded';
      final pilotPorts = _FakePorts();
      final pilot = await PersonalEvalAuthoredOperator.load(
        options: _operatorOptions(
          protocolFile: protocolFile,
          corpusPath: corpusPath,
          outDir: outDir,
          execute: true,
          maxEvents: 2,
        ),
        ports: pilotPorts,
      );

      final pilotResult = await pilot.run();

      expect(pilotResult.completedEvents, 2);
      expect(pilotPorts.executedEvents, [
        '1-authored_textkit_trailing_run-trial-1-incumbent',
        '2-authored_textkit_trailing_run-trial-1-candidate',
      ]);
      expect(pilotPorts.restoredModels, ['qwen3.6-27b-vision']);
      expect(
        File('$outDir/suite/personal_eval_suite_report.json').existsSync(),
        isFalse,
      );

      final resumePorts = _FakePorts(startAt: DateTime.utc(2026, 8, 12, 1));
      final resumed = await PersonalEvalAuthoredOperator.load(
        options: _operatorOptions(
          protocolFile: protocolFile,
          corpusPath: corpusPath,
          outDir: outDir,
          execute: true,
          resume: true,
          maxEvents: 2,
        ),
        ports: resumePorts,
      );

      final resumedResult = await resumed.run();

      expect(resumedResult.completedEvents, 4);
      expect(resumePorts.executedEvents, [
        '3-authored_textkit_trailing_run-trial-2-candidate',
        '4-authored_textkit_trailing_run-trial-2-incumbent',
      ]);
      expect(
        File('$outDir/suite/personal_eval_suite_report.json').existsSync(),
        isTrue,
      );
    },
  );

  test(
    'process ports retry warm-up while loaded state becomes ready',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var warmUpRequests = 0;
      final warmUpContentLengths = <int>[];
      final serving = server.forEach((request) async {
        if (request.uri.path == '/v1/models') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'id': 'candidate',
                  'status': {
                    'value': warmUpRequests == 0 ? 'unloaded' : 'loaded',
                  },
                },
                {
                  'id': 'incumbent',
                  'status': {
                    'value': warmUpRequests == 0 ? 'loaded' : 'unloaded',
                  },
                },
              ],
            }),
          );
        } else if (request.uri.path == '/v1/chat/completions') {
          warmUpRequests += 1;
          warmUpContentLengths.add(request.contentLength);
          await request.drain<void>();
          request.response.statusCode = warmUpRequests == 1 ? 503 : 200;
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      final baseUrl = 'http://${server.address.host}:${server.port}/v1';
      final candidate = PersonalEvalProtocolModel(
        model: 'candidate',
        baseUrl: baseUrl,
        samplerSettings: const {
          'temperature': 0.2,
          'topP': 0.95,
          'maxTokens': 8192,
        },
        warmupIterations: 1,
      );
      final incumbent = PersonalEvalProtocolModel(
        model: 'incumbent',
        baseUrl: baseUrl,
        samplerSettings: candidate.samplerSettings,
        warmupIterations: 1,
      );
      final ports = ProcessPersonalEvalOperatorPorts(
        apiKey: 'no-key',
        warmUpRetryDelay: Duration.zero,
        warmUpMaxAttempts: 3,
      );

      try {
        await ports.prepareModel(
          target: candidate,
          otherModels: [incumbent],
          apiKey: 'no-key',
        );
      } finally {
        await server.close(force: true);
        await serving;
      }

      expect(warmUpRequests, 2);
      // The probe must be at least as demanding as the eval request it gates.
      // A 16-token ping passed readiness in the 2026-08-12 pilot and the
      // ~9,471-token request that followed took an immediate 500, which was
      // then scored as a model failure.
      expect(
        warmUpContentLengths,
        everyElement(greaterThan(20000)),
        reason: 'readiness probe must carry a realistic tool payload',
      );
    },
  );
}

PersonalEvalAuthoredOperatorOptions _operatorOptions({
  required File protocolFile,
  required String corpusPath,
  required String outDir,
  bool execute = false,
  bool resume = false,
  int? maxEvents,
}) => PersonalEvalAuthoredOperatorOptions(
  protocolPath: protocolFile.path,
  corpusPath: corpusPath,
  outDir: outDir,
  execute: execute,
  resume: resume,
  apiKey: 'no-key',
  maxEvents: maxEvents,
);

Map<String, dynamic> _protocolConfig() => {
  'schemaName': 'caverno_personal_eval_experiment_protocol',
  'schemaVersion': 2,
  'label': '27B versus 35B authored pilot',
  'studyIntent': 'model_selection',
  'decisionCriteria': {
    'minimumEffectTaskCount': 1,
    'minimumHeldOutEffectTaskCount': 0,
  },
  'incumbent': {
    'model': 'qwen3.6-35b-a3b-vision',
    'baseUrl': 'http://192.168.100.241:1234/v1',
    'samplerSettings': {'temperature': 0.2, 'topP': 0.95, 'maxTokens': 8192},
    'warmup': {'completed': true, 'iterations': 1},
  },
  'candidate': {
    'model': 'qwen3.6-27b-vision',
    'baseUrl': 'http://192.168.100.241:1234/v1',
    'samplerSettings': {'temperature': 0.2, 'topP': 0.95, 'maxTokens': 8192},
    'warmup': {'completed': true, 'iterations': 1},
  },
  'executionBudget': {
    'maxDurationMs': 900000,
    'maxTurns': 24,
    'maxToolCalls': 100,
  },
  'trialOrders': [
    {
      'caseId': 'authored_textkit_trailing_run',
      'trialId': 'trial-1',
      'first': 'incumbent',
    },
    {
      'caseId': 'authored_textkit_trailing_run',
      'trialId': 'trial-2',
      'first': 'candidate',
    },
  ],
};

class _FakePorts implements PersonalEvalOperatorPorts {
  _FakePorts({this.failEventId, DateTime? startAt})
    : _clock = startAt ?? DateTime.utc(2026, 8, 12);

  final String? failEventId;
  final List<String> preparedModels = [];
  final List<String> executedEvents = [];
  final List<String?> restoredModels = [];
  DateTime _clock;

  @override
  Future<String?> captureInitialModel({
    required Iterable<PersonalEvalProtocolModel> models,
    required String baseUrl,
  }) async => 'qwen3.6-27b-vision';

  @override
  Future<void> prepareModel({
    required PersonalEvalProtocolModel target,
    required Iterable<PersonalEvalProtocolModel> otherModels,
    required String apiKey,
  }) async {
    preparedModels.add(target.model);
  }

  @override
  Future<PersonalEvalOperatorEventResult> executeEvent({
    required PersonalEvalOperatorEvent event,
    required PersonalEvalProtocolModel model,
    required String corpusPath,
    required Directory outputDirectory,
    required PersonalEvalExecutionBudget executionBudget,
    required String apiKey,
  }) async {
    executedEvents.add(event.eventId);
    if (event.eventId == failEventId) throw StateError('injected failure');
    outputDirectory.createSync(recursive: true);
    final startedAt = _clock;
    _clock = _clock.add(const Duration(seconds: 1));
    final logFile = File('${outputDirectory.path}/log.jsonl')
      ..writeAsStringSync(
        jsonEncode({
          'schemaName': 'caverno_llm_session_log_entry',
          'schemaVersion': 1,
          'timestamp': startedAt.toIso8601String(),
          'startedAt': startedAt.toIso8601String(),
          'finishedAt': _clock.toIso8601String(),
          'durationMs': 1000,
          'operation': 'createChatCompletion',
          'context': {
            'phase': 'personal_eval_replay',
            'workspaceMode': 'coding',
          },
          'request': {
            'messages': [
              {'role': 'user', 'content': 'Run the replay task.'},
            ],
            'tools': <Object?>[],
            'model': model.model,
            'temperature': 0.2,
            'maxTokens': 8192,
          },
          'response': {'finishReason': 'stop', 'content': 'done'},
        }),
      );
    final manifestFile = File('${outputDirectory.path}/manifest.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaName': 'caverno_personal_eval_case_manifest',
          'schemaVersion': 1,
          'generatedAt': startedAt.toIso8601String(),
          'caseId': event.caseId,
          'title': 'Authored task',
          'readiness': 'ready',
          'split': 'heldIn',
          'origin': 'authored',
          'task': {
            'prompt': 'Fix the fixture.',
            'repoStateRef': '',
            'fixtureDirectory': 'fixture',
            'verificationCommand': 'dart run bin/verify.dart',
            'verificationResult': 'inconclusive',
            'workspaceMode': 'coding',
          },
          'consent': {
            'explicitUserConsent': false,
            'recordedAt': startedAt.toIso8601String(),
            'scope': 'personal_eval_authored_fixture_task',
          },
          'privacy': {
            'localOnly': false,
            'anonymization': 'none',
            'exportPolicy': 'shareable',
          },
        }),
      );
    return PersonalEvalOperatorEventResult(
      eventId: event.eventId,
      caseId: event.caseId,
      trialId: event.trialId,
      role: event.role.jsonValue,
      model: model.model,
      baseUrl: model.baseUrl!,
      startedAt: startedAt,
      completedAt: _clock,
      verificationResult: 'passed',
      logPath: logFile.path,
      manifestPath: manifestFile.path,
    );
  }

  @override
  Future<void> restoreInitialModel({
    required String? model,
    required Iterable<PersonalEvalProtocolModel> models,
    required String baseUrl,
    required String apiKey,
  }) async {
    restoredModels.add(model);
  }
}
