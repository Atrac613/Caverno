import 'dart:async';

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
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/thread_scoped_chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/turn_thread_scope.dart';
import 'package:caverno/features/chat/presentation/providers/caverno_execution_runtime_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const String _projectARoot = '/tmp/caverno-test/project-a';
const String _projectBRoot = '/tmp/caverno-test/project-b';

class _MockBox extends Mock implements Box<String> {}

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

class _TestSessionMemoryService extends SessionMemoryService {
  _TestSessionMemoryService() : super(ChatMemoryRepository.fromBox(_MockBox()));

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

class _TwoProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() {
    final now = DateTime(2026, 7, 25);
    return CodingProjectsState(
      projects: [
        CodingProject(
          id: 'project-a',
          name: 'project-a',
          rootPath: _projectARoot,
          createdAt: now,
          updatedAt: now,
        ),
        CodingProject(
          id: 'project-b',
          name: 'project-b',
          rootPath: _projectBRoot,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      selectedProjectId: 'project-a',
    );
  }

  @override
  Future<bool> ensureProjectAccess(String? projectId) async => true;
}

class _TestSettingsNotifier extends SettingsNotifier {
  _TestSettingsNotifier([this.assistantMode = AssistantMode.coding]);

  final AssistantMode assistantMode;

  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    enableLlmSessionLogs: false,
    assistantMode: assistantMode,
    mcpEnabled: true,
    demoMode: false,
  );
}

/// Runs [onExecute] while the tool is executing, which is the window in which
/// the user switched threads in the 2026-07-25 incident.
class _SwitchingToolService extends McpToolService {
  _SwitchingToolService(this.onExecute);

  final Future<void> Function() onExecute;
  final List<String> receivedPaths = [];
  int executions = 0;

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': 'list_directory',
        'description': 'List a directory',
        'parameters': const <String, dynamic>{'type': 'object'},
      },
    },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executions += 1;
    receivedPaths.add((arguments['path'] as String?) ?? '');
    await onExecute();
    return McpToolResult(
      toolName: name,
      result: '[dir] bin\n[file] pubspec.yaml',
      isSuccess: true,
    );
  }
}

/// Answers the first request with a tool call, then records every later
/// request so the test can inspect the system prompt of the follow-up.
class _RecordingDataSource implements ChatDataSource {
  _RecordingDataSource({this.finalContent = 'done', this.onFirstRequest});

  final String finalContent;

  /// Runs while the first request is in flight, i.e. before the tool call it
  /// answers with is dispatched.
  final Future<void> Function()? onFirstRequest;
  final List<List<Message>> requests = [];
  int completions = 0;

  String? get lastSystemPrompt {
    for (final messages in requests.reversed) {
      for (final message in messages) {
        if (message.role == MessageRole.system && message.id == 'system') {
          return message.content;
        }
      }
    }
    return null;
  }

  ChatCompletionResult _answer(List<Message> messages) {
    requests.add(messages);
    completions += 1;
    if (completions == 1) {
      return ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-list',
            name: 'list_directory',
            arguments: const {'path': 'bin'},
          ),
        ],
      );
    }
    return ChatCompletionResult(content: finalContent, finishReason: 'stop');
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    requests.add(messages);
    yield finalContent;
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _answer(messages);

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    final result = _answer(messages);
    final hook = onFirstRequest;
    return StreamWithToolsResult(
      stream: const Stream<String>.empty(),
      completion: hook == null || completions != 1
          ? Future<ChatCompletionResult>.value(result)
          : hook().then((_) => result),
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
  }) async* {
    requests.add(messages);
    yield finalContent;
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
  }) async => _answer(messages);

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _answer(messages);
}

/// Replays the two payloads a plan draft needs — the workflow proposal then
/// the task proposal — running [onFirstRequest] while the first is in flight.
class _PlanProposalDataSource implements ChatDataSource {
  _PlanProposalDataSource(this.onFirstRequest);

  final Future<void> Function() onFirstRequest;
  final List<String> systemPrompts = [];
  int completions = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    completions += 1;
    systemPrompts.add(
      messages
          .where((message) => message.role == MessageRole.system)
          .map((message) => message.content)
          .join('\n'),
    );
    if (completions == 1) {
      await onFirstRequest();
      return ChatCompletionResult(
        content:
            '{"kind":"proposal","workflowStage":"plan",'
            '"goal":"Ship the slice","constraints":["Keep it small"],'
            '"acceptanceCriteria":["The draft survives a thread switch"],'
            '"openQuestions":[]}',
        finishReason: 'stop',
      );
    }
    return ChatCompletionResult(
      content:
          '{"tasks":[{"title":"Track the plan drafting turn",'
          '"targetFiles":["lib/features/chat/presentation/providers/chat_notifier.dart"],'
          '"validationCommand":"flutter test","notes":"Cover the switch."}]}',
      finishReason: 'stop',
    );
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => throw UnimplementedError();
}

ProviderContainer _buildContainer({
  required ChatDataSource dataSource,
  required McpToolService toolService,
  AssistantMode assistantMode = AssistantMode.coding,
}) {
  final conversationBox = _MockBox();
  final storage = <String, String>{};
  when(() => conversationBox.keys).thenAnswer((_) => storage.keys);
  when(
    () => conversationBox.get(any()),
  ).thenAnswer((call) => storage[call.positionalArguments[0]]);
  when(() => conversationBox.put(any(), any())).thenAnswer((call) async {
    storage[call.positionalArguments[0] as String] =
        call.positionalArguments[1] as String;
  });
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final notificationService = _MockNotificationService();
  when(
    () => notificationService.showApprovalRequiredNotification(
      conversationId: any(named: 'conversationId'),
      title: any(named: 'title'),
      body: any(named: 'body'),
    ),
  ).thenAnswer((_) async {});

  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _TestSettingsNotifier(assistantMode),
      ),
      conversationBoxProvider.overrideWithValue(conversationBox),
      conversationsNotifierProvider.overrideWith(ConversationsNotifier.new),
      codingProjectsNotifierProvider.overrideWith(_TwoProjectsNotifier.new),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(notificationService),
    ],
  );
}

void main() {
  test(
    'a detached turn keeps its own project in the system prompt',
    () async {
      // Regression for the cross-thread contamination observed 2026-07-25: a
      // background turn on one project kept running while another thread was
      // visible, and its next request was assembled with the *visible*
      // thread's coding project. The model was handed its own tool results
      // under another project's root path.
      late final ProviderContainer container;
      final dataSource = _RecordingDataSource();
      final toolService = _SwitchingToolService(() async {
        // The user opens the other thread while the tool runs.
        container
            .read(conversationsNotifierProvider.notifier)
            .createNewConversation(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-b',
            );
        await Future<void>.delayed(Duration.zero);
      });

      container = _buildContainer(
        dataSource: dataSource,
        toolService: toolService,
      );
      addTearDown(container.dispose);

      final conversationsNotifier = container.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-a',
      );
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('list the project');

      expect(
        toolService.executions,
        greaterThan(0),
        reason: 'the tool has to run for the thread switch to interleave',
      );
      expect(
        container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.normalizedProjectId,
        'project-b',
        reason: 'the visible thread must be the other project by now',
      );

      final systemPrompt = dataSource.lastSystemPrompt;
      expect(systemPrompt, isNotNull);
      expect(
        systemPrompt,
        contains(_projectARoot),
        reason: 'the detached turn must keep describing its own project',
      );
      expect(
        systemPrompt,
        isNot(contains(_projectBRoot)),
        reason:
            'inheriting the visible thread project is the contamination: the '
            'turn would report its own tool results under another root',
      );
    },
  );

  test('a hidden-prompt turn survives the user switching threads', () async {
    // sendHiddenPrompt used to skip the tracking _sendMessageNow does, so an
    // auto-continue turn was not an active response. Switching threads then
    // ran the conversation-change reset over it: the generation was bumped and
    // the turn was cancelled *after* its tools had already run, discarding the
    // work, and its requests logged under the newly visible thread.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource(
      finalContent: 'ANSWER-BELONGING-TO-THREAD-A',
    );
    final toolService = _SwitchingToolService(() async {
      // The user opens another thread while the hidden turn's tool runs. No
      // new turn starts, so thread A's generation is still the current one.
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.sendHiddenPrompt('keep going on thread A');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      toolService.executions,
      greaterThan(0),
      reason: 'the tool has to run for the thread switch to interleave',
    );
    expect(
      dataSource.completions,
      greaterThanOrEqualTo(2),
      reason:
          'the tool ran, so its result has to reach a follow-up request '
          'instead of being discarded when the user switched threads',
    );
    final visibleContent = container
        .read(chatNotifierProvider)
        .messages
        .map((message) => message.content)
        .join('\n');
    expect(
      visibleContent,
      isNot(contains('ANSWER-BELONGING-TO-THREAD-A')),
      reason:
          'the background turn must not append its answer to the thread the '
          'user switched to',
    );
  });

  test('a queued message survives a thread switch and stays on its thread', () async {
    // Reported 2026-07-25: messages vanished when moving between threads. A
    // message typed while another thread was busy went onto one flat queue
    // that the thread switch cleared outright.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource(
      onFirstRequest: () async {
        final notifier = container.read(chatNotifierProvider.notifier);
        // Typed while the first turn is still in flight, so it is queued.
        unawaited(notifier.sendMessage('queued-for-thread-a'));
        await Future<void>.delayed(Duration.zero);
        container
            .read(conversationsNotifierProvider.notifier)
            .createNewConversation(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-b',
            );
        await Future<void>.delayed(Duration.zero);
      },
    );

    container = _buildContainer(
      dataSource: dataSource,
      toolService: _SwitchingToolService(() async {}),
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadA = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    await container.read(chatNotifierProvider.notifier).sendMessage('first');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      container
          .read(chatNotifierProvider)
          .queuedMessages
          .map((message) => message.content),
      isNot(contains('queued-for-thread-a')),
      reason: "the other thread's queued message must not appear here",
    );

    conversations.selectConversation(threadA);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      container
          .read(chatNotifierProvider)
          .queuedMessages
          .map((message) => message.content),
      contains('queued-for-thread-a'),
      reason:
          'the message was typed on this thread, so leaving and coming back '
          'must not discard it',
    );
  });

  test('a finished plan draft is still there after leaving the thread', () async {
    // Reported 2026-07-25: the review sheet never appeared for a plan drafted
    // while the user was on another thread; the plan only showed after
    // pressing expand. The sheet auto-presents from the draft fields, and the
    // thread switch rebuilt ChatState without them.
    late final ProviderContainer container;
    final dataSource = _PlanProposalDataSource(() async {});

    container = _buildContainer(
      dataSource: dataSource,
      toolService: _SwitchingToolService(() async {}),
      assistantMode: AssistantMode.plan,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final draftingThread = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    await container.read(chatNotifierProvider.notifier).generatePlanProposal();
    expect(
      container.read(chatNotifierProvider).workflowProposalDraft,
      isNotNull,
      reason: 'the draft has to exist before the switch for this to mean much',
    );

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(chatNotifierProvider).workflowProposalDraft,
      isNull,
      reason: "the other thread must not show this thread's draft",
    );

    conversations.selectConversation(draftingThread);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(chatNotifierProvider).workflowProposalDraft,
      isNotNull,
      reason:
          'coming back must restore the draft, otherwise the review sheet '
          'never auto-presents and the plan looks lost',
    );
  });

  test('a pending approval follows its thread and is announced', () async {
    // Leaving a thread that is waiting on the user used to drop the approval
    // outright. It has to survive, stay off the other thread, and be visible
    // to the sidebar so the thread can say "waiting for you" instead of
    // spinning.
    final container = _buildContainer(
      dataSource: _RecordingDataSource(),
      toolService: _SwitchingToolService(() async {}),
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final waitingThread = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    final notifier = container.read(chatNotifierProvider.notifier);
    notifier.state = notifier.state.copyWith(
      pendingLocalCommand: PendingLocalCommand(
        id: 'call-1',
        command: 'rm -rf build',
        workingDirectory: _projectARoot,
        reason: 'clean the build directory',
        warningTitle: 'Destructive command',
        warningMessage: 'This deletes files.',
        completer: Completer<LocalCommandApproval>(),
      ),
    );

    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    await Future<void>.delayed(Duration.zero);

    final onOtherThread = container.read(chatNotifierProvider);
    expect(
      onOtherThread.pendingLocalCommand,
      isNull,
      reason: "the other thread must not be asked to answer this thread's tool",
    );
    expect(
      onOtherThread.approvalRequiredConversationIds,
      contains(waitingThread),
      reason:
          'the sidebar needs this to replace the spinner with an approval '
          'prompt for the thread that is actually blocked',
    );

    conversations.selectConversation(waitingThread);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(chatNotifierProvider).pendingLocalCommand,
      isNotNull,
      reason: 'coming back must restore the approval, not discard it',
    );
  });

  test('a plan finished in the background lands on its own thread', () async {
    // Reported 2026-07-26: two threads drafting at once. The first finished
    // while the user was reading the second, and its draft was written into
    // the visible ChatState — so the second thread's own draft overwrote it,
    // the first thread showed nothing on return, and the dialog the user
    // approved was not necessarily the plan they were looking at.
    late final ProviderContainer container;
    final dataSource = _PlanProposalDataSource(() async {
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: _SwitchingToolService(() async {}),
      assistantMode: AssistantMode.plan,
    );
    addTearDown(container.dispose);

    final conversations = container.read(
      conversationsNotifierProvider.notifier,
    );
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final draftingThread = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    await container.read(chatNotifierProvider.notifier).generatePlanProposal();

    final onOtherThread = container.read(chatNotifierProvider);
    expect(
      onOtherThread.workflowProposalDraft,
      isNull,
      reason:
          "the thread the user switched to must not display another thread's "
          'plan, which is what made the approved dialog ambiguous',
    );
    expect(
      onOtherThread.approvalRequiredConversationIds,
      contains(draftingThread),
      reason: 'a finished plan is waiting on the user, so announce it',
    );

    conversations.selectConversation(draftingThread);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(chatNotifierProvider).workflowProposalDraft,
      isNotNull,
      reason: 'the thread that drafted the plan has to show it on return',
    );
  });

  test('an exhausted quality gate still yields a plan to review', () async {
    // Live 2026-07-25: the task-proposal gate rejected three usable drafts for
    // a single-file CLI project, the heuristic fallback tripped the same
    // rules, and the plan run failed outright — the user got an error instead
    // of a plan. A gate may ask for better; it may not destroy the only draft
    // there is. This fixture's single-task proposal trips the gate 3/3.
    final container = _buildContainer(
      dataSource: _PlanProposalDataSource(() async {}),
      toolService: _SwitchingToolService(() async {}),
      assistantMode: AssistantMode.plan,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );

    await container.read(chatNotifierProvider.notifier).generatePlanProposal();

    expect(
      container.read(chatNotifierProvider).taskProposalDraft,
      isNotNull,
      reason:
          'the rejected draft is still the best answer available, and the '
          'review sheet is where the user would fix it',
    );
    expect(
      container.read(chatNotifierProvider).taskProposalError,
      isNull,
      reason: 'presenting a plan and an error at once would be contradictory',
    );
  });

  test('an approval raised by a background turn goes to its own thread', () {
    // Approval prompts are raised from tool handlers that do not know which
    // thread they serve, so they landed on whoever the user was reading.
    final byThread = <String, ThreadScopedChatState>{};
    final visible = ChatState.initial();
    PendingLocalCommand pending() => PendingLocalCommand(
      id: 'call-1',
      command: 'rm -rf build',
      workingDirectory: _projectARoot,
      reason: 'clean the build directory',
      warningTitle: 'Destructive command',
      warningMessage: 'This deletes files.',
      completer: Completer<LocalCommandApproval>(),
    );

    final afterBackground = ThreadScopedChatState.routeToThread(
      byThread: byThread,
      turnThread: 'thread-a',
      visibleThread: 'thread-b',
      current: visible,
      apply: (s) => s.copyWith(pendingLocalCommand: pending()),
    );
    expect(
      afterBackground.pendingLocalCommand,
      isNull,
      reason: 'the reader of thread-b was never asked to approve this',
    );
    expect(
      byThread['thread-a']?.pendingLocalCommand,
      isNotNull,
      reason: 'it belongs to the thread whose turn asked for it',
    );
    expect(
      afterBackground.approvalRequiredConversationIds,
      contains('thread-a'),
      reason: 'and the sidebar has to be able to announce it',
    );

    final afterForeground = ThreadScopedChatState.routeToThread(
      byThread: byThread,
      turnThread: 'thread-b',
      visibleThread: 'thread-b',
      current: visible,
      apply: (s) => s.copyWith(pendingLocalCommand: pending()),
    );
    expect(
      afterForeground.pendingLocalCommand,
      isNotNull,
      reason: 'a turn on the visible thread still prompts inline as before',
    );
  });

  test('the runtime workspace follows the thread, not the sidebar', () async {
    // Live 2026-07-25: a plan run on run20 asked to lease run19's workspace
    // and failed as "workspace:todo is already owned by flutterGui process N",
    // because the snapshot took the project from CodingProjectsState's
    // selectedProjectId — the sidebar selection, left on the thread opened
    // before it. _TwoProjectsNotifier keeps project-a selected, so a thread on
    // project-b reproduces exactly that skew.
    final container = _buildContainer(
      dataSource: _RecordingDataSource(),
      toolService: _SwitchingToolService(() async {}),
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-b',
        );

    final snapshot = container.read(cavernoRuntimeSettingsPortProvider).current;
    expect(
      snapshot.workspace,
      _projectBRoot,
      reason:
          'the lease is taken on this path; using the sidebar selection makes '
          'one thread collide with another project\'s running turn',
    );
  });

  test('a relative tool path resolves against the turn project', () async {
    // Observed live on 2026-07-25: a turn on run19 asked for
    // read_file {"path":"todo_app.md"} and the resolver turned it into
    // run20/todo/todo_app.md because the user had that thread open. A relative
    // write would have landed in the other project.
    late final ProviderContainer container;
    final toolService = _SwitchingToolService(() async {});
    final dataSource = _RecordingDataSource(
      onFirstRequest: () async {
        // The user opens the other thread while the request is in flight, so
        // the tool call is dispatched with a different thread visible.
        container
            .read(conversationsNotifierProvider.notifier)
            .createNewConversation(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-b',
            );
        await Future<void>.delayed(Duration.zero);
      },
    );

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );

    await container.read(chatNotifierProvider.notifier).sendMessage('look');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      toolService.receivedPaths,
      isNotEmpty,
      reason: 'the tool has to run for its path to be resolved',
    );
    for (final path in toolService.receivedPaths) {
      expect(
        path,
        startsWith(_projectARoot),
        reason:
            'the relative path belongs to the thread that asked for it; '
            'resolving it into the visible project reads — and would write — '
            'another project',
      );
    }
  });

  test('a plan draft keeps its own project after a thread switch', () async {
    // Observed live on 2026-07-25 (build 96d23ed7): a plan draft on run19 kept
    // running while the user opened a second project, and its task proposal
    // went out describing run20 and was logged under that thread. The proposal
    // builders pass the turn's conversation to the user message but built the
    // system message from the visible thread. Plan drafting takes tens of
    // seconds, so a switch lands inside it easily.
    late final ProviderContainer container;
    final dataSource = _PlanProposalDataSource(() async {
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: _SwitchingToolService(() async {}),
      assistantMode: AssistantMode.plan,
    );
    addTearDown(container.dispose);

    container
        .read(conversationsNotifierProvider.notifier)
        .createNewConversation(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-a',
        );
    final draftingThreadId = container
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    await container.read(chatNotifierProvider.notifier).generatePlanProposal();

    final conversations = container
        .read(conversationsNotifierProvider)
        .conversations;
    final draftingThread = conversations.firstWhere(
      (conversation) => conversation.id == draftingThreadId,
    );
    final otherThread = conversations.firstWhere(
      (conversation) => conversation.id != draftingThreadId,
    );
    expect(
      draftingThread.planArtifact?.hasContent ?? false,
      isTrue,
      reason: 'the plan belongs to the thread it was drafted for',
    );
    expect(
      otherThread.planArtifact?.hasContent ?? false,
      isFalse,
      reason:
          'persisting to the visible thread is why the user saw no plan: the '
          'draft was filed under the thread they had just opened',
    );

    expect(
      dataSource.systemPrompts.length,
      greaterThanOrEqualTo(2),
      reason: 'the workflow proposal landed, so the task proposal follows',
    );
    // The first request goes out before the switch; the later ones are the
    // ones that used to inherit the newly visible thread.
    for (final prompt in dataSource.systemPrompts.skip(1)) {
      expect(
        prompt,
        contains(_projectARoot),
        reason: 'the draft must keep describing the project it was started on',
      );
      expect(
        prompt,
        isNot(contains(_projectBRoot)),
        reason:
            'this is the live 2026-07-25 failure: the run19 draft proposed '
            'against run20 once that thread became visible',
      );
    }
  });

  test('a finished background turn hands its thread back complete', () async {
    // Observed live on 2026-07-26 (build 08199a3b), with two coding threads
    // running at once. The thread the user was not reading finished its turn —
    // the conversation store proves it, and so does the session log's final
    // response — yet opening that thread showed the transcript snapshot taken
    // when the user left it, under a spinner that never stopped. Quitting and
    // relaunching the app healed both, because startup reads the store while a
    // thread switch prefers the in-flight registration.
    //
    // So the invariant is: once a background turn is over, its thread must
    // present what the turn produced, and must not still look busy.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource(
      finalContent: 'ANSWER-FROM-THE-BACKGROUND-TURN',
    );
    final toolService = _SwitchingToolService(() async {
      // The user opens another thread while the first thread's tool runs.
      container
          .read(conversationsNotifierProvider.notifier)
          .createNewConversation(
            workspaceMode: WorkspaceMode.coding,
            projectId: 'project-b',
          );
      await Future<void>.delayed(Duration.zero);
    });

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    final conversations = container.read(conversationsNotifierProvider.notifier);
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final backgroundThreadId =
        container.read(conversationsNotifierProvider).currentConversation!.id;
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.sendMessage('list the project');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      toolService.executions,
      greaterThan(0),
      reason: 'the tool has to run for the thread switch to interleave',
    );

    // The user goes back to the thread that was working.
    conversations.selectConversation(backgroundThreadId);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(chatNotifierProvider);
    expect(
      state.messages.map((message) => message.content).join('\n'),
      contains('ANSWER-FROM-THE-BACKGROUND-TURN'),
      reason:
          'the turn finished while this thread was in the background, so its '
          'answer has to be here — showing the snapshot taken at switch time '
          'is the data loss the user sees until an app restart',
    );
    expect(
      state.isLoading,
      isFalse,
      reason:
          'the turn is over, so the thread must not come back holding a '
          'spinner and a stop button',
    );
    expect(
      state.busyConversationIds,
      isNot(contains(backgroundThreadId)),
      reason: 'a finished turn must not leave its thread listed as busy',
    );
  });

  test('an ephemeral hidden-prompt turn releases its thread', () async {
    // The branch that drops a hidden prompt's answer from the visible history
    // (chat_notifier.dart, "Hidden prompt responses are ephemeral") returns
    // without releasing the turn's active-response registration. A registration
    // that outlives its turn is what a thread switch shows instead of the
    // persisted transcript, and what the spinner is derived from — so the
    // thread is left looking busy, on a frozen snapshot, until the app is
    // relaunched.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource(finalContent: 'EPHEMERAL-ANSWER');
    final toolService = _SwitchingToolService(() async {});

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    final conversations = container.read(conversationsNotifierProvider.notifier);
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final threadId =
        container.read(conversationsNotifierProvider).currentConversation!.id;
    final notifier = container.read(chatNotifierProvider.notifier);

    await notifier.sendHiddenPrompt('check on the build');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      container.read(chatNotifierProvider).busyConversationIds,
      isNot(contains(threadId)),
      reason:
          'the hidden turn is over, so its registration has to be handed back; '
          'holding it keeps the thread spinning and freezes what a switch back '
          'to it will show',
    );
    expect(
      container.read(chatNotifierProvider).isLoading,
      isFalse,
      reason: 'nothing is running once the hidden turn has finished',
    );
  });

  test('a background plan decision waits on its own thread', () async {
    // Measured live 2026-07-27 (gen-5): plan drafting raised its decision
    // prompt with a bare `state = state.copyWith(...)`, so a background draft's
    // question landed on whichever thread was on screen, and that thread's own
    // flow cleared it moments later. Nothing could reach the completer after
    // that, so the turn kept its registration, its runtime handle and its
    // workspace lease until the app was quit.
    late final ProviderContainer container;
    final dataSource = _RecordingDataSource();
    final toolService = _SwitchingToolService(() async {});

    container = _buildContainer(
      dataSource: dataSource,
      toolService: toolService,
    );
    addTearDown(container.dispose);

    final conversations = container.read(conversationsNotifierProvider.notifier);
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-a',
    );
    final draftingThread =
        container.read(conversationsNotifierProvider).currentConversation!.id;
    final notifier = container.read(chatNotifierProvider.notifier);

    // The user opens another thread, and only then does the background draft
    // reach its question. Raising it while the drafting thread is still on
    // screen proves nothing: the un-routed write lands on the right thread by
    // accident and the negative control passes.
    conversations.createNewConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-b',
    );
    final answer = TurnThread.runScoped(
      draftingThread,
      () => notifier.requestWorkflowDecision(
        decision: const WorkflowPlanningDecision(
          id: 'decision-1',
          question: 'Which runtime?',
          options: <WorkflowPlanningDecisionOption>[
            WorkflowPlanningDecisionOption(id: 'dart', label: 'Dart'),
            WorkflowPlanningDecisionOption(id: 'node', label: 'Node'),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      container.read(chatNotifierProvider).pendingWorkflowDecision,
      isNull,
      reason:
          'the question belongs to the other thread, so it must not be put in '
          'front of the thread the user is reading',
    );
    expect(
      container.read(chatNotifierProvider).approvalRequiredConversationIds,
      contains(draftingThread),
      reason:
          'the drafting thread has stopped and cannot proceed alone, so the '
          'sidebar has to say so rather than spin',
    );

    // Going back to it hands the question over, and answering completes the
    // turn's future instead of stranding it.
    conversations.selectConversation(draftingThread);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final restored = container.read(chatNotifierProvider).pendingWorkflowDecision;
    expect(
      restored,
      isNotNull,
      reason: 'opening the thread must present the question it is waiting on',
    );
    notifier.resolveWorkflowDecision(
      id: restored!.id,
      answer: const WorkflowPlanningDecisionAnswer(
        decisionId: 'decision-1',
        question: 'Which runtime?',
        optionId: 'dart',
        optionLabel: 'Dart',
      ),
    );

    expect(
      await answer.timeout(const Duration(seconds: 2)),
      isNotNull,
      reason:
          'the drafting turn must resume; a completer nobody can reach is what '
          'held the registration, runtime handle and workspace lease open',
    );
  });
}
