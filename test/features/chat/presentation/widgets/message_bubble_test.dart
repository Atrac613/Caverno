import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/services/tts_service.dart';
import 'package:caverno/core/services/voice_providers.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/widgets/message_bubble.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

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

class _FakeTtsService extends TtsService {
  @override
  bool get isSpeaking => false;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setSpeechRate(double rate) async {}
}

Future<void> _pumpMessageBubble(
  WidgetTester tester, {
  required Message message,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();

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
          return ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(preferences),
              ttsServiceProvider.overrideWithValue(_FakeTtsService()),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(
                body: Center(
                  child: MessageBubble(message: message),
                ),
              ),
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

  testWidgets('shows timestamp and copy action on user message hover', (
    tester,
  ) async {
    final message = Message(
      id: 'user-message',
      content: 'Ship the hover toolbar',
      role: MessageRole.user,
      timestamp: DateTime(2026, 4, 18, 21, 1),
    );

    await _pumpMessageBubble(tester, message: message);

    expect(find.text('9:01 PM'), findsNothing);
    expect(find.byIcon(Icons.content_copy_outlined), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.text('Ship the hover toolbar')));
    await tester.pumpAndSettle();

    expect(find.text('9:01 PM'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);

    final messageRect = tester.getRect(find.text('Ship the hover toolbar'));
    final timestampRect = tester.getRect(find.text('9:01 PM'));
    expect(timestampRect.top, greaterThan(messageRect.bottom));
  });
}
