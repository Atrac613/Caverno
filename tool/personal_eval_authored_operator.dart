import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_authored_corpus.dart';
import 'package:crypto/crypto.dart';

import 'personal_eval_case_manifest.dart' as manifest;
import 'personal_eval_experiment_protocol.dart';
import 'personal_eval_suite_pipeline.dart';

const _planSchemaName = 'caverno_personal_eval_authored_operator_plan';
const _checkpointSchemaName =
    'caverno_personal_eval_authored_operator_checkpoint';
const _operatorSchemaVersion = 1;

Future<void> main(List<String> args) async {
  final options = PersonalEvalAuthoredOperatorOptions.parse(args);
  if (options == null) {
    stderr.writeln(PersonalEvalAuthoredOperatorOptions.usage);
    exitCode = 64;
    return;
  }

  try {
    final operator = await PersonalEvalAuthoredOperator.load(options: options);
    final result = await operator.run();
    stdout.writeln('Personal eval operator plan: ${result.planFile.path}');
    stdout.writeln(
      'Personal eval operator checkpoint: ${result.checkpointFile.path}',
    );
    stdout.writeln(
      options.execute
          ? 'Checkpoint contains ${result.completedEvents}/'
                '${result.totalEvents} completed events.'
          : 'Dry run complete: ${result.totalEvents} events planned.',
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) stderr.writeln(error.path);
    exitCode = 66;
  } on PersonalEvalOperatorException catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

final class PersonalEvalAuthoredOperatorOptions {
  const PersonalEvalAuthoredOperatorOptions({
    required this.protocolPath,
    required this.corpusPath,
    required this.outDir,
    required this.execute,
    required this.resume,
    required this.apiKey,
    required this.maxEvents,
  });

  static const usage = '''
Usage: dart run tool/personal_eval_authored_operator.dart
  --protocol PATH --corpus PATH --out-dir PATH
  [--execute] [--resume] [--max-events COUNT] [--api-key KEY]

The default is a side-effect-free dry run. --execute permits model lifecycle
changes and live candidate calls. --resume requires an existing compatible
checkpoint and skips only events already recorded as completed. --max-events
limits live events in one invocation and requires --execute.
''';

  final String protocolPath;
  final String corpusPath;
  final String outDir;
  final bool execute;
  final bool resume;
  final String apiKey;
  final int? maxEvents;

  static PersonalEvalAuthoredOperatorOptions? parse(List<String> args) {
    String? protocolPath;
    String? corpusPath;
    String? outDir;
    var execute = false;
    var resume = false;
    int? maxEvents;
    var apiKey = Platform.environment['CAVERNO_LLM_API_KEY'] ?? 'no-key';
    for (var index = 0; index < args.length; index += 1) {
      switch (args[index]) {
        case '--protocol':
          protocolPath = _nextValue(args, ++index);
          if (protocolPath == null) return null;
        case '--corpus':
          corpusPath = _nextValue(args, ++index);
          if (corpusPath == null) return null;
        case '--out-dir':
          outDir = _nextValue(args, ++index);
          if (outDir == null) return null;
        case '--api-key':
          apiKey = _nextValue(args, ++index) ?? '';
          if (apiKey.isEmpty) return null;
        case '--max-events':
          maxEvents = int.tryParse(_nextValue(args, ++index) ?? '');
          if (maxEvents == null || maxEvents <= 0) return null;
        case '--execute':
          execute = true;
        case '--resume':
          resume = true;
        default:
          return null;
      }
    }
    if (protocolPath == null || corpusPath == null || outDir == null) {
      return null;
    }
    if (resume && !execute) return null;
    if (maxEvents != null && !execute) return null;
    return PersonalEvalAuthoredOperatorOptions(
      protocolPath: protocolPath,
      corpusPath: corpusPath,
      outDir: outDir,
      execute: execute,
      resume: resume,
      apiKey: apiKey,
      maxEvents: maxEvents,
    );
  }
}

final class PersonalEvalAuthoredOperator {
  PersonalEvalAuthoredOperator._({
    required this.options,
    required this.protocol,
    required this.corpus,
    required this.protocolDigest,
    required PersonalEvalOperatorPorts ports,
  }) : _ports = ports;

  final PersonalEvalAuthoredOperatorOptions options;
  final PersonalEvalExperimentProtocol protocol;
  final PersonalEvalAuthoredCorpus corpus;
  final String protocolDigest;
  final PersonalEvalOperatorPorts _ports;

  static Future<PersonalEvalAuthoredOperator> load({
    required PersonalEvalAuthoredOperatorOptions options,
    PersonalEvalOperatorPorts? ports,
  }) async {
    final protocolFile = File(options.protocolPath).absolute;
    final corpusFile = File(options.corpusPath).absolute;
    final protocolSource = await protocolFile.readAsString();
    final experimentProtocol = PersonalEvalExperimentProtocol.fromJson(
      _jsonObject(protocolSource, protocolFile.path),
      path: protocolFile.path,
    );
    final authoredCorpus = PersonalEvalAuthoredCorpus.parse(
      await corpusFile.readAsString(),
    );
    _validateProtocolCases(experimentProtocol, authoredCorpus);
    _validateSamplerSettings(experimentProtocol);
    return PersonalEvalAuthoredOperator._(
      options: PersonalEvalAuthoredOperatorOptions(
        protocolPath: protocolFile.path,
        corpusPath: corpusFile.path,
        outDir: Directory(options.outDir).absolute.path,
        execute: options.execute,
        resume: options.resume,
        apiKey: options.apiKey,
        maxEvents: options.maxEvents,
      ),
      protocol: experimentProtocol,
      corpus: authoredCorpus,
      protocolDigest: sha256.convert(utf8.encode(protocolSource)).toString(),
      ports: ports ?? ProcessPersonalEvalOperatorPorts(apiKey: options.apiKey),
    );
  }

  Future<PersonalEvalOperatorRunResult> run() async {
    final outDirectory = Directory(options.outDir)..createSync(recursive: true);
    final plan = PersonalEvalOperatorPlan.build(
      protocol: protocol,
      protocolDigest: protocolDigest,
    );
    final planFile = File('${outDirectory.path}/operator_plan.json');
    await _writeJsonAtomically(planFile, plan.toJson());
    await File(
      '${outDirectory.path}/operator_plan.md',
    ).writeAsString(plan.toMarkdown());
    final checkpointFile = File(
      '${outDirectory.path}/operator_checkpoint.json',
    );
    var checkpoint = await _loadOrCreateCheckpoint(
      file: checkpointFile,
      plan: plan,
    );

    if (!options.execute) {
      return PersonalEvalOperatorRunResult(
        planFile: planFile,
        checkpointFile: checkpointFile,
        totalEvents: plan.events.length,
        completedEvents: checkpoint.completedCount,
      );
    }

    final initialModel = await _ports.captureInitialModel(
      models: _comparisonModels,
      baseUrl: _commonBaseUrl,
    );
    Object? runError;
    var eventsStartedThisRun = 0;
    try {
      for (final event in plan.events) {
        if (checkpoint.isCompleted(event.eventId)) continue;
        if (options.maxEvents case final maxEvents?) {
          if (eventsStartedThisRun >= maxEvents) break;
        }
        eventsStartedThisRun += 1;
        checkpoint = checkpoint.markRunning(
          event.eventId,
          DateTime.now().toUtc(),
        );
        await _writeJsonAtomically(checkpointFile, checkpoint.toJson());
        try {
          final model = _modelFor(event.role);
          await _ports.prepareModel(
            target: model,
            otherModels: _comparisonModels.where(
              (item) => item.model != model.model,
            ),
            apiKey: options.apiKey,
          );
          final eventDirectory = Directory(
            '${outDirectory.path}/events/${event.eventId}/'
            'attempt-${checkpoint.attemptFor(event.eventId)}',
          )..createSync(recursive: true);
          final result = await _ports.executeEvent(
            event: event,
            model: model,
            corpusPath: options.corpusPath,
            outputDirectory: eventDirectory,
            executionBudget: protocol.executionBudget,
            apiKey: options.apiKey,
          );
          result.requireMatches(event: event, model: model);
          checkpoint = checkpoint.markCompleted(event.eventId, result);
          await _writeJsonAtomically(checkpointFile, checkpoint.toJson());
        } catch (error) {
          checkpoint = checkpoint.markFailed(
            event.eventId,
            error.toString(),
            DateTime.now().toUtc(),
          );
          await _writeJsonAtomically(checkpointFile, checkpoint.toJson());
          rethrow;
        }
      }
      if (checkpoint.completedCount == plan.events.length) {
        await _buildSuiteArtifacts(checkpoint, outDirectory);
      }
    } catch (error) {
      runError = error;
    } finally {
      try {
        await _ports.restoreInitialModel(
          model: initialModel,
          models: _comparisonModels,
          baseUrl: _commonBaseUrl,
          apiKey: options.apiKey,
        );
      } catch (restoreError) {
        runError ??= restoreError;
      }
    }
    if (runError != null) {
      throw PersonalEvalOperatorException(runError.toString());
    }
    return PersonalEvalOperatorRunResult(
      planFile: planFile,
      checkpointFile: checkpointFile,
      totalEvents: plan.events.length,
      completedEvents: checkpoint.completedCount,
    );
  }

  Iterable<PersonalEvalProtocolModel> get _comparisonModels => [
    protocol.incumbent,
    protocol.candidate,
  ];

  String get _commonBaseUrl {
    final incumbent = protocol.incumbent.baseUrl;
    final candidate = protocol.candidate.baseUrl;
    if (incumbent == null || candidate == null || incumbent != candidate) {
      throw const FormatException(
        'The authored operator requires one explicit shared baseUrl.',
      );
    }
    return incumbent;
  }

  PersonalEvalProtocolModel _modelFor(PersonalEvalModelRole role) =>
      role == PersonalEvalModelRole.incumbent
      ? protocol.incumbent
      : protocol.candidate;

  Future<PersonalEvalOperatorCheckpoint> _loadOrCreateCheckpoint({
    required File file,
    required PersonalEvalOperatorPlan plan,
  }) async {
    if (!file.existsSync()) {
      final checkpoint = PersonalEvalOperatorCheckpoint.create(plan);
      await _writeJsonAtomically(file, checkpoint.toJson());
      return checkpoint;
    }
    final existing = PersonalEvalOperatorCheckpoint.fromJson(
      _jsonObject(await file.readAsString(), file.path),
      path: file.path,
    );
    existing.requireCompatible(plan);
    if (options.execute && !options.resume) {
      throw const PersonalEvalOperatorException(
        'Checkpoint already exists. Use a new out-dir or pass --resume.',
      );
    }
    return existing;
  }

  Future<void> _buildSuiteArtifacts(
    PersonalEvalOperatorCheckpoint checkpoint,
    Directory outDirectory,
  ) async {
    final manifests = <String, File>{};
    final incumbentLogs = <String, File>{};
    final candidateLogs = <String, File>{};
    final incumbentResults =
        <String, manifest.PersonalEvalVerificationResult>{};
    final candidateResults =
        <String, manifest.PersonalEvalVerificationResult>{};
    for (final event in checkpoint.events) {
      final result = event.result;
      if (event.status != PersonalEvalOperatorEventStatus.completed ||
          result == null) {
        throw PersonalEvalOperatorException(
          'Cannot build suite artifacts before ${event.eventId} completes.',
        );
      }
      manifests.putIfAbsent(result.caseId, () => File(result.manifestPath));
      final logs = event.role == PersonalEvalModelRole.incumbent
          ? incumbentLogs
          : candidateLogs;
      final results = event.role == PersonalEvalModelRole.incumbent
          ? incumbentResults
          : candidateResults;
      logs[event.trialKey] = File(result.logPath);
      results[event.trialKey] = manifest.PersonalEvalVerificationResult.values
          .byName(result.verificationResult);
    }
    await runPersonalEvalSuitePipeline(
      manifestFiles: manifests.values.toList(growable: false),
      incumbent: PersonalEvalSuitePipelineRunInput(
        label: 'incumbent',
        caseLogFiles: incumbentLogs,
        verificationResults: incumbentResults,
        model: protocol.incumbent.model,
        baseUrl: protocol.incumbent.baseUrl,
      ),
      candidate: PersonalEvalSuitePipelineRunInput(
        label: 'candidate',
        caseLogFiles: candidateLogs,
        verificationResults: candidateResults,
        model: protocol.candidate.model,
        baseUrl: protocol.candidate.baseUrl,
      ),
      outDir: Directory('${outDirectory.path}/suite'),
      label: protocol.label,
      protocolFile: File(options.protocolPath),
    );
  }
}

abstract interface class PersonalEvalOperatorPorts {
  Future<String?> captureInitialModel({
    required Iterable<PersonalEvalProtocolModel> models,
    required String baseUrl,
  });

  Future<void> prepareModel({
    required PersonalEvalProtocolModel target,
    required Iterable<PersonalEvalProtocolModel> otherModels,
    required String apiKey,
  });

  Future<PersonalEvalOperatorEventResult> executeEvent({
    required PersonalEvalOperatorEvent event,
    required PersonalEvalProtocolModel model,
    required String corpusPath,
    required Directory outputDirectory,
    required PersonalEvalExecutionBudget executionBudget,
    required String apiKey,
  });

  Future<void> restoreInitialModel({
    required String? model,
    required Iterable<PersonalEvalProtocolModel> models,
    required String baseUrl,
    required String apiKey,
  });
}

final class ProcessPersonalEvalOperatorPorts
    implements PersonalEvalOperatorPorts {
  ProcessPersonalEvalOperatorPorts({
    required this.apiKey,
    this.warmUpRetryDelay = const Duration(seconds: 5),
    this.warmUpMaxAttempts = 12,
  });

  final String apiKey;
  final Duration warmUpRetryDelay;
  final int warmUpMaxAttempts;
  final HttpClient _client = HttpClient();

  @override
  Future<String?> captureInitialModel({
    required Iterable<PersonalEvalProtocolModel> models,
    required String baseUrl,
  }) async {
    final states = await _modelStates(baseUrl);
    final loaded = models
        .where((model) => states[model.model] == 'loaded')
        .map((model) => model.model)
        .toList();
    if (loaded.length > 1) {
      throw const PersonalEvalOperatorException(
        'More than one comparison model is loaded before execution.',
      );
    }
    return loaded.isEmpty ? null : loaded.single;
  }

  @override
  Future<void> prepareModel({
    required PersonalEvalProtocolModel target,
    required Iterable<PersonalEvalProtocolModel> otherModels,
    required String apiKey,
  }) async {
    final baseUrl = target.baseUrl!;
    await _warmUp(target);
    final states = await _modelStates(baseUrl);
    if (states[target.model] != 'loaded') {
      throw PersonalEvalOperatorException(
        'Router warm-up completed but ${target.model} is '
        '${states[target.model] ?? 'missing'}.',
      );
    }
    final stillLoaded = otherModels
        .where((model) => states[model.model] == 'loaded')
        .map((model) => model.model)
        .toList(growable: false);
    if (stillLoaded.isNotEmpty) {
      throw PersonalEvalOperatorException(
        'Router left multiple comparison models loaded: '
        '${[target.model, ...stillLoaded].join(', ')}.',
      );
    }
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
    final settings = model.samplerSettings;
    final environment = Map<String, String>.from(Platform.environment)
      ..addAll({
        'CAVERNO_PERSONAL_EVAL_AUTHORED_LIVE': '1',
        'CAVERNO_LLM_BASE_URL': model.baseUrl!,
        'CAVERNO_LLM_API_KEY': apiKey,
        'CAVERNO_LLM_MODEL': model.model,
        'CAVERNO_PERSONAL_EVAL_CASE_ID': event.caseId,
        'CAVERNO_PERSONAL_EVAL_TRIAL_ID': event.trialId,
        'CAVERNO_PERSONAL_EVAL_MODEL_ROLE': event.role.jsonValue,
        'CAVERNO_PERSONAL_EVAL_EVENT_ID': event.eventId,
        'CAVERNO_PERSONAL_EVAL_CORPUS': corpusPath,
        'CAVERNO_PERSONAL_EVAL_EVENT_OUT_DIR': outputDirectory.path,
        'CAVERNO_PERSONAL_EVAL_TEMPERATURE': '${settings['temperature']}',
        'CAVERNO_PERSONAL_EVAL_TOP_P': '${settings['topP']}',
        'CAVERNO_PERSONAL_EVAL_MAX_TOKENS': '${settings['maxTokens']}',
        'CAVERNO_PERSONAL_EVAL_MAX_DURATION_MS':
            '${executionBudget.maxDurationMs}',
        'CAVERNO_PERSONAL_EVAL_MAX_TURNS': '${executionBudget.maxTurns}',
        'CAVERNO_PERSONAL_EVAL_MAX_TOOL_CALLS':
            '${executionBudget.maxToolCalls}',
      });
    final process = await Process.start(
      'fvm',
      [
        'flutter',
        'test',
        'tool/canaries/personal_eval_authored_live_canary_test.dart',
        '--plain-name',
        'live authored personal eval event',
        '-r',
        'compact',
      ],
      workingDirectory: Directory.current.path,
      environment: environment,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode.timeout(
      Duration(milliseconds: executionBudget.maxDurationMs + 120000),
      onTimeout: () {
        process.kill();
        return 124;
      },
    );
    final processOut = await stdoutFuture;
    final processError = await stderrFuture;
    await File(
      '${outputDirectory.path}/executor_stdout.txt',
    ).writeAsString(processOut);
    await File(
      '${outputDirectory.path}/executor_stderr.txt',
    ).writeAsString(processError);
    if (exitCode != 0) {
      throw PersonalEvalOperatorException(
        'Event ${event.eventId} executor exited with code $exitCode.',
      );
    }
    final resultFile = File('${outputDirectory.path}/event_result.json');
    final result = PersonalEvalOperatorEventResult.fromJson(
      _jsonObject(await resultFile.readAsString(), resultFile.path),
      path: resultFile.path,
    );
    if (!File(result.logPath).existsSync() ||
        !File(result.manifestPath).existsSync()) {
      throw PersonalEvalOperatorException(
        'Event ${event.eventId} did not produce its declared artifacts.',
      );
    }
    return result;
  }

  @override
  Future<void> restoreInitialModel({
    required String? model,
    required Iterable<PersonalEvalProtocolModel> models,
    required String baseUrl,
    required String apiKey,
  }) async {
    if (model == null) {
      final states = await _modelStates(baseUrl);
      for (final candidate in models) {
        if (states[candidate.model] == 'loaded') {
          await _lifecycle(baseUrl, 'unload', candidate.model);
          await _waitForState(baseUrl, candidate.model, 'unloaded');
        }
      }
      return;
    }
    final target = models.singleWhere((item) => item.model == model);
    await prepareModel(
      target: target,
      otherModels: models.where((item) => item.model != model),
      apiKey: apiKey,
    );
  }

  Future<void> _warmUp(PersonalEvalProtocolModel model) async {
    for (var index = 0; index < model.warmupIterations; index += 1) {
      Object? lastError;
      for (var attempt = 1; attempt <= warmUpMaxAttempts; attempt += 1) {
        try {
          await _warmUpOnce(model);
          lastError = null;
          break;
        } catch (error) {
          lastError = error;
          if (attempt < warmUpMaxAttempts) {
            await Future<void>.delayed(warmUpRetryDelay);
          }
        }
      }
      if (lastError != null) {
        throw PersonalEvalOperatorException(
          'Warm-up failed for ${model.model} after $warmUpMaxAttempts '
          'attempts: $lastError',
        );
      }
    }
  }

  /// Tool definitions that pad the readiness probe up to the shape of a real
  /// eval request.
  ///
  /// Measured on 2026-08-12: the old 'Reply with OK.' probe carried **16**
  /// prompt tokens while the eval request sent immediately afterwards carried
  /// **9,471**. Readiness proven ~600x smaller than the work is not readiness:
  /// three trials in that pilot passed warm-up and then took an immediate
  /// `proxy error: 500`, and each was scored as a model failure. Sixty
  /// definitions reproduce that payload closely enough to gate on it.
  static List<Map<String, dynamic>> _readinessProbeTools() {
    return List<Map<String, dynamic>>.generate(60, (index) {
      return {
        'type': 'function',
        'function': {
          'name': 'readiness_probe_tool_$index',
          'description':
              'Readiness probe padding that mirrors the size and shape of a '
                  'Caverno tool definition so the endpoint is exercised with a '
                  'realistic request before the eval scores anything. ' *
              3,
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string', 'description': 'Filesystem path.'},
              'content': {'type': 'string', 'description': 'Body to write.'},
              'flag': {'type': 'boolean', 'description': 'Optional switch.'},
            },
            'required': ['path'],
          },
        },
      };
    });
  }

  Future<void> _warmUpOnce(PersonalEvalProtocolModel model) async {
    final uri = Uri.parse(
      '${_stripV1Slash(model.baseUrl!)}/v1/chat/completions',
    );
    final request = await _client.postUrl(uri);
    _applyHeaders(request);
    _writeJsonBody(request, {
      'model': model.model,
      'messages': [
        {
          'role': 'system',
          'content':
              'You are replaying a recorded coding task to evaluate a model.',
        },
        {'role': 'user', 'content': 'Reply with OK.'},
      ],
      // The probe has to be at least as demanding as the request that follows
      // it, or it cannot gate on the endpoint's ability to serve that request.
      'tools': _readinessProbeTools(),
      'temperature': model.samplerSettings['temperature'],
      'top_p': model.samplerSettings['topP'],
      'max_tokens': 8,
    });
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PersonalEvalOperatorException(
        'Warm-up failed for ${model.model}: HTTP ${response.statusCode}: '
        '${_compactDiagnostic(body)}',
      );
    }
  }

  Future<Map<String, String>> _modelStates(String baseUrl) async {
    final request = await _client.getUrl(
      Uri.parse('${_stripV1Slash(baseUrl)}/v1/models'),
    );
    _applyHeaders(request);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw PersonalEvalOperatorException(
        'Model catalog failed with HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return {
      for (final item in (decoded['data'] as List).cast<Map<String, dynamic>>())
        item['id'] as String:
            ((item['status'] as Map<String, dynamic>?)?['value'] as String? ??
            'unknown'),
    };
  }

  Future<void> _lifecycle(String baseUrl, String action, String model) async {
    final request = await _client.postUrl(
      Uri.parse('${_stripV1Slash(baseUrl)}/models/$action'),
    );
    _applyHeaders(request);
    _writeJsonBody(request, {'model': model});
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PersonalEvalOperatorException(
        'Model $action failed for $model: HTTP ${response.statusCode}.',
      );
    }
  }

  Future<void> _waitForState(
    String baseUrl,
    String model,
    String expected,
  ) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      if ((await _modelStates(baseUrl))[model] == expected) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw PersonalEvalOperatorException(
      'Timed out waiting for $model to become $expected.',
    );
  }

  void _applyHeaders(HttpClientRequest request) {
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
  }

  void _writeJsonBody(HttpClientRequest request, Map<String, Object?> value) {
    final bytes = utf8.encode(jsonEncode(value));
    request.contentLength = bytes.length;
    request.add(bytes);
  }
}

final class PersonalEvalOperatorPlan {
  const PersonalEvalOperatorPlan({
    required this.protocolDigest,
    required this.events,
  });

  final String protocolDigest;
  final List<PersonalEvalOperatorEvent> events;

  factory PersonalEvalOperatorPlan.build({
    required PersonalEvalExperimentProtocol protocol,
    required String protocolDigest,
  }) {
    final events = <PersonalEvalOperatorEvent>[];
    for (final trial in protocol.trialOrders) {
      for (final role in [trial.first, trial.second]) {
        events.add(
          PersonalEvalOperatorEvent(
            eventId:
                '${events.length + 1}-${trial.caseId}-${trial.trialId}-${role.jsonValue}',
            sequence: events.length + 1,
            caseId: trial.caseId,
            trialId: trial.trialId,
            role: role,
          ),
        );
      }
    }
    return PersonalEvalOperatorPlan(
      protocolDigest: protocolDigest,
      events: List.unmodifiable(events),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaName': _planSchemaName,
    'schemaVersion': _operatorSchemaVersion,
    'protocolSha256': protocolDigest,
    'eventCount': events.length,
    'events': events.map((event) => event.toJson()).toList(),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Authored Personal Eval Operator Plan')
      ..writeln()
      ..writeln('- Protocol SHA-256: `$protocolDigest`')
      ..writeln('- Events: `${events.length}`')
      ..writeln()
      ..writeln('| Sequence | Case | Trial | Role |')
      ..writeln('|----------|------|-------|------|');
    for (final event in events) {
      buffer.writeln(
        '| ${event.sequence} | ${event.caseId} | ${event.trialId} | '
        '${event.role.jsonValue} |',
      );
    }
    return buffer.toString();
  }
}

final class PersonalEvalOperatorEvent {
  const PersonalEvalOperatorEvent({
    required this.eventId,
    required this.sequence,
    required this.caseId,
    required this.trialId,
    required this.role,
  });

  final String eventId;
  final int sequence;
  final String caseId;
  final String trialId;
  final PersonalEvalModelRole role;
  String get trialKey => '$caseId#$trialId';

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'sequence': sequence,
    'caseId': caseId,
    'trialId': trialId,
    'role': role.jsonValue,
  };
}

enum PersonalEvalOperatorEventStatus { pending, running, completed, failed }

final class PersonalEvalOperatorCheckpoint {
  const PersonalEvalOperatorCheckpoint({
    required this.protocolDigest,
    required this.events,
  });

  final String protocolDigest;
  final List<PersonalEvalOperatorCheckpointEvent> events;
  int get completedCount => events
      .where(
        (event) => event.status == PersonalEvalOperatorEventStatus.completed,
      )
      .length;

  factory PersonalEvalOperatorCheckpoint.create(
    PersonalEvalOperatorPlan plan,
  ) => PersonalEvalOperatorCheckpoint(
    protocolDigest: plan.protocolDigest,
    events: [
      for (final event in plan.events)
        PersonalEvalOperatorCheckpointEvent.fromPlan(event),
    ],
  );

  factory PersonalEvalOperatorCheckpoint.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    if (json['schemaName'] != _checkpointSchemaName ||
        json['schemaVersion'] != _operatorSchemaVersion) {
      throw FormatException('Unsupported operator checkpoint in $path.');
    }
    return PersonalEvalOperatorCheckpoint(
      protocolDigest: json['protocolSha256'] as String,
      events: [
        for (final raw in (json['events'] as List).cast<Map<String, dynamic>>())
          PersonalEvalOperatorCheckpointEvent.fromJson(raw, path: path),
      ],
    );
  }

  bool isCompleted(String eventId) => events.any(
    (event) =>
        event.eventId == eventId &&
        event.status == PersonalEvalOperatorEventStatus.completed,
  );

  int attemptFor(String eventId) =>
      events.singleWhere((event) => event.eventId == eventId).attempt;

  void requireCompatible(PersonalEvalOperatorPlan plan) {
    if (protocolDigest != plan.protocolDigest ||
        events.length != plan.events.length) {
      throw const FormatException(
        'Checkpoint does not match the current protocol.',
      );
    }
    for (var index = 0; index < events.length; index += 1) {
      if (events[index].eventId != plan.events[index].eventId) {
        throw const FormatException(
          'Checkpoint event order does not match the current protocol.',
        );
      }
    }
  }

  PersonalEvalOperatorCheckpoint markRunning(String eventId, DateTime at) =>
      _replace(
        eventId,
        (event) => event.copyWith(
          status: PersonalEvalOperatorEventStatus.running,
          attempt: event.attempt + 1,
          startedAt: at,
          completedAt: null,
          error: null,
        ),
      );

  PersonalEvalOperatorCheckpoint markCompleted(
    String eventId,
    PersonalEvalOperatorEventResult result,
  ) => _replace(
    eventId,
    (event) => event.copyWith(
      status: PersonalEvalOperatorEventStatus.completed,
      completedAt: result.completedAt,
      result: result,
      error: null,
    ),
  );

  PersonalEvalOperatorCheckpoint markFailed(
    String eventId,
    String error,
    DateTime at,
  ) => _replace(
    eventId,
    (event) => event.copyWith(
      status: PersonalEvalOperatorEventStatus.failed,
      completedAt: at,
      error: error,
    ),
  );

  PersonalEvalOperatorCheckpoint _replace(
    String eventId,
    PersonalEvalOperatorCheckpointEvent Function(
      PersonalEvalOperatorCheckpointEvent,
    )
    update,
  ) => PersonalEvalOperatorCheckpoint(
    protocolDigest: protocolDigest,
    events: [
      for (final event in events)
        event.eventId == eventId ? update(event) : event,
    ],
  );

  Map<String, dynamic> toJson() => {
    'schemaName': _checkpointSchemaName,
    'schemaVersion': _operatorSchemaVersion,
    'protocolSha256': protocolDigest,
    'completedCount': completedCount,
    'events': events.map((event) => event.toJson()).toList(),
  };
}

final class PersonalEvalOperatorCheckpointEvent {
  const PersonalEvalOperatorCheckpointEvent({
    required this.eventId,
    required this.sequence,
    required this.caseId,
    required this.trialId,
    required this.role,
    required this.status,
    required this.attempt,
    this.startedAt,
    this.completedAt,
    this.result,
    this.error,
  });

  factory PersonalEvalOperatorCheckpointEvent.fromPlan(
    PersonalEvalOperatorEvent event,
  ) => PersonalEvalOperatorCheckpointEvent(
    eventId: event.eventId,
    sequence: event.sequence,
    caseId: event.caseId,
    trialId: event.trialId,
    role: event.role,
    status: PersonalEvalOperatorEventStatus.pending,
    attempt: 0,
  );

  factory PersonalEvalOperatorCheckpointEvent.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) => PersonalEvalOperatorCheckpointEvent(
    eventId: json['eventId'] as String,
    sequence: json['sequence'] as int,
    caseId: json['caseId'] as String,
    trialId: json['trialId'] as String,
    role: PersonalEvalModelRole.parse(json['role'])!,
    status: PersonalEvalOperatorEventStatus.values.byName(
      json['status'] as String,
    ),
    attempt: json['attempt'] as int? ?? 0,
    startedAt: _optionalDate(json['startedAt'], path),
    completedAt: _optionalDate(json['completedAt'], path),
    result: json['result'] is Map<String, dynamic>
        ? PersonalEvalOperatorEventResult.fromJson(
            json['result'] as Map<String, dynamic>,
            path: path,
          )
        : null,
    error: json['error'] as String?,
  );

  final String eventId;
  final int sequence;
  final String caseId;
  final String trialId;
  final PersonalEvalModelRole role;
  final PersonalEvalOperatorEventStatus status;
  final int attempt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final PersonalEvalOperatorEventResult? result;
  final String? error;
  String get trialKey => '$caseId#$trialId';

  PersonalEvalOperatorCheckpointEvent copyWith({
    PersonalEvalOperatorEventStatus? status,
    int? attempt,
    DateTime? startedAt,
    DateTime? completedAt,
    PersonalEvalOperatorEventResult? result,
    String? error,
  }) => PersonalEvalOperatorCheckpointEvent(
    eventId: eventId,
    sequence: sequence,
    caseId: caseId,
    trialId: trialId,
    role: role,
    status: status ?? this.status,
    attempt: attempt ?? this.attempt,
    startedAt: startedAt ?? this.startedAt,
    completedAt: completedAt,
    result: result ?? this.result,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'sequence': sequence,
    'caseId': caseId,
    'trialId': trialId,
    'role': role.jsonValue,
    'status': status.name,
    'attempt': attempt,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (result != null) 'result': result!.toJson(),
    if (error != null) 'error': error,
  };
}

final class PersonalEvalOperatorEventResult {
  const PersonalEvalOperatorEventResult({
    required this.eventId,
    required this.caseId,
    required this.trialId,
    required this.role,
    required this.model,
    required this.baseUrl,
    required this.startedAt,
    required this.completedAt,
    required this.verificationResult,
    required this.logPath,
    required this.manifestPath,
    this.error,
  });

  factory PersonalEvalOperatorEventResult.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    if (json['schemaName'] != 'caverno_personal_eval_authored_event_result' ||
        json['schemaVersion'] != 1) {
      throw FormatException('Unsupported event result in $path.');
    }
    return PersonalEvalOperatorEventResult(
      eventId: json['eventId'] as String,
      caseId: json['caseId'] as String,
      trialId: json['trialId'] as String,
      role: json['role'] as String,
      model: json['model'] as String,
      baseUrl: json['baseUrl'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: DateTime.parse(json['completedAt'] as String),
      verificationResult: json['verificationResult'] as String,
      logPath: json['logPath'] as String,
      manifestPath: json['manifestPath'] as String,
      error: json['error'] as String?,
    );
  }

  final String eventId;
  final String caseId;
  final String trialId;
  final String role;
  final String model;
  final String baseUrl;
  final DateTime startedAt;
  final DateTime completedAt;
  final String verificationResult;
  final String logPath;
  final String manifestPath;
  final String? error;

  void requireMatches({
    required PersonalEvalOperatorEvent event,
    required PersonalEvalProtocolModel model,
  }) {
    if (eventId != event.eventId ||
        caseId != event.caseId ||
        trialId != event.trialId ||
        role != event.role.jsonValue ||
        this.model != model.model ||
        baseUrl != model.baseUrl) {
      throw PersonalEvalOperatorException(
        'Event result identity does not match ${event.eventId}.',
      );
    }
    if (verificationResult != 'passed' && verificationResult != 'failed') {
      throw PersonalEvalOperatorException(
        'Event ${event.eventId} has no conclusive verification result.',
      );
    }
    if (completedAt.isBefore(startedAt) ||
        logPath.trim().isEmpty ||
        manifestPath.trim().isEmpty) {
      throw PersonalEvalOperatorException(
        'Event ${event.eventId} returned incomplete artifact metadata.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'schemaName': 'caverno_personal_eval_authored_event_result',
    'schemaVersion': 1,
    'eventId': eventId,
    'caseId': caseId,
    'trialId': trialId,
    'role': role,
    'model': model,
    'baseUrl': baseUrl,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'verificationResult': verificationResult,
    'logPath': logPath,
    'manifestPath': manifestPath,
    if (error != null) 'error': error,
  };
}

final class PersonalEvalOperatorRunResult {
  const PersonalEvalOperatorRunResult({
    required this.planFile,
    required this.checkpointFile,
    required this.totalEvents,
    required this.completedEvents,
  });

  final File planFile;
  final File checkpointFile;
  final int totalEvents;
  final int completedEvents;
}

final class PersonalEvalOperatorException implements Exception {
  const PersonalEvalOperatorException(this.message);
  final String message;

  @override
  String toString() => message;
}

void _validateProtocolCases(
  PersonalEvalExperimentProtocol protocol,
  PersonalEvalAuthoredCorpus corpus,
) {
  final ids = corpus.cases.map((item) => item.caseId).toSet();
  for (final trial in protocol.trialOrders) {
    if (!ids.contains(trial.caseId)) {
      throw FormatException(
        'Protocol references unknown authored case ${trial.caseId}.',
      );
    }
  }
}

void _validateSamplerSettings(PersonalEvalExperimentProtocol protocol) {
  for (final entry in {
    'incumbent': protocol.incumbent,
    'candidate': protocol.candidate,
  }.entries) {
    final settings = entry.value.samplerSettings;
    for (final key in const ['temperature', 'topP']) {
      if (settings[key] is! num) {
        throw FormatException('${entry.key} samplerSettings.$key is required.');
      }
    }
    if (settings['maxTokens'] is! int) {
      throw FormatException(
        '${entry.key} samplerSettings.maxTokens is required.',
      );
    }
    final unsupported = settings.keys.toSet().difference({
      'temperature',
      'topP',
      'maxTokens',
    });
    if (unsupported.isNotEmpty) {
      throw FormatException(
        '${entry.key} has unsupported sampler settings: '
        '${unsupported.join(', ')}.',
      );
    }
  }
}

Map<String, dynamic> _jsonObject(String source, String path) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

Future<void> _writeJsonAtomically(
  File destination,
  Map<String, dynamic> value,
) async {
  await destination.parent.create(recursive: true);
  final temporary = File('${destination.path}.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
  await temporary.rename(destination.path);
}

String? _nextValue(List<String> args, int index) {
  if (index >= args.length || args[index].startsWith('--')) return null;
  return args[index];
}

DateTime? _optionalDate(Object? value, String path) {
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid timestamp in $path.');
  return DateTime.parse(value);
}

String _stripV1Slash(String baseUrl) {
  var value = baseUrl.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  if (value.endsWith('/v1')) value = value.substring(0, value.length - 3);
  return value;
}

String _compactDiagnostic(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) return '<empty response>';
  return compact.length <= 500 ? compact : '${compact.substring(0, 500)}...';
}
