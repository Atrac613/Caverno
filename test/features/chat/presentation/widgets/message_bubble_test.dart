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
  bool settle = true,
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
                body: Center(child: MessageBubble(message: message)),
              ),
            ),
          );
        },
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
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
    final timestampFinder = find.textContaining('9:01');

    expect(timestampFinder, findsNothing);
    expect(find.byIcon(Icons.content_copy_outlined), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.text('Ship the hover toolbar')));
    await tester.pumpAndSettle();

    expect(timestampFinder, findsOneWidget);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);

    final messageRect = tester.getRect(find.text('Ship the hover toolbar'));
    final timestampRect = tester.getRect(timestampFinder);
    expect(timestampRect.top, greaterThan(messageRect.bottom));
  });

  testWidgets('shows timestamp and copy action on touch tap', (tester) async {
    final message = Message(
      id: 'touch-message',
      content: 'Tap to reveal actions',
      role: MessageRole.user,
      timestamp: DateTime(2026, 4, 18, 21, 2),
    );

    await _pumpMessageBubble(tester, message: message);
    final timestampFinder = find.textContaining('9:02');

    expect(timestampFinder, findsNothing);
    expect(find.byIcon(Icons.content_copy_outlined), findsNothing);

    await tester.tap(find.text('Tap to reveal actions'));
    await tester.pumpAndSettle();

    expect(timestampFinder, findsOneWidget);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);

    await tester.tap(find.text('Tap to reveal actions'));
    await tester.pumpAndSettle();

    expect(timestampFinder, findsNothing);
    expect(find.byIcon(Icons.content_copy_outlined), findsNothing);
  });

  testWidgets('keeps attached image bytes stable across rebuilds', (
    tester,
  ) async {
    const imageBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUl'
        'EQVR42mP8z8BQDwAFgwJ/lA0T8QAAAABJRU5ErkJggg==';
    final message = Message(
      id: 'image-message',
      content: 'Describe this image',
      role: MessageRole.user,
      timestamp: DateTime(2026, 5, 28, 21),
      imageBase64: imageBase64,
      imageMimeType: 'image/png',
    );

    await _pumpMessageBubble(tester, message: message);
    final firstImage = tester.widget<Image>(find.byType(Image));
    final firstProvider = firstImage.image as MemoryImage;

    await _pumpMessageBubble(
      tester,
      message: message.copyWith(content: 'Describe this image, please'),
    );
    final secondImage = tester.widget<Image>(find.byType(Image));
    final secondProvider = secondImage.image as MemoryImage;

    expect(identical(firstProvider.bytes, secondProvider.bytes), isTrue);
    expect(secondImage.width, 200);
    expect(secondImage.height, 140);
    expect(secondImage.gaplessPlayback, isTrue);
  });

  testWidgets('shows assistant response metrics after completion', (
    tester,
  ) async {
    final message = Message(
      id: 'assistant-message',
      content: 'Done.',
      role: MessageRole.assistant,
      timestamp: DateTime(2026, 6, 18, 11),
      responseMetrics: const MessageResponseMetrics(
        completionTokens: 88,
        elapsedMilliseconds: 2200,
        finishReason: 'stop',
      ),
    );

    await _pumpMessageBubble(tester, message: message);

    expect(find.text('40.00 tok/sec'), findsOneWidget);
    expect(find.text('88 tokens'), findsOneWidget);
    expect(find.text('2.20s'), findsOneWidget);
    expect(find.text('Stop reason: Stop'), findsOneWidget);
  });

  testWidgets('renders assistant messages without a bubble fill', (
    tester,
  ) async {
    final message = Message(
      id: 'plain-assistant-message',
      content: 'Plain assistant answer.',
      role: MessageRole.assistant,
      timestamp: DateTime(2026, 6, 29, 19, 20),
    );

    await _pumpMessageBubble(tester, message: message);

    final theme = Theme.of(tester.element(find.byType(MessageBubble)));
    final legacyAssistantBubbleContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration &&
              decoration.color == theme.colorScheme.surfaceContainerHighest;
        });

    expect(find.text('Plain assistant answer.'), findsOneWidget);
    expect(legacyAssistantBubbleContainers, isEmpty);
  });

  testWidgets('shows participant speaker snapshot for attributed assistant', (
    tester,
  ) async {
    final message = Message(
      id: 'participant-message',
      content: 'This proposal needs a rollback path.',
      role: MessageRole.assistant,
      timestamp: DateTime(2026, 6, 23, 12),
      participantId: 'reviewer',
      participantDisplayName: 'Reviewer',
      participantRoleLabel: 'Critic',
      participantColorValue: 0xFF006A6A,
    );

    await _pumpMessageBubble(tester, message: message);

    expect(find.text('Reviewer'), findsOneWidget);
    expect(find.text('Critic'), findsOneWidget);
    expect(find.text('This proposal needs a rollback path.'), findsOneWidget);
  });

  testWidgets('shows participant tool summary after completion', (
    tester,
  ) async {
    final message = Message(
      id: 'participant-tool-message',
      content: 'The current docs already cover the risky path.',
      role: MessageRole.assistant,
      timestamp: DateTime(2026, 6, 23, 12, 30),
      participantId: 'researcher',
      participantDisplayName: 'Researcher',
      participantRoleLabel: 'Evidence',
      participantToolNames: const [
        'builtin_search',
        'datetime_now',
        'builtin_search',
        ' ',
      ],
    );

    await _pumpMessageBubble(tester, message: message);

    expect(find.text('Tools'), findsOneWidget);
    expect(find.text('builtin_search'), findsOneWidget);
    expect(find.text('datetime_now'), findsOneWidget);
  });

  testWidgets('shows participant handoff cue after completion', (tester) async {
    final message = Message(
      id: 'participant-handoff-message',
      content:
          'The implementation details should be covered next.\n'
          'Engineer, what do you think about this risk?',
      role: MessageRole.assistant,
      timestamp: DateTime(2026, 6, 23, 12, 32),
      participantId: 'primary',
      participantDisplayName: 'Primary',
      participantRoleLabel: 'Facilitator',
      handoffTargetParticipantId: 'engineer',
      handoffTargetDisplayName: 'Engineer',
      handoffTargetRoleLabel: 'Senior Engineer',
    );

    await _pumpMessageBubble(tester, message: message);

    expect(
      find.text('Asked Engineer · Senior Engineer to respond'),
      findsOneWidget,
    );
  });

  testWidgets('hides participant tool summary while streaming', (tester) async {
    final message = Message(
      id: 'participant-streaming-tool-message',
      content: 'Looking up the current context',
      role: MessageRole.assistant,
      timestamp: DateTime(2026, 6, 23, 12, 35),
      isStreaming: true,
      participantId: 'researcher',
      participantDisplayName: 'Researcher',
      participantToolNames: const ['builtin_search'],
    );

    await _pumpMessageBubble(tester, message: message, settle: false);

    expect(find.text('Tools'), findsNothing);
    expect(find.text('builtin_search'), findsNothing);
  });
}
