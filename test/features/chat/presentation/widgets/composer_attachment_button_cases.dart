part of 'chat_presentation_widgets_tiny_test.dart';

class _TestTranslationLoaderComposerAttachmentButton extends AssetLoader {
  const _TestTranslationLoaderComposerAttachmentButton();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

Future<void> _pumpComposerAttachmentButton(
  WidgetTester tester, {
  required bool videoEnabled,
  VoidCallback? onPickVideo,
  VoidCallback? onEnterVideoUrl,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoaderComposerAttachmentButton(),
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Scaffold(
            body: ComposerAttachmentButton(
              onPickImage: () {},
              onPickFile: () {},
              onPickVideo: onPickVideo ?? () {},
              onEnterVideoUrl: onEnterVideoUrl ?? () {},
              videoEnabled: videoEnabled,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add));
  await tester.pumpAndSettle();
}

void _runComposerAttachmentButton() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('offers video only when the endpoint accepts it', (tester) async {
    await _pumpComposerAttachmentButton(tester, videoEnabled: true);

    expect(find.text('Attach video'), findsOneWidget);
    expect(find.text('Video URL'), findsOneWidget);
  });

  testWidgets('hides video entries when the endpoint cannot take one', (
    tester,
  ) async {
    await _pumpComposerAttachmentButton(tester, videoEnabled: false);

    expect(find.text('Attach video'), findsNothing);
    expect(find.text('Video URL'), findsNothing);
    // The rest of the menu is untouched.
    expect(find.text('Attach image'), findsOneWidget);
  });

  testWidgets('selecting the video entry runs its action', (tester) async {
    var picked = false;
    await _pumpComposerAttachmentButton(
      tester,
      videoEnabled: true,
      onPickVideo: () => picked = true,
    );

    await tester.tap(find.text('Attach video'));
    await tester.pumpAndSettle();

    expect(picked, isTrue);
  });
}
