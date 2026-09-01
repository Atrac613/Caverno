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
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_detector.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _ownerProjectRoot = '/tmp/caverno-snapshot-owner-a';
const _ownerWorkflow = 'OWNER_A_WORKFLOW_TOKEN';
const _visiblePoison = 'VISIBLE_B_MESSAGE_POISON';

class _MockBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _MockNotificationService extends Mock implements NotificationService {}

final class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

final class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(ChatMemoryRepository.fromBox(_MockBox()));

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

final class _SnapshotSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.general,
    mcpEnabled: true,
    demoMode: false,
    enableLlmSessionLogs: false,
  );
}

final class _OwnerProjectNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() {
    final now = DateTime(2026, 7, 28);
    return CodingProjectsState(
      projects: [
        CodingProject(
          id: 'project-a',
          name: 'Owner A Project',
          rootPath: _ownerProjectRoot,
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

final class _SnapshotToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    for (final name in const ['read_file', 'update_goal'])
      {
        'type': 'function',
        'function': {
          'name': name,
          'description': 'Snapshot adoption test tool',
          'parameters': const <String, dynamic>{'type': 'object'},
        },
      },
  ];

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) {
    throw StateError('No tool execution is expected in this test.');
  }
}

final class _RequestProbe {
  const _RequestProbe({
    required this.messages,
    required this.context,
    required this.toolResults,
  });

  final List<Message> messages;
  final LlmSessionLogContext? context;
  final List<ToolResultInfo> toolResults;
}

final class _SnapshotProbeDataSource
    implements ChatDataSource, FinishReasonAware {
  _SnapshotProbeDataSource({required this.initialContent});

  final String initialContent;
  final String recoveryContent = 'Owner A recovery completed.';
  final Completer<void> initialRequestSeen = Completer<void>();
  final Completer<void> releaseInitialCompletion = Completer<void>();
  final List<_RequestProbe> requests = [];

  @override
  String? get lastFinishReason => 'stop';

  void _record(
    List<Message> messages, {
    List<ToolResultInfo> toolResults = const [],
  }) {
    requests.add(
      _RequestProbe(
        messages: List<Message>.from(messages),
        context: LlmSessionLogContext.current,
        toolResults: List<ToolResultInfo>.from(toolResults),
      ),
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
    _record(messages);
    if (!initialRequestSeen.isCompleted) initialRequestSeen.complete();
    return StreamWithToolsResult(
      stream: Stream<String>.value(initialContent),
      completion: releaseInitialCompletion.future.then(
        (_) =>
            ChatCompletionResult(content: initialContent, finishReason: 'stop'),
      ),
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
    _record(messages, toolResults: toolResults);
    return ChatCompletionResult(content: recoveryContent, finishReason: 'stop');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'detached continuation uses owner messages, mode, workflow, and log context',
    () async {
      final dataSource = _SnapshotProbeDataSource(
        initialContent:
            'Next I will read the project Dart file and continue implementation.',
      );
      final fixture = await _buildFixture(dataSource);
      addTearDown(fixture.container.dispose);

      final send = fixture.notifier.sendMessage('continue');
      await dataSource.initialRequestSeen.future;
      fixture.conversations.selectConversation(fixture.visibleConversationId);
      await Future<void>.delayed(Duration.zero);
      dataSource.releaseInitialCompletion.complete();
      await send.timeout(const Duration(seconds: 2));

      expect(dataSource.requests, hasLength(2));
      final recovery = dataSource.requests.last;
      expect(
        recovery.toolResults.single.result,
        contains('prose_only_coding_continuation'),
      );
      _expectOwnerRequest(recovery, fixture.ownerConversationId);
    },
  );

  test(
    'detached structured deferral uses the owner auto-continue workflow',
    () async {
      final dataSource = _SnapshotProbeDataSource(
        initialContent: '''
Next implementation step:
1. Read lib/owner_a.dart
2. Implement the owner A project change
''',
      );
      final fixture = await _buildFixture(dataSource, activeAutoGoal: true);
      addTearDown(fixture.container.dispose);

      final send = fixture.notifier.sendMessage('Implement the owner A task.');
      await dataSource.initialRequestSeen.future;
      fixture.conversations.selectConversation(fixture.visibleConversationId);
      await Future<void>.delayed(Duration.zero);
      dataSource.releaseInitialCompletion.complete();
      await send.timeout(const Duration(seconds: 2));

      expect(dataSource.requests, hasLength(2));
      expect(
        dataSource.requests.last.toolResults.single.result,
        contains('prose_only_coding_continuation'),
      );
      _expectOwnerRequest(
        dataSource.requests.last,
        fixture.ownerConversationId,
      );
    },
  );

  test(
    'restricted detached turn does not inherit command tools from visible state',
    () async {
      const claim =
          'The flutter build completed successfully and the IPA was uploaded.';
      final dataSource = _SnapshotProbeDataSource(initialContent: claim);
      final fixture = await _buildFixture(dataSource);
      addTearDown(fixture.container.dispose);

      final send = fixture.notifier.sendHiddenPrompt(
        'Summarize the owner A goal.',
        persistAssistantResponse: true,
        allowedToolNames: const {'update_goal'},
      );
      await dataSource.initialRequestSeen.future;
      fixture.conversations.selectConversation(fixture.visibleConversationId);
      await Future<void>.delayed(Duration.zero);
      dataSource.releaseInitialCompletion.complete();
      await send.timeout(const Duration(seconds: 2));

      expect(dataSource.requests, hasLength(1));
      expect(
        dataSource.requests.single.context?.conversationId,
        fixture.ownerConversationId,
      );
      final owner = fixture.container
          .read(conversationsNotifierProvider)
          .conversations
          .singleWhere(
            (conversation) => conversation.id == fixture.ownerConversationId,
          );
      expect(owner.messages.last.content, contains(claim));
      expect(
        owner.messages.last.content,
        isNot(contains(FinalAnswerClaimDetector.unexecutedCommandActionNotice)),
      );
    },
  );
}

typedef _Fixture = ({
  ProviderContainer container,
  ChatNotifier notifier,
  ConversationsNotifier conversations,
  String ownerConversationId,
  String visibleConversationId,
});

Future<_Fixture> _buildFixture(
  _SnapshotProbeDataSource dataSource, {
  bool activeAutoGoal = false,
}) async {
  final conversationBox = _MockBox();
  final storage = <String, String>{};
  when(() => conversationBox.keys).thenAnswer((_) => storage.keys);
  when(
    () => conversationBox.get(any()),
  ).thenAnswer((call) => storage[call.positionalArguments.first]);
  when(() => conversationBox.put(any(), any())).thenAnswer((call) async {
    storage[call.positionalArguments[0] as String] =
        call.positionalArguments[1] as String;
  });

  final lifecycle = _MockAppLifecycleService();
  when(() => lifecycle.isInBackground).thenReturn(false);
  final notifications = _MockNotificationService();
  when(
    () => notifications.showApprovalRequiredNotification(
      conversationId: any(named: 'conversationId'),
      title: any(named: 'title'),
      body: any(named: 'body'),
      approvalId: any(named: 'approvalId'),
      allowsDirectDecision: any(named: 'allowsDirectDecision'),
    ),
  ).thenAnswer((_) async {});

  final container = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(_SnapshotSettingsNotifier.new),
      conversationBoxProvider.overrideWithValue(conversationBox),
      conversationsNotifierProvider.overrideWith(ConversationsNotifier.new),
      codingProjectsNotifierProvider.overrideWith(_OwnerProjectNotifier.new),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(_SnapshotToolService()),
      appLifecycleServiceProvider.overrideWithValue(lifecycle),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(notifications),
    ],
  );
  final conversations = container.read(conversationsNotifierProvider.notifier);
  conversations.createNewConversation(
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-a',
  );
  final ownerConversationId = container
      .read(conversationsNotifierProvider)
      .currentConversationId!;
  await conversations.updateCurrentWorkflow(
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: const ConversationWorkflowSpec(
      goal: _ownerWorkflow,
      tasks: [
        ConversationWorkflowTask(
          id: 'owner-a-task',
          title: 'Implement owner A',
          targetFiles: ['lib/owner_a.dart'],
          validationCommand: 'flutter test test/owner_a_test.dart',
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    ),
  );
  if (activeAutoGoal) {
    await conversations.saveCurrentGoal(
      objective: 'Complete the owner A workflow',
      enabled: true,
      autoContinue: true,
      status: ConversationGoalStatus.active,
      turnBudget: 4,
    );
  }

  conversations.createNewConversation(workspaceMode: WorkspaceMode.chat);
  final visibleConversationId = container
      .read(conversationsNotifierProvider)
      .currentConversationId!;
  await conversations.updateConversationMessages(visibleConversationId, [
    Message(
      id: 'visible-b-message',
      content: _visiblePoison,
      role: MessageRole.user,
      timestamp: DateTime(2026, 7, 28, 12),
    ),
  ]);
  conversations.selectConversation(ownerConversationId);
  await Future<void>.delayed(Duration.zero);
  final notifier = container.read(chatNotifierProvider.notifier);
  return (
    container: container,
    notifier: notifier,
    conversations: conversations,
    ownerConversationId: ownerConversationId,
    visibleConversationId: visibleConversationId,
  );
}

void _expectOwnerRequest(_RequestProbe request, String ownerConversationId) {
  expect(request.context?.conversationId, ownerConversationId);
  expect(request.context?.workspaceMode, WorkspaceMode.coding);
  final prompt = request.messages.map((message) => message.content).join('\n');
  expect(prompt, contains('continue'));
  expect(prompt, contains(_ownerProjectRoot));
  expect(prompt, contains(_ownerWorkflow));
  expect(prompt, isNot(contains(_visiblePoison)));
}
