import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

// Test doubles mirror the trimmed helpers in chat_notifier_subagent_test.dart;
// this file stays standalone so the chat_notifier_test library keeps its F1
// ratchet headroom.

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockConversationBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _TestBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

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

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
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
  Conversation? getById(String id) => _store[id];

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

/// Planning-session settings with an optional planning-role model assignment.
class _PlanRoleSettingsNotifier extends SettingsNotifier {
  _PlanRoleSettingsNotifier(this.planningModel);

  final String planningModel;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      enableLlmSessionLogs: false,
      assistantMode: AssistantMode.plan,
      mcpEnabled: true,
      demoMode: false,
      model: 'main-model',
      planningModel: planningModel,
    );
  }
}

/// Advertises a tool catalog, so a proposal request that leaks it into the
/// system prompt is detectable.
class _CatalogToolService extends McpToolService {
  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => [
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Read a file.',
        'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
      },
    },
  ];
}

/// Replays queued proposal payloads and records the model each call requested.
class _ModelRecordingProposalDataSource implements ChatDataSource {
  _ModelRecordingProposalDataSource(List<ChatCompletionResult> responses)
    : _responses = Queue<ChatCompletionResult>.from(responses);

  final Queue<ChatCompletionResult> _responses;
  final List<String?> requestedModels = [];
  final List<String> systemPrompts = [];
  final List<List<Map<String, dynamic>>?> attachedTools = [];

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requestedModels.add(model);
    attachedTools.add(tools);
    systemPrompts.add(
      messages
          .where((message) => message.role == MessageRole.system)
          .map((message) => message.content)
          .join('\n'),
    );
    return _responses.removeFirst();
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

ProviderContainer _buildPlanContainer({
  required ChatDataSource dataSource,
  required String planningModel,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _PlanRoleSettingsNotifier(planningModel),
      ),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(dataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifier.new,
      ),
      mcpToolServiceProvider.overrideWithValue(_CatalogToolService()),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
    ],
  );
}

_ModelRecordingProposalDataSource _proposalDataSource() {
  return _ModelRecordingProposalDataSource([
    ChatCompletionResult(
      content:
          '{"kind":"proposal","workflowStage":"plan","goal":"Ship the routing slice","constraints":["Keep the change small"],"acceptanceCriteria":["Plan drafting uses the assigned model"],"openQuestions":[]}',
      finishReason: 'stop',
    ),
    ChatCompletionResult(
      content:
          '{"tasks":[{"title":"Route plan drafting to the planning model","targetFiles":["lib/features/chat/presentation/providers/chat_notifier.dart"],"validationCommand":"flutter test","notes":"Cover both proposal calls."},{"title":"Cover the planning role in tests","targetFiles":["test/features/chat/presentation/providers/chat_notifier_plan_model_routing_test.dart"],"validationCommand":"flutter test","notes":"Assert the requested model."}]}',
      finishReason: 'stop',
    ),
  ]);
}

Future<void> _generatePlan(ProviderContainer container) async {
  container
      .read(conversationsNotifierProvider.notifier)
      .activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );
  await container.read(chatNotifierProvider.notifier).generatePlanProposal();
}

void main() {
  test('plan drafting uses the assigned planning model', () async {
    final dataSource = _proposalDataSource();
    final container = _buildPlanContainer(
      dataSource: dataSource,
      planningModel: 'planner-model',
    );

    try {
      await _generatePlan(container);

      expect(
        dataSource.requestedModels,
        everyElement('planner-model'),
        reason:
            'both the workflow and the task proposal run on the planning role',
      );
      expect(dataSource.requestedModels, hasLength(2));
    } finally {
      container.dispose();
    }
  });

  test('plan drafting never advertises tools it cannot attach', () async {
    final dataSource = _proposalDataSource();
    final container = _buildPlanContainer(
      dataSource: dataSource,
      planningModel: 'planner-model',
    );

    try {
      await _generatePlan(container);

      expect(dataSource.attachedTools, everyElement(isNull));
      for (final prompt in dataSource.systemPrompts) {
        expect(
          prompt,
          isNot(contains('Available tools:')),
          reason:
              'a JSON-only proposal request that carries no tools must not '
              'invite the model to call any',
        );
        expect(prompt, isNot(contains('call tool_search')));
      }
    } finally {
      container.dispose();
    }
  });

  test(
    'plan drafting keeps the main model when the role is unassigned',
    () async {
      final dataSource = _proposalDataSource();
      final container = _buildPlanContainer(
        dataSource: dataSource,
        planningModel: '',
      );

      try {
        await _generatePlan(container);

        expect(dataSource.requestedModels, everyElement('main-model'));
        expect(dataSource.requestedModels, hasLength(2));
      } finally {
        container.dispose();
      }
    },
  );
}
