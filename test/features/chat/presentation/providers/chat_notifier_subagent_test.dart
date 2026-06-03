import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/subagent_task_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

// ---------------------------------------------------------------------------
// Test doubles (mirrors of the helpers in chat_notifier_test.dart, trimmed to
// what the subagent scenarios need).
// ---------------------------------------------------------------------------

class _ToolEnabledSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: CodingApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      enableCodingVerificationFeedback: false,
    );
  }
}

class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();
}

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _TestSessionMemoryService extends SessionMemoryService {
  _TestSessionMemoryService() : super(ChatMemoryRepository(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) => null;

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async => const MemoryUpdateResult.none();

  @override
  UserMemoryProfile loadProfile() => UserMemoryProfile.empty();
}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _MockNotificationService extends Mock implements NotificationService {}

class _TestBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Scripted data source: routes parent vs child requests.
//
//  - parent first request   -> streamChatCompletionWithTools  (spawn_subagent)
//  - parent final answer    -> streamChatCompletion           (final text)
//  - child requests         -> createChatCompletion           (queued)
//  - tool-result follow-ups -> createChatCompletionWithToolResults
//
// The child's system prompt contains "focused subagent" (see
// SubagentExecutionService._buildSystemPrompt), which disambiguates the
// shared createChatCompletionWithToolResults path.
// ---------------------------------------------------------------------------

class _SubagentScriptedDataSource implements ChatDataSource {
  _SubagentScriptedDataSource({
    required this.parentInitialToolCalls,
    required List<ChatCompletionResult> childCompletions,
    this.parentFinalChunks = const ['Parent final answer'],
    ChatCompletionResult? childToolResultFollowUp,
  }) : _childCompletions = Queue<ChatCompletionResult>.from(childCompletions),
       childToolResultFollowUp =
           childToolResultFollowUp ??
           ChatCompletionResult(content: '', finishReason: 'stop');

  final List<ToolCallInfo> parentInitialToolCalls;
  final Queue<ChatCompletionResult> _childCompletions;
  final List<String> parentFinalChunks;
  final ChatCompletionResult childToolResultFollowUp;

  final List<List<ToolResultInfo>> parentToolResultBatches = [];

  static bool _isChild(List<Message> messages) => messages.any(
    (message) =>
        message.role == MessageRole.system &&
        message.content.contains('focused subagent'),
  );

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: const Stream<String>.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: '',
          toolCalls: parentInitialToolCalls,
          finishReason: 'tool_calls',
        ),
      ),
    );
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => Stream<String>.fromIterable(parentFinalChunks);

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (_childCompletions.isEmpty) {
      return ChatCompletionResult(content: '', finishReason: 'stop');
    }
    return _childCompletions.removeFirst();
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
    if (_isChild(messages)) {
      return childToolResultFollowUp;
    }
    parentToolResultBatches.add(List<ToolResultInfo>.from(toolResults));
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
  }) => const Stream<String>.empty();

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
  }) async => throw UnimplementedError();
}

// ---------------------------------------------------------------------------
// Tool service exposing the delegation tools plus a project-free child tool.
// spawn_subagent / get_subagent_result are intercepted in ChatNotifier, so
// executeTool only ever runs lookup_fact.
// ---------------------------------------------------------------------------

class _SubagentTestToolService extends McpToolService {
  final List<String> executedToolNames = [];

  static const lookupFactResult = 'LOOKUP_FACT_RESULT_42';

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    Map<String, dynamic> fn(
      String name,
      String description,
      Map<String, dynamic> properties,
      List<String> required,
    ) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          'required': required,
        },
      },
    };

    return [
      fn('spawn_subagent', 'Delegate a sub-task to a child agent.', {
        'description': {'type': 'string'},
        'prompt': {'type': 'string'},
        'background': {'type': 'boolean'},
      }, ['description', 'prompt']),
      fn('get_subagent_result', 'Fetch a background subagent result.', {
        'task_id': {'type': 'string'},
      }, ['task_id']),
      fn('lookup_fact', 'Look up a fact by key.', {
        'key': {'type': 'string'},
      }, ['key']),
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    if (name == 'lookup_fact') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'value': lookupFactResult}),
        isSuccess: true,
      );
    }
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'unsupported'}),
      isSuccess: false,
      errorMessage: 'unsupported tool $name',
    );
  }
}

ProviderContainer _buildContainer({
  required ChatDataSource dataSource,
  required McpToolService toolService,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final notification = _MockNotificationService();
  when(
    () => notification.showSubagentCompletionNotification(
      taskId: any(named: 'taskId'),
      description: any(named: 'description'),
      isSuccessful: any(named: 'isSuccessful'),
      body: any(named: 'body'),
    ),
  ).thenAnswer((_) async {});
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
      conversationsNotifierProvider.overrideWith(
        _TestConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifier.new,
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(notification),
    ],
  );
}

/// Pumps the microtask/timer queue until [condition] is true or [timeout]
/// elapses — used to await fire-and-forget background subagent completion.
Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

ToolCallInfo _spawnSubagentCall({
  required String description,
  required String prompt,
  bool background = false,
}) => ToolCallInfo(
  id: 'parent-spawn-1',
  name: 'spawn_subagent',
  arguments: {
    'description': description,
    'prompt': prompt,
    if (background) 'background': true,
  },
);

void main() {
  test('child subagent uses a tool and its summary reaches the parent', () async {
    final dataSource = _SubagentScriptedDataSource(
      parentInitialToolCalls: [
        _spawnSubagentCall(
          description: 'look up the fact',
          prompt: 'Use lookup_fact with key "answer" and report the value.',
        ),
      ],
      childCompletions: [
        // Child first turn: call lookup_fact.
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'child-lookup-1',
              name: 'lookup_fact',
              arguments: const {'key': 'answer'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        // Child final turn: summarize.
        ChatCompletionResult(
          content: 'The fact is ${_SubagentTestToolService.lookupFactResult}.',
          finishReason: 'stop',
        ),
      ],
      parentFinalChunks: const ['Parent reports the delegated result.'],
    );
    final toolService = _SubagentTestToolService();
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );

    try {
      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage('Delegate the fact lookup to a subagent.');

      // The child actually invoked the tool.
      expect(toolService.executedToolNames, contains('lookup_fact'));

      // The subagent summary (carrying the tool result) was handed back to the
      // parent as a tool result.
      final parentToolResultText = dataSource.parentToolResultBatches
          .expand((batch) => batch)
          .map((result) => result.result)
          .join('\n');
      expect(
        parentToolResultText,
        contains(_SubagentTestToolService.lookupFactResult),
      );

      // The parent produced its final answer.
      expect(
        notifier.state.messages.last.role,
        MessageRole.assistant,
      );
      expect(
        notifier.state.messages.last.content,
        contains('Parent reports the delegated result'),
      );
    } finally {
      container.dispose();
    }
  });

  test('background subagent returns a task id and the result is recoverable', () async {
    final dataSource = _SubagentScriptedDataSource(
      parentInitialToolCalls: [
        _spawnSubagentCall(
          description: 'background compute',
          prompt: 'Compute the answer and report it.',
          background: true,
        ),
      ],
      childCompletions: [
        ChatCompletionResult(
          content:
              'Background result: ${_SubagentTestToolService.lookupFactResult}',
          finishReason: 'stop',
        ),
      ],
      parentFinalChunks: const ['Started the background task.'],
    );
    final toolService = _SubagentTestToolService();
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );

    try {
      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage('Run the computation in the background.');

      // A background task was registered immediately.
      final tasks = container.read(subagentTaskNotifierProvider);
      expect(tasks, isNotEmpty);
      final taskId = tasks.first.id;
      expect(tasks.first.isBackground, isTrue);

      // Wait for the fire-and-forget run to settle.
      final taskNotifier = container.read(
        subagentTaskNotifierProvider.notifier,
      );
      await _pumpUntil(() => taskNotifier.byId(taskId)?.isTerminal ?? false);

      final settled = taskNotifier.byId(taskId);
      expect(settled, isNotNull);
      expect(settled!.status, SubagentTaskStatus.completed);
      expect(
        settled.resultSummary,
        contains(_SubagentTestToolService.lookupFactResult),
        reason: 'get_subagent_result reads this notifier-backed summary',
      );
    } finally {
      container.dispose();
    }
  });

  test('a child cannot spawn another subagent (delegation depth stays 1)', () async {
    final dataSource = _SubagentScriptedDataSource(
      parentInitialToolCalls: [
        _spawnSubagentCall(
          description: 'tries to nest',
          prompt: 'Attempt to spawn another subagent, then summarize.',
        ),
      ],
      childCompletions: [
        // Child attempts a nested spawn_subagent.
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'child-nest-1',
              name: 'spawn_subagent',
              arguments: const {
                'description': 'nested',
                'prompt': 'do more work',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        // After the rejection, the child finishes directly.
        ChatCompletionResult(
          content: 'Could not nest; finished the task directly.',
          finishReason: 'stop',
        ),
      ],
      childToolResultFollowUp: ChatCompletionResult(
        content: 'Acknowledged the rejection.',
        finishReason: 'stop',
      ),
      parentFinalChunks: const ['Parent done.'],
    );
    final toolService = _SubagentTestToolService();
    final container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );

    try {
      final notifier = container.read(chatNotifierProvider.notifier);
      await notifier.sendMessage('Delegate something that tries to nest.');
      await _pumpUntil(() => false, timeout: const Duration(milliseconds: 50));

      // The nested spawn_subagent was rejected before reaching the handler:
      // no nested background task was registered and executeTool never saw it.
      expect(
        container.read(subagentTaskNotifierProvider),
        isEmpty,
        reason: 'a nested subagent must not be created',
      );
      expect(
        toolService.executedToolNames,
        isNot(contains('spawn_subagent')),
      );

      // The child still completed and the parent produced its final answer.
      final parentToolResultText = dataSource.parentToolResultBatches
          .expand((batch) => batch)
          .map((result) => result.result)
          .join('\n');
      expect(parentToolResultText, contains('finished the task directly'));
      expect(notifier.state.messages.last.role, MessageRole.assistant);
    } finally {
      container.dispose();
    }
  });
}
