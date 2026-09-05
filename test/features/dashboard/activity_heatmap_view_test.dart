import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/theme/app_theme.dart';
import 'package:caverno/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:caverno/features/dashboard/presentation/widgets/activity_heatmap_view.dart';
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

  // Sunday-aligned 2-week window so month labels and cells are deterministic.
  final heatmap = ActivityHeatmap(
    startDay: DateTime(2026, 1, 4),
    endDay: DateTime(2026, 1, 17),
    dailyCounts: List<int>.generate(14, (index) => index == 10 ? 7 : 0),
    dailyBuckets: List<int>.generate(14, (index) => index == 10 ? 4 : 0),
  );

  testWidgets('shows past-year title, unit label, and legend', (tester) async {
    await _pump(tester, heatmap: heatmap);

    expect(find.text('Past year'), findsOneWidget);
    expect(find.text('messages per day'), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('defaults selection to the latest active day', (tester) async {
    await _pump(tester, heatmap: heatmap);

    expect(find.textContaining('7 messages'), findsOneWidget);
  });

  testWidgets('updates the footer when another day is selected', (
    tester,
  ) async {
    await _pump(tester, heatmap: heatmap);

    // Tap the first cell (Jan 4, 2026) which has 0 messages.
    final cells = find.byType(GestureDetector);
    expect(cells, findsWidgets);
    await tester.tap(cells.first);
    await tester.pump();

    expect(find.textContaining('0 messages'), findsOneWidget);
  });

  testWidgets('renders a full year on a phone-width screen', (tester) async {
    // A year is 53 columns. On a phone the inter-column gaps take more width
    // than the cells, so the cell shrinks below three logical pixels — and the
    // corner radius was computed as `radii.xs.clamp(1.0, cellSize / 3)`, whose
    // upper bound then falls under its lower bound and throws. Every cell threw
    // at once, and the error widgets that replaced them are what produced the
    // five-million-pixel RenderFlex overflow beside it.
    final year = ActivityHeatmap(
      startDay: DateTime(2025, 1, 5),
      endDay: DateTime(2026, 1, 3),
      dailyCounts: List<int>.filled(364, 0),
      dailyBuckets: List<int>.filled(364, 0),
    );

    await _pump(tester, heatmap: year, width: 390);

    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a width with no room for the grid at all', (
    tester,
  ) async {
    // The label column and its gap can exceed the available width, which
    // clamps the grid to zero and the cell with it.
    final year = ActivityHeatmap(
      startDay: DateTime(2025, 1, 5),
      endDay: DateTime(2026, 1, 3),
      dailyCounts: List<int>.filled(364, 0),
      dailyBuckets: List<int>.filled(364, 0),
    );

    await _pump(tester, heatmap: year, width: 24);

    expect(tester.takeException(), isNull);
  });

  testWidgets('fits the grid to the available width', (tester) async {
    await _pump(tester, heatmap: heatmap, width: 400);

    final grid = tester.getSize(
      find
          .descendant(
            of: find.byType(ActivityHeatmapView),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(grid.width, lessThanOrEqualTo(400));
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ActivityHeatmap heatmap,
  double width = 800,
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
          return MaterialApp(
            theme: AppTheme.dark,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: SingleChildScrollView(
                    child: ActivityHeatmapView(heatmap: heatmap),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
