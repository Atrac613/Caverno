import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/browser_session_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _marker = 'BROWSER_SAVE_LIVE_OK';
const _expectedFilename = 'アジサイ_概要.md';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_BROWSER_SAVE_LIVE_CANARY'] == '1';

  test(
    'live LLM saves local browser fixture data to app storage by default',
    () async {
      final env = _BrowserSaveLiveEnv.fromEnvironment();
      final fixture = _BrowserSaveFixture(
        Directory('tool/fixtures/browser_save_live_canary'),
      );
      final saveDirectory = Directory.systemTemp.createTempSync(
        'browser_save_live_canary_',
      );
      final browserSessionService = BrowserSessionService(
        saveDirectoryOverride: saveDirectory,
      );
      final toolService = _LocalBrowserToolService(
        fixture: fixture,
        browserSessionService: browserSessionService,
      );
      final dataSource = _BrowserSaveLiveDataSource(
        ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
      );
      final container = _buildContainer(
        env,
        dataSource: dataSource,
        toolService: toolService,
        browserSessionService: browserSessionService,
      );

      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        final sendFuture = notifier.sendMessage(
          'Use the built-in browser tools against this local fixture URL: '
          '${fixture.searchUrl}. The page is already a deterministic search '
          'results page for アジサイ. Open it, inspect the page, click the '
          'Wikipedia result for アジサイ, get the page content, and save a '
          'Markdown summary as $_expectedFilename. The user did not ask for '
          'Downloads or Documents, so use the default app storage destination. '
          'After saving, answer with $_marker and the exact saved path from '
          'the browser_save_data result.',
        );

        await _approveBrowserActionsUntilComplete(
          container,
          sendFuture,
          expectedSaveDirectory: saveDirectory,
        );
        await _waitForChatIdle(container);

        final executedTools = toolService.executedToolNames;
        expect(executedTools, contains('browser_open'));
        expect(executedTools, contains('browser_snapshot'));
        expect(executedTools, contains('browser_click'));
        expect(executedTools, contains('browser_get_content'));
        expect(executedTools, contains('browser_save_data'));
        expect(
          toolService.unsafeSaveDestinationAttempts,
          isEmpty,
          reason: _diagnostic(container, toolService, dataSource),
        );

        final saveArguments = toolService.argumentsFor('browser_save_data');
        expect(saveArguments, isNotEmpty);
        final lastSaveArguments = saveArguments.last;
        expect(lastSaveArguments['filename'], _expectedFilename);
        expect(
          lastSaveArguments['destination'],
          anyOf(isNull, 'app'),
          reason: _diagnostic(container, toolService, dataSource),
        );

        final savedFile = toolService.savedFile;
        expect(
          savedFile,
          isNotNull,
          reason: _diagnostic(container, toolService, dataSource),
        );
        expect(savedFile!.path, startsWith(saveDirectory.path));
        expect(savedFile.path, endsWith(_expectedFilename));
        final savedContent = savedFile.readAsStringSync();
        expect(savedContent, contains('アジサイ'));
        expect(savedContent, contains('Hydrangea macrophylla'));

        final finalContent = _lastAssistantContent(container);
        expect(finalContent.toUpperCase(), contains(_marker));
        expect(finalContent, contains(savedFile.path));
        expect(finalContent.toLowerCase(), isNot(contains('downloads')));
      } finally {
        container.dispose();
        if (saveDirectory.existsSync()) {
          saveDirectory.deleteSync(recursive: true);
        }
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_BROWSER_SAVE_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

ProviderContainer _buildContainer(
  _BrowserSaveLiveEnv env, {
  required _BrowserSaveLiveDataSource dataSource,
  required _LocalBrowserToolService toolService,
  required BrowserSessionService browserSessionService,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(() => _LiveSettingsNotifier(env)),
      conversationsNotifierProvider.overrideWith(
        _LiveConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(
        _LiveCodingProjectsNotifier.new,
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      browserSessionServiceProvider.overrideWithValue(browserSessionService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

Future<void> _approveBrowserActionsUntilComplete(
  ProviderContainer container,
  Future<void> sendFuture, {
  required Directory expectedSaveDirectory,
}) async {
  final notifier = container.read(chatNotifierProvider.notifier);
  final approvedActionIds = <String>{};
  Object? failure;
  StackTrace? failureStackTrace;
  var completed = false;
  unawaited(
    sendFuture.then(
      (_) {
        completed = true;
      },
      onError: (Object error, StackTrace stackTrace) {
        failure = error;
        failureStackTrace = stackTrace;
        completed = true;
      },
    ),
  );

  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (!completed && DateTime.now().isBefore(deadline)) {
    final pending = container.read(chatNotifierProvider).pendingBrowserAction;
    if (pending != null && approvedActionIds.add(pending.id)) {
      final details = pending.details.join('\n');
      if (pending.toolName == 'browser_save_data') {
        expect(details, contains('Destination: Caverno application storage'));
        expect(details, contains('Final file: $_expectedFilename'));
        expect(
          details,
          contains('Save location: ${expectedSaveDirectory.path}'),
        );
        expect(details.toLowerCase(), isNot(contains('downloads folder')));
      }
      notifier.resolveBrowserAction(id: pending.id, approved: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  if (!completed) {
    throw TimeoutException(
      'Timed out waiting for browser save live canary completion.\n'
      '${_chatDiagnostic(container)}',
    );
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStackTrace!);
  }
}

Future<void> _waitForChatIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 1),
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
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    'Timed out waiting for chat idle.\n${_chatDiagnostic(container)}',
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

String _chatDiagnostic(ProviderContainer container) {
  final state = container.read(chatNotifierProvider);
  return [
    'isLoading=${state.isLoading}',
    'error=${state.error}',
    'pendingBrowserAction=${state.pendingBrowserAction?.toolName}',
    ...state.messages.map(
      (message) => '${message.role.name}: ${message.content}',
    ),
  ].join('\n');
}

String _diagnostic(
  ProviderContainer container,
  _LocalBrowserToolService toolService,
  _BrowserSaveLiveDataSource dataSource,
) {
  return [
    _chatDiagnostic(container),
    'executedTools=${toolService.executedToolNames.join(',')}',
    'executedArguments=${toolService.executedArguments.map(jsonEncode).join(' | ')}',
    'toolResultBatches=${dataSource.toolResultBatches.length}',
    'savedFile=${toolService.savedFile?.path}',
    'unsafeDestinations=${toolService.unsafeSaveDestinationAttempts.map(jsonEncode).join(' | ')}',
  ].join('\n');
}

class _BrowserSaveLiveEnv {
  const _BrowserSaveLiveEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;

  factory _BrowserSaveLiveEnv.fromEnvironment() {
    String requiredEnv(String name) {
      final value = Platform.environment[name]?.trim();
      if (value == null || value.isEmpty) {
        throw StateError('$name is required for live LLM validation.');
      }
      return value;
    }

    return _BrowserSaveLiveEnv(
      baseUrl: requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: requiredEnv('CAVERNO_LLM_API_KEY'),
      model: requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_BROWSER_SAVE_LIVE_MAX_TOKENS'] ?? '',
          ) ??
          2048,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_BROWSER_SAVE_LIVE_TEMPERATURE'] ?? '',
          ) ??
          0.1,
    );
  }
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier(this.env);

  final _BrowserSaveLiveEnv env;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: true,
      demoMode: false,
    );
  }
}

class _LiveConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Conversation? ensureCurrentConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    final resolvedWorkspaceMode = workspaceMode ?? state.activeWorkspaceMode;
    if (!resolvedWorkspaceMode.usesConversations) {
      return null;
    }
    final resolvedProjectId = resolvedWorkspaceMode.usesProjects
        ? (projectId ?? state.activeProjectId)
        : null;
    if (resolvedWorkspaceMode.usesProjects &&
        (resolvedProjectId == null || resolvedProjectId.trim().isEmpty)) {
      return null;
    }

    final currentConversation = state.currentConversation;
    if (currentConversation != null &&
        currentConversation.workspaceMode == resolvedWorkspaceMode &&
        (!resolvedWorkspaceMode.usesProjects ||
            currentConversation.normalizedProjectId == resolvedProjectId)) {
      return currentConversation;
    }

    final now = DateTime.now();
    final conversation = Conversation(
      id: 'browser-save-live-${now.microsecondsSinceEpoch}',
      title: defaultConversationTitle,
      messages: const <Message>[],
      createdAt: now,
      updatedAt: now,
      workspaceMode: resolvedWorkspaceMode,
      projectId: resolvedProjectId ?? '',
    );
    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspaceMode,
      activeProjectId: resolvedProjectId,
      clearActiveProject:
          !resolvedWorkspaceMode.usesProjects || resolvedProjectId == null,
    );
    return conversation;
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final currentConversationId = state.currentConversationId;
    if (currentConversationId == null) {
      return;
    }
    await updateConversationMessages(currentConversationId, messages);
  }

  @override
  Future<void> updateConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    final conversation = state.conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      return;
    }
    final updated = conversation.copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(
      conversations: state.conversations
          .map((item) => item.id == conversationId ? updated : item)
          .toList(growable: false),
    );
  }
}

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
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

class _BrowserSaveLiveDataSource implements ChatDataSource {
  _BrowserSaveLiveDataSource(this.delegate);

  final ChatRemoteDataSource delegate;
  final List<List<ToolResultInfo>> toolResultBatches = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.streamChatCompletion(
      messages: messages,
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
    return delegate.streamChatCompletionWithTools(
      messages: messages,
      tools: tools,
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
    return delegate.createChatCompletion(
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
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
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
}

class _BrowserSaveFixture {
  _BrowserSaveFixture(this.directory);

  final Directory directory;

  File get searchFile =>
      File('${directory.path}${Platform.pathSeparator}search.html');
  File get wikipediaFile =>
      File('${directory.path}${Platform.pathSeparator}wikipedia.html');

  String get searchUrl => searchFile.absolute.uri.toString();
  String get wikipediaUrl => wikipediaFile.absolute.uri.toString();

  String get wikipediaMarkdown => '''
# アジサイ

アジサイはアジサイ科アジサイ属の落葉低木で、学名は Hydrangea macrophylla です。

## 概要

- 分類: アジサイ科アジサイ属
- 学名: Hydrangea macrophylla
- 特徴: 梅雨期に装飾花がまとまって咲く
''';
}

enum _FixturePage { search, wikipedia }

class _LocalBrowserToolService extends McpToolService {
  _LocalBrowserToolService({
    required this.fixture,
    required this.browserSessionService,
  });

  final _BrowserSaveFixture fixture;
  final BrowserSessionService browserSessionService;
  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedArguments = [];
  final List<Map<String, dynamic>> unsafeSaveDestinationAttempts = [];
  _FixturePage? _currentPage;
  File? savedFile;

  List<Map<String, dynamic>> argumentsFor(String toolName) {
    return [
      for (var index = 0; index < executedToolNames.length; index += 1)
        if (executedToolNames[index] == toolName) executedArguments[index],
    ];
  }

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
          'name': 'browser_open',
          'description':
              'Open a URL in the built-in browser pane. Use this first, then browser_snapshot to inspect the page.',
          'parameters': {
            'type': 'object',
            'properties': {
              'url': {'type': 'string'},
            },
            'required': ['url'],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_snapshot',
          'description':
              'List visible interactive elements in the current browser page, each with a stable ref index. Use only refs from the latest snapshot.',
          'parameters': {
            'type': 'object',
            'properties': {
              'max_elements': {'type': 'integer'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_click',
          'description':
              'Click an element identified by ref from browser_snapshot. Requires user approval.',
          'parameters': {
            'type': 'object',
            'properties': {
              'ref': {'type': 'integer'},
              'selector': {'type': 'string'},
              'reason': {'type': 'string'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_get_content',
          'description':
              'Extract the current page content as text or Markdown after navigation.',
          'parameters': {
            'type': 'object',
            'properties': {
              'format': {
                'type': 'string',
                'enum': ['text', 'markdown', 'md'],
              },
              'max_chars': {'type': 'integer'},
            },
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'browser_save_data',
          'description':
              'Save extracted data to a file. Defaults to Caverno application storage; set destination to downloads or documents only when the user explicitly requested that location. Requires user approval.',
          'parameters': {
            'type': 'object',
            'properties': {
              'filename': {'type': 'string'},
              'data': {'type': 'string'},
              'format': {'type': 'string'},
              'destination': {
                'type': 'string',
                'enum': ['app', 'downloads', 'documents'],
                'description':
                    'Optional save location. Use app by default. Use downloads or documents only when the user explicitly asks for that folder.',
              },
              'reason': {'type': 'string'},
            },
            'required': ['filename', 'data'],
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
    executedToolNames.add(name);
    executedArguments.add(Map<String, dynamic>.from(arguments));
    return switch (name) {
      'browser_open' => _open(arguments),
      'browser_snapshot' => _snapshot(),
      'browser_click' => _click(arguments),
      'browser_get_content' => _getContent(arguments),
      'browser_save_data' => _saveData(arguments),
      _ => _error(name, 'unsupported_tool', 'Unsupported browser tool: $name'),
    };
  }

  McpToolResult _ok(String toolName, Map<String, dynamic> payload) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({'ok': true, ...payload}),
      isSuccess: true,
    );
  }

  McpToolResult _error(String toolName, String code, String message) {
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({'ok': false, 'code': code, 'error': message}),
      isSuccess: false,
      errorMessage: message,
    );
  }

  McpToolResult _open(Map<String, dynamic> arguments) {
    final url = arguments['url']?.toString() ?? '';
    if (url != fixture.searchUrl && !url.endsWith('/search.html')) {
      return _error(
        'browser_open',
        'unexpected_url',
        'Open the local search fixture URL: ${fixture.searchUrl}',
      );
    }
    _currentPage = _FixturePage.search;
    return _ok('browser_open', {
      'url': fixture.searchUrl,
      'title': 'Local Search Fixture',
      'loaded': true,
      'nextAction': 'Call browser_snapshot to inspect the local results.',
    });
  }

  McpToolResult _snapshot() {
    if (_currentPage == _FixturePage.wikipedia) {
      return _ok('browser_snapshot', {
        'url': fixture.wikipediaUrl,
        'title': 'アジサイ - Local Wikipedia Fixture',
        'count': 0,
        'elements': const <Map<String, dynamic>>[],
      });
    }
    if (_currentPage != _FixturePage.search) {
      return _error(
        'browser_snapshot',
        'no_page_open',
        'Open the local search fixture before taking a snapshot.',
      );
    }
    return _ok('browser_snapshot', {
      'url': fixture.searchUrl,
      'title': 'Local Search Fixture',
      'count': 2,
      'elements': [
        {
          'ref': 1,
          'tag': 'a',
          'role': 'link',
          'label': 'アジサイ - Wikipedia',
          'href': fixture.wikipediaUrl,
        },
        {
          'ref': 2,
          'tag': 'a',
          'role': 'link',
          'label': 'Garden Notes: Hydrangea Care',
          'href': 'gardening.html',
        },
      ],
      'instruction':
          'Click ref 1 to open the local Wikipedia fixture for アジサイ.',
    });
  }

  McpToolResult _click(Map<String, dynamic> arguments) {
    if (_currentPage != _FixturePage.search) {
      return _error(
        'browser_click',
        'wrong_page',
        'The Wikipedia result can only be clicked from the search fixture.',
      );
    }
    final ref = arguments['ref'];
    final selector = arguments['selector']?.toString().toLowerCase() ?? '';
    final clickedWikipedia =
        ref == 1 ||
        ref == '1' ||
        selector.contains('wikipedia') ||
        selector.contains('wikipedia-result');
    if (!clickedWikipedia) {
      return _error(
        'browser_click',
        'wrong_target',
        'Click the アジサイ - Wikipedia result from the latest snapshot.',
      );
    }
    _currentPage = _FixturePage.wikipedia;
    return _ok('browser_click', {
      'url': fixture.wikipediaUrl,
      'title': 'アジサイ - Local Wikipedia Fixture',
      'navigated': true,
      'instruction':
          'Call browser_get_content with Markdown format before saving.',
    });
  }

  McpToolResult _getContent(Map<String, dynamic> arguments) {
    if (_currentPage != _FixturePage.wikipedia) {
      return _error(
        'browser_get_content',
        'wrong_page',
        'Open the local Wikipedia fixture before extracting content.',
      );
    }
    final maxChars = (arguments['max_chars'] as num?)?.toInt();
    final content = maxChars == null
        ? fixture.wikipediaMarkdown
        : fixture.wikipediaMarkdown.substring(
            0,
            maxChars.clamp(0, fixture.wikipediaMarkdown.length),
          );
    return _ok('browser_get_content', {
      'url': fixture.wikipediaUrl,
      'title': 'アジサイ - Local Wikipedia Fixture',
      'format': arguments['format'] ?? 'markdown',
      'content': content,
      'instruction':
          'Save this Markdown with browser_save_data as $_expectedFilename. Use destination app or omit destination.',
    });
  }

  Future<McpToolResult> _saveData(Map<String, dynamic> arguments) async {
    final destination = arguments['destination']?.toString().trim();
    if (destination == 'downloads' || destination == 'documents') {
      unsafeSaveDestinationAttempts.add(Map<String, dynamic>.from(arguments));
      return _error(
        'browser_save_data',
        'unsafe_destination',
        'The user did not ask for Downloads or Documents. Use app storage.',
      );
    }
    final filename = arguments['filename']?.toString() ?? '';
    final format = arguments['format']?.toString() ?? 'md';
    final data = arguments['data']?.toString() ?? '';
    final target = await browserSessionService.resolveSaveTarget(
      filename: filename,
      format: format,
      destination: destination,
    );
    await target.directory.create(recursive: true);
    final file = File(target.path);
    await file.writeAsString(data);
    savedFile = file;
    return _ok('browser_save_data', {
      'path': file.absolute.path,
      'directory': target.directory.path,
      'destination': target.destination.toolValue,
      'requestedDestination': target.requestedDestination,
      'destinationChanged': target.destinationChanged,
      'filename': target.filename,
      'requestedFilename': target.requestedFilename,
      'filenameChanged': target.filenameChanged,
      'bytes': utf8.encode(data).length,
      'format': target.format,
      'instruction':
          'Final answer must include $_marker and the exact path ${file.absolute.path}.',
    });
  }
}
