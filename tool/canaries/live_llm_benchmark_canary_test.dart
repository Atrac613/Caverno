import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/apple_foundation_models_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_scoring.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';

import '../live_llm_benchmark_repeat_summary.dart';
import '../live_llm_benchmark_mcp_config.dart';
import '../live_llm_benchmark_app_tool_profile.dart';
import '../live_llm_benchmark_warmup.dart';

/// LL39 headless benchmark canary.
///
/// The diagnostic previously had no runner outside the app, so its probes could
/// only be exercised by tapping a button: nothing could validate them against a
/// real model, and the repeat runs the score's noise floor depends on were not
/// scriptable. This runs the same `LiveLlmDiagnosticService` the app runs and
/// writes the scored report as an artifact.
///
/// It deliberately does **not** assert that the model is good. A benchmark that
/// fails on a weak model is a gate, not a measurement. What it asserts is that
/// the harness measured something: every probe reached a terminal state, and
/// the probes did not all quietly skip. Set
/// `CAVERNO_BENCHMARK_CANARY_MIN_POINTS` to use it as a gate on purpose.
void main() {
  final liveEnabled = Platform.environment['CAVERNO_BENCHMARK_CANARY'] == '1';

  test(
    'live benchmark canary scores the configured model',
    () async {
      final env = _BenchmarkCanaryEnv.fromEnvironment();
      final warmupRuns = <_BenchmarkWarmupRun>[];
      final runs = <_BenchmarkCanaryRun>[];
      final toolProfile = await LiveLlmBenchmarkToolProfile.create(
        mcpServers: env.mcpServers,
        includeAppToolProfile: env.includeAppToolProfile,
      );
      addTearDown(toolProfile.dispose);
      final mcpToolService = toolProfile.service;
      if (env.mcpServers.isNotEmpty) {
        await mcpToolService.connect();
        final connectedCount = mcpToolService.serverStates
            .where((state) => state.status == McpConnectionStatus.connected)
            .length;
        if (connectedCount != env.mcpServers.length) {
          throw StateError(
            'Configured MCP discovery incomplete: connected '
            '$connectedCount of ${env.mcpServers.length} servers.',
          );
        }
      }
      if (env.includeAppToolProfile) {
        final definitions = mcpToolService.getOpenAiToolDefinitions();
        final initialDefinitions =
            ToolDefinitionSearchService.buildInitialSelection(
              definitions,
            ).toolDefinitions;
        final remoteToolCount = mcpToolService.tools.length;
        if (definitions.length != 170 ||
            initialDefinitions.length != 48 ||
            remoteToolCount != 52) {
          throw StateError(
            'Host-app catalog parity failed: expected 170 total, 48 initial, '
            'and 52 remote tools; found ${definitions.length} total, '
            '${initialDefinitions.length} initial, and $remoteToolCount remote.',
          );
        }
      }

      for (var index = 0; index < env.warmupRepeatCount; index += 1) {
        warmupRuns.add(
          await _executeWarmup(
            env: env,
            mcpToolService: mcpToolService,
            index: index,
          ),
        );
      }
      for (var index = 0; index < env.repeatCount; index += 1) {
        runs.add(
          await _executeRun(
            env: env,
            mcpToolService: mcpToolService,
            index: index,
          ),
        );
      }

      final artifact = _writeArtifact(env, warmupRuns, runs);
      stdout.writeln('Benchmark canary artifact: ${artifact.path}');
      for (final run in warmupRuns) {
        final diagnosticRun = run.diagnosticRun;
        if (diagnosticRun != null) {
          stdout.writeln(
            '  warm-up ${run.index} (${run.mode.name}): '
            '${diagnosticRun.score.earnedPoints}/'
            '${diagnosticRun.score.maxPoints} '
            '(attempted ${diagnosticRun.score.attemptedPoints}, '
            '${run.wallClock.inSeconds}s)',
          );
        } else {
          stdout.writeln(
            '  warm-up ${run.index} (${run.mode.name}): marker passed '
            '(${run.wallClock.inMilliseconds}ms)',
          );
        }
      }
      for (final run in runs) {
        stdout.writeln(
          '  run ${run.index}: ${run.score.earnedPoints}/'
          '${run.score.maxPoints} '
          '(attempted ${run.score.attemptedPoints}, '
          '${run.wallClock.inSeconds}s)',
        );
      }

      for (final run in warmupRuns) {
        _validateWarmupRun(env, run);
      }
      for (final run in runs) {
        _validateRun(env, run, label: 'Run');
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_BENCHMARK_CANARY=1 to run the live benchmark canary.',
  );
}

Future<_BenchmarkWarmupRun> _executeWarmup({
  required _BenchmarkCanaryEnv env,
  required McpToolService mcpToolService,
  required int index,
}) async {
  switch (env.warmupMode) {
    case LiveLlmBenchmarkWarmupMode.diagnostic:
      final run = await _executeRun(
        env: env,
        mcpToolService: mcpToolService,
        index: index,
      );
      return _BenchmarkWarmupRun.diagnostic(run);
    case LiveLlmBenchmarkWarmupMode.unrelatedCompletion:
      final dataSource = env.createDataSource();
      final startedAt = DateTime.now();
      final result = await dataSource.createChatCompletion(
        messages: buildUnrelatedLiveLlmBenchmarkWarmupMessages(
          timestamp: startedAt,
        ),
        model: env.settings.effectiveModel,
        temperature: 0.0,
        maxTokens: 64,
      );
      return _BenchmarkWarmupRun.unrelatedCompletion(
        index: index,
        result: result,
        wallClock: DateTime.now().difference(startedAt),
      );
  }
}

Future<_BenchmarkCanaryRun> _executeRun({
  required _BenchmarkCanaryEnv env,
  required McpToolService mcpToolService,
  required int index,
}) async {
  final service = LiveLlmDiagnosticService(
    settings: env.settings,
    chatDataSource: env.createDataSource(),
    mcpToolService: mcpToolService,
    effectiveContextMaxTokens: env.effectiveContextMaxTokens,
  );
  final startedAt = DateTime.now();
  final report = await service.run(probeIds: env.probeIds);
  return _BenchmarkCanaryRun(
    index: index,
    report: report,
    score: LiveLlmDiagnosticScore.fromReport(report),
    wallClock: DateTime.now().difference(startedAt),
  );
}

void _validateRun(
  _BenchmarkCanaryEnv env,
  _BenchmarkCanaryRun run, {
  required String label,
  bool requireRequiredProbePass = false,
}) {
  final nonTerminal = run.report.results
      .where((result) => !result.status.isTerminal)
      .map((result) => result.id)
      .toList(growable: false);
  expect(
    nonTerminal,
    isEmpty,
    reason:
        '$label ${run.index} left probes unfinished: '
        '${nonTerminal.join(", ")}. The report would score them as zero '
        'while nothing actually measured them.',
  );

  final attemptedProbeIds = run.score.probeScores
      .where((probe) => probe.attempted)
      .map((probe) => probe.id)
      .toList(growable: false);
  expect(
    attemptedProbeIds.isNotEmpty || run.score.samplerAttempted,
    isTrue,
    reason:
        '$label ${run.index} attempted no diagnostic probe. Check MCP settings '
        'and the selected provider before trusting this as a pass.',
  );

  if (env.requiredProbeIds.isNotEmpty) {
    final skipped = run.report.results
        .where((result) => env.requiredProbeIds.contains(result.id))
        .where((result) => result.status == LiveLlmDiagnosticStatus.skipped)
        .map((result) => result.id)
        .toList(growable: false);
    expect(
      skipped,
      isEmpty,
      reason:
          '$label ${run.index} skipped probes this canary was told to '
          'verify: ${skipped.join(", ")}.',
    );
    if (requireRequiredProbePass) {
      final failures = run.report.results
          .where((result) => env.requiredProbeIds.contains(result.id))
          .where((result) => result.status != LiveLlmDiagnosticStatus.passed)
          .map((result) => '${result.id}:${result.status.name}')
          .toList(growable: false);
      expect(
        failures,
        isEmpty,
        reason:
            '$label ${run.index} did not pass every required probe: '
            '${failures.join(", ")}.',
      );
    }
  }

  final floor = env.minimumPoints;
  if (floor != null) {
    expect(
      run.score.earnedPoints,
      greaterThanOrEqualTo(floor),
      reason:
          '$label ${run.index} scored ${run.score.earnedPoints}, below the '
          'configured floor of $floor.',
    );
  }
}

void _validateWarmupRun(_BenchmarkCanaryEnv env, _BenchmarkWarmupRun run) {
  final diagnosticRun = run.diagnosticRun;
  if (diagnosticRun != null) {
    _validateRun(
      env,
      diagnosticRun,
      label: 'Warm-up',
      requireRequiredProbePass: true,
    );
    return;
  }
  expect(
    isValidUnrelatedLiveLlmBenchmarkWarmupContent(run.completion!.content),
    isTrue,
    reason:
        'Warm-up ${run.index} did not return the exact unrelated completion '
        'marker. The measured run cannot treat this as a successful warm-up.',
  );
}

File _writeArtifact(
  _BenchmarkCanaryEnv env,
  List<_BenchmarkWarmupRun> warmupRuns,
  List<_BenchmarkCanaryRun> runs,
) {
  final directory = Directory(env.reportDirectory);
  directory.createSync(recursive: true);
  final points =
      runs.map((run) => run.score.earnedPoints).toList(growable: false)..sort();
  final streamingSummary = buildLiveLlmStreamingRepeatSummary(
    runs.map((run) => run.report.streamingMetrics),
  );
  final probeSummaries = buildLiveLlmProbeRepeatSummaries(
    runs.map((run) => run.report.results),
  );
  final warmupProbeSummaries = buildLiveLlmProbeRepeatSummaries(
    warmupRuns
        .map((run) => run.diagnosticRun)
        .whereType<_BenchmarkCanaryRun>()
        .map((run) => run.report.results),
  );
  final payload = <String, dynamic>{
    'schema': 'caverno_live_llm_benchmark_canary',
    'suiteId': LiveLlmDiagnosticSuite.id,
    'suiteVersion': LiveLlmDiagnosticSuite.version,
    'generatedAt': DateTime.now().toIso8601String(),
    'provider': env.settings.llmProvider.name,
    'baseUrl': env.settings.baseUrl,
    'model': env.settings.effectiveModel,
    if (env.settings.embeddingsModel.isNotEmpty)
      'embeddingsModel': env.settings.embeddingsModel,
    if (env.effectiveContextMaxTokens > 0)
      'effectiveContextMaxTokens': env.effectiveContextMaxTokens,
    'appToolProfile': env.includeAppToolProfile,
    'warmupMode': env.warmupMode.name,
    'warmupRepeatCount': warmupRuns.length,
    'repeatCount': runs.length,
    // The spread across repeats is the whole reason this canary takes a repeat
    // count: it is the same noise floor the in-app history derives from stored
    // revisions, measured in one command instead of over several nights.
    'points': points,
    if (points.isNotEmpty) 'minPoints': points.first,
    if (points.isNotEmpty) 'maxPoints': points.last,
    if (points.length > 1) 'spread': points.last - points.first,
    if (streamingSummary.isNotEmpty) 'streamingSummary': streamingSummary,
    if (probeSummaries.isNotEmpty) 'probeSummaries': probeSummaries,
    if (warmupProbeSummaries.isNotEmpty)
      'warmupProbeSummaries': warmupProbeSummaries,
    if (warmupRuns.isNotEmpty)
      'warmupRuns': [for (final run in warmupRuns) run.toJson()],
    'runs': [for (final run in runs) _runToJson(run)],
  };
  final file = File('${directory.path}/benchmark_run.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
  );
  return file;
}

Map<String, Object?> _runToJson(_BenchmarkCanaryRun run) => {
  'index': run.index,
  'wallClockMs': run.wallClock.inMilliseconds,
  ...buildLiveLlmDiagnosticExport(run.report),
};

class _BenchmarkCanaryRun {
  const _BenchmarkCanaryRun({
    required this.index,
    required this.report,
    required this.score,
    required this.wallClock,
  });

  final int index;
  final LiveLlmDiagnosticReport report;
  final LiveLlmDiagnosticScore score;
  final Duration wallClock;
}

class _BenchmarkWarmupRun {
  const _BenchmarkWarmupRun._({
    required this.index,
    required this.mode,
    required this.wallClock,
    this.diagnosticRun,
    this.completion,
  });

  factory _BenchmarkWarmupRun.diagnostic(_BenchmarkCanaryRun run) {
    return _BenchmarkWarmupRun._(
      index: run.index,
      mode: LiveLlmBenchmarkWarmupMode.diagnostic,
      wallClock: run.wallClock,
      diagnosticRun: run,
    );
  }

  factory _BenchmarkWarmupRun.unrelatedCompletion({
    required int index,
    required ChatCompletionResult result,
    required Duration wallClock,
  }) {
    return _BenchmarkWarmupRun._(
      index: index,
      mode: LiveLlmBenchmarkWarmupMode.unrelatedCompletion,
      wallClock: wallClock,
      completion: result,
    );
  }

  final int index;
  final LiveLlmBenchmarkWarmupMode mode;
  final Duration wallClock;
  final _BenchmarkCanaryRun? diagnosticRun;
  final ChatCompletionResult? completion;

  Map<String, Object?> toJson() {
    final diagnostic = diagnosticRun;
    if (diagnostic != null) {
      return {'mode': mode.name, ..._runToJson(diagnostic)};
    }
    final result = completion!;
    return {
      'index': index,
      'mode': mode.name,
      'wallClockMs': wallClock.inMilliseconds,
      'finishReason': result.finishReason,
      'content': result.content,
      'usage': {
        'promptTokens': result.usage.promptTokens,
        'completionTokens': result.usage.completionTokens,
        'totalTokens': result.usage.totalTokens,
        'cachedPromptTokens': result.usage.cachedPromptTokens,
      },
    };
  }
}

class _BenchmarkCanaryEnv {
  const _BenchmarkCanaryEnv({
    required this.settings,
    required this.warmupMode,
    required this.warmupRepeatCount,
    required this.repeatCount,
    required this.reportDirectory,
    required this.probeIds,
    required this.requiredProbeIds,
    required this.minimumPoints,
    required this.effectiveContextMaxTokens,
    required this.mcpServers,
    required this.includeAppToolProfile,
  });

  final AppSettings settings;
  final LiveLlmBenchmarkWarmupMode warmupMode;
  final int warmupRepeatCount;
  final int repeatCount;
  final String reportDirectory;
  final Set<String>? probeIds;
  final Set<String> requiredProbeIds;
  final int? minimumPoints;
  final int effectiveContextMaxTokens;
  final List<McpServerConfig> mcpServers;
  final bool includeAppToolProfile;

  static _BenchmarkCanaryEnv fromEnvironment() {
    final provider = _providerFromEnvironment();
    final isApple = provider == LlmProvider.appleFoundationModels;
    final baseUrl = isApple
        ? 'apple-foundation-models://local'
        : _requiredEnv('CAVERNO_LLM_BASE_URL');
    final model = isApple
        ? AppSettings.appleFoundationModelsModelId
        : _requiredEnv('CAVERNO_LLM_MODEL');
    final mcpServers = loadLiveLlmBenchmarkMcpServers(
      Platform.environment['CAVERNO_BENCHMARK_CANARY_MCP_CONFIG_PATH'],
    );
    return _BenchmarkCanaryEnv(
      settings: AppSettings.defaults().copyWith(
        llmProvider: provider,
        baseUrl: baseUrl,
        apiKey: isApple
            ? ''
            : (Platform.environment['CAVERNO_LLM_API_KEY'] ?? ''),
        model: model,
        embeddingsModel:
            Platform.environment['CAVERNO_EMBEDDINGS_MODEL']?.trim() ?? '',
        demoMode: false,
        mcpEnabled: true,
        mcpUrl: '',
        mcpUrls: const <String>[],
        mcpServers: mcpServers,
      ),
      warmupMode: parseLiveLlmBenchmarkWarmupMode(
        Platform.environment['CAVERNO_BENCHMARK_CANARY_WARMUP_MODE'],
      ),
      warmupRepeatCount: _boundedNonNegativeIntEnv(
        'CAVERNO_BENCHMARK_CANARY_WARMUP_REPEAT_COUNT',
        maximum: 20,
      ),
      repeatCount: _positiveIntEnv('CAVERNO_BENCHMARK_CANARY_REPEAT_COUNT', 1),
      reportDirectory: _requiredEnv('CAVERNO_BENCHMARK_CANARY_REPORT_DIR'),
      probeIds: _idSetEnv('CAVERNO_BENCHMARK_CANARY_PROBE_IDS'),
      requiredProbeIds:
          _idSetEnv('CAVERNO_BENCHMARK_CANARY_REQUIRED_PROBE_IDS') ??
          const <String>{},
      minimumPoints: int.tryParse(
        Platform.environment['CAVERNO_BENCHMARK_CANARY_MIN_POINTS']?.trim() ??
            '',
      ),
      effectiveContextMaxTokens: _boundedNonNegativeIntEnv(
        'CAVERNO_EFFECTIVE_CONTEXT_MAX_TOKENS',
        maximum: 1048576,
      ),
      mcpServers: mcpServers,
      includeAppToolProfile:
          Platform.environment['CAVERNO_BENCHMARK_CANARY_APP_TOOL_PROFILE'] ==
          '1',
    );
  }

  ChatDataSource createDataSource() {
    return switch (settings.llmProvider) {
      LlmProvider.appleFoundationModels => AppleFoundationModelsDataSource(),
      LlmProvider.openAiCompatible => ChatRemoteDataSource(
        baseUrl: settings.baseUrl,
        apiKey: settings.apiKey,
      ),
    };
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for the live benchmark canary.');
  }
  return value;
}

int _positiveIntEnv(String name, int fallback) {
  final parsed = int.tryParse(Platform.environment[name]?.trim() ?? '');
  if (parsed == null || parsed < 1) {
    return fallback;
  }
  return parsed;
}

int _boundedNonNegativeIntEnv(String name, {required int maximum}) {
  final raw = Platform.environment[name]?.trim() ?? '';
  if (raw.isEmpty) return 0;
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0 || parsed > maximum) {
    throw StateError('$name must be between 0 and $maximum.');
  }
  return parsed;
}

Set<String>? _idSetEnv(String name) {
  final raw = Platform.environment[name]?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final ids = raw
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
  return ids.isEmpty ? null : ids;
}

LlmProvider _providerFromEnvironment() {
  final value = Platform.environment['CAVERNO_LLM_PROVIDER']?.trim();
  return switch (value) {
    null ||
    '' ||
    'openAiCompatible' ||
    'openai' ||
    'openai_compatible' => LlmProvider.openAiCompatible,
    'appleFoundationModels' ||
    'apple_foundation_models' ||
    'foundation_models' => LlmProvider.appleFoundationModels,
    _ => throw StateError(
      'Unsupported CAVERNO_LLM_PROVIDER "$value" for the benchmark canary.',
    ),
  };
}
