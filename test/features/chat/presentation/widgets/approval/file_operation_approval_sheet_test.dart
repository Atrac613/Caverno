import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/file_operation_approval_sheet.dart';

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

  testWidgets('renders file operation details and approves', (tester) async {
    bool? result;
    await _pumpHarness(tester, onResult: (approved) => result = approved);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Edit file'), findsOneWidget);
    expect(find.text('/repo/lib/main.dart'), findsOneWidget);
    expect(find.text('Apply requested change'), findsOneWidget);
    expect(find.text('updated content'), findsOneWidget);

    await tester.tap(find.text('Approve Change'));
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
                          await FileOperationApprovalSheet.show(
                            sheetContext,
                            PendingFileOperation(
                              id: 'file-operation-test',
                              operation: 'Edit file',
                              path: '/repo/lib/main.dart',
                              preview: 'updated content',
                              reason: 'Apply requested change',
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
