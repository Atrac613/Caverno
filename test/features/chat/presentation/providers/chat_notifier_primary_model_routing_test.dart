import 'dart:async';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_data_source_provider.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coding turn uses one captured endpoint model and harness', () async {
    final primary = _RecordingDataSource(content: 'primary');
    final assigned = _RecordingDataSource(content: 'assigned');
    final container = _container(primary: primary, assigned: assigned);
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);

    final owner = await notifier.sendMessage('Implement the change');
    expect(owner, isNotNull);
    await notifier.waitForTurnCompletion(owner!);

    expect(primary.models, isEmpty);
    expect(assigned.models, ['quality-model']);
    expect(assigned.systemPrompts.single, contains('QUALITY ROUTE HARNESS'));
    expect(notifier.primaryRouteCountForTest(), 0);
    expect(
      container.read(chatNotifierProvider).messages.last.content,
      'assigned',
    );
  });

  test('assigned endpoint failure completes on the primary model', () async {
    final primary = _RecordingDataSource(content: 'fallback');
    final assigned = _RecordingDataSource(
      content: 'unused',
      streamError: StateError('connection refused'),
    );
    final container = _container(primary: primary, assigned: assigned);
    addTearDown(container.dispose);
    final notifier = container.read(chatNotifierProvider.notifier);

    final owner = await notifier.sendMessage('Implement the change');
    expect(owner, isNotNull);
    await notifier.waitForTurnCompletion(owner!);

    expect(assigned.models, ['quality-model']);
    expect(primary.models, ['main-model']);
    expect(
      container.read(chatNotifierProvider).messages.last.content,
      'fallback',
    );
    expect(notifier.primaryRouteCountForTest(), 0);
  });
}

ProviderContainer _container({
  required _RecordingDataSource primary,
  required _RecordingDataSource assigned,
}) {
  final lifecycle = _MockAppLifecycleService();
  when(() => lifecycle.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(_RoutingSettingsNotifier.new),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepository(),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(primary),
      primaryRouteEndpointDataSourceFactoryProvider.overrideWithValue(
        ({required baseUrl, required apiKey, required endpointId}) => assigned,
      ),
      sessionMemoryServiceProvider.overrideWithValue(_TestMemoryService()),
      mcpToolServiceProvider.overrideWithValue(null),
      appLifecycleServiceProvider.overrideWithValue(lifecycle),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
    ],
  );
}

final class _RoutingSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    demoMode: true,
    enableLlmSessionLogs: false,
    mcpEnabled: false,
    assistantMode: AssistantMode.coding,
    baseUrl: 'http://primary.example/v1',
    model: 'main-model',
    codingPrimaryModel: 'quality-model',
    codingPrimaryEndpointId: 'quality-host',
    llmEndpoints: const [
      LlmEndpoint(
        id: 'quality-host',
        baseUrl: 'http://quality.example/v1',
        model: 'quality-model',
      ),
    ],
    modelHarnessConfigs: const [
      ModelHarnessConfig(
        id: 'quality-route-harness',
        provider: LlmProvider.openAiCompatible,
        baseUrl: 'http://quality.example/v1',
        model: 'quality-model',
        bootstrapInstruction: 'QUALITY ROUTE HARNESS',
      ),
    ],
  );
}

final class _RecordingDataSource extends ChatDataSource {
  _RecordingDataSource({required this.content, this.streamError});

  final String content;
  final Object? streamError;
  final List<String?> models = <String?>[];
  final List<String> systemPrompts = <String>[];

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    models.add(model);
    systemPrompts.add(
      messages
          .where((message) => message.role == MessageRole.system)
          .map((message) => message.content)
          .join('\n'),
    );
    Stream<String> stream() async* {
      final error = streamError;
      if (error != null) throw error;
      yield content;
    }

    return StreamedChatCompletion.fromStream(stream(), finishReason: 'stop');
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => ChatCompletionResult(content: content, finishReason: 'stop');

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
}

final class _MockMemoryBox extends Mock implements Box<String> {}

final class _MockConversationBox extends Mock implements Box<String> {}

final class _MockAppLifecycleService extends Mock
    implements AppLifecycleService {}

final class _TestMemoryService extends SessionMemoryService {
  _TestMemoryService() : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

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

final class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());
  final Map<String, Conversation> _store = <String, Conversation>{};

  @override
  List<Conversation> getAll() => _store.values.toList(growable: false);
  @override
  Conversation? getById(String id) => _store[id];
  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async => _store.remove(id);
  @override
  Future<void> deleteAll() async => _store.clear();
}

final class _TestBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}
  @override
  Future<void> endBackgroundTask() async {}
  @override
  void dispose() {}
}
