import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _editMarker = 'CODING_GOAL_EDIT_TEST_OK';
const _testCommand = 'dart lib/canary_greeting_test.dart';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY'] == '1';
  final runLabel = Platform
      .environment['CAVERNO_CODING_GOAL_LIVE_EDIT_RUN_LABEL']
      ?.trim();
  final testNamePrefix = runLabel == null || runLabel.isEmpty
      ? ''
      : '[$runLabel] ';

  test(
    '${testNamePrefix}live LLM edits code and runs the fixture test for an active coding goal',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.create(env.workspaceRoot);
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final toolService = _SandboxCodingToolService(fixture.root);
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Fix the selected coding project by editing lib/canary_greeting.dart '
              'so canaryGreeting("Ada") returns exactly '
              '"Hello, Ada! $_editMarker". Then run local_execute_command '
              'with command "$_testCommand" in the project root. The goal is '
              'complete only after the command exits with code 0 and prints '
              '$_editMarker.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 12000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Inspect the fixture if needed, make the '
          'smallest code change, run exactly "$_testCommand", and finish only '
          'after the test passes. Mention $_editMarker and say '
          '"Goal complete. Tests passed." in the final answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        final testResult = await fixture.runTest();
        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);

        expect(
          dataSource.firstSystemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          dataSource.firstSystemPrompt,
          contains(project.rootPath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.sourceFile.readAsStringSync(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.executedToolNames,
          anyOf(contains('edit_file'), contains('write_file')),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulTestCommandCount,
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.exitCode,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.stdout,
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 8)),
  );

  test(
    '${testNamePrefix}live LLM repairs code after observing the failing fixture test',
    () async {
      final env = _CodingGoalLiveEditEnv.fromEnvironment();
      final fixture = _CodingGoalEditFixture.create(env.workspaceRoot);
      final project = fixture.project;
      final dataSource = _CodingGoalLiveEditDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final toolService = _SandboxCodingToolService(fixture.root);
      final container = _buildCodingGoalLiveEditContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
        );
        await conversations.saveCurrentGoal(
          objective:
              'Repair the selected coding project with a red-green workflow. '
              'First run local_execute_command with command "$_testCommand" '
              'in the project root before any edit_file or write_file call; '
              'that first test failure is expected. Use the failure output to '
              'edit lib/canary_greeting.dart so canaryGreeting("Ada") returns '
              'exactly "Hello, Ada! $_editMarker". Then rerun '
              'local_execute_command with the same command. The goal is '
              'complete only after a later command exits with code 0 and '
              'prints $_editMarker.',
          enabled: true,
          status: ConversationGoalStatus.active,
          tokenBudget: 16000,
          turnBudget: 6,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use the active coding goal. Run exactly "$_testCommand" before '
          'editing any file, inspect the failure, make the smallest repair, '
          'rerun exactly "$_testCommand", and finish only after the rerun '
          'passes. Mention $_editMarker and say '
          '"Goal complete. Tests passed." in the final answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        final testResult = await fixture.runTest();
        final goal = _currentGoal(container);
        final finalContent = _lastAssistantContent(container);
        final testExitCodes = toolService.testCommandExitCodes;
        final sourceBeforeTestCommands =
            toolService.testCommandSourceContainsMarkerBeforeCall;

        expect(
          dataSource.firstSystemPrompt,
          contains('Active coding goal for this thread:'),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          dataSource.firstSystemPrompt,
          contains(project.rootPath),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.firstTestCommandIndex,
          isNot(-1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.firstMutationIndex,
          greaterThan(toolService.firstTestCommandIndex),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testExitCodes.length,
          greaterThanOrEqualTo(2),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testExitCodes.first,
          isNot(0),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testExitCodes.last,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          sourceBeforeTestCommands.first,
          isFalse,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          fixture.sourceFile.readAsStringSync(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          toolService.successfulTestCommandCount,
          greaterThanOrEqualTo(1),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.exitCode,
          0,
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          testResult.stdout,
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_editMarker),
          reason: _diagnostic(container, dataSource, toolService, fixture),
        );
        expect(goal?.status, ConversationGoalStatus.completed);
        expect(goal?.turnsUsed, 1);
        expect(goal?.completedAt, isNotNull);
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_GOAL_LIVE_EDIT_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

ProviderContainer _buildCodingGoalLiveEditContainer({
  required _CodingGoalLiveEditEnv env,
  required _CodingGoalLiveEditDataSource dataSource,
  required _SandboxCodingToolService toolService,
  required CodingProject project,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(() => _LiveSettingsNotifier(env)),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _LiveCodingProjectsNotifier(project),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

Future<void> _waitForChatIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    final hasFinishedAssistant = state.messages.any(
      (message) =>
          message.role == MessageRole.assistant && !message.isStreaming,
    );
    if (!state.isLoading && hasFinishedAssistant) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for coding goal live edit canary completion.\n'
    '${_diagnostic(container, null, null, null)}',
  );
}

String _lastAssistantContent(ProviderContainer container) {
  final messages = container.read(chatNotifierProvider).messages;
  for (final message in messages.reversed) {
    if (message.role == MessageRole.assistant) {
      return message.content;
    }
  }
  return '';
}

ConversationGoal? _currentGoal(ProviderContainer container) {
  return container
      .read(conversationsNotifierProvider)
      .currentConversation
      ?.goal;
}

String _diagnostic(
  ProviderContainer container,
  _CodingGoalLiveEditDataSource? dataSource,
  _SandboxCodingToolService? toolService,
  _CodingGoalEditFixture? fixture,
) {
  final chatState = container.read(chatNotifierProvider);
  final conversation = container
      .read(conversationsNotifierProvider)
      .currentConversation;
  final messages = chatState.messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n');
  return [
    'isLoading=${chatState.isLoading}',
    'error=${chatState.error}',
    'messages=${chatState.messages.length}',
    'goal=${jsonEncode(conversation?.goal?.toJson())}',
    'streamRequests=${dataSource?.streamRequests.length ?? 0}',
    'streamWithToolsRequests=${dataSource?.streamWithToolsRequests.length ?? 0}',
    'fixtureRoot=${fixture?.root.path ?? '(none)'}',
    'source=${fixture?.sourceFile.existsSync() == true ? fixture!.sourceFile.readAsStringSync() : '(missing)'}',
    'toolCalls=${toolService?.executedCalls.map((call) => call.toJson()).map(jsonEncode).join(' | ') ?? '(none)'}',
    messages,
  ].join('\n');
}

class _CodingGoalEditFixture {
  _CodingGoalEditFixture({
    required this.root,
    required this.project,
    required this.deleteOnDispose,
  });

  final Directory root;
  final CodingProject project;
  final bool deleteOnDispose;

  File get sourceFile => File('${root.path}/lib/canary_greeting.dart');

  static _CodingGoalEditFixture create(String? workspaceRoot) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_goal_live_edit_')
        : Directory(workspaceRoot);
    root.createSync(recursive: true);
    final lib = Directory('${root.path}/lib')..createSync(recursive: true);
    File('${lib.path}/canary_greeting.dart').writeAsStringSync('''
String canaryGreeting(String name) {
  return 'Hello, \$name.';
}
''');
    File('${lib.path}/canary_greeting_test.dart').writeAsStringSync('''
import 'dart:io';

import 'canary_greeting.dart';

void main() {
  const marker = '$_editMarker';
  final actual = canaryGreeting('Ada');
  const expected = 'Hello, Ada! $_editMarker';
  if (actual != expected) {
    throw StateError('Expected "\$expected" but got "\$actual".');
  }
  stdout.writeln(marker);
}
''');
    final now = DateTime.now();
    return _CodingGoalEditFixture(
      root: root,
      project: CodingProject(
        id: 'coding-goal-live-edit-project',
        name: 'coding_goal_live_edit_fixture',
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  Future<ProcessResult> runTest() {
    return Process.run('dart', [
      'lib/canary_greeting_test.dart',
    ], workingDirectory: root.path);
  }

  void dispose() {
    if (deleteOnDispose && root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

class _CodingGoalLiveEditEnv {
  const _CodingGoalLiveEditEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
    required this.workspaceRoot,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;
  final String? workspaceRoot;

  static _CodingGoalLiveEditEnv fromEnvironment() {
    return _CodingGoalLiveEditEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_MAX_TOKENS'] ??
                '',
          ) ??
          4096,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_TEMPERATURE'] ??
                '',
          ) ??
          0.1,
      workspaceRoot:
          Platform.environment['CAVERNO_CODING_GOAL_LIVE_EDIT_WORK_ROOT'],
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for coding goal live edit validation.');
  }
  return value;
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.env);

  final _CodingGoalLiveEditEnv env;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.coding,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: true,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      demoMode: false,
    );
  }
}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  _LiveCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() {
    return CodingProjectsState(
      projects: [project],
      selectedProjectId: project.id,
    );
  }

  @override
  Future<bool> ensureProjectAccess(String? projectId) async {
    return projectId == project.id;
  }
}

class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _MockConversationBox extends Mock implements Box<String> {}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(ChatMemoryRepository(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    return null;
  }

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    return const MemoryUpdateResult.none();
  }

  @override
  UserMemoryProfile loadProfile() {
    return UserMemoryProfile.empty();
  }
}

class _SandboxToolCall {
  const _SandboxToolCall({
    required this.name,
    required this.arguments,
    required this.result,
    required this.success,
    required this.sourceBeforeCall,
  });

  final String name;
  final Map<String, dynamic> arguments;
  final String result;
  final bool success;
  final String? sourceBeforeCall;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'arguments': arguments,
      'success': success,
      'result': result,
      if (sourceBeforeCall != null) 'sourceBeforeCall': sourceBeforeCall,
    };
  }
}

class _SandboxCodingToolService extends McpToolService {
  _SandboxCodingToolService(this.root);

  final Directory root;
  final List<_SandboxToolCall> executedCalls = [];

  List<String> get executedToolNames =>
      executedCalls.map((call) => call.name).toList(growable: false);

  List<int> get testCommandExitCodes => executedCalls
      .where((call) => call.name == 'local_execute_command')
      .map((call) => _tryDecodeObject(call.result)['exit_code'])
      .whereType<num>()
      .map((code) => code.toInt())
      .toList(growable: false);

  List<bool> get testCommandSourceContainsMarkerBeforeCall => executedCalls
      .where((call) => call.name == 'local_execute_command')
      .map((call) => call.sourceBeforeCall?.contains(_editMarker) ?? false)
      .toList(growable: false);

  int get firstTestCommandIndex =>
      executedCalls.indexWhere((call) => call.name == 'local_execute_command');

  int get firstMutationIndex => executedCalls.indexWhere(
    (call) => call.name == 'edit_file' || call.name == 'write_file',
  );

  int get successfulTestCommandCount => executedCalls.where((call) {
    if (call.name != 'local_execute_command' || !call.success) {
      return false;
    }
    final decoded = _tryDecodeObject(call.result);
    return decoded['exit_code'] == 0 &&
        (decoded['stdout'] as String? ?? '').contains(_editMarker);
  }).length;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const [
      {
        'type': 'function',
        'function': {
          'name': 'list_directory',
          'description':
              'List files in the isolated coding goal edit canary fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'recursive': {'type': 'boolean'},
              'max_entries': {'type': 'integer'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'read_file',
          'description':
              'Read a UTF-8 text file from the isolated coding goal edit canary fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'offset': {'type': 'integer'},
              'limit': {'type': 'integer'},
            },
            'required': ['path'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'edit_file',
          'description':
              'Replace exact text inside a file in the isolated fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'old_text': {'type': 'string'},
              'new_text': {'type': 'string'},
              'replace_all': {'type': 'boolean'},
              'reason': {'type': 'string'},
            },
            'required': ['path', 'old_text', 'new_text'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'write_file',
          'description':
              'Write a full UTF-8 text file in the isolated fixture.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
              'create_parents': {'type': 'boolean'},
              'reason': {'type': 'string'},
            },
            'required': ['path', 'content'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'local_execute_command',
          'description':
              'Run the fixture test. Only "dart lib/canary_greeting_test.dart" is accepted.',
          'parameters': {
            'type': 'object',
            'properties': {
              'command': {'type': 'string'},
              'working_directory': {'type': 'string'},
              'reason': {'type': 'string'},
            },
            'required': ['command'],
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final sourceBeforeCall = _sourceText();
    final result = await _executeTool(name: name, arguments: arguments);
    executedCalls.add(
      _SandboxToolCall(
        name: name,
        arguments: Map<String, dynamic>.from(arguments),
        result: result.result,
        success: result.isSuccess,
        sourceBeforeCall: sourceBeforeCall,
      ),
    );
    return result;
  }

  String? _sourceText() {
    final file = File('${root.path}/lib/canary_greeting.dart');
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsStringSync();
  }

  Future<McpToolResult> _executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    switch (name) {
      case 'list_directory':
        final path = _resolveInsideRoot(
          arguments['path'] as String?,
          allowEmpty: true,
        );
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.listDirectory(
          path: path.value!,
          recursive: arguments['recursive'] as bool? ?? false,
          maxEntries: ((arguments['max_entries'] as num?)?.toInt() ?? 200)
              .clamp(1, 500),
        );
        return _toolResult(name, result);
      case 'read_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.readFile(
          path: path.value!,
          offset: ((arguments['offset'] as num?)?.toInt() ?? 1).clamp(
            1,
            1000000,
          ),
          limit: (arguments['limit'] as num?)?.toInt(),
        );
        return _toolResult(name, result);
      case 'edit_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.editFile(
          path: path.value!,
          oldText: arguments['old_text'] as String? ?? '',
          newText: arguments['new_text'] as String? ?? '',
          replaceAll: arguments['replace_all'] as bool? ?? false,
        );
        return _toolResult(name, result);
      case 'write_file':
        final path = _resolveInsideRoot(arguments['path'] as String?);
        if (path.error != null) {
          return _toolError(name, path.error!);
        }
        final result = await FilesystemTools.writeFile(
          path: path.value!,
          content: arguments['content'] as String? ?? '',
          createParents: arguments['create_parents'] as bool? ?? true,
        );
        return _toolResult(name, result);
      case 'local_execute_command':
        return _executeTestCommand(name, arguments);
      default:
        return _toolError(name, 'Unsupported canary tool: $name');
    }
  }

  Future<McpToolResult> _executeTestCommand(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final command = (arguments['command'] as String?)?.trim() ?? '';
    if (!_isAcceptedTestCommand(command)) {
      return _toolError(
        name,
        'Only "$_testCommand" is accepted by this canary fixture.',
      );
    }
    final workingDirectory = _resolveInsideRoot(
      arguments['working_directory'] as String?,
      allowEmpty: true,
      directory: true,
    );
    if (workingDirectory.error != null) {
      return _toolError(name, workingDirectory.error!);
    }
    if (workingDirectory.value != root.absolute.path) {
      return _toolError(
        name,
        'working_directory must be the canary project root.',
      );
    }

    final result = await Process.run('dart', [
      'lib/canary_greeting_test.dart',
    ], workingDirectory: root.path).timeout(const Duration(seconds: 30));
    final stdoutText = result.stdout as String;
    final stderrText = result.stderr as String;
    final payload = jsonEncode({
      'command': _testCommand,
      'working_directory': root.absolute.path,
      'exit_code': result.exitCode,
      'stdout': stdoutText,
      'stderr': stderrText,
    });
    return McpToolResult(
      toolName: name,
      result: payload,
      isSuccess: result.exitCode == 0,
      errorMessage: result.exitCode == 0 ? null : 'Fixture test failed',
    );
  }

  bool _isAcceptedTestCommand(String command) {
    final normalized = command
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(
          './lib/canary_greeting_test.dart',
          'lib/canary_greeting_test.dart',
        )
        .trim();
    return normalized == _testCommand ||
        normalized == 'dart --enable-asserts lib/canary_greeting_test.dart';
  }

  _ResolvedPath _resolveInsideRoot(
    String? rawPath, {
    bool allowEmpty = false,
    bool directory = false,
  }) {
    final trimmed = rawPath?.trim();
    final effectivePath = (trimmed == null || trimmed.isEmpty) && allowEmpty
        ? '.'
        : trimmed;
    final resolved = FilesystemTools.resolvePath(
      effectivePath,
      defaultRoot: root.absolute.path,
    );
    if (resolved == null || resolved.trim().isEmpty) {
      return const _ResolvedPath(error: 'path is required');
    }

    final rootPath = root.absolute.path;
    final targetPath = directory
        ? Directory(resolved).absolute.path
        : File(resolved).absolute.path;
    if (targetPath != rootPath &&
        !targetPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return const _ResolvedPath(
        error: 'Path must stay inside the canary project root.',
      );
    }
    return _ResolvedPath(value: targetPath);
  }

  McpToolResult _toolResult(String name, String result) {
    final decoded = _tryDecodeObject(result);
    final error = decoded['error'] as String?;
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: error == null || error.isEmpty,
      errorMessage: error,
    );
  }

  McpToolResult _toolError(String name, String error) {
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': error}),
      isSuccess: false,
      errorMessage: error,
    );
  }
}

class _ResolvedPath {
  const _ResolvedPath({this.value, this.error});

  final String? value;
  final String? error;
}

Map<String, dynamic> _tryDecodeObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

class _CodingGoalLiveEditDataSource implements ChatDataSource {
  _CodingGoalLiveEditDataSource(this.delegate);

  final ChatRemoteDataSource delegate;
  final List<List<Message>> streamRequests = [];
  final List<List<Message>> streamWithToolsRequests = [];
  final List<List<Message>> createWithToolResultRequests = [];

  List<String> get systemPrompts {
    return [
          ...streamRequests,
          ...streamWithToolsRequests,
          ...createWithToolResultRequests,
        ]
        .expand((request) => request)
        .where(
          (message) =>
              message.role == MessageRole.system &&
              message.content.startsWith('Current local date and time'),
        )
        .map((message) => message.content)
        .toList(growable: false);
  }

  String get firstSystemPrompt {
    return systemPrompts.firstOrNull ?? '';
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamRequests.add(List<Message>.unmodifiable(messages));
    return delegate.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final firstContent = messages.isEmpty ? '' : messages.first.content;
    if (firstContent.startsWith(
      'You extract reusable user memory from a conversation.',
    )) {
      return Future.value(
        ChatCompletionResult(
          content: jsonEncode(<String, dynamic>{
            'summary': '',
            'open_loops': const <String>[],
            'profile': <String, dynamic>{
              'persona': const <String>[],
              'preferences': const <String>[],
              'do_not': const <String>[],
            },
            'memories': const <Map<String, dynamic>>[],
          }),
          finishReason: 'stop',
        ),
      );
    }
    return delegate.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamWithToolsRequests.add(List<Message>.unmodifiable(messages));
    return delegate.streamChatCompletionWithTools(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    createWithToolResultRequests.add(List<Message>.unmodifiable(messages));
    return delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
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
  }) {
    createWithToolResultRequests.add(List<Message>.unmodifiable(messages));
    return delegate.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
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
    createWithToolResultRequests.add(List<Message>.unmodifiable(messages));
    return delegate.streamWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}
