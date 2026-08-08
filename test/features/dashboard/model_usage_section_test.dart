import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/theme/app_theme.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/dashboard/domain/entities/model_usage_stats.dart';
import 'package:caverno/features/dashboard/domain/services/model_usage_stats_calculator.dart';
import 'package:caverno/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:caverno/features/dashboard/presentation/widgets/model_usage_section.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  ModelUsageEntry entry({
    required String label,
    String endpointId = 'primary',
    int promptTokens = 1000,
    int completionTokens = 100,
    int totalTokens = 1100,
    int cachedPromptTokens = 0,
    int reasoningTokens = 0,
    int requestCount = 4,
    int durationMs = 8000,
  }) => ModelUsageEntry(
    key: ModelUsageStatsCalculator.modelKey(
      model: label,
      endpointId: endpointId,
    ),
    label: label,
    endpointId: endpointId,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: totalTokens,
    cachedPromptTokens: cachedPromptTokens,
    reasoningTokens: reasoningTokens,
    requestCount: requestCount,
    durationMs: durationMs,
  );

  testWidgets('shows the empty state before anything is recorded', (
    tester,
  ) async {
    await _pump(tester, ModelUsageStats.empty);

    expect(find.textContaining('No usage recorded yet'), findsOneWidget);
  });

  testWidgets('lists each model with its share and endpoint', (tester) async {
    await _pump(
      tester,
      ModelUsageStats(
        models: [
          entry(label: 'model-a', totalTokens: 900),
          entry(label: 'model-b', endpointId: 'lan-mesh', totalTokens: 100),
        ],
      ),
    );

    // Names and shares appear twice by design: once in the chart legend and
    // once in the list row.
    expect(find.text('model-a'), findsWidgets);
    expect(find.text('model-b'), findsWidgets);
    expect(find.text('lan-mesh'), findsOneWidget);
    expect(find.text('90.0%'), findsWidgets);
    expect(find.text('10.0%'), findsWidgets);
  });

  testWidgets('renders unreported cache and reasoning as a dash, not 0%', (
    tester,
  ) async {
    // Local llama.cpp reports no *_tokens_details; 0 there would read as a
    // measured zero rather than "not reported".
    await _pump(tester, ModelUsageStats(models: [entry(label: 'local-model')]));

    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('0.0%'), findsNothing);
  });

  testWidgets('shows a cache hit rate when the provider reported one', (
    tester,
  ) async {
    await _pump(
      tester,
      ModelUsageStats(
        models: [
          entry(
            label: 'cloud-model',
            promptTokens: 1000,
            cachedPromptTokens: 900,
            reasoningTokens: 50,
          ),
        ],
      ),
    );

    expect(find.text('90.0%'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('names each role in the breakdown', (tester) async {
    await _pump(
      tester,
      ModelUsageStats(
        models: [entry(label: 'model-a')],
        roles: [
          ModelUsageEntry(
            key: ModelUsageRole.chat.name,
            label: ModelUsageRole.chat.name,
            totalTokens: 800,
          ),
          ModelUsageEntry(
            key: ModelUsageRole.memoryExtraction.name,
            label: ModelUsageRole.memoryExtraction.name,
            totalTokens: 300,
          ),
        ],
      ),
    );

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Memory extraction'), findsOneWidget);
  });

  testWidgets('surfaces an unattributed role as a defect signal', (
    tester,
  ) async {
    await _pump(
      tester,
      ModelUsageStats(
        models: [entry(label: 'model-a')],
        roles: [
          ModelUsageEntry(
            key: ModelUsageRole.unknown.name,
            label: ModelUsageRole.unknown.name,
            totalTokens: 1100,
          ),
        ],
      ),
    );

    expect(find.text('Unattributed'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, ModelUsageStats stats) async {
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
              modelUsageStatsProvider.overrideWith(
                (ref) => Stream<ModelUsageStats>.value(stats),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.dark,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const Scaffold(
                body: SingleChildScrollView(child: ModelUsageSection()),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
