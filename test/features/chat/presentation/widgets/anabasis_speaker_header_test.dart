import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/widgets/anabasis_speaker_header.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

Future<void> _pump(WidgetTester tester) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('names the speaker and what it is', (tester) async {
    await _pump(tester);

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
