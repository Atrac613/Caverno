import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/successful_read_result_replay_cache.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/subagent_task_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

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
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      enableCodingVerificationFeedback: false,
    );
  }
}

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockConversationBox extends Mock implements Box<String> {}

class _TestSessionMemoryService extends SessionMemoryService {
  _TestSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

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
    this.failChildAfterTools = false,
    ChatCompletionResult? childToolResultFollowUp,
    List<ChatCompletionResult> parentToolResultFollowUps =
        const <ChatCompletionResult>[],
  }) : _parentToolResultFollowUps = Queue<ChatCompletionResult>.from(
         parentToolResultFollowUps,
       ),
       _childCompletions = Queue<ChatCompletionResult>.from(childCompletions),
       childToolResultFollowUp =
           childToolResultFollowUp ??
           ChatCompletionResult(content: '', finishReason: 'stop');

  final bool failChildAfterTools;
  /// Reassignable so a test can drive a *second* parent turn with different
  /// calls: the cross-turn reads are the ones that broke.
  List<ToolCallInfo> parentInitialToolCalls;
  final Queue<ChatCompletionResult> _childCompletions;

  /// What the parent says after each tool batch, so a turn can be driven past
  /// the first one. Empty means the turn ends after one batch, as before.
  final Queue<ChatCompletionResult> _parentToolResultFollowUps;
  final List<String> parentFinalChunks;
  final ChatCompletionResult childToolResultFollowUp;

  final List<List<ToolResultInfo>> parentToolResultBatches = [];
  final List<List<ToolResultInfo>> childToolResultBatches = [];
  final List<List<Message>> childRequests = [];
  final List<List<Message>> parentRequests = [];

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
    parentRequests.add(messages);
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
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(
    Stream<String>.fromIterable(parentFinalChunks),
    finishReason: 'stop',
  );

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (_isChild(messages)) childRequests.add(messages);
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
      childToolResultBatches.add(toolResults);
      if (failChildAfterTools) {
        throw StateError('Model unloaded after mutation');
      }
      return childToolResultFollowUp;
    }
    parentToolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    if (_parentToolResultFollowUps.isEmpty) {
      return ChatCompletionResult(content: '', finishReason: 'stop');
    }
    return _parentToolResultFollowUps.removeFirst();
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
  _SubagentTestToolService({this.lookupOutcome});
  final ToolOutcome? lookupOutcome;
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
      fn(
        'spawn_subagent',
        'Delegate a sub-task to a child agent.',
        {
          'description': {'type': 'string'},
          'prompt': {'type': 'string'},
          'background': {'type': 'boolean'},
        },
        ['description', 'prompt'],
      ),
      fn(
        'get_subagent_result',
        'Fetch a background subagent result.',
        {
          'task_id': {'type': 'string'},
        },
        ['task_id'],
      ),
      fn(
        'lookup_fact',
        'Look up a fact by key.',
        {
          'key': {'type': 'string'},
        },
        ['key'],
      ),
      fn(
        'process_status',
        'Read the result of a local process.',
        {
          'job_id': {'type': 'string'},
        },
        ['job_id'],
      ),
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
        outcome: lookupOutcome,
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

  @override
  Future<McpToolResult> executeProcessTool({
    required ChatTurnOwner owner,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'status': 'exited', 'exit_code': 0}),
      outcome: const ToolOutcome(
        processState: ToolProcessState.exited,
        exitCode: 0,
      ),
      isSuccess: true,
    );
  }
}

ProviderContainer _buildContainer({
  required ChatDataSource dataSource,
  required McpToolService toolService,
}) {
  final conversationStorage = <String, String>{};
  final conversationBox = _MockConversationBox();
  when(() => conversationBox.keys).thenAnswer((_) => conversationStorage.keys);
  when(() => conversationBox.get(any())).thenAnswer(
    (invocation) => conversationStorage[invocation.positionalArguments[0]],
  );
  when(() => conversationBox.put(any(), any())).thenAnswer((invocation) async {
    final key = invocation.positionalArguments[0] as String;
    final value = invocation.positionalArguments[1] as String;
    conversationStorage[key] = value;
  });
  when(() => conversationBox.delete(any())).thenAnswer((invocation) async {
    conversationStorage.remove(invocation.positionalArguments[0]);
  });
  when(conversationBox.clear).thenAnswer((_) async {
    final deleted = conversationStorage.length;
    conversationStorage.clear();
    return deleted;
  });

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
      conversationBoxProvider.overrideWithValue(conversationBox),
      conversationsNotifierProvider.overrideWith(ConversationsNotifier.new),
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
  for (final background in [false, true]) {
    for (final failAfterMutation in [false, true]) {
      test(
        'child mutation expires parent reads (background=$background, failed=$failAfterMutation)',
        () async {
          final dataSource = _SubagentScriptedDataSource(
            parentInitialToolCalls: [
              _spawnSubagentCall(
                description: 'Modify project',
                prompt: 'Perform the tool operation.',
                background: background,
              ),
            ],
            childCompletions: [
              ChatCompletionResult(
                content: '',
                finishReason: 'tool_calls',
                toolCalls: [
                  ToolCallInfo(
                    id: 'child-write',
                    name: 'lookup_fact',
                    arguments: const {'key': 'answer'},
                  ),
                ],
              ),
            ],
            failChildAfterTools: failAfterMutation,
            childToolResultFollowUp: ChatCompletionResult(
              content: 'Produced result.',
              finishReason: 'stop',
            ),
          );
          final container = _buildContainer(
            dataSource: dataSource,
            toolService: _SubagentTestToolService(
              lookupOutcome: const ToolOutcome(
                fileMutations: [
                  ToolFileMutation(path: 'count_field.py', changed: true),
                ],
              ),
            ),
          );
          try {
            final conversations = container.read(
              conversationsNotifierProvider.notifier,
            );
            conversations.createNewConversation();
            final id = container
                .read(conversationsNotifierProvider)
                .currentConversation!
                .id;
            final before = container
                .read(conversationsNotifierProvider)
                .conversationForId(id)!
                .mutationGeneration;
            final read = ToolCallInfo(
              id: 'read',
              name: 'read_file',
              arguments: const {'path': 'count_field.py'},
            );
            final cache = SuccessfulReadResultReplayCache();
            cache.record(
              toolCall: read,
              result: 'lines = f',
              isSuccess: true,
              interactionGeneration: 1,
              mutationGeneration: before,
            );
            await container
                .read(chatNotifierProvider.notifier)
                .sendMessage('Delegate the operation.');
            await _pumpUntil(
              () =>
                  container
                      .read(conversationsNotifierProvider)
                      .conversationForId(id)!
                      .mutationGeneration >
                  before,
            );
            final after = container
                .read(conversationsNotifierProvider)
                .conversationForId(id)!
                .mutationGeneration;
            expect(after, before + 1);
            expect(
              cache.lookup(
                toolCall: read,
                interactionGeneration: 1,
                mutationGeneration: after,
              ),
              isNull,
              reason:
                  'A child-modified file must not replay the pre-delegation content',
            );
            if (background) {
              await _pumpUntil(
                () => container
                    .read(subagentTaskNotifierProvider)
                    .tasksForConversation(id)
                    .every((task) => !task.isActive),
              );
            }
          } finally {
            container.dispose();
          }
        },
      );
    }
  }

  test(
    'planned Anabasis refuses completed-task delegation before child runs',
    () async {
      final dataSource = _SubagentScriptedDataSource(
        parentInitialToolCalls: [
          ToolCallInfo(
            id: 'recreate',
            name: 'spawn_subagent',
            arguments: {
              'description': 'Recreate CLI',
              'prompt': 'Overwrite count_field.py',
              'workflow_task_id': 'cli',
            },
          ),
        ],
        childCompletions: [],
        parentFinalChunks: const ['No ready work.'],
      );
      final service = _SubagentTestToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: service,
      );
      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation();
        final id = container
            .read(conversationsNotifierProvider)
            .currentConversation!
            .id;
        await conversations.updateCurrentWorkflow(
          conversationId: id,
          workflowSpec: ConversationWorkflowSpec(
            tasks: [
              ConversationWorkflowTask(
                id: 'cli',
                title: 'Build CLI',
                status: ConversationWorkflowTaskStatus.completed,
              ),
            ],
          ),
        );
        await container
            .read(chatNotifierProvider.notifier)
            .sendMessage('@anabasis Continue');
        final result = dataSource.parentToolResultBatches
            .expand((batch) => batch)
            .singleWhere((result) => result.name == 'spawn_subagent');
        expect(
          jsonDecode(result.result)['code'],
          'anabasis_delegation_not_ready',
        );
        expect(service.executedToolNames, isEmpty);
        expect(dataSource.childRequests, isEmpty);
      } finally {
        container.dispose();
      }
    },
  );
  test(
    'planned Anabasis leaves the ready task pending for its own delegation queue',
    () async {
      // The parent's turn used to claim the next pending task for itself before
      // its prompt was built, and `pending` is the status the delegation queue
      // requires -- so a plan with one ready task showed the parent an empty
      // queue in the very turn that asked it to delegate, and refused the id it
      // read from the plan body instead.
      final dataSource = _SubagentScriptedDataSource(
        parentInitialToolCalls: [
          ToolCallInfo(
            id: 'delegate',
            name: 'spawn_subagent',
            arguments: {
              'description': 'Build CLI',
              'prompt': 'Implement the CLI.',
              'workflow_task_id': 'cli',
            },
          ),
        ],
        childCompletions: [],
        parentFinalChunks: const ['Delegated the ready task.'],
      );
      final service = _SubagentTestToolService();
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: service,
      );
      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
        );
        final id = container
            .read(conversationsNotifierProvider)
            .currentConversation!
            .id;
        await conversations.updateCurrentWorkflow(
          conversationId: id,
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: const ConversationWorkflowSpec(
            tasks: [
              ConversationWorkflowTask(
                id: 'cli',
                title: 'Build CLI',
                status: ConversationWorkflowTaskStatus.pending,
              ),
            ],
          ),
        );
        await container
            .read(chatNotifierProvider.notifier)
            .sendMessage('@anabasis Continue');
        final openingPrompt = dataSource.parentRequests.first
            .firstWhere((message) => message.role == MessageRole.system)
            .content;
        expect(
          openingPrompt,
          contains('[workflow_task_id: cli]'),
          reason:
              'The turn-opening prompt must still offer the task the queue held '
              'before the turn started',
        );
        final results = dataSource.parentToolResultBatches
            .expand((batch) => batch)
            .where((result) => result.name == 'spawn_subagent');
        expect(
          results.map((result) => result.result),
          everyElement(isNot(contains('anabasis_delegation_not_ready'))),
        );
        expect(dataSource.childRequests, isNotEmpty);
      } finally {
        container.dispose();
      }
    },
  );
  test(
    'the parent records an acceptance of the child it delegated to',
    () async {
      // ANA3 PR 2b's write path had no test above the notifier, and shipped
      // unreachable: the authority guard refused accept_task before the handler
      // in every real turn. A test that drives the real dispatch chain is what
      // would have caught that, because the guard sits in the chain and the
      // handler's own five grounds sit after it.
      final dataSource = _SubagentScriptedDataSource(
        parentInitialToolCalls: [
          ToolCallInfo(
            id: 'delegate',
            name: 'spawn_subagent',
            arguments: const {
              'description': 'Scaffold the CLI',
              'prompt': 'Create the scaffold and report what you made.',
              'workflow_task_id': 'cli',
            },
          ),
          ToolCallInfo(
            id: 'accept',
            name: 'accept_task',
            arguments: const {
              'workflow_task_id': 'cli',
              'rationale':
                  'The child reported the scaffold and the analyzer was clean.',
            },
          ),
        ],
        childCompletions: [
          ChatCompletionResult(
            content: 'Created pubspec.yaml and bin/todo.dart; analyze clean.',
            finishReason: 'stop',
          ),
        ],
        parentFinalChunks: const ['Accepted the scaffold.'],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SubagentTestToolService(),
      );
      try {
        final conversations = container.read(
          conversationsNotifierProvider.notifier,
        );
        conversations.createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
        );
        final id = container
            .read(conversationsNotifierProvider)
            .currentConversation!
            .id;
        await conversations.updateCurrentWorkflow(
          conversationId: id,
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: const ConversationWorkflowSpec(
            tasks: [
              ConversationWorkflowTask(
                id: 'cli',
                title: 'Scaffold the CLI',
                status: ConversationWorkflowTaskStatus.pending,
              ),
            ],
          ),
        );
        await container
            .read(chatNotifierProvider.notifier)
            .sendMessage('@anabasis Delegate the scaffold and judge it.');

        final acceptance = dataSource.parentToolResultBatches
            .expand((batch) => batch)
            .singleWhere((result) => result.name == 'accept_task');
        expect(
          acceptance.result,
          isNot(contains('anabasis_parent_authority_refused')),
          reason:
              'The parent is the only role allowed to accept, so the authority '
              'guard refusing it leaves the tool with no caller at all.',
        );
        expect(jsonDecode(acceptance.result), containsPair('ok', true));
        expect(acceptance.result, contains('accepted_task_id'));
        expect(
          container
              .read(conversationsNotifierProvider)
              .conversationForId(id)!
              .taskAcceptances
              .map((entry) => entry.taskId),
          contains('cli'),
        );
      } finally {
        container.dispose();
      }
    },
  );
  test(
    'a child delegated in an earlier turn is still readable',
    () async {
      // Measured live: the parent was asked to judge the child's result, called
      // get_subagent_result, was told not_found because the lookup matched the
      // turn owner, and re-delegated the task instead of judging it. The
      // acceptance audit next to it is conversation-scoped, so the two reads
      // disagreed about which children exist.
      final dataSource = _SubagentScriptedDataSource(
        parentInitialToolCalls: [
          ToolCallInfo(
            id: 'delegate',
            name: 'spawn_subagent',
            arguments: const {
              'description': 'Scaffold the CLI',
              'prompt': 'Create the scaffold and report what you made.',
            },
          ),
        ],
        childCompletions: [
          ChatCompletionResult(
            content: 'Created pubspec.yaml and bin/todo.dart.',
            finishReason: 'stop',
          ),
        ],
        parentFinalChunks: const ['Delegated.'],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SubagentTestToolService(),
      );
      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage('Delegate the scaffold.');
        final delegated = jsonDecode(
          dataSource.parentToolResultBatches
              .expand((batch) => batch)
              .singleWhere((result) => result.name == 'spawn_subagent')
              .result,
        );
        final childTaskId = (delegated as Map)['task_id'] as String;

        dataSource.parentToolResultBatches.clear();
        dataSource.parentInitialToolCalls = [
          ToolCallInfo(
            id: 'read-back',
            name: 'get_subagent_result',
            arguments: {'task_id': childTaskId},
          ),
        ];
        await notifier.sendMessage('What did the child report?');

        final readBack = dataSource.parentToolResultBatches
            .expand((batch) => batch)
            .singleWhere((result) => result.name == 'get_subagent_result');
        expect(
          readBack.result,
          isNot(contains('not_found')),
          reason:
              'A result the parent is asked to judge in a later turn has to '
              'outlive the turn that produced it.',
        );
        expect(readBack.result, contains('Created pubspec.yaml'));
      } finally {
        container.dispose();
      }
    },
  );
  test(
    'a twice-refused parent keeps the turn and delegates instead',
    () async {
      // Measured: a parent lost a whole turn to a compound shell expression the
      // harness asked it to split, and another to a tool its own prompt told it
      // to use. A policy refusal names a different call to make, so ending the
      // turn takes away the one move that was left.
      final write = ToolCallInfo(
        id: 'write',
        name: 'write_file',
        arguments: const {'path': 'bin/todo.dart', 'content': '// ...'},
      );
      final dataSource = _SubagentScriptedDataSource(
        parentInitialToolCalls: [write],
        childCompletions: [
          ChatCompletionResult(
            content: 'Wrote bin/todo.dart.',
            finishReason: 'stop',
          ),
        ],
        parentToolResultFollowUps: [
          // The same refused call again: the second one used to end the turn.
          ChatCompletionResult(
            content: '',
            toolCalls: [write],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'delegate',
                name: 'spawn_subagent',
                arguments: const {
                  'description': 'Write the entry point',
                  'prompt': 'Create bin/todo.dart and report what you wrote.',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        parentFinalChunks: const ['Delegated the write.'],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SubagentTestToolService(),
      );
      try {
        await container
            .read(chatNotifierProvider.notifier)
            .sendMessage('@anabasis Create the entry point.');

        final results = dataSource.parentToolResultBatches
            .expand((batch) => batch)
            .toList();
        expect(
          results.where((result) => result.name == 'write_file'),
          hasLength(2),
          reason: 'Both writes are still refused; that is the boundary working.',
        );
        expect(
          results.where((result) => result.name == 'spawn_subagent'),
          hasLength(1),
          reason:
              'The refusal names delegation as the next action, and the turn '
              'has to survive long enough for the parent to take it.',
        );
        expect(dataSource.childRequests, isNotEmpty);
      } finally {
        container.dispose();
      }
    },
  );
  test(
    'foreground delegation returns observed child command evidence',
    () async {
      final dataSource = _SubagentScriptedDataSource(
        parentInitialToolCalls: [
          _spawnSubagentCall(
            description: 'verify the child result',
            prompt: 'Run the verification command and report its result.',
          ),
        ],
        childCompletions: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'child-command-1',
                name: 'process_status',
                arguments: const {'job_id': 'child-job'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        childToolResultFollowUp: ChatCompletionResult(
          content: 'flutter analyze completed successfully.',
          finishReason: 'stop',
        ),
        parentFinalChunks: const ['flutter analyze completed successfully.'],
      );
      final container = _buildContainer(
        dataSource: dataSource,
        toolService: _SubagentTestToolService(),
      );

      try {
        await container
            .read(chatNotifierProvider.notifier)
            .sendMessage('Delegate command verification.');

        final delegation = dataSource.parentToolResultBatches
            .expand((batch) => batch)
            .singleWhere((result) => result.name == 'spawn_subagent');
        expect(delegation.outcome?.exitCode, 0);
        expect(
          jsonDecode(delegation.result),
          containsPair('status', 'completed'),
        );
        expect(
          dataSource.parentToolResultBatches
              .expand((batch) => batch)
              .where(
                (result) => result.result.contains(
                  'unexecuted_command_action_retry_required',
                ),
              ),
          isEmpty,
        );
      } finally {
        container.dispose();
      }
    },
  );

  test(
    'child subagent uses a tool and its summary reaches the parent',
    () async {
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
            content:
                'The fact is ${_SubagentTestToolService.lookupFactResult}.',
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
        expect(notifier.state.messages.last.role, MessageRole.assistant);
        expect(
          notifier.state.messages.last.content,
          contains('Parent reports the delegated result'),
        );
      } finally {
        container.dispose();
      }
    },
  );

  test(
    'background subagent returns a task id and the result is recoverable',
    () async {
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
        final owner = await notifier.sendMessage(
          'Run the computation in the background.',
        );
        expect(owner, isNotNull);
        final turnOwner = owner!;

        // A background task was registered immediately.
        final tasks = container
            .read(subagentTaskNotifierProvider)
            .tasksFor(turnOwner);
        expect(tasks, isNotEmpty);
        final taskId = tasks.first.id;
        expect(tasks.first.isBackground, isTrue);

        // Wait for the fire-and-forget run to settle.
        final taskNotifier = container.read(
          subagentTaskNotifierProvider.notifier,
        );
        await _pumpUntil(
          () => taskNotifier.byId(turnOwner, taskId)?.isTerminal ?? false,
        );

        final settled = taskNotifier.byId(turnOwner, taskId);
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
    },
  );

  for (final blockedTool in ['spawn_subagent', 'update_goal']) {
    test('a child cannot invoke parent control tool: $blockedTool', () async {
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
                name: blockedTool,
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
        final owner = await notifier.sendMessage(
          'Delegate something that tries to nest.',
        );
        expect(owner, isNotNull);
        final turnOwner = owner!;
        await _pumpUntil(
          () => false,
          timeout: const Duration(milliseconds: 50),
        );

        // The nested spawn_subagent was rejected before reaching the handler:
        // only the top-level child is registered, and executeTool never saw it.
        // Emptiness used to stand in for that, until foreground children started
        // being registered so the acceptance audit could find them -- a proxy
        // that could not tell "no nested child" from "no child at all".
        final registered = container
            .read(subagentTaskNotifierProvider)
            .tasksFor(turnOwner);
        expect(
          registered.map((task) => task.parentToolUseId),
          ['parent-spawn-1'],
          reason: 'a nested subagent must not be created',
        );
        expect(
          toolService.executedToolNames,
          isNot(contains('spawn_subagent')),
        );

        final denial = dataSource.childToolResultBatches
            .expand((batch) => batch)
            .singleWhere((result) => result.name == blockedTool);
        expect(denial.result, contains('parent goal updates are not allowed'));

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
}
