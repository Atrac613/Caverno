import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/widgets/parsed_content_view.dart';

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

Future<void> _pumpParsedContentView(
  WidgetTester tester, {
  required String content,
  required bool isStreaming,
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
              body: ParsedContentView(
                content: content,
                textColor: Colors.white,
                isStreaming: isStreaming,
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets(
    'auto-collapses a thought block once the thought completes during streaming',
    (tester) async {
      await _pumpParsedContentView(
        tester,
        content: '<think>Draft reasoning',
        isStreaming: true,
      );

      expect(find.text('Draft reasoning'), findsOneWidget);
      expect(find.text('Thinking...'), findsOneWidget);

      await _pumpParsedContentView(
        tester,
        content: '<think>Draft reasoning</think>\nFinal answer',
        isStreaming: true,
      );

      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('Draft reasoning'), findsNothing);
      expect(find.text('Final answer'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    },
  );

  testWidgets('renders malformed leading bracket text without throwing', (
    tester,
  ) async {
    await _pumpParsedContentView(
      tester,
      content: '[broken\\',
      isStreaming: false,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('[broken\\'), findsOneWidget);
  });
}
