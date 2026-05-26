import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
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

Future<SharedPreferences> _pumpMessageInput(
  WidgetTester tester, {
  required ValueNotifier<bool> isLoading,
  required VoidCallback onCancel,
  void Function(String message, String? imageBase64, String? imageMimeType)?
  onSend,
  MessageInputImageAttachment? droppedImageAttachment,
  AppSettings? initialSettings,
  bool isCodingWorkspace = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (initialSettings != null)
      'app_settings': jsonEncode(initialSettings.toJson()),
  });
  final preferences = await SharedPreferences.getInstance();

  await tester.runAsync(() async {
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
              ],
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: Scaffold(
                  body: ValueListenableBuilder<bool>(
                    valueListenable: isLoading,
                    builder: (context, loading, child) {
                      return MessageInput(
                        onSend: onSend ?? (_, _, _) {},
                        onCancel: onCancel,
                        isLoading: loading,
                        assistantMode: AssistantMode.general,
                        droppedImageAttachment: droppedImageAttachment,
                        isCodingWorkspace: isCodingWorkspace,
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  });
  await tester.pump();
  return preferences;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('keeps the composer enabled and queues send while loading', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    var cancelCount = 0;
    final sentMessages = <String>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {
        cancelCount += 1;
      },
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
    );

    expect(find.byIcon(Icons.record_voice_over), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    isLoading.value = true;
    await tester.pump();

    expect(find.byIcon(Icons.record_voice_over), findsNothing);
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    await tester.enterText(find.byType(TextField), 'Queued question');
    await tester.pump();

    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentMessages, ['Queued question']);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.byIcon(Icons.send), findsNothing);
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.stop_circle));
    await tester.pump();

    expect(cancelCount, 1);
  });

  testWidgets('attaches a dropped image to the composer', (tester) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    String? sentMessage;
    String? sentImageBase64;
    String? sentImageMimeType;
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
    );

    final previousDebugPrint = debugPrint;
    try {
      debugPrint = (String? message, {int? wrapWidth}) {};
      await _pumpMessageInput(
        tester,
        isLoading: isLoading,
        onCancel: () {},
        onSend: (message, imageBase64, imageMimeType) {
          sentMessage = message;
          sentImageBase64 = imageBase64;
          sentImageMimeType = imageMimeType;
        },
        droppedImageAttachment: MessageInputImageAttachment(
          id: 1,
          bytes: imageBytes,
          mimeType: 'image/png',
          filePath: 'drop.png',
        ),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(find.byIcon(Icons.send), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentMessage, isEmpty);
    expect(sentImageBase64, isNotEmpty);
    expect(sentImageMimeType, 'image/png');
  });

  testWidgets('updates reasoning effort from the composer menu', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final preferences = await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
    );

    expect(find.byIcon(Icons.psychology_alt_outlined), findsOneWidget);
    expect(find.byTooltip('Reasoning effort: API default'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.psychology_alt_outlined));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<ReasoningEffortPreference>,
        'High',
      ),
    );
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);

    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );
    expect(storedSettings.reasoningEffort, ReasoningEffortPreference.high);
    expect(find.byTooltip('Reasoning effort: High'), findsOneWidget);
  });

  testWidgets('updates coding approval mode from the composer menu', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final preferences = await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
    );

    expect(find.text('Default permissions'), findsOneWidget);
    expect(
      find.byTooltip('Permission mode: Default permissions'),
      findsOneWidget,
    );

    await tester.tap(find.text('Default permissions'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<CodingApprovalMode>,
        'Auto-review',
      ),
    );
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);

    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );
    expect(storedSettings.codingApprovalMode, CodingApprovalMode.autoReview);
    expect(find.byTooltip('Permission mode: Auto-review'), findsOneWidget);
  });
}
