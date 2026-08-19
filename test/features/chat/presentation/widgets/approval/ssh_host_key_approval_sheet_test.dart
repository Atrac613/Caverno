import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/services/ssh_host_key.dart';
import 'package:caverno/features/chat/presentation/widgets/approval/ssh_host_key_approval_sheet.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _unknown = SshHostKeyDecision(
  verdict: SshHostKeyVerdict.unknown,
  presented: SshKnownHostIdentity(
    host: 'ssh.example',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: 'SHA256:presented-fingerprint',
  ),
);

const _mismatch = SshHostKeyDecision(
  verdict: SshHostKeyVerdict.mismatch,
  presented: SshKnownHostIdentity(
    host: 'ssh.example',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: 'SHA256:presented-fingerprint',
  ),
  stored: SshKnownHostIdentity(
    host: 'ssh.example',
    port: 22,
    keyType: 'ssh-ed25519',
    fingerprint: 'SHA256:stored-fingerprint',
  ),
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required SshHostKeyDecision decision,
  required ValueChanged<bool?> onResult,
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
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      onResult(
                        await SshHostKeyApprovalSheet.show(context, decision),
                      );
                    },
                    child: const Text('Open Sheet'),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('unknown host shows the fingerprint and trusts on confirm', (
    tester,
  ) async {
    bool? result;
    await _pumpSheet(tester, decision: _unknown, onResult: (value) => result = value);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Trust this SSH host?'), findsOneWidget);
    expect(find.text('SHA256:presented-fingerprint'), findsOneWidget);

    await tester.tap(find.text('Trust host'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('mismatch shows both fingerprints and replaces on confirm', (
    tester,
  ) async {
    bool? result;
    await _pumpSheet(
      tester,
      decision: _mismatch,
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('SSH host key changed'), findsOneWidget);
    expect(find.text('SHA256:stored-fingerprint'), findsOneWidget);
    expect(find.text('SHA256:presented-fingerprint'), findsOneWidget);

    await tester.tap(find.text('Replace key'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancel rejects the host key', (tester) async {
    bool? result;
    await _pumpSheet(tester, decision: _unknown, onResult: (value) => result = value);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
