part of 'chat_presentation_providers_tiny_test.dart';

final class _TestSettingsNotifierChatNotifierPythonAttachmentRepair
    extends SettingsNotifier {
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

void _runChatNotifierPythonAttachmentRepair() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'repair adapter uses the registered owner instead of the visible thread',
    () {
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _TestSettingsNotifierChatNotifierPythonAttachmentRepair.new,
          ),
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
