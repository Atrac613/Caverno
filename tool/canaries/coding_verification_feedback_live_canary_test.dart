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
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _trigger = 'VERIFICATION_FEEDBACK_LIVE_CANARY_TRIGGER';
const _marker = 'VERIFICATION_FEEDBACK_LIVE_OK';
const _brokenMarker = 'VERIFICATION_FEEDBACK_LIVE_BROKEN';
const _scriptedWriteId = 'verification-feedback-scripted-write';
const _scenarios = [
  _VerificationFeedbackScenario(
    name: 'root package',
    sourcePath: 'lib/canary_value.dart',
    testPath: 'test/canary_value_test.dart',
    packageName: 'caverno_coding_verification_feedback_canary',
  ),
  _VerificationFeedbackScenario(
    name: 'nested package',
    sourcePath: 'packages/nested_app/lib/canary_value.dart',
    testPath: 'packages/nested_app/test/canary_value_test.dart',
    packageName: 'caverno_nested_verification_feedback_canary',
  ),
];

class _VerificationFeedbackScenario {
  const _VerificationFeedbackScenario({
    required this.name,
    required this.sourcePath,
    required this.testPath,
    required this.packageName,
  });

  final String name;
  final String sourcePath;
  final String testPath;
  final String packageName;

  String? get packageDirectory {
    final segments = sourcePath.split('/');
    final libIndex = segments.indexOf('lib');
    if (libIndex <= 0) {
      return null;
    }
    return segments.take(libIndex).join('/');
  }

  String get packageRelativeTestPath {
    final packageDir = packageDirectory;
    if (packageDir == null || packageDir.isEmpty) {
      return testPath;
    }
    return testPath.substring(packageDir.length + 1);
  }
}

void main() {
  final liveEnabled =
      Platform
          .environment['CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_CANARY'] ==
      '1';
  final runLabel = Platform
      .environment['CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_RUN_LABEL']
      ?.trim();
  final testNamePrefix = runLabel == null || runLabel.isEmpty
      ? ''
      : '[$runLabel] ';

  for (final scenario in _scenarios) {
    test(
      '${testNamePrefix}live LLM repairs ${scenario.name} Dart after test feedback',
      () async {
        final env = _VerificationFeedbackLiveEnv.fromEnvironment();
        final fixture = _VerificationFeedbackFixture.create(
          env.workspaceRoot,
          scenario,
        );
        final project = fixture.project;
        final dataSource = _VerificationFeedbackLiveDataSource(
          ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
          scenario,
        );
        final toolService = _VerificationFeedbackToolService(fixture.root);
        final container = _buildVerificationFeedbackContainer(
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

          final notifier = container.read(chatNotifierProvider.notifier);
          await notifier.sendMessage(
            'Run $_trigger. The first tool call is intentionally scripted to '
            'write a Dart implementation that fails ${scenario.testPath}. The '
            'next assistant completion is intentionally premature so the '
            'harness can inject dart_test_feedback. After that test feedback is '
            'available, repair ${scenario.sourcePath} so the test passes. Keep '
            'the function named canaryValue; only change the returned marker. '
            'Finish only after the final verification accepts the completion, '
            'and include $_marker in the final answer.',
            bypassPlanMode: true,
          );
          await _waitForChatIdle(container);

          final finalRun = await fixture.runTest();
          final finalSource = fixture.sourceFile.readAsStringSync();
          final finalContent = _lastAssistantContent(container);

          expect(
            dataSource.scriptedPreludeUsed,
            isTrue,
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
          expect(
            dataSource.scriptedCompletionUsed,
            isTrue,
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
          expect(
            dataSource.sawVerificationFeedback,
            isTrue,
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
          expect(
            toolService.successfulMutationCount,
            greaterThanOrEqualTo(2),
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
          expect(
            finalSource,
            contains(_marker),
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
          expect(
            finalSource,
            isNot(contains(_brokenMarker)),
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
          expect(
            finalRun.exitCode,
            0,
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
          expect(
            finalContent.toUpperCase(),
            contains(_marker),
            reason: _diagnostic(container, dataSource, toolService, fixture),
          );
        } finally {
          container.dispose();
          fixture.dispose();
        }
      },
      skip: liveEnabled
          ? false
          : 'Set CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}

ProviderContainer _buildVerificationFeedbackContainer({
  required _VerificationFeedbackLiveEnv env,
  required _VerificationFeedbackLiveDataSource dataSource,
  required _VerificationFeedbackToolService toolService,
  required CodingProject project,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _VerificationFeedbackSettingsNotifier(env),
      ),
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
  Duration timeout = const Duration(minutes: 8),
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
    'Timed out waiting for coding verification feedback live canary completion.\n'
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

String _diagnostic(
  ProviderContainer container,
  _VerificationFeedbackLiveDataSource? dataSource,
  _VerificationFeedbackToolService? toolService,
  _VerificationFeedbackFixture? fixture,
) {
  final chatState = container.read(chatNotifierProvider);
  final messages = chatState.messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n');
  return [
    'isLoading=${chatState.isLoading}',
    'error=${chatState.error}',
    'messages=${chatState.messages.length}',
    'scriptedPreludeUsed=${dataSource?.scriptedPreludeUsed}',
    'scriptedCompletionUsed=${dataSource?.scriptedCompletionUsed}',
    'sawVerificationFeedback=${dataSource?.sawVerificationFeedback}',
    'fixtureRoot=${fixture?.root.path ?? '(none)'}',
    'source=${fixture?.sourceDiagnostic() ?? '(missing)'}',
    'toolCalls=${toolService?.executedCalls.map((call) => call.toJson()).map(jsonEncode).join(' | ') ?? '(none)'}',
    'toolResultBatches=${dataSource?.toolResultBatches.map((batch) => batch.map((result) => result.name).toList()).map(jsonEncode).join(' | ') ?? '(none)'}',
    messages,
  ].join('\n');
}

class _VerificationFeedbackFixture {
  _VerificationFeedbackFixture({
    required this.root,
    required this.project,
    required this.deleteOnDispose,
    required this.scenario,
  });

  final Directory root;
  final CodingProject project;
  final bool deleteOnDispose;
  final _VerificationFeedbackScenario scenario;

  File get sourceFile => File('${root.path}/${scenario.sourcePath}');

  Directory get packageRoot {
    final packageDir = scenario.packageDirectory;
    if (packageDir == null || packageDir.isEmpty) {
      return root;
    }
    return Directory('${root.path}/$packageDir');
  }

  static _VerificationFeedbackFixture create(
    String? workspaceRoot,
    _VerificationFeedbackScenario scenario,
  ) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_verification_feedback_')
        : Directory(workspaceRoot);
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
    root.createSync(recursive: true);

    final packageDir = scenario.packageDirectory;
    final packageRoot =
        packageDir == null || packageDir.isEmpty
              ? root
              : Directory('${root.path}/$packageDir')
          ..createSync(recursive: true);

    _writePubspec(packageRoot, scenario.packageName);
    final sourceFile = File('${root.path}/${scenario.sourcePath}');
    sourceFile.parent.createSync(recursive: true);
    sourceFile.writeAsStringSync(_passingSource());

    final testFile = File('${root.path}/${scenario.testPath}');
    testFile.parent.createSync(recursive: true);
    testFile.writeAsStringSync(_testSource(scenario.packageName));

    final now = DateTime.now();
    return _VerificationFeedbackFixture(
      root: root,
      project: CodingProject(
        id: 'coding-verification-feedback-live-project',
        name: 'coding_verification_feedback_live_fixture',
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
      scenario: scenario,
    );
  }

  Future<ProcessResult> runTest() {
    return Process.run('flutter', [
      'test',
      scenario.packageRelativeTestPath,
    ], workingDirectory: packageRoot.path).timeout(const Duration(minutes: 2));
  }

  String sourceDiagnostic() {
    if (!sourceFile.existsSync()) {
      return '${scenario.sourcePath}=(missing)';
    }
    return '${scenario.sourcePath}=${sourceFile.readAsStringSync()}';
  }

  void dispose() {
    if (deleteOnDispose && root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }

  static void _writePubspec(Directory directory, String packageName) {
    File('${directory.path}/pubspec.yaml').writeAsStringSync('''
name: $packageName
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
''');
  }

  static String _passingSource() {
    return '''
String canaryValue() => '$_marker';
''';
  }

  static String _brokenSource() {
    return '''
String canaryValue() => '$_brokenMarker';
''';
  }

  static String _testSource(String packageName) {
    return '''
import 'package:flutter_test/flutter_test.dart';
import 'package:$packageName/canary_value.dart';

void main() {
  test('returns verification marker', () {
    expect(canaryValue(), '$_marker');
  });
}
''';
  }
}

class _VerificationFeedbackLiveEnv {
  const _VerificationFeedbackLiveEnv({
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

  static _VerificationFeedbackLiveEnv fromEnvironment() {
    return _VerificationFeedbackLiveEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_MAX_TOKENS'] ??
                '',
          ) ??
          4096,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_TEMPERATURE'] ??
                '',
          ) ??
          0.1,
      workspaceRoot: Platform
          .environment['CAVERNO_CODING_VERIFICATION_FEEDBACK_LIVE_WORK_ROOT'],
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError(
      '$name is required for coding verification feedback live validation.',
    );
  }
  return value;
}

class _VerificationFeedbackSettingsNotifier extends SettingsNotifier {
  _VerificationFeedbackSettingsNotifier(this.env);

  final _VerificationFeedbackLiveEnv env;

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
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      demoMode: false,
      codingVerificationTimeoutSeconds: 120,
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

class _VerificationToolCall {
  const _VerificationToolCall({
    required this.name,
    required this.arguments,
    required this.result,
    required this.success,
  });

  final String name;
  final Map<String, dynamic> arguments;
  final String result;
  final bool success;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'arguments': arguments,
      'success': success,
      'result': result,
    };
  }
}

class _VerificationFeedbackToolService extends McpToolService {
  _VerificationFeedbackToolService(this.root);

  final Directory root;
  final List<_VerificationToolCall> executedCalls = [];

  int get successfulMutationCount => executedCalls.where((call) {
    return (call.name == 'write_file' || call.name == 'edit_file') &&
        call.success;
  }).length;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'list_directory',
          'description':
              'List files in the isolated verification feedback canary fixture.',
          'parameters': const <String, dynamic>{
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
              'Read a UTF-8 text file from the isolated verification feedback canary fixture.',
          'parameters': const <String, dynamic>{
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
              'Replace exact text inside a fixture file. Use this to repair failing tests.',
          'parameters': const <String, dynamic>{
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
              'Write a full UTF-8 text file in the verification feedback canary fixture.',
          'parameters': const <String, dynamic>{
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
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final result = await _executeTool(name: name, arguments: arguments);
    executedCalls.add(
      _VerificationToolCall(
        name: name,
        arguments: Map<String, dynamic>.from(arguments),
        result: result.result,
        success: result.isSuccess,
      ),
    );
    return result;
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
      default:
        return _toolError(name, 'Unsupported canary tool: $name');
    }
  }

  _ResolvedPath _resolveInsideRoot(String? rawPath, {bool allowEmpty = false}) {
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
    final targetPath = File(resolved).absolute.path;
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

class _VerificationFeedbackLiveDataSource implements ChatDataSource {
  _VerificationFeedbackLiveDataSource(this.delegate, this.scenario);

  final ChatRemoteDataSource delegate;
  final _VerificationFeedbackScenario scenario;
  final List<List<Message>> streamRequests = [];
  final List<List<Message>> streamWithToolsRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<ChatCompletionResult> toolResultResponses = [];
  bool scriptedPreludeUsed = false;
  bool scriptedCompletionUsed = false;

  bool get sawVerificationFeedback {
    return toolResultBatches.any(
      (batch) => batch.any(
        (result) => result.name == CodingVerificationFeedbackService.toolName,
      ),
    );
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
    if (!scriptedPreludeUsed && _messagesContainTrigger(messages)) {
      scriptedPreludeUsed = true;
      return StreamWithToolsResult(
        stream: const Stream<String>.empty(),
        completion: Future<ChatCompletionResult>.value(
          ChatCompletionResult(
            content: 'Writing intentionally broken Dart for test feedback.',
            toolCalls: [
              ToolCallInfo(
                id: _scriptedWriteId,
                name: 'write_file',
                arguments: {
                  'path': scenario.sourcePath,
                  'content': _VerificationFeedbackFixture._brokenSource(),
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ),
      );
    }
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
  }) async {
    toolResultBatches.add(List<ToolResultInfo>.unmodifiable(toolResults));
    if (!scriptedCompletionUsed &&
        toolResults.any((result) => result.id == _scriptedWriteId)) {
      scriptedCompletionUsed = true;
      final result = ChatCompletionResult(
        content: 'Done.',
        finishReason: 'stop',
      );
      toolResultResponses.add(result);
      return result;
    }
    final result = await delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    toolResultResponses.add(result);
    return result;
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

  bool _messagesContainTrigger(List<Message> messages) {
    return messages.any(
      (message) =>
          message.role == MessageRole.user &&
          message.content.contains(_trigger),
    );
  }
}
