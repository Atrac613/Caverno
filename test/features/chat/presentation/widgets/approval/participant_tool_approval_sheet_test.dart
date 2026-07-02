import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/participant_tool_approval_sheet.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('renders participant rows and truncated arguments preview', (
    tester,
  ) async {
    bool? result;
    await _pumpHarness(tester, onResult: (approved) => result = approved);
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
    await _pumpHarness(tester, onResult: (approved) => result = approved);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}

Future<void> _pumpHarness(
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
      assetLoader: const _TestTranslationLoader(),
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
                              id: 'participant-tool-test',
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
