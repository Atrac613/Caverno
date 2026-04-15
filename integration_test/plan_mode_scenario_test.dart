import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _NoOpNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _PlanModeScenario {
  const _PlanModeScenario({
    required this.name,
    required this.userPrompt,
    required this.projectName,
    required this.initialTaskTitle,
    required this.requirementsContent,
    required this.readmeContent,
    required this.finalAnswer,
  });

  final String name;
  final String userPrompt;
  final String projectName;
  final String initialTaskTitle;
  final String requirementsContent;
  final String readmeContent;
  final String finalAnswer;
}

class _FakePlanModeChatDataSource implements ChatDataSource {
  _FakePlanModeChatDataSource(this.scenario);

  final _PlanModeScenario scenario;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final prompt = messages.last.content;

    if (messages.first.content.startsWith(
      'You extract reusable user memory from a conversation.',
    )) {
      appLog('[ScenarioLLM] memory extraction');
      return ChatCompletionResult(
        content: jsonEncode({
          'summary': 'The user is building a host health check tool.',
          'open_loops': const <String>[],
          'profile': {
            'persona': const <String>[],
            'preferences': const <String>[],
            'constraints': const <String>[],
          },
        }),
        finishReason: 'stop',
      );
    }

    if (prompt.contains(
      'Create a workflow proposal for the current coding thread.',
    )) {
      appLog('[ScenarioLLM] workflow proposal');
      return ChatCompletionResult(
        content: jsonEncode({
          'workflowStage': 'plan',
          'goal':
              'Create a Python host health check scaffold that starts with ping-based diagnostics.',
          'constraints': [
            'Keep the first slice small and reviewable.',
            'Use a simple Python dependency list.',
          ],
          'acceptanceCriteria': [
            'requirements.txt exists with the initial dependency list.',
            'README.md describes the scaffolded project.',
          ],
          'openQuestions': const <String>[],
        }),
        finishReason: 'stop',
      );
    }

    if (prompt.contains(
      'Create a task proposal for the current coding thread.',
    )) {
      appLog('[ScenarioLLM] task proposal');
      return ChatCompletionResult(
        content: jsonEncode({
          'tasks': [
            {
              'title': scenario.initialTaskTitle,
              'targetFiles': ['requirements.txt', 'README.md'],
              'validationCommand': 'ls requirements.txt',
              'notes':
                  'Initialize the repository with basic documentation and dependency list.',
            },
            {
              'title': 'Implement the ping health check entry point',
              'targetFiles': ['main.py'],
              'validationCommand': 'python main.py --help',
              'notes':
                  'Add the first executable slice after the scaffold exists.',
            },
          ],
        }),
        finishReason: 'stop',
      );
    }

    appLog('[ScenarioLLM] createChatCompletion fallback');
    return ChatCompletionResult(content: '{}', finishReason: 'stop');
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final prompt = messages.last.content;
    if (prompt.startsWith(
      'Please answer the user\'s question based on the following search results.',
    )) {
      appLog('[ScenarioLLM] final answer stream');
      yield scenario.finalAnswer;
      return;
    }

    appLog('[ScenarioLLM] empty stream fallback');
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final prompt = messages.last.content;
    if (prompt.contains('Use the saved task "${scenario.initialTaskTitle}"')) {
      appLog('[ScenarioLLM] implementation tool call stream');
      return StreamWithToolsResult(
        stream: const Stream<String>.empty(),
        completion: Future.value(
          ChatCompletionResult(
            content: '',
            finishReason: 'tool_calls',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-write-requirements',
                name: 'write_file',
                arguments: {
                  'path': 'requirements.txt',
                  'content': scenario.requirementsContent,
                },
              ),
            ],
          ),
        ),
      );
    }

    appLog('[ScenarioLLM] streamWithTools fallback');
    return StreamWithToolsResult(
      stream: const Stream<String>.empty(),
      completion: Future.value(
        ChatCompletionResult(content: '', finishReason: 'stop'),
      ),
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final arguments = jsonDecode(toolArguments) as Map<String, dynamic>;
    final path = arguments['path'] as String? ?? '';

    if (path == 'requirements.txt') {
      appLog('[ScenarioLLM] follow-up tool call for README');
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-write-readme',
            name: 'write_file',
            arguments: {'path': 'README.md', 'content': scenario.readmeContent},
          ),
        ],
      );
    }

    appLog('[ScenarioLLM] tool loop complete');
    return ChatCompletionResult(content: '', finishReason: 'stop');
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return const Stream<String>.empty();
  }
}

Future<void> _takeScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  await tester.pumpAndSettle();
  try {
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot(name);
  } on MissingPluginException {
    appLog('[Scenario] Screenshot plugin unavailable, skipping "$name"');
  }
}

Future<Widget> _buildScenarioApp({
  required SharedPreferences prefs,
  required Box<String> conversationBox,
  required Box<String> memoryBox,
  required ChatDataSource dataSource,
}) async {
  await EasyLocalization.ensureInitialized();
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('ja')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    useOnlyLangCode: true,
    child: Builder(
      builder: (context) {
        return ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            conversationBoxProvider.overrideWithValue(conversationBox),
            chatMemoryBoxProvider.overrideWithValue(memoryBox),
            chatRemoteDataSourceProvider.overrideWithValue(dataSource),
            notificationServiceProvider.overrideWithValue(
              _NoOpNotificationService(),
            ),
          ],
          child: MaterialApp(
            title: 'Caverno',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
            ),
            themeMode: ThemeMode.dark,
            home: const ChatPage(),
          ),
        );
      },
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Plan mode scenarios', () {
    late Box<String> conversationBox;
    late Box<String> memoryBox;
    late DebugPrintCallback originalDebugPrint;
    late List<String> logs;

    setUp(() async {
      await Hive.initFlutter();
      await EasyLocalization.ensureInitialized();

      logs = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
        originalDebugPrint(message, wrapWidth: wrapWidth);
      };

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      conversationBox = await Hive.openBox<String>('plan_mode_conv_$timestamp');
      memoryBox = await Hive.openBox<String>('plan_mode_mem_$timestamp');
    });

    tearDown(() async {
      debugPrint = originalDebugPrint;
      await conversationBox.close();
      await memoryBox.close();
    });

    testWidgets('approves a plan and scaffolds the first task', (tester) async {
      final scenario = _PlanModeScenario(
        name: 'host_health_scaffold',
        userPrompt:
            'Create a Python script to diagnose the health of a specific host using ping.',
        projectName: 'tmp',
        initialTaskTitle: 'Setup project structure and dependencies',
        requirementsContent: 'ping3>=4.0.0\n',
        readmeContent:
            '# Host Health Check\n\nThis project bootstraps a ping-based host health check tool.\n',
        finalAnswer:
            'I created requirements.txt and README.md to bootstrap the project scaffold.',
      );

      final scenarioDir = await Directory.systemTemp.createTemp(
        'caverno_plan_mode_',
      );
      final project = CodingProject(
        id: 'project-plan-mode',
        name: scenario.projectName,
        rootPath: scenarioDir.path,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final settings = AppSettings.defaults().copyWith(
        assistantMode: AssistantMode.plan,
        language: 'en',
        mcpEnabled: true,
        mcpUrl: '',
        mcpUrls: const [],
        mcpServers: const [],
        confirmFileMutations: false,
        confirmLocalCommands: false,
        confirmGitWrites: false,
        showMemoryUpdates: false,
      );

      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode(settings.toJson()),
        'coding_projects': jsonEncode([project.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        await _buildScenarioApp(
          prefs: prefs,
          conversationBox: conversationBox,
          memoryBox: memoryBox,
          dataSource: _FakePlanModeChatDataSource(scenario),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatPage)),
        listen: false,
      );
      container
          .read(codingProjectsNotifierProvider.notifier)
          .selectProject(project.id);
      container
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      await tester.pumpAndSettle();

      expect(find.text('Coding'), findsOneWidget);
      expect(find.text('Plan mode'), findsAtLeastNWidgets(1));

      await tester.enterText(find.byType(TextField), scenario.userPrompt);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Suggested plan'), findsOneWidget);
      expect(
        find.textContaining(scenario.initialTaskTitle),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Approve and start'), findsOneWidget);

      await _takeScreenshot(
        binding,
        tester,
        'plan_mode_${scenario.name}_proposal',
      );

      final approveFinder = find.text('Approve and start');
      await tester.ensureVisible(approveFinder);
      await tester.tap(approveFinder, warnIfMissed: false);
      await tester.pump();
      await tester.pumpAndSettle();

      final requirementsFile = File('${scenarioDir.path}/requirements.txt');
      final readmeFile = File('${scenarioDir.path}/README.md');

      expect(requirementsFile.existsSync(), isTrue);
      expect(readmeFile.existsSync(), isTrue);
      expect(requirementsFile.readAsStringSync(), scenario.requirementsContent);
      expect(readmeFile.readAsStringSync(), scenario.readmeContent);
      expect(
        find.textContaining('requirements.txt and README.md'),
        findsAtLeastNWidgets(1),
      );

      expect(
        logs.any((line) => line.contains('[ScenarioLLM] workflow proposal')),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[Tool] Executing tool: write_file')),
        isTrue,
      );
      expect(
        logs.any((line) => line.contains('[ScenarioLLM] final answer stream')),
        isTrue,
      );

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(currentConversation, isNotNull);
      expect(
        currentConversation!.workflowSpec?.tasks.first.title,
        scenario.initialTaskTitle,
      );

      await _takeScreenshot(
        binding,
        tester,
        'plan_mode_${scenario.name}_completed',
      );

      final report = {
        'scenario': scenario.name,
        'status': 'passed',
        'projectRoot': scenarioDir.path,
        'artifacts': {
          'requirements.txt': requirementsFile.readAsStringSync(),
          'README.md': readmeFile.readAsStringSync(),
        },
        'logChecks': [
          '[ScenarioLLM] workflow proposal',
          '[Tool] Executing tool: write_file',
          '[ScenarioLLM] final answer stream',
        ],
        'capturedLogs': logs
            .where(
              (line) =>
                  line.contains('[ScenarioLLM]') ||
                  line.contains('[Tool]') ||
                  line.contains('[LLM]'),
            )
            .toList(growable: false),
      };
      final reportFile = File('${scenarioDir.path}/scenario_report.json');
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );
      appLog('[Scenario] Report written to ${reportFile.path}');
    });
  });
}
