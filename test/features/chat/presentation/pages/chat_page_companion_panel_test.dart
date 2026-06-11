import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_environment_snapshot_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.coding,
      demoMode: false,
      mcpEnabled: false,
    );
  }
}

class _CompanionConversationsNotifier extends ConversationsNotifier {
  _CompanionConversationsNotifier(this.conversation);

  final Conversation conversation;

  @override
  ConversationsState build() {
    return ConversationsState(
      conversations: [conversation],
      currentConversationId: conversation.id,
      activeWorkspaceMode: WorkspaceMode.coding,
      activeProjectId: conversation.projectId,
    );
  }
}

class _CompanionCodingProjectsNotifier extends CodingProjectsNotifier {
  _CompanionCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() {
    return CodingProjectsState(
      projects: [project],
      selectedProjectId: project.id,
    );
  }
}

class _TestChatNotifier extends ChatNotifier {
  @override
  ChatState build() => ChatState.initial();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets('wide coding workspace shows the companion panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync(
      'chat_page_companion_panel_test_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final now = DateTime(2026, 5, 28, 9, 25);
    final project = CodingProject(
      id: 'project-1',
      name: 'example_app',
      rootPath: tempDir.path,
      createdAt: now,
      updatedAt: now,
    );
    final conversation = Conversation(
      id: 'thread-1',
      title: 'Companion panel thread',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Inspect current parser state',
            status: ConversationWorkflowTaskStatus.completed,
            targetFiles: ['lib/parser.dart'],
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Add parser regression coverage',
            status: ConversationWorkflowTaskStatus.inProgress,
            targetFiles: ['test/parser_test.dart'],
          ),
        ],
      ),
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    var currentBranch = 'feature/companion-panel';
    final gitCommands = <String>[];
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          () => _CompanionConversationsNotifier(conversation),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _CompanionCodingProjectsNotifier(project),
        ),
        chatNotifierProvider.overrideWith(_TestChatNotifier.new),
        routineSchedulerProvider.overrideWith(RoutineSchedulerController.new),
        codingEnvironmentProcessRunnerProvider.overrideWithValue((
          executable,
          arguments, {
          workingDirectory,
        }) async {
          gitCommands.add(arguments.join(' '));
          return switch (arguments.join(' ')) {
            'rev-parse --show-toplevel' => ProcessResult(
              1,
              0,
              '${tempDir.path}\n',
              '',
            ),
            'branch --show-current' => ProcessResult(
              1,
              0,
              '$currentBranch\n',
              '',
            ),
            'for-each-ref --format=%(refname:short) refs/heads' =>
              ProcessResult(
                1,
                0,
                'main\nfeature/companion-panel\nfeature/other-panel\n',
                '',
              ),
            'status --short' => ProcessResult(
              1,
              0,
              ' M lib/parser.dart\nA  test/parser_test.dart\n',
              '',
            ),
            'diff --shortstat' => ProcessResult(
              1,
              0,
              ' 2 files changed, 4 insertions(+), 1 deletion(-)\n',
              '',
            ),
            'diff --cached --shortstat' => ProcessResult(1, 0, '', ''),
            'diff --numstat HEAD --' => ProcessResult(
              1,
              0,
              '3\t1\tlib/parser.dart\n1\t0\ttest/parser_test.dart\n',
              '',
            ),
            'diff --no-ext-diff --unified=3 HEAD --' => ProcessResult(1, 0, '''
diff --git a/lib/parser.dart b/lib/parser.dart
--- a/lib/parser.dart
+++ b/lib/parser.dart
@@ -1,3 +1,5 @@
 const keep = true;
-const old = true;
+const old = false;
+const next = true;
+const another = true;
diff --git a/test/parser_test.dart b/test/parser_test.dart
--- a/test/parser_test.dart
+++ b/test/parser_test.dart
@@ -0,0 +1 @@
+test('parser', () {});
''', ''),
            'ls-files --others --exclude-standard -z' => ProcessResult(
              1,
              0,
              '',
              '',
            ),
            'checkout feature/other-panel' => () {
              currentBranch = 'feature/other-panel';
              return ProcessResult(
                1,
                0,
                'Switched to branch feature/other-panel\n',
                '',
              );
            }(),
            _ => ProcessResult(1, 1, '', 'unexpected git command'),
          };
        }),
      ],
    );
    addTearDown(container.dispose);

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
            return UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: const ChatPage(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsNothing);
    expect(
      find.byKey(const ValueKey('persistent-workspace-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('drawer-workspace-coding')),
      findsOneWidget,
    );
    expect(find.text('example_app'), findsWidgets);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('1 of 2 complete'), findsOneWidget);
    expect(find.text('Inspect current parser state'), findsOneWidget);
    expect(find.text('Add parser regression coverage'), findsOneWidget);
    expect(find.text('feature/companion-panel'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('feature/other-panel').last);
    await tester.pumpAndSettle();

    expect(currentBranch, 'feature/other-panel');
    expect(gitCommands, contains('checkout feature/other-panel'));
    expect(find.text('Switched to feature/other-panel.'), findsOneWidget);
    expect(find.text('feature/other-panel'), findsOneWidget);
    expect(find.text('Uncommitted changes'), findsOneWidget);
    final changesValueFinder = find.byWidgetPredicate((widget) {
      return widget is Text &&
          widget.textSpan?.toPlainText() == 'git diff HEAD  +4 -1';
    });
    expect(changesValueFinder, findsOneWidget);
    final changesText = tester.widget<Text>(changesValueFinder);
    final changesSpan = changesText.textSpan! as TextSpan;
    final changesChildren = changesSpan.children!.cast<TextSpan>();
    expect(
      changesChildren.firstWhere((span) => span.text == '+4').style?.color,
      Colors.green.shade700,
    );
    expect(
      changesChildren.firstWhere((span) => span.text == '-1').style?.color,
      Theme.of(tester.element(changesValueFinder)).colorScheme.error,
    );
    expect(find.text('lib/parser.dart'), findsOneWidget);
    expect(find.text('test/parser_test.dart'), findsOneWidget);

    await tester.tap(find.text('Uncommitted changes'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('right-sidebar-tabs')), findsOneWidget);
    expect(find.text('Companion'), findsOneWidget);
    expect(find.text('Files'), findsWidgets);
    expect(find.text('Progress'), findsNothing);
    expect(find.text('lib/parser.dart'), findsWidgets);

    await tester.tap(find.text('Companion'));
    await tester.pumpAndSettle();

    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);

    await tester.tap(find.text('Files').first);
    await tester.pumpAndSettle();

    expect(find.text('Progress'), findsNothing);
    expect(find.text('Uncommitted changes'), findsOneWidget);
  });
}
