import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';
import 'package:caverno/features/chat/presentation/widgets/pro_reasoning_progress_card.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final source = File('$path/${locale.languageCode}.json');
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('shows current stage, candidates, endpoints, and cancel', (
    tester,
  ) async {
    var cancelCount = 0;
    final now = DateTime(2026, 8, 13, 12);

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
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: ProReasoningProgressCard(
                progress: ProReasoningProgress(
                  stage: ProReasoningStage.explore,
                  startedAt: now,
                  deadline: now.add(const Duration(minutes: 10)),
                  completedCandidates: 2,
                  requestedCandidates: 3,
                  endpointLabels: const ['GPU A', 'GPU B'],
                ),
                onCancel: () => cancelCount += 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Exploring candidate answers…'), findsOneWidget);
    expect(find.text('Candidates 2/3'), findsOneWidget);
    expect(find.text('Endpoints: GPU A, GPU B'), findsOneWidget);
    expect(find.textContaining('Deadline '), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('pro-reasoning-progress-cancel')),
    );
    await tester.pump();
    expect(cancelCount, 1);
  });
}
