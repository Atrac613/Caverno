part of 'approval_widgets_tiny_test.dart';

class _TestTranslationLoaderParticipantToolApprovalSheet extends AssetLoader {
  const _TestTranslationLoaderParticipantToolApprovalSheet();

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

void _runParticipantToolApprovalSheet() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('renders participant rows and truncated arguments preview', (
    tester,
  ) async {
    bool? result;
    await _pumpHarnessParticipantToolApprovalSheet(
      tester,
      onResult: (approved) => result = approved,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Reviewer'), findsOneWidget);
    expect(find.text('Needs another read-only check'), findsOneWidget);
    expect(find.textContaining('"query"'), findsOneWidget);
    expect(find.textContaining('...'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('deny returns false', (tester) async {
    bool? result = true;
    await _pumpHarnessParticipantToolApprovalSheet(
      tester,
      onResult: (approved) => result = approved,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}

Future<void> _pumpHarnessParticipantToolApprovalSheet(
  WidgetTester tester, {
  required ValueChanged<bool?> onResult,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  return tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoaderParticipantToolApprovalSheet(),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: Builder(
                builder: (sheetContext) {
                  return Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        onResult(
                          await ParticipantToolApprovalSheet.show(
                            sheetContext,
                            PendingParticipantToolApproval(
                              owner: ChatTurnOwner(
                                conversationId: 'thread-a',
                                interactionGeneration: 7,
                              ),
                              id: 'participant-tool-test',
                              participantId: 'researcher',
                              participantName: 'Researcher',
                              participantRoleLabel: 'Reviewer',
                              toolName: 'search_files',
                              arguments: {
                                'query': 'approval',
                                'payload': List.filled(1300, 'x').join(),
                              },
                              reason: 'Needs another read-only check',
                              completer: Completer<bool>(),
                            ),
                          ),
                        );
                      },
                      child: const Text('Show Sheet'),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}
