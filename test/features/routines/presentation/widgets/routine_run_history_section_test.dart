import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/routines/presentation/widgets/routine_run_history_section.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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

  Routine routineWith(List<RoutineRunRecord> runs) {
    final createdAt = DateTime(2026, 7, 18, 8);
    return Routine(
      id: 'routine-1',
      name: 'Service health',
      prompt: 'Check the service.',
      createdAt: createdAt,
      updatedAt: createdAt,
      runs: runs,
    );
  }

  RoutineRunRecord runWith({
    required String id,
    required int durationMs,
    String output = '',
    String error = '',
    List<RoutineRunToolCall> toolCalls = const [],
  }) {
    final startedAt = DateTime(2026, 7, 18, 9);
    return RoutineRunRecord(
      id: id,
      startedAt: startedAt,
      finishedAt: startedAt.add(Duration(milliseconds: durationMs)),
      durationMs: durationMs,
      preview: 'Preview $id',
      output: output,
      error: error,
      toolCalls: toolCalls,
    );
  }

  Future<void> pumpSection(WidgetTester tester, Routine routine) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2200);
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
            return MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: RoutineRunHistorySection(routine: routine),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('formats sub-second, second, and minute durations', (
    tester,
  ) async {
    await pumpSection(
      tester,
      routineWith([
        runWith(id: 'sub-second', durationMs: 999),
        runWith(id: 'seconds', durationMs: 1200),
        runWith(id: 'minutes', durationMs: 61000),
      ]),
    );

    expect(find.text('999ms'), findsOneWidget);
    expect(find.text('1.2s'), findsOneWidget);
    expect(find.text('1m 01s'), findsOneWidget);
    expect(find.text('View transcript'), findsNothing);
    expect(find.text('View error'), findsNothing);
  });

  testWidgets('opens a tool-only transcript and omits empty tool content', (
    tester,
  ) async {
    await pumpSection(
      tester,
      routineWith([
        runWith(
          id: 'tool-only',
          durationMs: 1000,
          toolCalls: const [
            RoutineRunToolCall(
              id: 'arguments-only',
              name: 'inspect',
              arguments: '{"path":"status.json"}',
            ),
            RoutineRunToolCall(
              id: 'result-only',
              name: 'read',
              result: 'healthy',
            ),
            RoutineRunToolCall(id: 'empty', name: 'empty_tool'),
          ],
        ),
      ]),
    );

    await tester.tap(find.text('View transcript'));
    await tester.pumpAndSettle();

    expect(find.text('Routine transcript'), findsOneWidget);
    expect(find.text('Tool: inspect'), findsOneWidget);
    expect(find.text('Arguments\n{"path":"status.json"}'), findsOneWidget);
    expect(find.text('Tool: read'), findsOneWidget);
    expect(find.text('Result\nhealthy'), findsOneWidget);
    expect(find.text('Tool: empty_tool'), findsOneWidget);
    expect(find.text('Assistant'), findsNothing);
  });

  testWidgets('shows transcript and error actions for output and error data', (
    tester,
  ) async {
    await pumpSection(
      tester,
      routineWith([
        runWith(
          id: 'output-and-error',
          durationMs: 1000,
          output: 'Summary response',
          error: '  Diagnostic details  ',
        ),
      ]),
    );

    expect(find.text('View transcript'), findsOneWidget);
    expect(find.text('View error'), findsOneWidget);

    await tester.tap(find.text('View error'));
    await tester.pumpAndSettle();

    expect(find.text('Routine error'), findsOneWidget);
    expect(find.text('Diagnostic details'), findsOneWidget);
  });
}
