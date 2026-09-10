import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/presentation/widgets/assistant_turn_phase.dart';
import 'package:caverno/features/chat/presentation/widgets/assistant_turn_status_row.dart';
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

/// Wall clock the test advances by hand. `testWidgets` fakes timers but not
/// `DateTime.now()`, so the row's elapsed value would otherwise never move.
class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}

Future<void> _pumpStatusRow(
  WidgetTester tester, {
  required DateTime startedAt,
  required String label,
  DateTime Function()? now,
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
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: Center(
                child: AssistantTurnStatusRow(
                  startedAt: startedAt,
                  label: label,
                  now: now ?? DateTime.now,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.enableBuildModes = [];

  Future<String> labelFor(
    WidgetTester tester, {
    required String content,
    required List<String> runningToolNames,
  }) async {
    late String resolved;
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
            home: Builder(
              builder: (_) {
                resolved = assistantTurnStatusLabel(
                  content: content,
                  runningToolNames: runningToolNames,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return resolved;
  }

  testWidgets('names the single tool the turn is running', (tester) async {
    expect(
      await labelFor(
        tester,
        content: '<tool_use>{"name":"read_file"}</tool_use>\n',
        runningToolNames: const ['read_file'],
      ),
      'Running read_file…',
    );
  });

  testWidgets('counts a parallel batch', (tester) async {
    expect(
      await labelFor(
        tester,
        content: '<tool_use>{"name":"read_file"}</tool_use>\n',
        runningToolNames: const ['read_file', 'grep'],
      ),
      'Running 2 tools…',
    );
  });

  testWidgets('stops claiming tools are running once the batch ends', (
    tester,
  ) async {
    // The content tail still carries </tool_use> here; the empty lifecycle
    // list is what tells the truth.
    expect(
      await labelFor(
        tester,
        content: '<tool_use>{"name":"read_file"}</tool_use>\n',
        runningToolNames: const [],
      ),
      'Running tools…',
    );
  });

  testWidgets('renders elapsed time next to the phase label', (tester) async {
    final now = DateTime(2026, 9, 10, 12, 0);
    await _pumpStatusRow(
      tester,
      startedAt: now.subtract(const Duration(minutes: 14, seconds: 8)),
      label: 'Running tools…',
      now: _FakeClock(now).call,
    );

    expect(find.text('14m 8s · Running tools…'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('omits the time for the first second of a turn', (tester) async {
    final now = DateTime(2026, 9, 10, 12, 0);
    await _pumpStatusRow(
      tester,
      startedAt: now,
      label: 'Thinking…',
      now: _FakeClock(now).call,
    );

    expect(find.text('Thinking…'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('omits the time for an implausibly old timestamp', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 10, 12, 0);
    await _pumpStatusRow(
      tester,
      startedAt: DateTime(2020),
      label: 'Thinking…',
      now: _FakeClock(now).call,
    );

    expect(find.text('Thinking…'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('counts up once per second', (tester) async {
    final clock = _FakeClock(DateTime(2026, 9, 10, 12, 0, 8));
    await _pumpStatusRow(
      tester,
      startedAt: DateTime(2026, 9, 10, 12, 0),
      label: 'Responding…',
      now: clock.call,
    );

    expect(find.text('8s · Responding…'), findsOneWidget);

    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('10s · Responding…'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('cancels its timer on dispose', (tester) async {
    final now = DateTime(2026, 9, 10, 12, 0);
    await _pumpStatusRow(
      tester,
      startedAt: now.subtract(const Duration(seconds: 5)),
      label: 'Thinking…',
      now: _FakeClock(now).call,
    );

    await _unmount(tester);

    expect(tester.takeException(), isNull);
  });
}
