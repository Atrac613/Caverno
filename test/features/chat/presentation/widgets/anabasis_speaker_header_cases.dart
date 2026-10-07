part of 'chat_presentation_widgets_tiny_test.dart';

class _TestTranslationLoaderAnabasisSpeakerHeader extends AssetLoader {
  const _TestTranslationLoaderAnabasisSpeakerHeader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

Future<void> _pumpAnabasisSpeakerHeader(WidgetTester tester) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoaderAnabasisSpeakerHeader(),
      child: Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: const Scaffold(body: AnabasisSpeakerHeader()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _runAnabasisSpeakerHeader() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('names the speaker and what it is', (tester) async {
    await _pumpAnabasisSpeakerHeader(tester);

    expect(find.text('Anabasis'), findsOneWidget);
    expect(
      find.text('orchestrator'),
      findsOneWidget,
      reason:
          'The name alone does not tell a reader why this reply changed '
          'nothing; the role does.',
    );
  });

  test('the flag survives persistence', () {
    final message = Message(
      id: 'm-1',
      content: 'Delegated to a child.',
      role: MessageRole.assistant,
      timestamp: DateTime(2026, 9, 4),
      isAnabasisParent: true,
    );

    expect(
      Message.fromJson(message.toJson()).isAnabasisParent,
      isTrue,
      reason:
          'Reopening a conversation has to keep the distinction, or the '
          'transcript stops explaining itself.',
    );
    expect(
      Message.fromJson(const {
        'id': 'm-0',
        'content': 'Older reply',
        'role': 'assistant',
        'timestamp': '2026-09-01T00:00:00.000',
      }).isAnabasisParent,
      isFalse,
      reason: 'Every message on disk predates this field.',
    );
  });
}
