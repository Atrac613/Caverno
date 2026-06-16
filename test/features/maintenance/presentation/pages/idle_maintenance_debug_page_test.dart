import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/maintenance/domain/services/maintenance_pipeline.dart';
import 'package:caverno/features/maintenance/presentation/pages/idle_maintenance_debug_page.dart';
import 'package:caverno/features/maintenance/presentation/providers/maintenance_scheduler_provider.dart';
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

class _Stage implements MaintenanceStage {
  _Stage(this.name, this.outcome);

  @override
  final String name;
  final MaintenanceStageOutcome outcome;

  @override
  Future<MaintenanceStageOutcome> run(MaintenanceStageContext context) async =>
      outcome;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  Future<void> pumpPage(
    WidgetTester tester,
    List<MaintenanceStage> stages,
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
            return ProviderScope(
              overrides: [
                maintenanceStagesProvider.overrideWithValue(stages),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const IdleMaintenanceDebugPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('run now executes the pipeline and renders the report', (
    tester,
  ) async {
    await pumpPage(tester, [
      _Stage('probe', const MaintenanceStageOutcome.completed('profiled')),
      _Stage('eval', const MaintenanceStageOutcome.skipped('no cases')),
    ]);

    expect(find.byKey(const ValueKey('idle-maintenance-debug-run')), findsOne);

    await tester.tap(find.byKey(const ValueKey('idle-maintenance-debug-run')));
    await tester.pumpAndSettle();

    // Per-stage results render with their detail.
    expect(find.text('probe'), findsOneWidget);
    expect(find.text('profiled'), findsOneWidget);
    expect(find.text('eval'), findsOneWidget);
    expect(find.text('no cases'), findsOneWidget);

    // The formatted markdown report renders.
    expect(find.textContaining('# Idle maintenance report'), findsOneWidget);
    expect(find.textContaining('Idle maintenance: 1 done'), findsOneWidget);
  });
}
