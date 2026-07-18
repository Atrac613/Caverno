import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/pages/routine_detail_view.dart';
import 'package:caverno/features/routines/presentation/providers/routines_notifier.dart';
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

class _FakeRoutinesNotifier extends RoutinesNotifier {
  _FakeRoutinesNotifier(this.routines);

  final List<Routine> routines;

  @override
  RoutinesState build() => RoutinesState(routines: routines);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  Routine routineWith({List<RoutineRunRecord> runs = const []}) {
    final createdAt = DateTime(2026, 7, 18, 8);
    return Routine(
      id: 'routine-1',
      name: 'Service health',
      prompt: 'Check the service and summarize its status.',
      createdAt: createdAt,
      updatedAt: createdAt,
      enabled: false,
      runs: runs,
    );
  }

  RoutineRunRecord successfulRun() {
    return RoutineRunRecord(
      id: 'run-success',
      startedAt: DateTime(2026, 7, 18, 9),
      finishedAt: DateTime(2026, 7, 18, 9, 0, 12, 345),
      durationMs: 12345,
      usedPlan: true,
      usedTools: true,
      toolCallCount: 1,
      toolNames: const ['health_check'],
      toolSourceLabels: const {'health_check': 'Local tools'},
      toolCalls: const [
        RoutineRunToolCall(
          id: 'call-1',
          name: 'health_check',
          arguments: '{"target":"api"}',
          result: 'Healthy',
        ),
      ],
      deliveryStatus: RoutineDeliveryStatus.delivered,
      deliveredAt: DateTime(2026, 7, 18, 9, 0, 13),
      deliveryMessage: 'Delivery receipt 42',
      preview: 'All systems operational',
      output: 'The API is **healthy**.',
    );
  }

  RoutineRunRecord failedRun() {
    return RoutineRunRecord(
      id: 'run-failed',
      startedAt: DateTime(2026, 7, 18, 10),
      finishedAt: DateTime(2026, 7, 18, 10, 0, 0, 950),
      status: RoutineRunStatus.failed,
      trigger: RoutineRunTrigger.scheduled,
      deliveryStatus: RoutineDeliveryStatus.failed,
      deliveryMessage: 'Webhook unavailable',
      preview: 'Health check failed',
      error: '  Connection refused\nRetry exhausted  ',
      failureAcknowledged: true,
    );
  }

  Future<void> pumpPage(WidgetTester tester, Routine routine) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

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
                routinesNotifierProvider.overrideWith(
                  () => _FakeRoutinesNotifier([routine]),
                ),
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const Scaffold(
                  body: RoutineDetailView(routineId: 'routine-1'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty run-history state', (tester) async {
    await pumpPage(tester, routineWith());

    expect(find.text('Run history'), findsOneWidget);
    expect(
      find.text(
        'No runs yet. Use Run now or wait for the next scheduled execution.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders successful and failed run cards in stored order', (
    tester,
  ) async {
    await pumpPage(tester, routineWith(runs: [successfulRun(), failedRun()]));

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('1 tool call(s)'), findsOneWidget);
    expect(find.text('Plan used'), findsOneWidget);
    expect(find.text('Posted to Google Chat'), findsOneWidget);
    expect(find.text('All systems operational'), findsOneWidget);
    expect(find.text('12.3s'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Delivery failed'), findsOneWidget);
    expect(find.text('Health check failed'), findsOneWidget);
    expect(find.text('950ms'), findsOneWidget);
    expect(find.text('This failure has been reviewed.'), findsOneWidget);
    expect(find.text('Webhook unavailable'), findsOneWidget);

    final successTop = tester
        .getTopLeft(find.text('All systems operational'))
        .dy;
    final failureTop = tester.getTopLeft(find.text('Health check failed')).dy;
    expect(successTop, lessThan(failureTop));
  });

  testWidgets('opens transcript and error sheets with complete content', (
    tester,
  ) async {
    await pumpPage(tester, routineWith(runs: [successfulRun(), failedRun()]));

    final transcriptButton = find.text('View transcript');
    await tester.ensureVisible(transcriptButton);
    await tester.tap(transcriptButton);
    await tester.pumpAndSettle();

    expect(find.text('Routine transcript'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(
      find.text('Check the service and summarize its status.'),
      findsNWidgets(2),
    );
    expect(find.text('Tool: health_check'), findsOneWidget);
    expect(
      find.text('Arguments\n{"target":"api"}\n\nResult\nHealthy'),
      findsOneWidget,
    );
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('The API is healthy.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    final errorButton = find.text('View error');
    await tester.ensureVisible(errorButton);
    await tester.tap(errorButton);
    await tester.pumpAndSettle();

    expect(find.text('Routine error'), findsOneWidget);
    expect(find.text('Connection refused\nRetry exhausted'), findsOneWidget);
  });
}
