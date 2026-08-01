import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/active_response_registry.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

class _MockBox extends Mock implements Box<String> {}

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

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    enableLlmSessionLogs: false,
    assistantMode: AssistantMode.general,
    mcpEnabled: false,
    demoMode: false,
  );
}

/// Streams one short answer, so a turn starts and finishes normally.
class _StreamingDataSource implements ChatDataSource {
  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(
    Stream<String>.value('done'),
    finishReason: 'stop',
  );

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => ChatCompletionResult(content: '', finishReason: 'stop');

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

void main() {
  test('a detached response finishing clears the visible thread spinner', () {
    // Regression for the stall observed 2026-07-25: a turn finalized through
    // the detached path (run_completed with no turn_exit) left isLoading set
    // because the finished response belonged to another conversation, so both
    // the composer and the sidebar spinner ran forever.
    const visible = 'conversation-visible';
    final state = ChatState.initial().copyWith(
      isLoading: true,
      busyConversationIds: const <String>{},
    );

    expect(
      chatStateReportsConversationBusy(
        state: state,
        targetConversationId: visible,
        visibleConversationId: visible,
      ),
      isTrue,
      reason: 'this is the stuck state: nothing registered, isLoading stale',
    );
    expect(
      chatStateReportsConversationBusy(
        state: state.copyWith(isLoading: false),
        targetConversationId: visible,
        visibleConversationId: visible,
      ),
      isFalse,
      reason: 'clearing isLoading is what stops both spinners',
    );
  });

  test('a finished turn clears the thread busy state observably', () async {
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

    final container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationBoxProvider.overrideWithValue(conversationBox),
        conversationsNotifierProvider.overrideWith(ConversationsNotifier.new),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(_StreamingDataSource()),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // The thread list rebuilds from these emissions alone, so the busy flag
    // has to be visible in one of them — the registry is not observable.
    final busySnapshots = <Set<String>>[];
    container.listen(chatNotifierProvider, (previous, next) {
      busySnapshots.add(next.busyConversationIds);
    }, fireImmediately: true);

    final notifier = container.read(chatNotifierProvider.notifier);
    await notifier.sendMessage('hello');
    // Finalization continues past the send future (persistence, memory), so
    // give those continuations a bounded chance to run.
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (container
            .read(chatNotifierProvider)
            .busyConversationIds
            .isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(
      busySnapshots.any((snapshot) => snapshot.isNotEmpty),
      isTrue,
      reason: 'the running turn must be observable as busy',
    );
    expect(
      busySnapshots.last,
      isEmpty,
      reason:
          'the last emission must report the thread idle, otherwise the '
          'sidebar spinner keeps animating after the turn finished',
    );
    expect(container.read(chatNotifierProvider).busyConversationIds, isEmpty);
  });
}
