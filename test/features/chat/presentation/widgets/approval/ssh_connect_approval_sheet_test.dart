import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/ssh_connect_approval_sheet.dart';

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

  testWidgets('renders pending connection fields and returns approval', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SshConnectApproval? result;
    await _pumpHarness(
      tester,
      pending: _buildPending(savedPassword: 'secret-password'),
      onResult: (approval) => result = approval,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('remote.example'), findsOneWidget);
    expect(find.text('deploy'), findsOneWidget);
    expect(find.text('(saved)'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.host, 'remote.example');
    expect(result!.port, 2222);
    expect(result!.username, 'deploy');
    expect(result!.password, 'secret-password');
    expect(result!.savePassword, isTrue);
  });

  testWidgets('cancel returns null', (tester) async {
    SshConnectApproval? result = SshConnectApproval(
      host: 'unchanged',
      port: 22,
      username: 'unchanged',
      password: 'unchanged',
      savePassword: false,
    );
    await _pumpHarness(
      tester,
      pending: _buildPending(savedPassword: null),
      onResult: (approval) => result = approval,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required PendingSshConnect pending,
  required ValueChanged<SshConnectApproval?> onResult,
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
                          await SshConnectApprovalSheet.show(
                            sheetContext,
                            pending,
                          ),
                        );
                      },
                      child: const Text('Open Sheet'),
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

PendingSshConnect _buildPending({required String? savedPassword}) {
  return PendingSshConnect(
    id: 'ssh-connect-test',
    host: 'remote.example',
    port: 2222,
    username: 'deploy',
    savedPassword: savedPassword,
    completer: Completer<SshConnectApproval?>(),
  );
}
