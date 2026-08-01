import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/demo_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/key_value_store.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

final class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    enableLlmSessionLogs: false,
    mcpEnabled: false,
    demoMode: true,
  );
}

final class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();
}

final class _EmptyKeyValueStore implements KeyValueStore {
  @override
  bool get isReady => false;

  @override
  String? get(String key) => null;

  @override
  Future<void> refresh(Iterable<String> keys) async {}

  @override
  Future<void> put(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'repair adapter uses the registered owner instead of the visible thread',
    () {
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(DemoDataSource()),
          sessionMemoryServiceProvider.overrideWithValue(
            SessionMemoryService(ChatMemoryRepository(_EmptyKeyValueStore())),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(chatNotifierProvider.notifier);
      const pythonToolDefinitions = <Map<String, dynamic>>[
        {
          'type': 'function',
          'function': {'name': 'run_python_script'},
        },
      ];
      final timestamp = DateTime(2026, 7, 30, 10);

      notifier.syncConversation(
        conversationId: 'visible-thread-b',
        messages: [
          Message(
            id: 'visible-attachment',
            content: 'Use Python to analyze the metadata.',
            role: MessageRole.user,
            timestamp: timestamp,
            imageBase64: 'AQ==',
            imageMimeType: 'image/png',
          ),
        ],
      );

      expect(
        notifier.shouldRepairSkippedPythonAttachmentAnalysisForOwnerForTest(
          ownerConversationId: 'registered-owner-a',
          ownerMessages: [
            Message(
              id: 'owner-without-attachment',
              content: 'Use run_python_script to inspect the metadata.',
              role: MessageRole.user,
              timestamp: timestamp,
            ),
          ],
          candidateResponse: 'I will inspect the attachment.',
          tools: pythonToolDefinitions,
        ),
        isFalse,
      );

      notifier.syncConversation(
        conversationId: 'visible-thread-b',
        messages: [
          Message(
            id: 'visible-without-attachment',
            content: 'Summarize this conversation.',
            role: MessageRole.user,
            timestamp: timestamp,
          ),
        ],
      );

      expect(
        notifier.shouldRepairSkippedPythonAttachmentAnalysisForOwnerForTest(
          ownerConversationId: 'registered-owner-a',
          ownerMessages: [
            Message(
              id: 'owner-attachment',
              content: 'Use run_python_script to inspect the metadata.',
              role: MessageRole.user,
              timestamp: timestamp,
              originalImagePath: '/tmp/registered-owner-a.png',
              originalImageMimeType: 'image/png',
            ),
          ],
          candidateResponse: 'I will inspect the attachment.',
          tools: pythonToolDefinitions,
        ),
        isTrue,
      );
    },
  );
}
