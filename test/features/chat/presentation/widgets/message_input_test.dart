import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
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
  ConversationGoal? codingGoal,
  bool isCodingGoalSetupPending = false,
  bool isCodingGoalSuggestionInProgress = false,
  CodingGoalSwitchChanged? onCodingGoalSwitchChanged,
  VoidCallback? onCodingGoalEmptySwitchEnabled,
  VoidCallback? onCodingGoalEdit,
  VoidCallback? onCodingGoalMarkComplete,
  VoidCallback? onCodingGoalMarkBlocked,
  VoidCallback? onCodingGoalReactivate,
  VoidCallback? onCodingGoalClear,
  List<SlashCommandDefinition> slashCommands = const <SlashCommandDefinition>[],
  SlashCommandHandler? onSlashCommand,
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
                        codingGoal: codingGoal,
                        isCodingGoalSetupPending: isCodingGoalSetupPending,
                        isCodingGoalSuggestionInProgress:
                            isCodingGoalSuggestionInProgress,
                        onCodingGoalSwitchChanged: onCodingGoalSwitchChanged,
                        onCodingGoalEmptySwitchEnabled:
                            onCodingGoalEmptySwitchEnabled,
                        onCodingGoalEdit: onCodingGoalEdit,
                        onCodingGoalMarkComplete: onCodingGoalMarkComplete,
                        onCodingGoalMarkBlocked: onCodingGoalMarkBlocked,
                        onCodingGoalReactivate: onCodingGoalReactivate,
                        onCodingGoalClear: onCodingGoalClear,
                        slashCommands: slashCommands,
                        onSlashCommand: onSlashCommand,
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

const _testSlashCommands = <SlashCommandDefinition>[
  SlashCommandDefinition(
    name: 'help',
    action: SlashCommandAction.help,
    description: 'Show available slash commands',
    enabledWhileLoading: true,
  ),
  SlashCommandDefinition(
    name: 'clear',
    action: SlashCommandAction.clear,
    description: 'Clear the current conversation',
  ),
  SlashCommandDefinition(
    name: 'coding',
    action: SlashCommandAction.coding,
    description: 'Switch to coding mode',
    aliases: ['code'],
  ),
  SlashCommandDefinition(
    name: 'review',
    action: SlashCommandAction.review,
    description: 'Expand into a focused review prompt',
    aliases: ['rev'],
    argumentHint: '<target>',
    argumentRequirement: SlashCommandArgumentRequirement.required,
  ),
];

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

  testWidgets('shows slash command suggestions for a bare slash', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      slashCommands: _testSlashCommands,
      onSlashCommand: (_) => SlashCommandExecutionResult.handled,
    );

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('slash-command-suggestions')),
      findsOneWidget,
    );
    expect(find.text('/help'), findsOneWidget);
    expect(find.text('/clear'), findsOneWidget);
    expect(find.text('Show available slash commands'), findsOneWidget);
  });

  testWidgets('tab completes the selected slash command', (tester) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      slashCommands: _testSlashCommands,
      onSlashCommand: (_) => SlashCommandExecutionResult.handled,
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '/cl');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, '/clear ');
    expect(
      find.byKey(const ValueKey('slash-command-suggestions')),
      findsNothing,
    );
  });

  testWidgets('shows argument hints for prompt slash commands', (tester) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      slashCommands: _testSlashCommands,
      onSlashCommand: (_) => SlashCommandExecutionResult.handled,
    );

    await tester.enterText(find.byType(TextField), '/rev');
    await tester.pump();

    expect(find.text('/review <target>'), findsOneWidget);
    expect(find.text('Expand into a focused review prompt'), findsOneWidget);
  });

  testWidgets('enter executes a slash command without sending a message', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final sentMessages = <String>[];
    final invocations = <SlashCommandInvocation>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
      slashCommands: _testSlashCommands,
      onSlashCommand: (invocation) {
        invocations.add(invocation);
        return SlashCommandExecutionResult.handled;
      },
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '/help');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sentMessages, isEmpty);
    expect(invocations.single.definition.action, SlashCommandAction.help);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('prompt slash commands send expanded prompts with arguments', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final sentMessages = <String>[];
    final invocations = <SlashCommandInvocation>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
      slashCommands: _testSlashCommands,
      onSlashCommand: (invocation) {
        invocations.add(invocation);
        return SlashCommandExecutionResult.sendPrompt(
          'Review prompt for ${invocation.args}',
        );
      },
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '/review parser changes');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(invocations.single.definition.action, SlashCommandAction.review);
    expect(invocations.single.args, 'parser changes');
    expect(sentMessages, ['Review prompt for parser changes']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('required slash command arguments keep the draft when missing', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final sentMessages = <String>[];
    final invocations = <SlashCommandInvocation>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
      slashCommands: _testSlashCommands,
      onSlashCommand: (invocation) {
        invocations.add(invocation);
        return SlashCommandExecutionResult.sendPrompt('Should not send');
      },
    );

    await tester.enterText(find.byType(TextField), '/review');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentMessages, isEmpty);
    expect(invocations, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/review',
    );
    expect(
      find.text('Add details for /review. Usage: /review <target>'),
      findsOneWidget,
    );
  });

  testWidgets('no-argument slash commands reject extra arguments', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final sentMessages = <String>[];
    final invocations = <SlashCommandInvocation>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
      slashCommands: _testSlashCommands,
      onSlashCommand: (invocation) {
        invocations.add(invocation);
        return SlashCommandExecutionResult.handled;
      },
    );

    await tester.enterText(find.byType(TextField), '/clear now');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentMessages, isEmpty);
    expect(invocations, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/clear now',
    );
    expect(find.text('/clear does not take arguments.'), findsOneWidget);
  });

  testWidgets('unknown slash commands keep the draft', (tester) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final sentMessages = <String>[];
    final invocations = <SlashCommandInvocation>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
      slashCommands: _testSlashCommands,
      onSlashCommand: (invocation) {
        invocations.add(invocation);
        return SlashCommandExecutionResult.handled;
      },
    );

    await tester.enterText(find.byType(TextField), '/missing');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentMessages, isEmpty);
    expect(invocations, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/missing',
    );
    expect(find.text('Unknown slash command: /missing'), findsOneWidget);
  });

  testWidgets('slash-looking text with an attachment sends normally', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    String? sentMessage;
    String? sentImageBase64;
    var slashInvocationCount = 0;
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
        onSend: (message, imageBase64, _) {
          sentMessage = message;
          sentImageBase64 = imageBase64;
        },
        droppedImageAttachment: MessageInputImageAttachment(
          id: 2,
          bytes: imageBytes,
          mimeType: 'image/png',
          filePath: 'drop.png',
        ),
        slashCommands: _testSlashCommands,
        onSlashCommand: (_) {
          slashInvocationCount += 1;
          return SlashCommandExecutionResult.handled;
        },
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    } finally {
      debugPrint = previousDebugPrint;
    }

    await tester.enterText(find.byType(TextField), '/help');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(slashInvocationCount, 0);
    expect(sentMessage, '/help');
    expect(sentImageBase64, isNotEmpty);
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

  testWidgets('shows the empty coding goal switch inside the composer', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    bool? switchedTo;
    var editCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      onCodingGoalSwitchChanged: (value, draftText) {
        switchedTo = value;
      },
      onCodingGoalEdit: () {
        editCount += 1;
      },
    );

    expect(find.text('Goal'), findsOneWidget);
    expect(find.text('No active goal'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(switchedTo, isTrue);

    await tester.tap(find.byTooltip('Set goal'));
    await tester.pump();

    expect(editCount, 1);
  });

  testWidgets('defers an empty coding goal switch until the next send', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    bool? switchedTo;
    var deferredCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      onCodingGoalSwitchChanged: (value, draftText) {
        switchedTo = value;
      },
      onCodingGoalEmptySwitchEnabled: () {
        deferredCount += 1;
      },
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(deferredCount, 1);
    expect(switchedTo, isNull);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      isCodingGoalSetupPending: true,
      onCodingGoalSwitchChanged: (value, draftText) {
        switchedTo = value;
      },
      onCodingGoalEmptySwitchEnabled: () {
        deferredCount += 1;
      },
    );

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Goal setup pending'), findsOneWidget);
  });

  testWidgets('enables coding goal setup immediately when draft text exists', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    bool? switchedTo;
    String? switchDraftText;
    var deferredCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      onCodingGoalSwitchChanged: (value, draftText) {
        switchedTo = value;
        switchDraftText = draftText;
      },
      onCodingGoalEmptySwitchEnabled: () {
        deferredCount += 1;
      },
    );

    await tester.enterText(find.byType(TextField), 'Build the goal flow');
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(switchedTo, isTrue);
    expect(switchDraftText, 'Build the goal flow');
    expect(deferredCount, 0);
  });

  testWidgets('disables goal controls and send while suggesting a goal', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    var switchCount = 0;
    var editCount = 0;
    final sentMessages = <String>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
      isCodingWorkspace: true,
      onCodingGoalSwitchChanged: (_, _) {
        switchCount += 1;
      },
      onCodingGoalEdit: () {
        editCount += 1;
      },
    );

    await tester.enterText(find.byType(TextField), 'Build the goal flow');
    await tester.pump();

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _) {
        sentMessages.add(message);
      },
      isCodingWorkspace: true,
      isCodingGoalSuggestionInProgress: true,
      onCodingGoalSwitchChanged: (_, _) {
        switchCount += 1;
      },
      onCodingGoalEdit: () {
        editCount += 1;
      },
    );
    await tester.pump();

    expect(find.text('Drafting a goal...'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byType(Switch), warnIfMissed: false);
    await tester.tap(find.byTooltip('Set goal'), warnIfMissed: false);
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.send),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(switchCount, 0);
    expect(editCount, 0);
    expect(sentMessages, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Build the goal flow',
    );
  });

  testWidgets('keeps coding composer controls visible at narrow widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final overflowErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) {
        overflowErrors.add(details);
      } else {
        previousOnError?.call(details);
      }
    };
    addTearDown(() {
      FlutterError.onError = previousOnError;
    });

    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final goal = ConversationGoal(
      id: 'goal-1',
      objective:
          'Keep a very long coding goal objective visible without breaking the composer controls',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      codingGoal: goal,
    );

    await tester.enterText(find.byType(TextField), 'Ship the narrow composer');
    await tester.pump();

    expect(overflowErrors, isEmpty);
    expect(find.widgetWithIcon(IconButton, Icons.send), findsOneWidget);
    expect(find.textContaining('Keep a very long coding goal'), findsOneWidget);
  });

  testWidgets('shows active coding goal details and action callbacks', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final goal = ConversationGoal(
      id: 'goal-1',
      objective: 'Fix the composer goal flow',
      tokenBudget: 2000,
      tokenUsage: 500,
      turnBudget: 5,
      turnsUsed: 2,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    bool? switchedTo;
    var editCount = 0;
    var completeCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      codingGoal: goal,
      onCodingGoalSwitchChanged: (value, draftText) {
        switchedTo = value;
      },
      onCodingGoalEdit: () {
        editCount += 1;
      },
      onCodingGoalMarkComplete: () {
        completeCount += 1;
      },
    );

    expect(find.text('Fix the composer goal flow'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('500/2.0k tokens  2/5 turns'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(switchedTo, isFalse);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pump();

    expect(editCount, 1);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(completeCount, 1);
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
