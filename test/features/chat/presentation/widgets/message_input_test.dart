import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/presentation/providers/composer_shortcuts_notifier.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
import 'package:caverno/features/chat/domain/entities/video_attachment_draft.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/entities/model_catalog_entry.dart';
import 'package:caverno/features/settings/presentation/providers/model_list_provider.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

/// Seeds the shortcut bar without running a completion, and records what the
/// composer clears.
class _SeededComposerShortcutsNotifier extends ComposerShortcutsNotifier {
  _SeededComposerShortcutsNotifier({
    this.shortcuts = const <ComposerShortcut>[],
    this.isGenerating = false,
  });

  final List<ComposerShortcut> shortcuts;
  final bool isGenerating;
  int clearCount = 0;

  @override
  ComposerShortcutsState build() => const ComposerShortcutsState();

  @override
  List<ComposerShortcut> get visibleShortcuts => shortcuts;

  @override
  bool get isGeneratingForVisibleThread => isGenerating;

  @override
  void clear([String? threadId]) => clearCount++;
}

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
  void Function(
    String message,
    String? imageBase64,
    String? imageMimeType,
    String? originalImagePath,
    String? originalImageMimeType, {
    VideoAttachmentDraft? video,
    String? modelContent,
    String? attachmentPath,
  })?
  onSend,
  MessageInputImageAttachment? droppedImageAttachment,
  AppSettings? initialSettings,
  bool isCodingWorkspace = false,
  ConversationGoal? codingGoal,
  VoidCallback? onCodingGoalEdit,
  VoidCallback? onCodingGoalMarkComplete,
  VoidCallback? onCodingGoalMarkBlocked,
  VoidCallback? onCodingGoalReactivate,
  VoidCallback? onCodingGoalClear,
  WorktreeSessionSendHandler? onWorktreeSessionSend,
  List<SlashCommandDefinition> slashCommands = const <SlashCommandDefinition>[],
  SlashCommandHandler? onSlashCommand,
  bool Function(String question)? onProReasoningSend,
  _SeededComposerShortcutsNotifier? composerShortcuts,
  List<ModelCatalogEntry>? modelCatalog,
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
                // The composer reads the shortcut bar from this provider, whose
                // real notifier observes the whole chat graph.
                composerShortcutsNotifierProvider.overrideWith(
                  () => composerShortcuts ?? _SeededComposerShortcutsNotifier(),
                ),
                // The composer model picker reads the endpoint catalog; keep
                // the widget test off the network.
                if (modelCatalog != null)
                  modelCatalogProvider.overrideWith(
                    (ref, config) async => modelCatalog,
                  ),
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
                        onSend:
                            onSend ?? (_, _, _, _, _, {video, modelContent, attachmentPath}) {},
                        onCancel: onCancel,
                        isLoading: loading,
                        assistantMode: AssistantMode.general,
                        droppedImageAttachment: droppedImageAttachment,
                        isCodingWorkspace: isCodingWorkspace,
                        codingGoal: codingGoal,
                        onCodingGoalEdit: onCodingGoalEdit,
                        onCodingGoalMarkComplete: onCodingGoalMarkComplete,
                        onCodingGoalMarkBlocked: onCodingGoalMarkBlocked,
                        onCodingGoalReactivate: onCodingGoalReactivate,
                        onCodingGoalClear: onCodingGoalClear,
                        onWorktreeSessionSend: onWorktreeSessionSend,
                        slashCommands: slashCommands,
                        onSlashCommand: onSlashCommand,
                        onProReasoningSend: onProReasoningSend,
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

Future<void> _waitForImageAttachmentPreview(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    if (find.byIcon(Icons.close).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Timed out waiting for image attachment preview');
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

const _testShortcuts = <ComposerShortcut>[
  ComposerShortcut(
    kind: ComposerShortcutKind.git,
    label: 'Commit',
    prompt: 'Commit the composer shortcut changes.',
  ),
  ComposerShortcut(
    kind: ComposerShortcutKind.verify,
    label: 'Run tests',
    prompt: 'Run flutter test and report the failures.',
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
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) {
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
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const ValueKey('pro-reasoning-mode-button')),
          )
          .enabled,
      isFalse,
    );

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
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) {
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
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) {
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
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) {
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
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) {
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
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) {
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
        onSend: (message, imageBase64, _, _, _, {video, modelContent, attachmentPath}) {
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

      await _waitForImageAttachmentPreview(tester);
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
        onSend:
            (message, imageBase64, imageMimeType, _, _, {video, modelContent, attachmentPath}) {
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

      await _waitForImageAttachmentPreview(tester);
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

  testWidgets('persists Pro Reasoning depth from the chat composer', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final preferences = await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
    );

    expect(
      find.byKey(const ValueKey('pro-reasoning-mode-button')),
      findsOneWidget,
    );
    expect(find.text('Pro'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pro-reasoning-mode-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<String>, 'Standard'),
    );
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);
    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );
    expect(storedSettings.proReasoningEnabled, isTrue);
    expect(storedSettings.proReasoningDepth, ProReasoningDepth.standard);
    expect(find.text('Pro: Standard'), findsOneWidget);
  });

  testWidgets('routes sticky Pro text without calling ordinary send', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);
    final proQuestions = <String>[];
    final ordinaryMessages = <String>[];

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      initialSettings: AppSettings.defaults().copyWith(
        proReasoningEnabled: true,
      ),
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) =>
          ordinaryMessages.add(message),
      onProReasoningSend: (question) {
        proQuestions.add(question);
        return true;
      },
    );

    await tester.enterText(find.byType(TextField), 'Compare the options');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(proQuestions, ['Compare the options']);
    expect(ordinaryMessages, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('retains sticky Pro input and attachment when unsupported', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);
    var proStarts = 0;
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
        initialSettings: AppSettings.defaults().copyWith(
          proReasoningEnabled: true,
        ),
        droppedImageAttachment: MessageInputImageAttachment(
          id: 41,
          bytes: imageBytes,
          mimeType: 'image/png',
          filePath: 'evidence.png',
        ),
        onProReasoningSend: (_) {
          proStarts += 1;
          return true;
        },
      );
      await _waitForImageAttachmentPreview(tester);
    } finally {
      debugPrint = previousDebugPrint;
    }

    await tester.enterText(find.byType(TextField), 'Use this evidence');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(proStarts, 0);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Use this evidence',
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(
      find.textContaining('does not support attachments yet'),
      findsOneWidget,
    );
  });

  testWidgets('hides Pro Reasoning in coding and sends normally', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);
    final ordinaryMessages = <String>[];

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      initialSettings: AppSettings.defaults().copyWith(
        proReasoningEnabled: true,
      ),
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) =>
          ordinaryMessages.add(message),
      onProReasoningSend: (_) => true,
    );

    expect(
      find.byKey(const ValueKey('pro-reasoning-mode-button')),
      findsNothing,
    );
    await tester.enterText(find.byType(TextField), 'Fix the issue');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(ordinaryMessages, ['Fix the issue']);
  });

  testWidgets('hides empty coding goal controls inside the composer', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    var editCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      onCodingGoalEdit: () {
        editCount += 1;
      },
    );

    expect(find.text('Goal'), findsNothing);
    expect(find.text('No active goal'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byTooltip('Set goal'), findsNothing);

    expect(editCount, 0);
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
    var editCount = 0;
    var completeCount = 0;
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      codingGoal: goal,
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
    expect(find.byType(Switch), findsNothing);

    await tester.tap(find.byTooltip('Edit goal'));
    await tester.pump();

    expect(editCount, 1);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete'));
    await tester.pumpAndSettle();

    expect(completeCount, 1);
  });

  testWidgets('shows confirmation summary and completion controls', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);
    final goal = ConversationGoal(
      id: 'goal-confirmation',
      objective: 'Finish the release checks',
      status: ConversationGoalStatus.awaitingConfirmation,
      completionSummary:
          'The turn budget was reached. No mechanical gap is recorded.',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    var completeCount = 0;

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      codingGoal: goal,
      onCodingGoalMarkComplete: () => completeCount += 1,
      onCodingGoalMarkBlocked: () {},
      onCodingGoalReactivate: () {},
    );

    expect(find.text('Awaiting confirmation'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('coding-goal-confirmation-summary')),
      findsOneWidget,
    );
    expect(find.textContaining('turn budget was reached'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Reactivate'), findsOneWidget);
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

    // The control bar scrolls horizontally; the approval chip sits past the
    // model picker at the test viewport width.
    await tester.ensureVisible(find.text('Default permissions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default permissions'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<ToolApprovalMode>,
        'Auto-review',
      ),
    );
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);

    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );
    expect(storedSettings.codingApprovalMode, ToolApprovalMode.autoReview);
    expect(find.byTooltip('Permission mode: Auto-review'), findsOneWidget);
  });

  testWidgets('switches the chat model from the composer picker', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final preferences = await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      modelCatalog: const [
        ModelCatalogEntry(id: 'model-a'),
        ModelCatalogEntry(id: 'model-b'),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('composer-model-chip')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SubmenuButton, 'Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'model-b'));
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);
    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );
    expect(storedSettings.model, 'model-b');
    expect(
      find.byTooltip('Model: model-b / Effort: API default'),
      findsOneWidget,
    );
  });

  testWidgets('sets reasoning effort from the same composer chip', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final preferences = await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      modelCatalog: const [ModelCatalogEntry(id: 'model-a')],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('composer-model-chip')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SubmenuButton, 'Effort'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'High'));
    await tester.pumpAndSettle();

    final storedJson = preferences.getString('app_settings');
    expect(storedJson, isNotNull);
    final storedSettings = AppSettings.fromJson(
      jsonDecode(storedJson!) as Map<String, dynamic>,
    );
    expect(storedSettings.reasoningEffort, ReasoningEffortPreference.high);
    // The chip carries the effort next to the model name.
    expect(find.text('High'), findsOneWidget);
  });

  testWidgets('starts a new worktree session from composer text', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);
    final localMessages = <String>[];
    final worktreePrompts = <String>[];

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      isCodingWorkspace: true,
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) {
        localMessages.add(message);
      },
      onWorktreeSessionSend: (prompt) async {
        worktreePrompts.add(prompt);
        return 'feature/composer-ui';
      },
    );

    expect(find.text('Work locally'), findsOneWidget);
    expect(find.byTooltip('Start in: Work locally'), findsOneWidget);

    // The control bar scrolls horizontally; the worktree chip sits past the
    // model picker at the test viewport width.
    await tester.ensureVisible(
      find.byKey(const ValueKey('worktree-mode-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('worktree-mode-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<MessageInputWorktreeMode>,
        'New worktree',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New worktree'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('worktree-base-branch-chip')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'Build the composer UI');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(localMessages, isEmpty);
    expect(worktreePrompts, ['Build the composer UI']);
    expect(
      find.text('Switched to worktree: feature/composer-ui'),
      findsOneWidget,
    );
  });

  testWidgets('sends the tapped shortcut prompt through the composer', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final shortcuts = _SeededComposerShortcutsNotifier(
      shortcuts: _testShortcuts,
    );
    final sentMessages = <String>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) =>
          sentMessages.add(message),
      composerShortcuts: shortcuts,
    );

    expect(find.byKey(const ValueKey('composer-shortcut-bar')), findsOneWidget);
    expect(find.text('Commit'), findsOneWidget);
    expect(find.text('Run tests'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('composer-shortcut-1')));
    await tester.pumpAndSettle();

    expect(sentMessages, [_testShortcuts[1].prompt]);
    expect(shortcuts.clearCount, 1);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, isEmpty);
  });

  testWidgets('lays the shortcut chips out from the leading edge', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      composerShortcuts: _SeededComposerShortcutsNotifier(
        shortcuts: _testShortcuts,
      ),
    );

    final bar = tester.getRect(
      find.byKey(const ValueKey('composer-shortcut-bar')),
    );
    final firstChip = tester.getRect(
      find.byKey(const ValueKey('composer-shortcut-0')),
    );

    expect(firstChip.left, closeTo(bar.left, 0.5));
    expect(bar.width, greaterThan(firstChip.width * 2));
  });

  testWidgets('long press puts the shortcut prompt in the composer', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    final sentMessages = <String>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) =>
          sentMessages.add(message),
      composerShortcuts: _SeededComposerShortcutsNotifier(
        shortcuts: _testShortcuts,
      ),
    );

    await tester.longPress(find.byKey(const ValueKey('composer-shortcut-0')));
    await tester.pumpAndSettle();

    expect(sentMessages, isEmpty);
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller?.text, _testShortcuts[0].prompt);
  });

  testWidgets('shows a generating chip before any shortcut arrives', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      composerShortcuts: _SeededComposerShortcutsNotifier(isGenerating: true),
    );

    expect(
      find.byKey(const ValueKey('composer-shortcut-generating')),
      findsOneWidget,
    );
  });

  testWidgets('hides the shortcut bar when nothing is suggested', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      composerShortcuts: _SeededComposerShortcutsNotifier(),
    );

    expect(find.byKey(const ValueKey('composer-shortcut-bar')), findsNothing);
  });

  testWidgets('slash suggestions replace the shortcut bar', (tester) async {
    final isLoading = ValueNotifier<bool>(false);
    addTearDown(isLoading.dispose);

    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      slashCommands: _testSlashCommands,
      onSlashCommand: (_) => SlashCommandExecutionResult.handled,
      composerShortcuts: _SeededComposerShortcutsNotifier(
        shortcuts: _testShortcuts,
      ),
    );

    expect(find.byKey(const ValueKey('composer-shortcut-bar')), findsOneWidget);

    await tester.enterText(find.byType(TextField), '/');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('slash-command-suggestions')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('composer-shortcut-bar')), findsNothing);
  });

  testWidgets('disables shortcut chips while a response is running', (
    tester,
  ) async {
    final isLoading = ValueNotifier<bool>(true);
    addTearDown(isLoading.dispose);

    final sentMessages = <String>[];
    await _pumpMessageInput(
      tester,
      isLoading: isLoading,
      onCancel: () {},
      onSend: (message, _, _, _, _, {video, modelContent, attachmentPath}) =>
          sentMessages.add(message),
      composerShortcuts: _SeededComposerShortcutsNotifier(
        shortcuts: _testShortcuts,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('composer-shortcut-0')));
    await tester.pump();

    expect(sentMessages, isEmpty);
  });
}
