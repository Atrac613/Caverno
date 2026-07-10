part of 'chat_notifier_test.dart';

void registerChatNotifierAnalysisOptionsLintGuardTests() {
  test(
    'sendMessage blocks an analysis options lint edit without matching diagnostics',
    () async {
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_analysis_options_lint_guard_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 7, 10),
        updatedAt: DateTime(2026, 7, 10),
      );
      final diagnostics = ToolResultInfo(
        id: 'diagnostics-1',
        name: CodingDiagnosticFeedbackService.toolName,
        arguments: const {},
        result: jsonEncode({
          'schema': CodingDiagnosticFeedbackService.schemaName,
          'diagnostics': const [
            {'code': 'prefer_initializing_formals'},
          ],
        }),
      );
      final dataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'write-dart',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'void main() {}\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Suppress the warning.',
            toolCalls: [
              ToolCallInfo(
                id: 'edit-analysis-options',
                name: 'edit_file',
                arguments: const {
                  'path': 'analysis_options.yaml',
                  'old_text': 'include: package:lints/recommended.yaml',
                  'new_text': '''
include: package:lints/recommended.yaml

linter:
  rules:
    prefer_typing_uninitialized_variables: false
''',
                  'reason': 'Suppress unused_element.',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The unsupported suppression was not applied.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"lib/main.dart","bytes_written":15}',
          'edit_file': '{"path":"analysis_options.yaml","replacements":1}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final guardContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(diagnostics),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            _FakeCodingVerificationFeedbackService(null),
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(guardContainer.dispose);

      guardContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      await guardContainer
          .read(chatNotifierProvider.notifier)
          .sendMessage('Fix the Dart file');

      expect(toolService.executedToolNames, ['write_file']);
      final blockedResult = dataSource.toolResultBatches
          .expand((batch) => batch)
          .singleWhere((result) => result.id == 'edit-analysis-options');
      final payload = jsonDecode(blockedResult.result) as Map<String, dynamic>;
      expect(payload['code'], AnalysisOptionsLintEditIssue.code);
      expect(payload['error'], isNotEmpty);
      expect(payload['ungrounded_rules'], [
        'prefer_typing_uninitialized_variables',
      ]);
      expect(payload['observed_diagnostic_codes'], [
        'prefer_initializing_formals',
      ]);
    },
  );
}
