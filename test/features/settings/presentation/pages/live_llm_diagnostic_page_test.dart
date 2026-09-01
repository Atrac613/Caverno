import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/settings/data/live_llm_benchmark_artifact_file_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/live_llm_diagnostic.dart';
import 'package:caverno/features/settings/domain/services/live_llm_benchmark_artifact_importer.dart';
import 'package:caverno/features/settings/domain/services/live_llm_diagnostic_scoring.dart';
import 'package:caverno/features/settings/presentation/pages/live_llm_diagnostic_page.dart';
import 'package:caverno/features/settings/presentation/providers/live_llm_diagnostic_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('offers benchmark artifact import', (tester) async {
    await _pumpPage(tester, settings: AppSettings.defaults());

    expect(
      find.byKey(const ValueKey('live-llm-diag-import-artifact')),
      findsOneWidget,
    );
    expect(find.byTooltip('Import benchmark artifact'), findsOneWidget);
  });

  testWidgets('opens a saved diagnostic report from history', (tester) async {
    final settings = AppSettings.defaults();
    final startedAt = DateTime(2026, 8, 15, 9, 30);
    final historicalReport = LiveLlmDiagnosticReport(
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(seconds: 2)),
      baseUrl: settings.baseUrl,
      model: settings.effectiveModel,
      demoMode: false,
      mcpEnabled: false,
      results: const [
        LiveLlmDiagnosticProbeResult(
          id: 'instruction_echo',
          status: LiveLlmDiagnosticStatus.passed,
          summary: 'Saved probe passed',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          () => _FixedSettingsNotifier(settings),
        ),
        liveLlmDiagnosticNotifierProvider.overrideWith(
          () => _FixedLiveLlmDiagnosticNotifier(
            LiveLlmDiagnosticState(history: [historicalReport]),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pumpPageWithContainer(tester, container);

    expect(find.text('Diagnostic History'), findsOneWidget);
    expect(find.textContaining('1/1'), findsOneWidget);

    final historyCard = find.byKey(
      ValueKey('live-llm-diag-history-${startedAt.toIso8601String()}'),
    );
    await tester.ensureVisible(historyCard);
    await tester.tap(
      find.descendant(of: historyCard, matching: find.byType(ListTile)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(LiveLlmDiagnosticHistoryDetailPage),
      findsOneWidget,
      reason: 'tapping a saved run must push its own detail page',
    );
    expect(find.text('Saved probe passed'), findsOneWidget);
    expect(
      container.read(liveLlmDiagnosticNotifierProvider).report,
      isNull,
      reason: 'the detail page must not replace the latest run on the page',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LiveLlmDiagnosticHistoryDetailPage), findsNothing);
    expect(find.text('Diagnostic History'), findsOneWidget);
  });

  testWidgets('imports two same-version artifacts and announces saturation', (
    tester,
  ) async {
    final initialSettings = AppSettings.defaults();
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode(initialSettings.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();
    final artifacts = _QueuedBenchmarkArtifactFileService([
      _currentSuiteBenchmarkArtifact('qwen3.6-27b-vision'),
      _currentSuiteBenchmarkArtifact('qwen3.6-35b-a3b-vision'),
    ]);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        liveLlmBenchmarkArtifactFileServiceProvider.overrideWithValue(
          artifacts,
        ),
        liveLlmDiagnosticNotifierProvider.overrideWith(
          () => _FixedLiveLlmDiagnosticNotifier(LiveLlmDiagnosticState.initial),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pumpPageWithContainer(tester, container);

    await tester.tap(
      find.byKey(const ValueKey('live-llm-diag-import-artifact')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('live-llm-diag-saturation-watchdog')),
      findsNothing,
    );
    expect(
      container.read(settingsNotifierProvider).modelCapabilityProfiles,
      hasLength(1),
    );

    await tester.tap(
      find.byKey(const ValueKey('live-llm-diag-import-artifact')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('live-llm-diag-saturation-watchdog')),
      findsOneWidget,
    );
    expect(find.text('Conformance suite saturated'), findsOneWidget);
    expect(find.textContaining('All 2 registered models'), findsOneWidget);
    final settings = container.read(settingsNotifierProvider);
    expect(
      settings.modelCapabilityProfiles.map((profile) => profile.model),
      containsAll(['qwen3.6-27b-vision', 'qwen3.6-35b-a3b-vision']),
    );
    expect(settings.modelCapabilityProfileRevisions, hasLength(2));
    expect(
      settings.modelCapabilityProfileRevisions.map(
        (revision) => revision.source,
      ),
      everyElement('benchmark_artifact'),
    );
  });

  testWidgets('shows Foundation Models live canary guidance on macOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final platformCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    try {
      await _pumpPage(
        tester,
        settings: AppSettings.defaults().copyWith(
          llmProvider: LlmProvider.appleFoundationModels,
        ),
      );

      expect(find.text('Foundation Models Live Canary'), findsOneWidget);
      expect(
        find.text('tool/run_foundation_models_live_canary.sh'),
        findsOneWidget,
      );
      expect(
        find.text(
          'build/integration_test_reports/foundation_models_live_canary_<timestamp>/canary_summary.json',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(
          const ValueKey('foundation-models-live-canary-copy-command'),
        ),
      );
      await tester.pump();

      final clipboardCall = platformCalls.singleWhere(
        (call) => call.method == 'Clipboard.setData',
      );
      final arguments = clipboardCall.arguments as Map<Object?, Object?>;
      expect(arguments['text'], 'tool/run_foundation_models_live_canary.sh');
      expect(
        find.text('Foundation Models canary command copied.'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('hides Foundation Models live canary guidance for OpenAI mode', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await _pumpPage(tester, settings: AppSettings.defaults());

      expect(find.text('Foundation Models Live Canary'), findsNothing);
      expect(
        find.text('tool/run_foundation_models_live_canary.sh'),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('shows sampler calibration trial summaries', (tester) async {
    await _pumpPage(
      tester,
      settings: AppSettings.defaults(),
      diagnosticState: LiveLlmDiagnosticState(
        report: LiveLlmDiagnosticReport(
          startedAt: DateTime.utc(2026, 6, 12),
          finishedAt: DateTime.utc(2026, 6, 12, 0, 0, 2),
          baseUrl: 'http://localhost:1234/v1',
          model: 'sampler-model',
          demoMode: false,
          mcpEnabled: true,
          samplerCalibrationTrials: const [
            LiveLlmDiagnosticSamplerTrial(
              requestClass: 'toolLoop',
              temperature: 0.0,
              passed: true,
              repetitionDetected: true,
            ),
            LiveLlmDiagnosticSamplerTrial(
              requestClass: 'toolLoop',
              temperature: 0.2,
              passed: true,
            ),
            LiveLlmDiagnosticSamplerTrial(
              requestClass: 'toolLoop',
              temperature: 0.4,
              passed: false,
              malformedToolCallCount: 1,
            ),
          ],
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Sampler Calibration'),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Sampler Calibration'), findsOneWidget);
    expect(find.text('toolLoop'), findsOneWidget);
    expect(find.text('Trials: 3'), findsOneWidget);
    expect(find.text('Passed: 2/3'), findsOneWidget);
    expect(find.text('Candidates: 0.0, 0.2, 0.4'), findsOneWidget);
    expect(
      find.text(
        'JSON repairs: 0 • Malformed calls: 1 • Edit failures: 0 • Repetitions: 1',
      ),
      findsOneWidget,
    );
  });

  testWidgets('summarizes the run as absolute points, not a percentage', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      settings: AppSettings.defaults(),
      diagnosticState: LiveLlmDiagnosticState(
        report: LiveLlmDiagnosticReport(
          startedAt: DateTime.utc(2026, 8, 11),
          finishedAt: DateTime.utc(2026, 8, 11, 0, 0, 2),
          baseUrl: 'http://localhost:1234/v1',
          model: 'benchmark-model',
          demoMode: false,
          mcpEnabled: true,
          results: const [
            LiveLlmDiagnosticProbeResult(
              id: 'instruction_echo',
              status: LiveLlmDiagnosticStatus.passed,
              summary: 'passed',
            ),
          ],
        ),
      ),
    );

    // Denominated by what this run attempted (the one probe it ran), not the
    // fixed maximum: a narrower run must not read as a weaker model. The
    // coverage tile beside it reports the share that went unmeasured.
    final expectedPoints = LiveLlmDiagnosticSuite.pointsFor('instruction_echo');
    expect(find.text('$expectedPoints / $expectedPoints'), findsOneWidget);
    expect(
      find.text('$expectedPoints / ${LiveLlmDiagnosticSuite.maxPoints}'),
      findsNothing,
    );
    // The old headline: one passing probe out of one scored probe read as 100%.
    expect(find.text('100%'), findsNothing);
    expect(find.byKey(const ValueKey('live-llm-diag-coverage-tile')), findsOne);
    expect(
      find.byKey(const ValueKey('live-llm-diag-stability-tile')),
      findsOne,
    );
  });

  testWidgets('shows streaming capability measurements outside the score', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      settings: AppSettings.defaults(),
      diagnosticState: LiveLlmDiagnosticState(
        report: LiveLlmDiagnosticReport(
          startedAt: DateTime.utc(2026, 8, 11),
          finishedAt: DateTime.utc(2026, 8, 11, 0, 0, 2),
          baseUrl: 'http://localhost:1234/v1',
          model: 'streaming-model',
          demoMode: false,
          mcpEnabled: false,
          streamingMetrics: const LiveLlmDiagnosticStreamingMetrics(
            timeToFirstToken: Duration(milliseconds: 250),
            totalElapsed: Duration(milliseconds: 2250),
            completionTokens: 100,
            chunkCount: 12,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Capability (measured)'),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Capability (measured)'), findsOneWidget);
    expect(find.text('250 ms'), findsOneWidget);
    expect(find.text('50.0 tok/s'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('shows multi-round physical measurements outside the score', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      settings: AppSettings.defaults(),
      diagnosticState: LiveLlmDiagnosticState(
        report: LiveLlmDiagnosticReport(
          startedAt: DateTime.utc(2026, 8, 11),
          finishedAt: DateTime.utc(2026, 8, 11, 0, 0, 2),
          baseUrl: 'http://localhost:1234/v1',
          model: 'multi-round-model',
          demoMode: false,
          mcpEnabled: true,
          multiRoundToolLoopMetrics:
              const LiveLlmDiagnosticMultiRoundToolLoopMetrics(
                totalElapsed: Duration(milliseconds: 1875),
                modelTurnCount: 3,
                toolCallCount: 2,
                successfulToolExecutionCount: 2,
                promptTokens: 410,
                completionTokens: 90,
                taskCompleted: true,
              ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('live-llm-diag-loop-turns-tile')),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Capability (measured)'), findsOneWidget);
    expect(find.text('Tool-loop model turns'), findsOneWidget);
    expect(find.text('Tool-loop calls'), findsOneWidget);
    expect(find.text('Successful tool executions'), findsOneWidget);
    expect(find.text('Tool-loop prompt tokens'), findsOneWidget);
    expect(find.text('Tool-loop completion tokens'), findsOneWidget);
    expect(find.text('Tool-loop total tokens'), findsOneWidget);
    expect(find.text('Tool-loop elapsed'), findsOneWidget);
    expect(find.text('Tool-loop task completed'), findsOneWidget);
    expect(find.text('1875 ms'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
  });

  testWidgets('shows embeddings physical measurements outside the score', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      settings: AppSettings.defaults(),
      diagnosticState: LiveLlmDiagnosticState(
        report: LiveLlmDiagnosticReport(
          startedAt: DateTime.utc(2026, 8, 13),
          finishedAt: DateTime.utc(2026, 8, 13, 0, 0, 1),
          baseUrl: 'http://localhost:1234/v1',
          model: 'chat-model',
          demoMode: false,
          mcpEnabled: false,
          embeddingMetrics: const LiveLlmDiagnosticEmbeddingMetrics(
            totalElapsed: Duration(milliseconds: 42),
            inputCount: 3,
            returnedVectorCount: 3,
            dimension: 2048,
            model: 'qwen-embedding',
            similarCosine: 0.91,
            unrelatedCosine: 0.22,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('live-llm-diag-embedding-model-tile')),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Embedding model'), findsOneWidget);
    expect(find.text('qwen-embedding'), findsOneWidget);
    expect(find.text('Embedding dimension'), findsOneWidget);
    expect(find.text('2048'), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('0.690'), findsOneWidget);
    expect(find.text('42 ms'), findsOneWidget);
  });

  testWidgets('shows effective-context measurements outside the score', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      settings: AppSettings.defaults(),
      diagnosticState: LiveLlmDiagnosticState(
        report: LiveLlmDiagnosticReport(
          startedAt: DateTime.utc(2026, 8, 14),
          baseUrl: 'http://localhost:1234/v1',
          model: 'context-model',
          demoMode: false,
          mcpEnabled: false,
          effectiveContextMetrics:
              const LiveLlmDiagnosticEffectiveContextMetrics(
                configuredMaximumTokens: 8192,
                trials: [
                  LiveLlmDiagnosticContextTrial(
                    requestedApproximateTokens: 4096,
                    elapsed: Duration(milliseconds: 30),
                    passed: true,
                    promptTokens: 4200,
                  ),
                  LiveLlmDiagnosticContextTrial(
                    requestedApproximateTokens: 8192,
                    elapsed: Duration(milliseconds: 60),
                    passed: true,
                    promptTokens: 8300,
                  ),
                ],
              ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('live-llm-diag-context-measured-tile')),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Measured context'), findsOneWidget);
    expect(find.text('8300 tok'), findsOneWidget);
    expect(find.text('Context trials'), findsOneWidget);
    expect(find.text('Reached ceiling'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Difficulty ladder'), findsOneWidget);
    expect(find.text('ladder-v2'), findsOneWidget);
    expect(find.text('Highest passed stage'), findsOneWidget);
    expect(find.text('8192 tok'), findsOneWidget);
    expect(find.text('Next ladder stage'), findsOneWidget);
    expect(find.text('16384 tok'), findsOneWidget);
  });

  testWidgets('announces saturation across registered current-suite models', (
    tester,
  ) async {
    final defaults = AppSettings.defaults();
    await _pumpPage(
      tester,
      settings: defaults.copyWith(
        modelCapabilityProfiles: [
          _benchmarkProfile(defaults, 'model-a', points: 950),
          _benchmarkProfile(defaults, 'model-b', points: 1000),
        ],
      ),
    );

    expect(
      find.byKey(const ValueKey('live-llm-diag-saturation-watchdog')),
      findsOneWidget,
    );
    expect(find.text('Conformance suite saturated'), findsOneWidget);
    expect(find.textContaining('All 2 registered models'), findsOneWidget);
  });

  testWidgets('does not announce saturation with incomplete model coverage', (
    tester,
  ) async {
    final defaults = AppSettings.defaults();
    await _pumpPage(
      tester,
      settings: defaults.copyWith(
        modelCapabilityProfiles: [
          _benchmarkProfile(defaults, 'model-a', points: 1000),
          _benchmarkProfile(defaults, 'model-b', points: null),
        ],
      ),
      diagnosticState: LiveLlmDiagnosticState(
        report: LiveLlmDiagnosticReport(
          startedAt: DateTime.utc(2026, 8, 14),
          baseUrl: defaults.baseUrl,
          model: defaults.effectiveModel,
          demoMode: false,
          mcpEnabled: false,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('live-llm-diag-saturation-watchdog')),
      findsNothing,
    );
  });

  testWidgets('compares registered models independently by physical axis', (
    tester,
  ) async {
    final defaults = AppSettings.defaults();
    await _pumpPage(
      tester,
      settings: defaults.copyWith(
        modelCapabilityProfiles: [
          _benchmarkProfile(defaults, 'model-a', points: 1000).copyWith(
            probeMetadata: {
              ..._benchmarkProfile(
                defaults,
                'model-a',
                points: 1000,
              ).probeMetadata,
              'capability.effectiveContext.promptTokens': '16498',
              'capability.streaming.decodeTokensPerSecond': '42.50',
              'capability.streaming.ttftMs': '900',
            },
          ),
          _benchmarkProfile(defaults, 'model-b', points: 1000).copyWith(
            probeMetadata: {
              ..._benchmarkProfile(
                defaults,
                'model-b',
                points: 1000,
              ).probeMetadata,
              'capability.effectiveContext.promptTokens': '32768',
              'capability.streaming.decodeTokensPerSecond': '30.00',
              'capability.streaming.ttftMs': '500',
            },
          ),
        ],
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('live-llm-diag-capability-comparison')),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Registered model capability comparison'), findsOneWidget);
    expect(find.textContaining('No overall weighted score'), findsOneWidget);
    expect(find.text('model-b: 32768 tok'), findsOneWidget);
    expect(find.text('model-a: 16498 tok'), findsOneWidget);
    expect(find.text('model-a: 42.50 tok/s'), findsOneWidget);
    expect(find.text('model-b: 30.00 tok/s'), findsOneWidget);
    expect(find.text('model-b: 500 ms'), findsOneWidget);
    expect(find.text('model-a: 900 ms'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey(
          'live-llm-diag-comparison-effective-context-best-'
          '${_benchmarkProfile(defaults, 'model-b', points: 1000).computedId}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows profile history empty state when no revisions', (
    tester,
  ) async {
    await _pumpPage(tester, settings: AppSettings.defaults());

    await tester.scrollUntilVisible(
      find.text('Profile History'),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Profile History'), findsOneWidget);
    expect(
      find.textContaining('No profile revisions recorded yet'),
      findsOneWidget,
    );
  });

  testWidgets('lists profile revisions newest-first with model-swap warning', (
    tester,
  ) async {
    final defaults = AppSettings.defaults();
    final baseProfile = ModelCapabilityProfile(
      id: ModelCapabilityProfile.buildId(
        provider: defaults.llmProvider,
        baseUrl: defaults.baseUrl,
        model: defaults.effectiveModel,
      ),
      model: defaults.effectiveModel,
      baseUrl: defaults.baseUrl,
      toolCallStyle: ModelToolCallStyle.nativeToolCalls,
      structuredOutputSupport: ModelStructuredOutputSupport.jsonSchema,
      editFormatPreference: ModelEditFormatPreference.searchReplace,
      usableContextTokens: 8192,
    );
    final older = ModelCapabilityProfileRevision.fromProfile(
      baseProfile.copyWith(probedAt: DateTime.utc(2026, 1, 1, 9)),
      source: 'probe',
    );
    final newer = ModelCapabilityProfileRevision.fromProfile(
      baseProfile.copyWith(
        probedAt: DateTime.utc(2026, 6, 1, 9),
        probeMetadata: const {
          'difficultyLadder': 'ladder-v1',
          'difficultyLadderAxis': 'effective_context_recall',
          'difficultyLadderMeasuredPromptTokens': '8300',
          'difficultyLadderHighestStagePromptTokens': '8192',
          'difficultyLadderNextStagePromptTokens': '16384',
          'difficultyLadderPassedStageCount': '2',
          'difficultyLadderStageCount': '6',
          'capability.streaming.ttftMs': '900',
          'capability.streaming.decodeTokensPerSecond': '42.50',
          'capability.toolLoop.modelTurns': '3',
          'capability.toolLoop.totalTokens': '3282',
          'capability.embedding.semanticMargin': '0.500000',
        },
      ),
      source: 'idle_re_probe',
      capabilityChangeDetected: true,
    );

    await _pumpPage(
      tester,
      settings: defaults.copyWith(
        modelCapabilityProfileRevisions: [older, newer],
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Profile History'),
      400,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('Idle re-probe'), findsOneWidget);
    expect(find.text('Probe'), findsOneWidget);
    expect(find.textContaining('Capability change detected'), findsOneWidget);
    expect(find.text('Usable context: 8192'), findsWidgets);
    expect(find.text('Difficulty ladder: ladder-v1: 8192 tok'), findsOneWidget);
    expect(find.text('Time to first token: 900 ms'), findsOneWidget);
    expect(find.text('Decode rate: 42.50 tok/s'), findsOneWidget);
    expect(find.text('Tool-loop model turns: 3'), findsOneWidget);
    expect(find.text('Tool-loop total tokens: 3282'), findsOneWidget);
    expect(find.text('Semantic margin: 0.500000'), findsOneWidget);
  });
}

ModelCapabilityProfile _benchmarkProfile(
  AppSettings defaults,
  String model, {
  required int? points,
}) {
  return ModelCapabilityProfile(
    id: ModelCapabilityProfile.buildId(
      provider: defaults.llmProvider,
      baseUrl: defaults.baseUrl,
      model: model,
    ),
    provider: defaults.llmProvider,
    baseUrl: defaults.baseUrl,
    model: model,
    probeMetadata: points == null
        ? const {}
        : {
            'benchmarkSuite':
                '${LiveLlmDiagnosticSuite.id}-v${LiveLlmDiagnosticSuite.version}',
            'benchmarkPoints': '$points',
            'benchmarkMaxPoints': '${LiveLlmDiagnosticSuite.maxPoints}',
          },
  );
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required AppSettings settings,
  LiveLlmDiagnosticState diagnosticState = LiveLlmDiagnosticState.initial,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoader(),
      child: Builder(
        builder: (context) {
          return ProviderScope(
            overrides: [
              settingsNotifierProvider.overrideWith(
                () => _FixedSettingsNotifier(settings),
              ),
              liveLlmDiagnosticNotifierProvider.overrideWith(
                () => _FixedLiveLlmDiagnosticNotifier(diagnosticState),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const LiveLlmDiagnosticPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPageWithContainer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoader(),
      child: Builder(
        builder: (context) {
          return UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const LiveLlmDiagnosticPage(),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _currentSuiteBenchmarkArtifact(String model) {
  const baseUrl = 'http://127.0.0.1:11234/v1';
  const generatedAt = '2026-08-14T10:00:00Z';
  return {
    'schema': LiveLlmBenchmarkArtifactImporter.schema,
    'generatedAt': generatedAt,
    'suiteId': 'cavernobench',
    'suiteVersion': LiveLlmDiagnosticSuite.version,
    'provider': LlmProvider.openAiCompatible.name,
    'baseUrl': baseUrl,
    'model': model,
    'runs': [
      {
        'model': model,
        'baseUrl': baseUrl,
        'finishedAt': generatedAt,
        'benchmark': {
          'suiteId': 'cavernobench',
          'suiteVersion': LiveLlmDiagnosticSuite.version,
          'earnedPoints': 965,
          'attemptedPoints': 965,
          'maxPoints': 1000,
          'saturationHighWaterReached': true,
        },
      },
    ],
  };
}

class _QueuedBenchmarkArtifactFileService
    extends LiveLlmBenchmarkArtifactFileService {
  _QueuedBenchmarkArtifactFileService(this.artifacts);

  final List<Map<String, dynamic>> artifacts;
  var _nextArtifact = 0;

  @override
  Future<ModelCapabilityProfile?> importProfile({
    required Iterable<ModelCapabilityProfile> existingProfiles,
  }) async {
    final artifact = artifacts[_nextArtifact++];
    return LiveLlmBenchmarkArtifactImporter.importProfile(
      artifact,
      existingProfiles: existingProfiles,
    );
  }
}

class _FixedSettingsNotifier extends SettingsNotifier {
  _FixedSettingsNotifier(this.settings);

  final AppSettings settings;

  @override
  AppSettings build() => settings;
}

class _FixedLiveLlmDiagnosticNotifier extends LiveLlmDiagnosticNotifier {
  _FixedLiveLlmDiagnosticNotifier(this.fixedState);

  final LiveLlmDiagnosticState fixedState;

  @override
  LiveLlmDiagnosticState build() => fixedState;

  @override
  Future<void> run() async {}
}
