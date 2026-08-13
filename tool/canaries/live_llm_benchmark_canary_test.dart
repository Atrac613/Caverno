import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/apple_foundation_models_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_scoring.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_service.dart';

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
      final runs = <_BenchmarkCanaryRun>[];

      for (var index = 0; index < env.repeatCount; index += 1) {
        final service = LiveLlmDiagnosticService(
          settings: env.settings,
          chatDataSource: env.createDataSource(),
          mcpToolService: McpToolService(),
          effectiveContextMaxTokens: env.effectiveContextMaxTokens,
        );
        final startedAt = DateTime.now();
        final report = await service.run(probeIds: env.probeIds);
        runs.add(
          _BenchmarkCanaryRun(
            index: index,
            report: report,
            score: LiveLlmDiagnosticScore.fromReport(report),
            wallClock: DateTime.now().difference(startedAt),
          ),
        );
      }

      final artifact = _writeArtifact(env, runs);
      stdout.writeln('Benchmark canary artifact: ${artifact.path}');
      for (final run in runs) {
        stdout.writeln(
          '  run ${run.index}: ${run.score.earnedPoints}/'
          '${run.score.maxPoints} '
          '(attempted ${run.score.attemptedPoints}, '
          '${run.wallClock.inSeconds}s)',
        );
      }

      for (final run in runs) {
        final nonTerminal = run.report.results
            .where((result) => !result.status.isTerminal)
            .map((result) => result.id)
            .toList(growable: false);
        expect(
          nonTerminal,
          isEmpty,
          reason:
              'Run ${run.index} left probes unfinished: '
              '${nonTerminal.join(", ")}. The report would score them as zero '
              'while nothing actually measured them.',
        );

        // A run where everything skipped is the failure mode a green canary
        // hides: it proves the harness started, not that it measured anything.
        // Capability-only probes may intentionally carry zero conformance
        // points, so use attempted probe state instead of the score denominator.
        final attemptedProbeIds = run.score.probeScores
            .where((probe) => probe.attempted)
            .map((probe) => probe.id)
            .toList(growable: false);
        expect(
          attemptedProbeIds.isNotEmpty || run.score.samplerAttempted,
          isTrue,
          reason:
              'Run ${run.index} attempted no diagnostic probe. Check MCP settings '
              'and the selected provider before trusting this as a pass.',
        );

        if (env.requiredProbeIds.isNotEmpty) {
          final skipped = run.report.results
              .where((result) => env.requiredProbeIds.contains(result.id))
              .where(
                (result) => result.status == LiveLlmDiagnosticStatus.skipped,
              )
              .map((result) => result.id)
              .toList(growable: false);
          expect(
            skipped,
            isEmpty,
            reason:
                'Run ${run.index} skipped probes this canary was told to '
                'verify: ${skipped.join(", ")}.',
          );
        }

        final floor = env.minimumPoints;
        if (floor != null) {
          expect(
            run.score.earnedPoints,
            greaterThanOrEqualTo(floor),
            reason:
                'Run ${run.index} scored ${run.score.earnedPoints}, below the '
                'configured floor of $floor.',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_BENCHMARK_CANARY=1 to run the live benchmark canary.',
  );
}

File _writeArtifact(_BenchmarkCanaryEnv env, List<_BenchmarkCanaryRun> runs) {
  final directory = Directory(env.reportDirectory);
  directory.createSync(recursive: true);
  final points =
      runs.map((run) => run.score.earnedPoints).toList(growable: false)..sort();
  final payload = <String, dynamic>{
    'schema': 'caverno_live_llm_benchmark_canary',
    'suiteId': LiveLlmDiagnosticSuite.id,
    'suiteVersion': LiveLlmDiagnosticSuite.version,
    'generatedAt': DateTime.now().toIso8601String(),
    'baseUrl': env.settings.baseUrl,
    'model': env.settings.effectiveModel,
    if (env.settings.embeddingsModel.isNotEmpty)
      'embeddingsModel': env.settings.embeddingsModel,
    if (env.effectiveContextMaxTokens > 0)
      'effectiveContextMaxTokens': env.effectiveContextMaxTokens,
    'repeatCount': runs.length,
    // The spread across repeats is the whole reason this canary takes a repeat
    // count: it is the same noise floor the in-app history derives from stored
    // revisions, measured in one command instead of over several nights.
    'points': points,
    if (points.isNotEmpty) 'minPoints': points.first,
    if (points.isNotEmpty) 'maxPoints': points.last,
    if (points.length > 1) 'spread': points.last - points.first,
    'runs': [
      for (final run in runs)
        {
          'index': run.index,
          'wallClockMs': run.wallClock.inMilliseconds,
          ...buildLiveLlmDiagnosticExport(run.report),
        },
    ],
  };
  final file = File('${directory.path}/benchmark_run.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
  );
  return file;
}

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

class _BenchmarkCanaryEnv {
  const _BenchmarkCanaryEnv({
    required this.settings,
    required this.repeatCount,
    required this.reportDirectory,
    required this.probeIds,
    required this.requiredProbeIds,
    required this.minimumPoints,
    required this.effectiveContextMaxTokens,
  });

  final AppSettings settings;
  final int repeatCount;
  final String reportDirectory;
  final Set<String>? probeIds;
  final Set<String> requiredProbeIds;
  final int? minimumPoints;
  final int effectiveContextMaxTokens;

  static _BenchmarkCanaryEnv fromEnvironment() {
    final provider = _providerFromEnvironment();
    final isApple = provider == LlmProvider.appleFoundationModels;
    final baseUrl = isApple
        ? 'apple-foundation-models://local'
        : _requiredEnv('CAVERNO_LLM_BASE_URL');
    final model = isApple
        ? AppSettings.appleFoundationModelsModelId
        : _requiredEnv('CAVERNO_LLM_MODEL');
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
        mcpServers: const <McpServerConfig>[],
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
