import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/theme/app_theme.dart';
import 'package:caverno/core/theme/app_tokens.dart';
import 'package:caverno/features/chat/presentation/widgets/file_workspace_viewer_sheet.dart';
import 'package:caverno/features/chat/presentation/widgets/markdown_style_helpers.dart';
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
  ThemeData? theme,
  String? fileReferenceRootPath,
  ValueChanged<FileWorkspaceViewerRequest>? onOpenFileWorkspaceViewer,
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
            theme: theme,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: ParsedContentView(
                content: content,
                textColor: Colors.white,
                isStreaming: isStreaming,
                fileReferenceRootPath: fileReferenceRootPath,
                onOpenFileWorkspaceViewer: onOpenFileWorkspaceViewer,
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

  testWidgets('renders inline LaTeX math as a Math widget, not raw text', (
    tester,
  ) async {
    await _pumpParsedContentView(
      tester,
      content: r'The complexity is $O(\sqrt{n})$ overall.',
      isStreaming: false,
    );

    expect(tester.takeException(), isNull);
    // The TeX span is rendered by flutter_math, so the raw delimiters must not
    // survive as literal text.
    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'$O(\sqrt{n})$'), findsNothing);
  });

  testWidgets('renders display math delimited by double dollars', (
    tester,
  ) async {
    await _pumpParsedContentView(
      tester,
      content: r'$$\int_0^1 x^2 \, dx = \frac{1}{3}$$',
      isStreaming: false,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('renders markdown tables with visible border color', (
    tester,
  ) async {
    await _pumpParsedContentView(
      tester,
      theme: AppTheme.dark,
      content: '| Name | Value |\n| --- | --- |\n| Alpha | 1 |',
      isStreaming: false,
    );

    final table = tester.widget<Table>(find.byType(Table));
    final border = table.border;
    final expectedSide = markdownTableBorderSide(AppTheme.dark);
    final appColors = AppTheme.dark.extension<AppSemanticColors>()!;

    expect(border, isNotNull);
    expect(border!.top, expectedSide);
    expect(border.horizontalInside, expectedSide);
    expect(border.verticalInside, expectedSide);
    expect(border.top.color, appColors.textMuted);
    expect(border.top.width, 0.5);
  });

  testWidgets('notifies parent when a file reference link is selected', (
    tester,
  ) async {
    FileWorkspaceViewerRequest? openedRequest;

    await _pumpParsedContentView(
      tester,
      content: 'Open lib/main.dart:12 for context.',
      isStreaming: false,
      fileReferenceRootPath: '/tmp/project',
      onOpenFileWorkspaceViewer: (request) {
        openedRequest = request;
      },
    );

    await tester.tap(find.textContaining('lib/main.dart'));
    await tester.pump();

    expect(openedRequest, isNotNull);
    expect(openedRequest!.rootPath, '/tmp/project');
    expect(openedRequest!.initialPath, 'lib/main.dart');
    expect(openedRequest!.references.map((reference) => reference.label), [
      'lib/main.dart:12',
    ]);
  });
}
