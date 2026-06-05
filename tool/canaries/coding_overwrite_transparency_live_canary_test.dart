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
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _fileName = 'tokyo_weather_2026-06-02.md';
const _marker = 'OVERWRITE_TRANSPARENCY_LIVE_OK';

void main() {
  final liveEnabled =
      Platform
          .environment['CAVERNO_CODING_OVERWRITE_TRANSPARENCY_LIVE_CANARY'] ==
      '1';
  final runLabel = Platform
      .environment['CAVERNO_CODING_OVERWRITE_TRANSPARENCY_LIVE_RUN_LABEL']
      ?.trim();
  final testNamePrefix = runLabel == null || runLabel.isEmpty
      ? ''
      : '[$runLabel] ';

  test(
    '${testNamePrefix}live LLM reports write_file existing-file updates',
    () async {
      final env = _OverwriteTransparencyLiveEnv.fromEnvironment();
      final fixture = _OverwriteTransparencyFixture.create(env.workspaceRoot);
      final dataSource = ChatRemoteDataSource(
        baseUrl: env.baseUrl,
        apiKey: env.apiKey,
      );
      final toolService = _OverwriteTransparencyToolService(fixture.root);
      final container = _buildOverwriteTransparencyContainer(
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
          'Update the existing file $_fileName with a concise Markdown Tokyo '
          'weather report for 2026-06-02. Use this weather data: sunny '
          'intervals, high 25 C, low 18 C, northeast wind 12 km/h. Use '
          'write_file exactly once for $_fileName; the file already exists in '
          'the fixture. Include $_marker in the file content. You may read the '
          'file first if needed. In your final answer, include $_marker, name '
          '$_fileName, and state whether write_file created a new file or '
          'updated/overwrote an existing file based only on the tool result.',
          bypassPlanMode: true,
        );
        await _waitForChatIdle(container);

        final finalReport = fixture.reportFile.existsSync()
            ? fixture.reportFile.readAsStringSync()
            : '';
        final finalContent = _lastAssistantContent(container);
        final writeResults = _decodedResultsFor(
          toolService,
          'write_file',
        ).toList(growable: false);
        final normalizedFinalContent = finalContent.toLowerCase();

        expect(
          writeResults,
          isNotEmpty,
          reason: _diagnostic(container, toolService, fixture),
        );
        expect(
          writeResults.any((result) => result['created'] == false),
          isTrue,
          reason: _diagnostic(container, toolService, fixture),
        );
        expect(
          writeResults.any((result) => result['created'] == true),
          isFalse,
          reason: _diagnostic(container, toolService, fixture),
        );
        expect(
          finalReport,
          contains(_marker),
          reason: _diagnostic(container, toolService, fixture),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_marker),
          reason: _diagnostic(container, toolService, fixture),
        );
        expect(
          normalizedFinalContent,
          contains(_fileName),
          reason: _diagnostic(container, toolService, fixture),
        );
        expect(
          normalizedFinalContent,
          anyOf(
            contains('existing'),
            contains('updated'),
            contains('overwrote'),
            contains('overwrite'),
            contains('overwritten'),
          ),
          reason: _diagnostic(container, toolService, fixture),
        );
        expect(
          _containsOptionalFollowUpOffer(finalContent),
          isFalse,
          reason: _diagnostic(container, toolService, fixture),
        );
      } finally {
        container.dispose();
        fixture.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CODING_OVERWRITE_TRANSPARENCY_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

ProviderContainer _buildOverwriteTransparencyContainer({
  required _OverwriteTransparencyLiveEnv env,
  required ChatRemoteDataSource dataSource,
  required _OverwriteTransparencyToolService toolService,
  required CodingProject project,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _OverwriteTransparencySettingsNotifier(env),
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
    'Timed out waiting for coding overwrite transparency live canary completion.\n'
    '${_diagnostic(container, null, null)}',
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

bool _containsOptionalFollowUpOffer(String content) {
  final normalized = content.toLowerCase();
  return RegExp(
    r'\b(other|another|different)\s+(city|date|day|format|output)\b|'
    r'\b(would you like|do you want|want me|let me know|anything else)\b|'
    '別の|他の|調べますか|必要な場合|お知らせください',
  ).hasMatch(normalized);
}

String _diagnostic(
  ProviderContainer container,
  _OverwriteTransparencyToolService? toolService,
  _OverwriteTransparencyFixture? fixture,
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
    'toolCalls=${toolService?.executedCalls.map((call) => call.toJson()).map(jsonEncode).join(' | ') ?? '(none)'}',
    messages,
  ].join('\n');
}

Iterable<Map<String, dynamic>> _decodedResultsFor(
  _OverwriteTransparencyToolService toolService,
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

class _OverwriteTransparencyFixture {
  _OverwriteTransparencyFixture({
    required this.root,
    required this.project,
    required this.deleteOnDispose,
  });

  final Directory root;
  final CodingProject project;
  final bool deleteOnDispose;

  File get reportFile => File('${root.path}/$_fileName');

  static _OverwriteTransparencyFixture create(String? workspaceRoot) {
    final deleteOnDispose = workspaceRoot == null || workspaceRoot.isEmpty;
    final root = deleteOnDispose
        ? Directory.systemTemp.createTempSync('coding_overwrite_transparency_')
        : Directory(workspaceRoot);
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
    root.createSync(recursive: true);

    File('${root.path}/$_fileName').writeAsStringSync('''
# Previous Tokyo Weather Report

This stale report should be overwritten.
''');
    final now = DateTime.now();
    return _OverwriteTransparencyFixture(
      root: root,
      project: CodingProject(
        id: 'coding-overwrite-transparency-live-project',
        name: 'coding_overwrite_transparency_live_fixture',
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

class _OverwriteTransparencyLiveEnv {
  const _OverwriteTransparencyLiveEnv({
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

  static _OverwriteTransparencyLiveEnv fromEnvironment() {
    return _OverwriteTransparencyLiveEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CODING_OVERWRITE_TRANSPARENCY_LIVE_MAX_TOKENS'] ??
                '',
          ) ??
          4096,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CODING_OVERWRITE_TRANSPARENCY_LIVE_TEMPERATURE'] ??
                '',
          ) ??
          0.1,
      workspaceRoot: Platform
          .environment['CAVERNO_CODING_OVERWRITE_TRANSPARENCY_LIVE_WORK_ROOT'],
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError(
      '$name is required for coding overwrite transparency live validation.',
    );
  }
  return value;
}

class _OverwriteTransparencySettingsNotifier extends SettingsNotifier {
  _OverwriteTransparencySettingsNotifier(this.env);

  final _OverwriteTransparencyLiveEnv env;

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

class _OverwriteToolCall {
  const _OverwriteToolCall({
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

class _OverwriteTransparencyToolService extends McpToolService {
  _OverwriteTransparencyToolService(this.root);

  final Directory root;
  final List<_OverwriteToolCall> executedCalls = [];

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
              'List files in the isolated overwrite transparency canary fixture.',
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
              'Read a UTF-8 text file from the isolated overwrite transparency canary fixture.',
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
          'name': 'write_file',
          'description':
              'Write a full UTF-8 text file in the overwrite transparency canary fixture.',
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
      _OverwriteToolCall(
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
    if (!allowEmpty && (trimmed == null || trimmed.isEmpty)) {
      return const _ResolvedPath(error: 'path is required');
    }
    final effectivePath = trimmed == null || trimmed.isEmpty ? '.' : trimmed;
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
