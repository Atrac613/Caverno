import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final file = File('$path/${locale.languageCode}.json');
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _WorkflowSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.coding,
    demoMode: false,
    mcpEnabled: false,
  );
}

class _WorkflowCodingProjectsNotifier extends CodingProjectsNotifier {
  _WorkflowCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);
}

class _WorkflowConversationsNotifier extends ConversationsNotifier {
  _WorkflowConversationsNotifier(this.conversation);

  final Conversation conversation;
  final List<String> assistantEvidenceTaskIds = [];

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );

  @override
  Future<void> updateCurrentPlanArtifact({
    ConversationPlanArtifact? planArtifact,
    bool clearPlanArtifact = false,
  }) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    final updated = current.copyWith(
      planArtifact: clearPlanArtifact ? null : planArtifact,
      updatedAt: DateTime(2026, 7, 15, 15, 30),
    );
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }

  @override
  Future<bool> refreshCurrentWorkflowProjectionFromApprovedPlan() async => true;

  @override
  Future<void> exitPlanningSession() async {}

  @override
  Future<void> updateCurrentWorkflow({
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowSpec? workflowSpec,
    String? workflowSourceHash,
    DateTime? workflowDerivedAt,
    bool clearWorkflowSpec = false,
    bool preserveWorkflowProjection = false,
  }) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    final updated = current.copyWith(
      workflowStage: workflowStage ?? current.workflowStage,
      workflowSpec: clearWorkflowSpec
          ? null
          : workflowSpec ?? current.workflowSpec,
      workflowSourceHash: workflowSourceHash ?? current.workflowSourceHash,
      workflowDerivedAt: workflowDerivedAt ?? current.workflowDerivedAt,
      updatedAt: DateTime(2026, 7, 15, 15, 30),
    );
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }

  @override
  Future<void> updateCurrentExecutionTaskProgress({
    required String taskId,
    required ConversationWorkflowTaskStatus status,
    bool allowStatusRegression = false,
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    ConversationExecutionValidationStatus? validationStatus,
    String? summary,
    String? blockedReason,
    String? lastValidationCommand,
    String? lastValidationSummary,
    ConversationExecutionTaskEventType? eventType,
    String? eventSummary,
    DateTime? eventTimestamp,
  }) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    final progress = [
      ...current.effectiveExecutionProgress.where(
        (item) => item.taskId != taskId,
      ),
      ConversationExecutionTaskProgress(
        taskId: taskId,
        status: status,
        validationStatus:
            validationStatus ?? ConversationExecutionValidationStatus.unknown,
        updatedAt: DateTime(2026, 7, 15, 15, 30),
        lastRunAt: lastRunAt,
        lastValidationAt: lastValidationAt,
        summary: summary ?? '',
        blockedReason: blockedReason ?? '',
        lastValidationCommand: lastValidationCommand ?? '',
        lastValidationSummary: lastValidationSummary ?? '',
      ),
    ];
    final updated = current.copyWith(
      executionProgress: progress,
      updatedAt: DateTime(2026, 7, 15, 15, 30),
    );
    state = state.copyWith(
      conversations: [updated],
      currentConversationId: updated.id,
    );
  }

  @override
  Future<void> updateCurrentExecutionTaskProgressFromAssistantTurn({
    required ConversationWorkflowTask task,
    required String assistantResponse,
    required bool isValidationRun,
    String? fallbackAssistantResponse,
  }) async {
    assistantEvidenceTaskIds.add(task.id);
    await super.updateCurrentExecutionTaskProgressFromAssistantTurn(
      task: task,
      assistantResponse: assistantResponse,
      isValidationRun: isValidationRun,
      fallbackAssistantResponse: fallbackAssistantResponse,
    );
  }
}

class _ScriptedWorkflowTurn {
  const _ScriptedWorkflowTurn({
    this.toolResults = const [],
    this.hiddenAssistantResponse,
  });

  final List<ToolResultInfo> toolResults;
  final String? hiddenAssistantResponse;
}

class _ScriptedWorkflowChatNotifier extends ChatNotifier {
  _ScriptedWorkflowChatNotifier({
    required List<_ScriptedWorkflowTurn> visibleTurns,
    List<_ScriptedWorkflowTurn> hiddenTurns = const [],
  }) : _visibleTurns = Queue.of(visibleTurns),
       _hiddenTurns = Queue.of(hiddenTurns);

  final List<String> sentMessages = [];
  final List<String> hiddenPrompts = [];
  final Queue<_ScriptedWorkflowTurn> _visibleTurns;
  final Queue<_ScriptedWorkflowTurn> _hiddenTurns;
  List<ToolResultInfo> _latestToolResults = const [];
  String? _latestHiddenAssistantResponse;
  var hiddenAssistantResponseReadCount = 0;

  bool get hasPendingTurns =>
      _visibleTurns.isNotEmpty || _hiddenTurns.isNotEmpty;

  @override
  ChatState build() => ChatState.initial();

  @override
  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String? originalImagePath,
    String? originalImageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
    ChatInteractionOrigin origin = ChatInteractionOrigin.local,
  }) async {
    sentMessages.add(content);
    _activateNextTurn(_visibleTurns, label: 'visible');
  }

  @override
  Future<void> sendHiddenPrompt(
    String instruction, {
    bool isVoiceMode = false,
    String languageCode = 'en',
    bool persistAssistantResponse = false,
    bool preserveGoalAutoContinueEvidence = false,
    bool replayVerifierImmediatelyAfterMutation = false,
    bool verifierOnlyContinuation = false,
    Set<String>? allowedToolNames,
  }) async {
    hiddenPrompts.add(instruction);
    _activateNextTurn(_hiddenTurns, label: 'hidden');
  }

  @override
  List<ToolResultInfo> takeLatestToolResults() {
    final results = _latestToolResults;
    _latestToolResults = const [];
    return results;
  }

  @override
  String? takeLatestHiddenAssistantResponse() {
    hiddenAssistantResponseReadCount += 1;
    final response = _latestHiddenAssistantResponse;
    _latestHiddenAssistantResponse = null;
    return response;
  }

  void _activateNextTurn(
    Queue<_ScriptedWorkflowTurn> turns, {
    required String label,
  }) {
    if (turns.isEmpty) {
      throw StateError('Unexpected $label workflow turn.');
    }
    final turn = turns.removeFirst();
    _latestToolResults = turn.toolResults;
    _latestHiddenAssistantResponse = turn.hiddenAssistantResponse;
  }
}

class _WorkflowPageHarness {
  const _WorkflowPageHarness({
    required this.container,
    required this.chatNotifier,
  });

  final ProviderContainer container;
  final _ScriptedWorkflowChatNotifier chatNotifier;

  Conversation get conversation =>
      container.read(conversationsNotifierProvider).currentConversation!;

  _WorkflowConversationsNotifier get conversationsNotifier =>
      container.read(conversationsNotifierProvider.notifier)
          as _WorkflowConversationsNotifier;
}

ToolResultInfo _commandResult({
  required String id,
  required String command,
  required int exitCode,
  String stdout = '',
  String stderr = '',
}) {
  return ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: {'command': command},
    result: jsonEncode({
      'command': command,
      'exit_code': exitCode,
      'stdout': stdout,
      'stderr': stderr,
    }),
  );
}

ToolResultInfo _missingPythonRuntimeResult({
  required String id,
  required String command,
}) {
  return _commandResult(
    id: id,
    command: command,
    exitCode: 1,
    stderr:
        'Traceback (most recent call last):\n'
        '  File "main.py", line 3, in <module>\n'
        '    from ping3 import ping\n'
        'ModuleNotFoundError: No module named "ping3"',
  );
}

ToolResultInfo _syntheticUnexecutedCommandResult() {
  return ToolResultInfo(
    id: 'unexecuted-command',
    name: 'local_execute_command',
    arguments: const {
      'reason': 'No matching successful command result was available.',
    },
    result: jsonEncode({
      'ok': false,
      'code': 'unexecuted_command_action',
      'error': 'The requested command was not executed.',
    }),
  );
}

ConversationWorkflowTask _loadFixtureTask(String fixtureName) {
  final fixture =
      jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
          as Map<String, dynamic>;
  return ConversationWorkflowTask.fromJson(
    fixture['task'] as Map<String, dynamic>,
  );
}

List<ToolResultInfo> _loadFixtureToolResults(String fixtureName) {
  final fixture =
      jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
          as Map<String, dynamic>;
  return (fixture['toolResults'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(
        (item) => ToolResultInfo(
          id: item['id'] as String,
          name: item['name'] as String,
          arguments: item['arguments'] as Map<String, dynamic>,
          result: item['result'] as String,
        ),
      )
      .toList(growable: false);
}

String _buildPlanMarkdown(List<ConversationWorkflowTask> tasks) {
  final buffer = StringBuffer()
    ..writeln('# Plan')
    ..writeln()
    ..writeln('## Stage')
    ..writeln('implement')
    ..writeln()
    ..writeln('## Tasks');
  for (var index = 0; index < tasks.length; index += 1) {
    final task = tasks[index];
    buffer
      ..writeln('${index + 1}. ${task.title}')
      ..writeln('   - Task ID: ${task.id}')
      ..writeln('   - Status: pending');
    if (task.validationCommand.trim().isNotEmpty) {
      buffer.writeln('   - Validation: ${task.validationCommand}');
    }
  }
  return buffer.toString();
}

Future<_WorkflowPageHarness> _pumpWorkflowPage(
  WidgetTester tester, {
  required List<ConversationWorkflowTask> tasks,
  required List<_ScriptedWorkflowTurn> visibleTurns,
  List<_ScriptedWorkflowTurn> hiddenTurns = const [],
  List<ConversationExecutionTaskProgress> executionProgress = const [],
  Map<String, String> initialWorkspaceFiles = const {},
  bool approvedPlan = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final projectRoot = Directory.systemTemp.createTempSync(
    'saved_workflow_recovery_test_',
  );
  addTearDown(() {
    if (projectRoot.existsSync()) {
      projectRoot.deleteSync(recursive: true);
    }
  });
  for (final entry in initialWorkspaceFiles.entries) {
    final file = File('${projectRoot.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  final now = DateTime(2026, 7, 15, 15, 25);
  final project = CodingProject(
    id: 'project-1',
    name: 'todo',
    rootPath: projectRoot.path,
    createdAt: now,
    updatedAt: now,
  );
  final planMarkdown = _buildPlanMarkdown(tasks);
  final conversation = Conversation(
    id: 'conversation-1',
    title: 'Workflow test',
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workspaceMode: WorkspaceMode.coding,
    projectId: project.id,
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: ConversationWorkflowSpec(
      goal: 'Complete the saved workflow.',
      tasks: tasks,
    ),
    executionProgress: executionProgress,
    planArtifact: approvedPlan
        ? ConversationPlanArtifact(approvedMarkdown: planMarkdown)
        : ConversationPlanArtifact(draftMarkdown: planMarkdown),
    workflowSourceHash: computeConversationPlanHash(planMarkdown),
    workflowDerivedAt: now,
  );
  final chatNotifier = _ScriptedWorkflowChatNotifier(
    visibleTurns: visibleTurns,
    hiddenTurns: hiddenTurns,
  );

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      settingsNotifierProvider.overrideWith(_WorkflowSettingsNotifier.new),
      conversationsNotifierProvider.overrideWith(
        () => _WorkflowConversationsNotifier(conversation),
      ),
      codingProjectsNotifierProvider.overrideWith(
        () => _WorkflowCodingProjectsNotifier(project),
      ),
      chatNotifierProvider.overrideWith(() => chatNotifier),
      routineSchedulerProvider.overrideWith(RoutineSchedulerController.new),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      saveLocale: false,
      assetLoader: const _TestTranslationLoader(),
      child: Builder(
        builder: (context) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const ChatPage(showDashboardOnStartup: false),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _WorkflowPageHarness(container: container, chatNotifier: chatNotifier);
}

Future<void> _tapWorkflowAction(WidgetTester tester, String label) async {
  final action = find.text(label);
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void _expectSingleRecoveryPrompt(
  _WorkflowPageHarness harness, {
  required String containsText,
  List<String> excludes = const [],
}) {
  expect(harness.chatNotifier.hiddenPrompts, hasLength(1));
  final prompt = harness.chatNotifier.hiddenPrompts.single;
  expect(prompt, contains(containsText));
  for (final excludedText in excludes) {
    expect(prompt, isNot(contains(excludedText)));
  }
  expect(harness.chatNotifier.hasPendingTurns, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  testWidgets(
    'synthetic non-execution result triggers one bounded hidden recovery',
    (tester) async {
      const tasks = [
        ConversationWorkflowTask(
          id: 'request-test',
          title: 'Fulfill the sourced user request',
        ),
      ];
      final harness = await _pumpWorkflowPage(
        tester,
        tasks: tasks,
        visibleTurns: [
          _ScriptedWorkflowTurn(
            toolResults: [_syntheticUnexecutedCommandResult()],
          ),
        ],
        hiddenTurns: const [_ScriptedWorkflowTurn()],
      );

      await _tapWorkflowAction(tester, 'Approve and start');

      expect(harness.chatNotifier.sentMessages, hasLength(1));
      expect(harness.chatNotifier.hiddenPrompts, hasLength(1));
      expect(
        harness.chatNotifier.hiddenPrompts.single,
        contains('stalled without any concrete tool call'),
      );
      expect(
        harness.conversation.projectedExecutionTasks.single.status,
        ConversationWorkflowTaskStatus.inProgress,
      );
      expect(harness.chatNotifier.hasPendingTurns, isFalse);
    },
  );

  testWidgets('target mutation routes to validation-first recovery', (
    tester,
  ) async {
    const validationCommand = 'python3 main.py --help';
    const task = ConversationWorkflowTask(
      id: 'validation-first',
      title: 'Implement the CLI entrypoint',
      targetFiles: ['main.py'],
      validationCommand: validationCommand,
    );
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: const [task],
      visibleTurns: [
        _ScriptedWorkflowTurn(
          toolResults: [
            ToolResultInfo(
              id: 'write-main',
              name: 'write_file',
              arguments: {'path': 'main.py'},
              result:
                  '{"path":"/tmp/project/main.py","bytes_written":24,"created":false}',
            ),
          ],
        ),
      ],
      hiddenTurns: [
        _ScriptedWorkflowTurn(
          toolResults: [
            _commandResult(
              id: 'validate-main',
              command: validationCommand,
              exitCode: 0,
              stdout: 'usage: main.py [-h]',
            ),
          ],
        ),
      ],
      initialWorkspaceFiles: const {'main.py': 'print("ready")\n'},
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    _expectSingleRecoveryPrompt(
      harness,
      containsText: 'The saved task already made concrete file progress.',
      excludes: const [
        'The saved task hit a recoverable tool failure.',
        'Saved task drift detected.',
      ],
    );
    expect(
      harness.conversation.projectedExecutionTasks.single.status,
      ConversationWorkflowTaskStatus.completed,
    );
  });

  testWidgets('tool failure wins over overlapping missing-target recovery', (
    tester,
  ) async {
    const validationCommand = 'python3 main.py --help';
    const task = ConversationWorkflowTask(
      id: 'tool-failure-priority',
      title: 'Implement the CLI entrypoint',
      targetFiles: ['main.py'],
      validationCommand: validationCommand,
    );
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: const [task],
      visibleTurns: [
        _ScriptedWorkflowTurn(
          toolResults: [
            ToolResultInfo(
              id: 'unsupported-google',
              name: 'google',
              arguments: {},
              result: 'Error: No matching tool available: google',
            ),
            _commandResult(
              id: 'missing-main',
              command: validationCommand,
              exitCode: 2,
              stderr:
                  "python3: can't open file '/tmp/project/main.py': [Errno 2] No such file or directory",
            ),
          ],
        ),
      ],
      hiddenTurns: const [
        _ScriptedWorkflowTurn(
          hiddenAssistantResponse:
              'The saved task is blocked because the required tool is unavailable.',
        ),
      ],
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    _expectSingleRecoveryPrompt(
      harness,
      containsText: 'The saved task hit a recoverable tool failure.',
      excludes: const [
        'The saved validation command ran before every required target file existed.',
        'Saved task drift detected.',
      ],
    );
    expect(
      harness.chatNotifier.hiddenPrompts.single,
      contains('Do not call these unavailable tools again: google'),
    );
    expect(
      harness.conversation.projectedExecutionTasks.single.status,
      ConversationWorkflowTaskStatus.blocked,
    );
  });

  testWidgets('failed validation routes to missing-target recovery', (
    tester,
  ) async {
    const fixtureName =
        'plan_mode_ping_cli_missing_main_validation_replay.json';
    final task = _loadFixtureTask(fixtureName);
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: [task],
      visibleTurns: [
        _ScriptedWorkflowTurn(
          toolResults: _loadFixtureToolResults(fixtureName),
        ),
      ],
      hiddenTurns: const [_ScriptedWorkflowTurn()],
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    _expectSingleRecoveryPrompt(
      harness,
      containsText:
          'The saved validation command ran before every required target file existed.',
      excludes: const [
        'The saved task hit a recoverable tool failure.',
        'Missing dependency:',
      ],
    );
    expect(
      harness.chatNotifier.hiddenPrompts.single,
      contains('Missing target files: main.py'),
    );
  });

  testWidgets('missing pytest routes to Python test dependency recovery', (
    tester,
  ) async {
    const fixtureName =
        'plan_mode_ping_cli_pytest_missing_verification_replay.json';
    final task = _loadFixtureTask(fixtureName);
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: [task],
      visibleTurns: [
        _ScriptedWorkflowTurn(
          toolResults: _loadFixtureToolResults(fixtureName),
        ),
      ],
      hiddenTurns: const [_ScriptedWorkflowTurn()],
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    _expectSingleRecoveryPrompt(
      harness,
      containsText:
          'The saved verification command failed because a Python test dependency is unavailable',
      excludes: const [
        'missing runtime module',
        'src-layout module import was not discoverable',
      ],
    );
    expect(
      harness.chatNotifier.hiddenPrompts.single,
      contains('Missing dependency: pytest'),
    );
  });

  testWidgets('src-layout import failure routes to PYTHONPATH recovery', (
    tester,
  ) async {
    const fixtureName =
        'plan_mode_ping_cli_src_layout_import_block_replay.json';
    final task = _loadFixtureTask(fixtureName);
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: [task],
      visibleTurns: [
        _ScriptedWorkflowTurn(
          toolResults: _loadFixtureToolResults(fixtureName),
        ),
      ],
      hiddenTurns: const [_ScriptedWorkflowTurn()],
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    _expectSingleRecoveryPrompt(
      harness,
      containsText:
          'The saved validation command failed because the Python src-layout module import was not discoverable.',
      excludes: const [
        'missing runtime module',
        'Python test dependency is unavailable',
      ],
    );
    expect(
      harness.chatNotifier.hiddenPrompts.single,
      contains('Retry validation command: PYTHONPATH=src'),
    );
  });

  testWidgets('unrelated successful tools route to task-drift recovery', (
    tester,
  ) async {
    const fixtureName = 'plan_mode_ping_cli_execution_stall_replay.json';
    final task = _loadFixtureTask(fixtureName);
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: [task],
      visibleTurns: [
        _ScriptedWorkflowTurn(
          toolResults: _loadFixtureToolResults(fixtureName),
        ),
      ],
      hiddenTurns: const [_ScriptedWorkflowTurn()],
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    _expectSingleRecoveryPrompt(
      harness,
      containsText: 'Saved task drift detected.',
      excludes: const [
        'The saved task already made concrete file progress.',
        'The saved task hit a recoverable tool failure.',
      ],
    );
    expect(
      harness.chatNotifier.hiddenPrompts.single,
      contains('Ignore these unrelated paths: pyproject.toml'),
    );
  });

  testWidgets('hidden assistant fallback is consumed exactly once', (
    tester,
  ) async {
    const task = ConversationWorkflowTask(
      id: 'assistant-fallback',
      title: 'Fulfill the sourced user request',
    );
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: const [task],
      visibleTurns: const [
        _ScriptedWorkflowTurn(
          hiddenAssistantResponse:
              'The saved task is blocked because the required input is unavailable.',
        ),
      ],
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    expect(harness.chatNotifier.hiddenPrompts, isEmpty);
    expect(harness.chatNotifier.hiddenAssistantResponseReadCount, 1);
    expect(harness.conversationsNotifier.assistantEvidenceTaskIds, [task.id]);
    expect(
      harness.conversation.projectedExecutionTasks.single.status,
      ConversationWorkflowTaskStatus.blocked,
    );
    expect(harness.chatNotifier.hasPendingTurns, isFalse);
  });

  testWidgets(
    'successful task evidence auto-continues to the next saved task once',
    (tester) async {
      const firstCommand = 'python3 verify_build.py';
      const secondCommand = 'python3 verify_cli.py';
      const tasks = [
        ConversationWorkflowTask(
          id: 'verify-build',
          title: 'Verify build output',
          validationCommand: firstCommand,
        ),
        ConversationWorkflowTask(
          id: 'verify-cli',
          title: 'Verify CLI behavior',
          validationCommand: secondCommand,
        ),
      ];
      final harness = await _pumpWorkflowPage(
        tester,
        tasks: tasks,
        visibleTurns: [
          _ScriptedWorkflowTurn(
            toolResults: [
              _commandResult(
                id: 'verify-build-result',
                command: firstCommand,
                exitCode: 0,
                stdout: 'Build verification passed.',
              ),
            ],
          ),
        ],
        hiddenTurns: [
          _ScriptedWorkflowTurn(
            toolResults: [
              _commandResult(
                id: 'verify-cli-result',
                command: secondCommand,
                exitCode: 0,
                stdout: 'CLI verification passed.',
              ),
            ],
          ),
        ],
      );

      await _tapWorkflowAction(tester, 'Approve and start');

      expect(harness.chatNotifier.sentMessages, hasLength(1));
      expect(harness.chatNotifier.hiddenPrompts, hasLength(1));
      expect(
        harness.chatNotifier.hiddenPrompts.single,
        contains('Verify CLI behavior'),
      );
      for (final task in harness.conversation.projectedExecutionTasks) {
        expect(task.status, ConversationWorkflowTaskStatus.completed);
        expect(
          harness.conversation
              .executionProgressForTask(task.id)
              ?.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
      }
      expect(harness.chatNotifier.hasPendingTurns, isFalse);
    },
  );

  testWidgets('failed task evidence blocks the task and does not auto-continue', (
    tester,
  ) async {
    const validationCommand = 'python3 verify_current.py';
    const tasks = [
      ConversationWorkflowTask(
        id: 'verify-current',
        title: 'Verify current behavior',
        validationCommand: validationCommand,
      ),
      ConversationWorkflowTask(
        id: 'verify-follow-up',
        title: 'Verify follow-up behavior',
        validationCommand: 'python3 verify_follow_up.py',
      ),
    ];
    final harness = await _pumpWorkflowPage(
      tester,
      tasks: tasks,
      visibleTurns: [
        _ScriptedWorkflowTurn(
          toolResults: [
            _commandResult(
              id: 'failed-validation-result',
              command: validationCommand,
              exitCode: 1,
              stderr: 'AssertionError: expected current behavior.',
            ),
          ],
          hiddenAssistantResponse:
              'Validation failed because the current behavior assertion did not pass.',
        ),
      ],
    );

    await _tapWorkflowAction(tester, 'Approve and start');

    expect(harness.chatNotifier.sentMessages, hasLength(1));
    expect(harness.chatNotifier.hiddenPrompts, isEmpty);
    final projectedTasks = harness.conversation.projectedExecutionTasks;
    expect(projectedTasks.first.status, ConversationWorkflowTaskStatus.blocked);
    expect(
      harness.conversation
          .executionProgressForTask('verify-current')
          ?.blockedReason,
      contains('Validation failed'),
    );
    expect(projectedTasks.last.status, ConversationWorkflowTaskStatus.pending);
    expect(harness.chatNotifier.hasPendingTurns, isFalse);
  });

  testWidgets(
    'successful Python runtime recovery does not reprocess assistant evidence',
    (tester) async {
      const command = 'python3 main.py --help';
      const tasks = [
        ConversationWorkflowTask(
          id: 'runtime-direct',
          title: 'Implement the Python runtime fallback',
          targetFiles: ['main.py'],
          validationCommand: command,
        ),
      ];
      final harness = await _pumpWorkflowPage(
        tester,
        tasks: tasks,
        visibleTurns: [
          _ScriptedWorkflowTurn(
            toolResults: [
              _missingPythonRuntimeResult(
                id: 'missing-runtime-direct',
                command: command,
              ),
            ],
          ),
        ],
        hiddenTurns: [
          _ScriptedWorkflowTurn(
            toolResults: [
              _commandResult(
                id: 'runtime-recovery-direct',
                command: command,
                exitCode: 0,
                stdout: 'usage: main.py [-h]',
              ),
            ],
            hiddenAssistantResponse:
                'Updated main.py to use the standard library and validation passed.',
          ),
        ],
      );

      await _tapWorkflowAction(tester, 'Approve and start');

      expect(harness.chatNotifier.hiddenPrompts, hasLength(1));
      expect(
        harness.chatNotifier.hiddenPrompts.single,
        contains('Missing dependency: ping3'),
      );
      expect(
        harness.conversation.projectedExecutionTasks.single.status,
        ConversationWorkflowTaskStatus.completed,
      );
      expect(
        harness.conversation
            .executionProgressForTask('runtime-direct')
            ?.validationStatus,
        ConversationExecutionValidationStatus.passed,
      );
      expect(harness.conversationsNotifier.assistantEvidenceTaskIds, isEmpty);
      expect(harness.chatNotifier.hiddenAssistantResponseReadCount, 1);
      expect(harness.chatNotifier.hasPendingTurns, isFalse);
    },
  );

  testWidgets(
    'auto-continued Python runtime recovery does not reprocess assistant evidence',
    (tester) async {
      const firstCommand = 'python3 verify_bootstrap.py';
      const runtimeCommand = 'python3 main.py --help';
      const tasks = [
        ConversationWorkflowTask(
          id: 'verify-bootstrap',
          title: 'Verify bootstrap behavior',
          validationCommand: firstCommand,
        ),
        ConversationWorkflowTask(
          id: 'runtime-auto-continue',
          title: 'Implement the Python runtime fallback',
          targetFiles: ['main.py'],
          validationCommand: runtimeCommand,
        ),
      ];
      final harness = await _pumpWorkflowPage(
        tester,
        tasks: tasks,
        visibleTurns: [
          _ScriptedWorkflowTurn(
            toolResults: [
              _commandResult(
                id: 'verify-bootstrap-result',
                command: firstCommand,
                exitCode: 0,
                stdout: 'Bootstrap verification passed.',
              ),
            ],
          ),
        ],
        hiddenTurns: [
          _ScriptedWorkflowTurn(
            toolResults: [
              _missingPythonRuntimeResult(
                id: 'missing-runtime-auto-continue',
                command: runtimeCommand,
              ),
            ],
          ),
          _ScriptedWorkflowTurn(
            toolResults: [
              _commandResult(
                id: 'runtime-recovery-auto-continue',
                command: runtimeCommand,
                exitCode: 0,
                stdout: 'usage: main.py [-h]',
              ),
            ],
            hiddenAssistantResponse:
                'Updated main.py to use the standard library and validation passed.',
          ),
        ],
      );

      await _tapWorkflowAction(tester, 'Approve and start');

      expect(harness.chatNotifier.hiddenPrompts, hasLength(2));
      expect(
        harness.chatNotifier.hiddenPrompts.first,
        contains('Implement the Python runtime fallback'),
      );
      expect(
        harness.chatNotifier.hiddenPrompts.last,
        contains('Missing dependency: ping3'),
      );
      for (final task in harness.conversation.projectedExecutionTasks) {
        expect(task.status, ConversationWorkflowTaskStatus.completed);
      }
      expect(
        harness.conversation
            .executionProgressForTask('runtime-auto-continue')
            ?.validationStatus,
        ConversationExecutionValidationStatus.passed,
      );
      expect(harness.conversationsNotifier.assistantEvidenceTaskIds, isEmpty);
      expect(harness.chatNotifier.hiddenAssistantResponseReadCount, 3);
      expect(harness.chatNotifier.hasPendingTurns, isFalse);
    },
  );
}
