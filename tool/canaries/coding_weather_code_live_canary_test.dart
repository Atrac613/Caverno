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
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _fileName = 'tokyo_weather_2026-06-03.md';
const _marker = 'WEATHER_CODE_LIVE_OK';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_CODING_WEATHER_CODE_LIVE_CANARY'] == '1';
  final runLabel = Platform
      .environment['CAVERNO_CODING_WEATHER_CODE_LIVE_RUN_LABEL']
      ?.trim();
  final testNamePrefix = runLabel == null || runLabel.isEmpty
      ? ''
      : '[$runLabel] ';

  test(
    '${testNamePrefix}live LLM preserves Open-Meteo WMO weather code labels',
    () async {
      final env = _WeatherCodeLiveEnv.fromEnvironment();
      final fixture = _WeatherCodeFixture.create(env.workspaceRoot);
      final dataSource = ChatRemoteDataSource(
        baseUrl: env.baseUrl,
        apiKey: env.apiKey,
      );
      final toolService = _WeatherCodeToolService(fixture.root);
      final container = _buildWeatherCodeContainer(
        env: env,
        dataSource: dataSource,
        toolService: toolService,
        project: fixture.project,
      );

      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: fixture.project.id,
        );

        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Use http_get to retrieve the Tokyo Open-Meteo forecast for '
          '2026-06-03, then save a concise English Markdown report to '
          '$_fileName with write_file. Use the WMO weather label from the '
          'tool-result interpretation note instead of guessing from the '
          'numeric code. Include $_marker in the saved report and final '
          'answer.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        final finalReport = fixture.reportFile.existsSync()
            ? fixture.reportFile.readAsStringSync()
            : '';
        final finalContent = _lastAssistantContent(container);
        final reportText = finalReport.toLowerCase();
        final finalText = finalContent.toLowerCase();
        final decodedWriteResults = _decodedResultsFor(
          toolService,
          'write_file',
        ).toList(growable: false);

        expect(
          toolService.executedCalls.any((call) => call.name == 'http_get'),
          isTrue,
          reason: _diagnostic(container, toolService, fixture, null),
        );
        expect(
          decodedWriteResults,
          isNotEmpty,
          reason: _diagnostic(container, toolService, fixture, null),
        );
        expect(
          finalReport,
          contains(_marker),
          reason: _diagnostic(container, toolService, fixture, null),
        );
        expect(
          reportText,
          contains('rain'),
          reason: _diagnostic(container, toolService, fixture, null),
        );
        expect(
          reportText,
          isNot(contains('drizzle')),
          reason: _diagnostic(container, toolService, fixture, null),
        );
        expect(
          finalContent,
          contains(_marker),
          reason: _diagnostic(container, toolService, fixture, null),
        );
        expect(
          finalText,
          contains('rain'),
          reason: _diagnostic(container, toolService, fixture, null),
        );
        expect(
          finalText,
          isNot(contains('drizzle')),
          reason: _diagnostic(container, toolService, fixture, null),
        );

        final memoryProbe = await _extractMemoryDraft(
          dataSource: dataSource,
          env: env,
          container: container,
          toolService: toolService,
        );
        final memoryDraft = memoryProbe.draft;
        final memoryText = memoryProbe.combinedText.toLowerCase();
        expect(
          memoryDraft,
          isNotNull,
          reason: _diagnostic(container, toolService, fixture, memoryDraft),
        );
        expect(
          memoryText,
          contains('rain'),
          reason: _diagnostic(container, toolService, fixture, memoryDraft),
        );
        expect(
          memoryText,
          isNot(contains('drizzle')),
          reason: _diagnostic(container, toolService, fixture, memoryDraft),
        );
        expect(
          memoryText,
          isNot(contains(_marker.toLowerCase())),
          reason: _diagnostic(container, toolService, fixture, memoryDraft),
        );
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_WEATHER_CODE_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

ProviderContainer _buildWeatherCodeContainer({
  required _WeatherCodeLiveEnv env,
  required ChatRemoteDataSource dataSource,
  required _WeatherCodeToolService toolService,
  required CodingProject project,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(() => _WeatherCodeSettings(env)),
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
    'Timed out waiting for coding weather code live canary completion.\n'
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

Future<_MemoryExtractionProbe> _extractMemoryDraft({
  required ChatRemoteDataSource dataSource,
  required _WeatherCodeLiveEnv env,
  required ProviderContainer container,
  required _WeatherCodeToolService toolService,
}) async {
  final now = DateTime(2026, 6, 2, 9, 30);
  final messages = container.read(chatNotifierProvider).messages;
  final input = MemoryExtractionDraftService.buildInput(
    messages,
    UserMemoryProfile.empty(),
    toolResults: toolService.toToolResults(),
  );
  final result = await dataSource.createChatCompletion(
    messages: [
      Message(
        id: 'memory-system',
        content: MemoryExtractionDraftService.systemPrompt,
        role: MessageRole.system,
        timestamp: now,
      ),
      Message(
        id: 'memory-user',
        content: input,
        role: MessageRole.user,
        timestamp: now,
      ),
    ],
    model: env.model,
    temperature: 0.1,
    maxTokens: env.memoryMaxTokens,
  );
  return _MemoryExtractionProbe(
    rawContent: result.content,
    draft: MemoryExtractionDraftService.parseDraft(result.content),
  );
}

class _MemoryExtractionProbe {
  const _MemoryExtractionProbe({required this.rawContent, required this.draft});

  final String rawContent;
  final MemoryExtractionDraft? draft;

  String get combinedText => '$rawContent\n${_memoryDraftText(draft)}';
}

String _memoryDraftText(MemoryExtractionDraft? draft) {
  if (draft == null) {
    return '';
  }
  return [
    draft.summary,
    ...draft.openLoops,
    ...draft.persona,
    ...draft.preferences,
    ...draft.doNot,
    ...draft.entries.map((entry) => entry.text),
  ].join('\n');
}

String _diagnostic(
  ProviderContainer container,
  _WeatherCodeToolService? toolService,
  _WeatherCodeFixture? fixture,
  MemoryExtractionDraft? memoryDraft,
) {
  final chatState = container.read(chatNotifierProvider);
  final messages = chatState.messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n');
  return [
    'isLoading=${chatState.isLoading}',
    'error=${chatState.error}',
    'messages=${chatState.messages.length}',
    'fixtureRoot=${fixture?.root.path ?? '(none)'}',
    'report=${fixture?.reportDiagnostic() ?? '(missing)'}',
    'memoryDraft=${_memoryDraftText(memoryDraft)}',
    'toolCalls=${toolService?.executedCalls.map((call) => call.toJson()).map(jsonEncode).join(' | ') ?? '(none)'}',
    messages,
  ].join('\n');
}

Iterable<Map<String, dynamic>> _decodedResultsFor(
  _WeatherCodeToolService toolService,
  String name,
) sync* {
  for (final call in toolService.executedCalls.where(
    (call) => call.name == name,
  )) {
    try {
      final decoded = jsonDecode(call.result);
      if (decoded is Map<String, dynamic>) {
        yield decoded;
      } else if (decoded is Map) {
        yield Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      continue;
    }
  }
}

class _WeatherCodeFixture {
  _WeatherCodeFixture({
    required this.root,
    required this.project,
    required this.deleteOnDispose,
  });

  final Directory root;
  final CodingProject project;
  final bool deleteOnDispose;

  File get reportFile => File('${root.path}/$_fileName');

  static _WeatherCodeFixture create(String? workspaceRoot) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_weather_code_')
        : Directory(workspaceRoot);
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
    root.createSync(recursive: true);

    final now = DateTime.now();
    return _WeatherCodeFixture(
      root: root,
      project: CodingProject(
        id: 'coding-weather-code-live-project',
        name: 'coding_weather_code_live_fixture',
        rootPath: root.absolute.path,
        createdAt: now,
        updatedAt: now,
      ),
      deleteOnDispose: deleteOnDispose,
    );
  }

  String reportDiagnostic() {
    if (!reportFile.existsSync()) {
      return '$_fileName=(missing)';
    }
    return '$_fileName=${reportFile.readAsStringSync()}';
  }

  void dispose() {
    if (deleteOnDispose && root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

class _WeatherCodeLiveEnv {
  const _WeatherCodeLiveEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.memoryMaxTokens,
    required this.temperature,
    required this.workspaceRoot,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final int memoryMaxTokens;
  final double temperature;
  final String? workspaceRoot;

  static _WeatherCodeLiveEnv fromEnvironment() {
    return _WeatherCodeLiveEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_WEATHER_CODE_LIVE_MAX_TOKENS'] ??
                '',
          ) ??
          4096,
      memoryMaxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_WEATHER_CODE_LIVE_MEMORY_MAX_TOKENS'] ??
                '',
          ) ??
          1200,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_WEATHER_CODE_LIVE_TEMPERATURE'] ??
                '',
          ) ??
          0.1,
      workspaceRoot:
          Platform.environment['CAVERNO_CODING_WEATHER_CODE_LIVE_WORK_ROOT'],
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for coding weather code live canary.');
  }
  return value;
}

class _WeatherCodeSettings extends SettingsNotifier {
  _WeatherCodeSettings(this.env);

  final _WeatherCodeLiveEnv env;

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
      codingApprovalMode: CodingApprovalMode.fullAccess,
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

class _WeatherToolCall {
  const _WeatherToolCall({
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

class _WeatherCodeToolService extends McpToolService {
  _WeatherCodeToolService(this.root);

  final Directory root;
  final List<_WeatherToolCall> executedCalls = [];

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
          'name': 'http_get',
          'description':
              'Return a fixed Open-Meteo forecast payload for the weather-code canary.',
          'parameters': const <String, dynamic>{
            'type': 'object',
            'properties': {
              'url': {'type': 'string'},
              'timeout': {'type': 'integer'},
            },
            'required': ['url'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'write_file',
          'description':
              'Write a full UTF-8 text file in the weather-code canary fixture.',
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
      _WeatherToolCall(
        name: name,
        arguments: Map<String, dynamic>.from(arguments),
        result: result.result,
        success: result.isSuccess,
      ),
    );
    return result;
  }

  List<ToolResultInfo> toToolResults() {
    return [
      for (var index = 0; index < executedCalls.length; index += 1)
        ToolResultInfo(
          id: 'weather-code-tool-$index',
          name: executedCalls[index].name,
          arguments: executedCalls[index].arguments,
          result: executedCalls[index].result,
        ),
    ];
  }

  Future<McpToolResult> _executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    switch (name) {
      case 'http_get':
        return _toolResult(name, _openMeteoResult(arguments));
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

  String _openMeteoResult(Map<String, dynamic> arguments) {
    final url = (arguments['url'] as String?)?.trim();
    final body = jsonEncode({
      'latitude': 35.7,
      'longitude': 139.6875,
      'timezone': 'Asia/Tokyo',
      'daily_units': {
        'time': 'iso8601',
        'temperature_2m_max': 'C',
        'temperature_2m_min': 'C',
        'precipitation_probability_mean': '%',
        'weathercode': 'wmo code',
        'windspeed_10m_max': 'km/h',
      },
      'daily': {
        'time': ['2026-06-03'],
        'temperature_2m_max': [18.9],
        'temperature_2m_min': [16.7],
        'precipitation_probability_mean': [90],
        'weathercode': [65],
        'windspeed_10m_max': [20.3],
      },
    });
    return jsonEncode({
      'url': url == null || url.isEmpty
          ? 'https://api.open-meteo.com/v1/forecast'
          : url,
      'method': 'GET',
      'status_code': 200,
      'reason_phrase': 'OK',
      'response_time_ms': 12,
      'headers': {'content-type': 'application/json; charset=utf-8'},
      'redirects': const [],
      'content_type': 'application/json; charset=utf-8',
      'body_bytes': body.length,
      'body': body,
      'body_truncated': false,
      'body_encoding': 'utf-8',
    });
  }

  _ResolvedPath _resolveInsideRoot(String? rawPath) {
    final trimmed = rawPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return const _ResolvedPath(error: 'path is required');
    }
    final resolved = FilesystemTools.resolvePath(
      trimmed,
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
