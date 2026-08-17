import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/ssh_auth_credential.dart';
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
      pending: _buildPending(
        savedCredential: const SshPasswordCredential('secret-password'),
      ),
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
    expect(result!.credential, const SshPasswordCredential('secret-password'));
    expect(result!.remember, isTrue);
  });

  // The reported failure: a key-authenticated host left the sheet with no way
  // to approve, because Connect refused to close while the password box was
  // empty. Cancel was the only exit, and the model was told the user had
  // cancelled.
  testWidgets('approves private-key auth with no password entered', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SshConnectApproval? result;
    await _pumpHarness(
      tester,
      pending: _buildPending(
        savedCredential: null,
        identityCandidates: const ['/home/deploy/.ssh/id_ed25519'],
      ),
      onResult: (approval) => result = approval,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // A discovered default identity selects key auth and pre-fills the path.
    expect(find.text('/home/deploy/.ssh/id_ed25519'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(
      result!.credential,
      const SshPrivateKeyCredential(keyPath: '/home/deploy/.ssh/id_ed25519'),
    );
  });

  testWidgets('rejects key auth with no key file chosen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    var resolved = false;
    await _pumpHarness(
      tester,
      pending: _buildPending(savedCredential: null),
      onResult: (_) => resolved = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Private key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a private key file'), findsOneWidget);
    expect(resolved, isFalse);
  });

  testWidgets('cancel returns null', (tester) async {
    SshConnectApproval? result = SshConnectApproval(
      host: 'unchanged',
      port: 22,
      username: 'unchanged',
      credential: const SshPasswordCredential('unchanged'),
      remember: false,
    );
    await _pumpHarness(
      tester,
      pending: _buildPending(savedCredential: null),
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

PendingSshConnect _buildPending({
  required SshAuthCredential? savedCredential,
  List<String> identityCandidates = const [],
}) {
  return PendingSshConnect(
    owner: ChatTurnOwner(
      conversationId: 'ssh-sheet-test',
      interactionGeneration: 1,
    ),
    id: 'ssh-connect-test',
    host: 'remote.example',
    port: 2222,
    username: 'deploy',
    savedCredential: savedCredential,
    identityCandidates: identityCandidates,
    completer: Completer<SshConnectApproval?>(),
  );
}
