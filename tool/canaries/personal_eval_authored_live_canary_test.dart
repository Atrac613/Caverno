import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/session_logging_chat_datasource.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_authored_chat_replay_driver_factory.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_authored_corpus.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_authored_case_runner.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled =
      Platform.environment['CAVERNO_PERSONAL_EVAL_AUTHORED_LIVE'] == '1';

  test(
    'live authored personal eval event',
    () async {
      final config = _LiveEventConfig.fromEnvironment();
      final outputDirectory = Directory(config.outputDirectory)
        ..createSync(recursive: true);
      final corpus = PersonalEvalAuthoredCorpus.parse(
        File(config.corpusPath).readAsStringSync(),
      );
      final evalCase = corpus.cases.singleWhere(
        (item) => item.caseId == config.caseId,
      );
      final logStore = LlmSessionLogStore(
        rootDirectoryProvider: () async =>
            Directory('${outputDirectory.path}/session_logs'),
      );
      final verificationRunner = ProcessPersonalEvalVerificationRunner(
        timeout: Duration(milliseconds: config.maxDurationMs),
      );
      final dataSource = SessionLoggingChatDataSource(
        delegate: ChatRemoteDataSource(
          baseUrl: config.baseUrl,
          apiKey: config.apiKey,
          defaultTopP: config.topP,
        ),
        logStore: logStore,
      );
      final driverFactory = PersonalEvalAuthoredChatReplayDriverFactory(
        dataSource: dataSource,
        sessionLogStore: logStore,
        model: config.model,
        verificationRunner: verificationRunner,
        maxTokens: config.maxTokens,
        maxTurns: config.maxTurns,
        maxToolCalls: config.maxToolCalls,
        temperature: config.temperature,
        runId: config.eventId,
      );
      final runner = PersonalEvalAuthoredCaseRunner(
        driverFactory: driverFactory.call,
        verificationRunner: verificationRunner,
        repositoryRoot: Directory.current.path,
        seedRoot: corpus.seedRoot,
      );

      final startedAt = DateTime.now().toUtc();
      final outcome = await runner.run(evalCase);
      final completedAt = DateTime.now().toUtc();
      final manifestFile = File('${outputDirectory.path}/case_manifest.json');
      await manifestFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(evalCase.toCaseManifestJson())}\n',
      );
      final resultFile = File('${outputDirectory.path}/event_result.json');
      await resultFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'schemaName': 'caverno_personal_eval_authored_event_result', 'schemaVersion': 1, 'eventId': config.eventId, 'caseId': evalCase.caseId, 'trialId': config.trialId, 'role': config.role, 'model': config.model, 'baseUrl': config.baseUrl, 'startedAt': startedAt.toIso8601String(), 'completedAt': completedAt.toIso8601String(), 'verificationResult': outcome.verificationResult.name, 'logPath': outcome.logPath, 'manifestPath': manifestFile.path, if (outcome.error != null) 'error': outcome.error})}\n',
      );

      expect(outcome.skipped, isFalse);
      expect(
        outcome.verificationResult,
        isNot(PersonalEvalVerificationResult.inconclusive),
        reason: outcome.error,
      );
    },
    skip: enabled ? false : 'Set CAVERNO_PERSONAL_EVAL_AUTHORED_LIVE=1 to run.',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

class _LiveEventConfig {
  const _LiveEventConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.caseId,
    required this.trialId,
    required this.role,
    required this.eventId,
    required this.corpusPath,
    required this.outputDirectory,
    required this.temperature,
    required this.maxTokens,
    required this.topP,
    required this.maxDurationMs,
    required this.maxTurns,
    required this.maxToolCalls,
  });

  factory _LiveEventConfig.fromEnvironment() {
    final environment = Platform.environment;
    return _LiveEventConfig(
      baseUrl: _required(environment, 'CAVERNO_LLM_BASE_URL'),
      apiKey: environment['CAVERNO_LLM_API_KEY'] ?? 'no-key',
      model: _required(environment, 'CAVERNO_LLM_MODEL'),
      caseId: _required(environment, 'CAVERNO_PERSONAL_EVAL_CASE_ID'),
      trialId: _required(environment, 'CAVERNO_PERSONAL_EVAL_TRIAL_ID'),
      role: _required(environment, 'CAVERNO_PERSONAL_EVAL_MODEL_ROLE'),
      eventId: _required(environment, 'CAVERNO_PERSONAL_EVAL_EVENT_ID'),
      corpusPath: _required(environment, 'CAVERNO_PERSONAL_EVAL_CORPUS'),
      outputDirectory: _required(
        environment,
        'CAVERNO_PERSONAL_EVAL_EVENT_OUT_DIR',
      ),
      temperature: double.parse(
        _required(environment, 'CAVERNO_PERSONAL_EVAL_TEMPERATURE'),
      ),
      maxTokens: int.parse(
        _required(environment, 'CAVERNO_PERSONAL_EVAL_MAX_TOKENS'),
      ),
      topP: double.parse(_required(environment, 'CAVERNO_PERSONAL_EVAL_TOP_P')),
      maxDurationMs: int.parse(
        _required(environment, 'CAVERNO_PERSONAL_EVAL_MAX_DURATION_MS'),
      ),
      maxTurns: int.parse(
        _required(environment, 'CAVERNO_PERSONAL_EVAL_MAX_TURNS'),
      ),
      maxToolCalls: int.parse(
        _required(environment, 'CAVERNO_PERSONAL_EVAL_MAX_TOOL_CALLS'),
      ),
    );
  }

  final String baseUrl;
  final String apiKey;
  final String model;
  final String caseId;
  final String trialId;
  final String role;
  final String eventId;
  final String corpusPath;
  final String outputDirectory;
  final double temperature;
  final int maxTokens;
  final double topP;
  final int maxDurationMs;
  final int maxTurns;
  final int maxToolCalls;
}

String _required(Map<String, String> environment, String name) {
  final value = environment[name]?.trim() ?? '';
  if (value.isEmpty) throw StateError('$name is required.');
  return value;
}
