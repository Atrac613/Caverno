part of 'chat_notifier_test.dart';

class _TurnRollbackMcpToolService extends McpToolService {
  int previewCalls = 0;
  int rollbackCalls = 0;

  @override
  Future<FileTurnRollbackPreview?> previewLastFileTurnCheckpoint() async {
    previewCalls += 1;
    return const FileTurnRollbackPreview(
      turnId: 'turn-1',
      paths: ['/tmp/project/lib/main.dart'],
      preview: 'diff --git a/lib/main.dart b/lib/main.dart',
      summary: 'Revert the last agent turn file change.',
    );
  }

  @override
  Future<McpToolResult> rollbackLastFileTurnCheckpoint() async {
    rollbackCalls += 1;
    return const McpToolResult(
      toolName: 'rollback_last_turn_file_changes',
      result: '{"ok":true}',
      isSuccess: true,
    );
  }
}

void registerChatNotifierTurnRollbackTests() {
  test('turn rollback handler reports missing checkpoint service', () async {
    final controller = StreamController<String>();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(controller),
        ),
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
    addTearDown(() async {
      threadContainer.dispose();
      if (controller.hasListener) {
        await controller.close();
      } else {
        unawaited(controller.close());
      }
    });

    final threadNotifier = threadContainer.read(chatNotifierProvider.notifier);
    final rollbackResult = await threadNotifier.rollbackLastFileTurnChanges();

    expect(rollbackResult.isSuccess, isFalse);
    expect(
      rollbackResult.errorMessage,
      'No file checkpoint service is available',
    );
  });

  test(
    'turn rollback handler delegates preview and rollback to tool service',
    () async {
      final toolService = _TurnRollbackMcpToolService();
      final controller = StreamController<String>();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(
            _StreamingChatDataSource(controller),
          ),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        threadContainer.dispose();
        if (controller.hasListener) {
          await controller.close();
        } else {
          unawaited(controller.close());
        }
      });

      final threadNotifier = threadContainer.read(
        chatNotifierProvider.notifier,
      );
      final preview = await threadNotifier.previewLastFileTurnRollback();
      final rollbackResult = await threadNotifier.rollbackLastFileTurnChanges();

      expect(preview, isNotNull);
      expect(preview!.turnId, 'turn-1');
      expect(rollbackResult.isSuccess, isTrue);
      expect(toolService.previewCalls, 1);
      expect(toolService.rollbackCalls, 1);
    },
  );
}
