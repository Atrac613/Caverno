part of 'chat_presentation_widgets_tiny_test.dart';

void _runProjectRunControlSection() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, {required bool flutterSupported}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          flutterRunSupportedProvider(
            '/tmp/project',
          ).overrideWithValue(flutterSupported),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ProjectRunControlSection(
              projectRoot: '/tmp/project',
              threadId: 'thread-1',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a Flutter project gets the flutter run control', (tester) async {
    await pump(tester, flutterSupported: true);

    expect(find.byType(FlutterRunControlSection), findsOneWidget);
    expect(find.byType(HtmlPreviewControlSection), findsNothing);
  });

  testWidgets('anything else falls to the HTML preview control', (
    tester,
  ) async {
    // htmlPreviewSupportedProvider already returns false wherever the Flutter
    // one is true, so reaching here means the project is the HTML kind: the
    // panel only renders this section when one of the two holds.
    await pump(tester, flutterSupported: false);

    expect(find.byType(HtmlPreviewControlSection), findsOneWidget);
    expect(find.byType(FlutterRunControlSection), findsNothing);
  });

  test('the panel sees a runner when either kind is supported', () {
    ProviderContainer containerFor({
      required bool flutter,
      required bool html,
    }) => ProviderContainer(
      overrides: [
        flutterRunSupportedProvider('/tmp/p').overrideWithValue(flutter),
        htmlPreviewSupportedProvider('/tmp/p').overrideWithValue(html),
      ],
    );

    for (final (flutter, html, expected) in const [
      (true, false, true),
      (false, true, true),
      (false, false, false),
    ]) {
      final container = containerFor(flutter: flutter, html: html);
      addTearDown(container.dispose);
      expect(
        container.read(projectRunControlSupportedProvider('/tmp/p')),
        expected,
        reason: 'flutter=$flutter html=$html',
      );
    }
  });
}
