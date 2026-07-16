import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:test/test.dart';

class _ValidationConversationsNotifier extends ConversationsNotifier {
  _ValidationConversationsNotifier(this.conversation);

  final Conversation conversation;
  final List<ConversationExecutionTaskProgress> progressWrites = [];
  final List<ConversationWorkflowStage> workflowStageWrites = [];
  final List<String> assistantEvidenceTaskIds = [];

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.projectId,
  );

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
    final currentConversation = state.currentConversation;
    if (currentConversation == null) {
      return;
    }
    final previous = currentConversation.executionProgressForTask(taskId);
    final nextProgress = ConversationExecutionTaskProgress(
      taskId: taskId,
      status: status,
      validationStatus:
          validationStatus ??
          previous?.validationStatus ??
          ConversationExecutionValidationStatus.unknown,
      updatedAt: _fixedNow,
      lastRunAt: lastRunAt ?? previous?.lastRunAt,
      lastValidationAt: lastValidationAt ?? previous?.lastValidationAt,
      summary: summary ?? previous?.summary ?? '',
      blockedReason: blockedReason ?? previous?.blockedReason ?? '',
      lastValidationCommand:
          lastValidationCommand ?? previous?.lastValidationCommand ?? '',
      lastValidationSummary:
          lastValidationSummary ?? previous?.lastValidationSummary ?? '',
    );
    progressWrites.add(nextProgress);
    final updatedConversation = currentConversation.copyWith(
      executionProgress: [
        ...currentConversation.effectiveExecutionProgress.where(
          (progress) => progress.taskId != taskId,
        ),
        nextProgress,
      ],
      updatedAt: _fixedNow,
    );
    state = state.copyWith(
      conversations: [updatedConversation],
      currentConversationId: updatedConversation.id,
    );
  }

  @override
  Future<void> updateCurrentWorkflow({
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowSpec? workflowSpec,
    String? workflowSourceHash,
    DateTime? workflowDerivedAt,
    bool clearWorkflowSpec = false,
    bool preserveWorkflowProjection = false,
  }) async {
    final currentConversation = state.currentConversation;
    if (currentConversation == null) {
      return;
    }
    final nextStage = workflowStage ?? currentConversation.workflowStage;
    workflowStageWrites.add(nextStage);
    final updatedConversation = currentConversation.copyWith(
      workflowStage: nextStage,
      workflowSpec: clearWorkflowSpec
          ? null
          : workflowSpec ?? currentConversation.workflowSpec,
      workflowSourceHash:
          workflowSourceHash ?? currentConversation.workflowSourceHash,
      workflowDerivedAt:
          workflowDerivedAt ?? currentConversation.workflowDerivedAt,
      updatedAt: _fixedNow,
    );
    state = state.copyWith(
      conversations: [updatedConversation],
      currentConversationId: updatedConversation.id,
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

class _ScriptedChatTurn {
  const _ScriptedChatTurn({
    this.toolResults = const [],
    this.hiddenAssistantResponse,
    this.started,
    this.gate,
  });

  final List<ToolResultInfo> toolResults;
  final String? hiddenAssistantResponse;
  final Completer<void>? started;
  final Future<void>? gate;
}

class _ValidationChatNotifier extends ChatNotifier {
  _ValidationChatNotifier({
    required Iterable<_ScriptedChatTurn> visibleTurns,
    Iterable<_ScriptedChatTurn> hiddenTurns = const [],
  }) : _visibleTurns = Queue.of(visibleTurns),
       _hiddenTurns = Queue.of(hiddenTurns);

  final Queue<_ScriptedChatTurn> _visibleTurns;
  final Queue<_ScriptedChatTurn> _hiddenTurns;
  final List<String> sentMessages = [];
  final List<String> hiddenPrompts = [];
  final List<String> sentLanguageCodes = [];
  final List<bool> sentBypassPlanModes = [];
  List<ToolResultInfo> _latestToolResults = const [];
  String? _latestHiddenAssistantResponse;
  var toolResultReadCount = 0;

  bool get hasPendingTurns =>
      _visibleTurns.isNotEmpty || _hiddenTurns.isNotEmpty;
  int get remainingHiddenTurnCount => _hiddenTurns.length;

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
    sentLanguageCodes.add(languageCode);
    sentBypassPlanModes.add(bypassPlanMode);
    await _runTurn(_visibleTurns, kind: 'visible');
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
    await _runTurn(_hiddenTurns, kind: 'hidden');
  }

  @override
  List<ToolResultInfo> takeLatestToolResults() {
    toolResultReadCount += 1;
    final results = _latestToolResults;
    _latestToolResults = const [];
    return results;
  }

  @override
  String? takeLatestHiddenAssistantResponse() {
    final response = _latestHiddenAssistantResponse;
    _latestHiddenAssistantResponse = null;
    return response;
  }

  Future<void> _runTurn(
    Queue<_ScriptedChatTurn> turns, {
    required String kind,
  }) async {
    if (turns.isEmpty) {
      throw StateError('Unexpected $kind coordinator turn.');
    }
    final turn = turns.removeFirst();
    final started = turn.started;
    if (started != null && !started.isCompleted) {
      started.complete();
    }
    final gate = turn.gate;
    if (gate != null) {
      await gate;
    }
    _latestToolResults = turn.toolResults;
    _latestHiddenAssistantResponse = turn.hiddenAssistantResponse;
  }
}

class _CoordinatorHarness {
  const _CoordinatorHarness({
    required this.container,
    required this.coordinator,
    required this.chatNotifier,
    required this.conversationsNotifier,
    required this.task,
  });

  final ProviderContainer container;
  final WorkflowTaskRunCoordinator coordinator;
  final _ValidationChatNotifier chatNotifier;
  final _ValidationConversationsNotifier conversationsNotifier;
  final ConversationWorkflowTask task;

  Conversation get conversation =>
      container.read(conversationsNotifierProvider).currentConversation!;
}

final DateTime _fixedNow = DateTime(2026, 7, 16, 21, 45);

ToolResultInfo _commandResult({
  required String id,
  required String command,
  required int exitCode,
  String? stdout,
  String? stderr,
}) {
  return ToolResultInfo(
    id: id,
    name: 'local_execute_command',
    arguments: {'command': command},
    result: jsonEncode({
      'command': command,
      'exit_code': exitCode,
      'stdout': stdout ?? (exitCode == 0 ? 'All tests passed.' : ''),
      'stderr': stderr ?? (exitCode == 0 ? '' : '1 test failed.'),
    }),
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

_CoordinatorHarness _createWorkflowHarness({
  required List<ConversationWorkflowTask> tasks,
  required Iterable<_ScriptedChatTurn> visibleTurns,
  Iterable<_ScriptedChatTurn> hiddenTurns = const [],
  bool Function()? isPageMounted,
  bool Function()? isContextMounted,
}) {
  final planMarkdown = <String>[
    '# Plan',
    '',
    '## Stage',
    'implement',
    '',
    '## Tasks',
    for (var index = 0; index < tasks.length; index++) ...[
      '${index + 1}. ${tasks[index].title}',
      '   - Task ID: ${tasks[index].id}',
      '   - Status: pending',
      if (tasks[index].validationCommand.trim().isNotEmpty)
        '   - Validation: ${tasks[index].validationCommand}',
    ],
  ].join('\n');
  final conversation = Conversation(
    id: 'conversation-1',
    title: 'Coordinator test',
    messages: const [],
    createdAt: _fixedNow,
    updatedAt: _fixedNow,
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-1',
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: ConversationWorkflowSpec(
      goal: 'Validate the saved workflow.',
      tasks: tasks,
    ),
    planArtifact: ConversationPlanArtifact(approvedMarkdown: planMarkdown),
    workflowSourceHash: computeConversationPlanHash(planMarkdown),
    workflowDerivedAt: _fixedNow,
  );
  final container = ProviderContainer(
    overrides: [
      conversationsNotifierProvider.overrideWith(
        () => _ValidationConversationsNotifier(conversation),
      ),
      chatNotifierProvider.overrideWith(
        () => _ValidationChatNotifier(
          visibleTurns: visibleTurns,
          hiddenTurns: hiddenTurns,
        ),
      ),
    ],
  );
  final conversationsNotifier =
      container.read(conversationsNotifierProvider.notifier)
          as _ValidationConversationsNotifier;
  final chatNotifier =
      container.read(chatNotifierProvider.notifier) as _ValidationChatNotifier;
  final coordinator = WorkflowTaskRunCoordinator(
    chatNotifier: chatNotifier,
    conversationsNotifier: conversationsNotifier,
    readCurrentConversation: () =>
        container.read(conversationsNotifierProvider).currentConversation,
    readActiveProjectRoot: () => null,
    updateTaskStatus: (update) async {
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: update.task.id,
        status: update.status,
        allowStatusRegression: true,
        lastRunAt: update.lastRunAt,
        lastValidationAt: update.lastValidationAt,
        validationStatus: update.validationStatus,
        summary: update.summary,
        blockedReason: update.blockedReason,
        lastValidationCommand: update.lastValidationCommand,
        lastValidationSummary: update.lastValidationSummary,
        eventType: update.eventType,
        eventSummary: update.summary,
      );
      if (update.status == ConversationWorkflowTaskStatus.completed) {
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.review,
          preserveWorkflowProjection: true,
        );
      } else if (update.status == ConversationWorkflowTaskStatus.inProgress ||
          update.status == ConversationWorkflowTaskStatus.blocked) {
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.implement,
          preserveWorkflowProjection: true,
        );
      }
    },
    isPageMounted: isPageMounted ?? () => true,
    isContextMounted: isContextMounted ?? () => true,
    now: () => _fixedNow,
  );
  return _CoordinatorHarness(
    container: container,
    coordinator: coordinator,
    chatNotifier: chatNotifier,
    conversationsNotifier: conversationsNotifier,
    task: tasks.first,
  );
}

_CoordinatorHarness _createHarness({required int exitCode}) {
  const validationCommand = 'dart test';
  const task = ConversationWorkflowTask(
    id: 'verify-cli',
    title: 'Verify CLI behavior',
    validationCommand: validationCommand,
  );
  return _createWorkflowHarness(
    tasks: const [task],
    visibleTurns: [
      _ScriptedChatTurn(
        toolResults: [
          _commandResult(
            id: 'validation-result',
            command: validationCommand,
            exitCode: exitCode,
            stdout: exitCode == 0 ? 'All tests passed.' : 'Running tests...',
          ),
        ],
      ),
    ],
  );
}

const _promptText = WorkflowTaskValidationPromptText(
  intro:
      'Run the saved validation step for task "Verify CLI behavior" in this coding thread.',
  targetFilesLabel: 'Target files',
  validationLabel: 'Validation command',
  outro:
      'Use the approved plan and the current task context, run the validation when possible, and report failures before suggesting a replan.',
);

const _executionPromptText = WorkflowTaskExecutionPromptText(
  intro: 'Run the current saved workflow task.',
  targetFilesLabel: 'Target files',
  validationLabel: 'Validation command',
  notesLabel: 'Notes',
  outro: 'Implement the task and validate the result.',
);

void main() {
  test('runValidation records a passed command as completed', () async {
    final harness = _createHarness(exitCode: 0);
    addTearDown(harness.container.dispose);

    await harness.coordinator.runValidation(
      currentConversation: harness.conversation,
      task: harness.task,
      languageCode: 'en',
      promptText: _promptText,
    );

    final progress = harness.conversation.executionProgressForTask(
      harness.task.id,
    );
    expect(progress?.status, ConversationWorkflowTaskStatus.completed);
    expect(
      progress?.validationStatus,
      ConversationExecutionValidationStatus.passed,
    );
    expect(progress?.lastValidationCommand, harness.task.validationCommand);
    expect(progress?.lastValidationSummary, contains('All tests passed'));
    expect(progress?.blockedReason, isEmpty);
    expect(harness.conversationsNotifier.progressWrites, hasLength(2));
    expect(
      harness.conversationsNotifier.progressWrites.first.status,
      ConversationWorkflowTaskStatus.inProgress,
    );
    expect(
      harness.conversationsNotifier.progressWrites.first.validationStatus,
      ConversationExecutionValidationStatus.unknown,
    );
    expect(
      harness.conversation.workflowStage,
      ConversationWorkflowStage.review,
    );
    expect(
      harness.conversationsNotifier.workflowStageWrites.last,
      ConversationWorkflowStage.review,
    );
    expect(harness.chatNotifier.sentMessages, hasLength(1));
    expect(
      harness.chatNotifier.sentMessages.single,
      contains('Verify CLI behavior'),
    );
    expect(harness.chatNotifier.sentMessages.single, contains('dart test'));
    expect(harness.chatNotifier.sentLanguageCodes, ['en']);
    expect(harness.chatNotifier.sentBypassPlanModes, [true]);
    expect(harness.conversationsNotifier.assistantEvidenceTaskIds, isEmpty);
  });

  test('runValidation records a failed command as blocked', () async {
    final harness = _createHarness(exitCode: 1);
    addTearDown(harness.container.dispose);

    await harness.coordinator.runValidation(
      currentConversation: harness.conversation,
      task: harness.task,
      languageCode: 'en',
      promptText: _promptText,
    );

    final progress = harness.conversation.executionProgressForTask(
      harness.task.id,
    );
    expect(progress?.status, ConversationWorkflowTaskStatus.blocked);
    expect(
      progress?.validationStatus,
      ConversationExecutionValidationStatus.failed,
    );
    expect(progress?.lastValidationCommand, harness.task.validationCommand);
    expect(progress?.blockedReason, contains('1 test failed'));
    expect(progress?.lastValidationSummary, contains('1 test failed'));
    expect(harness.conversationsNotifier.progressWrites, hasLength(2));
    expect(
      harness.conversationsNotifier.progressWrites.first.status,
      ConversationWorkflowTaskStatus.inProgress,
    );
    expect(
      harness.conversationsNotifier.progressWrites.first.validationStatus,
      ConversationExecutionValidationStatus.unknown,
    );
    expect(
      harness.conversation.workflowStage,
      ConversationWorkflowStage.implement,
    );
    expect(
      harness.conversationsNotifier.workflowStageWrites.last,
      ConversationWorkflowStage.implement,
    );
    expect(harness.chatNotifier.sentMessages, hasLength(1));
    expect(
      harness.chatNotifier.sentMessages.single,
      contains('Verify CLI behavior'),
    );
    expect(harness.chatNotifier.sentMessages.single, contains('dart test'));
    expect(harness.chatNotifier.sentLanguageCodes, ['en']);
    expect(harness.chatNotifier.sentBypassPlanModes, [true]);
    expect(harness.conversationsNotifier.assistantEvidenceTaskIds, isEmpty);
  });

  test(
    'runTask stops after the initial task and eight continuations',
    () async {
      final tasks = List.generate(
        10,
        (index) => ConversationWorkflowTask(
          id: 'verify-step-${index + 1}',
          title: 'Verify step ${index + 1}',
          validationCommand: 'dart test test/step_${index + 1}_test.dart',
        ),
      );
      final harness = _createWorkflowHarness(
        tasks: tasks,
        visibleTurns: [
          _ScriptedChatTurn(
            toolResults: [
              _commandResult(
                id: 'step-1-result',
                command: tasks.first.validationCommand,
                exitCode: 0,
              ),
            ],
          ),
        ],
        hiddenTurns: [
          for (var index = 1; index < tasks.length; index++)
            _ScriptedChatTurn(
              toolResults: [
                _commandResult(
                  id: 'step-${index + 1}-result',
                  command: tasks[index].validationCommand,
                  exitCode: 0,
                ),
              ],
            ),
        ],
      );
      addTearDown(harness.container.dispose);

      await harness.coordinator.runTask(
        currentConversation: harness.conversation,
        task: harness.task,
        languageCode: 'en',
        promptText: _executionPromptText,
      );

      final projectedTasks = harness.conversation.projectedExecutionTasks;
      expect(
        projectedTasks.take(9).map((task) => task.status),
        everyElement(ConversationWorkflowTaskStatus.completed),
      );
      expect(
        projectedTasks.last.status,
        ConversationWorkflowTaskStatus.pending,
      );
      expect(harness.chatNotifier.sentMessages, hasLength(1));
      expect(harness.chatNotifier.hiddenPrompts, hasLength(8));
      expect(harness.chatNotifier.toolResultReadCount, 9);
      expect(harness.chatNotifier.remainingHiddenTurnCount, 1);
      expect(harness.chatNotifier.hasPendingTurns, isTrue);
    },
  );

  test(
    'a blocked auto-continued task leaves the following task pending',
    () async {
      const tasks = [
        ConversationWorkflowTask(
          id: 'verify-first',
          title: 'Verify the first step',
          validationCommand: 'dart test test/first_test.dart',
        ),
        ConversationWorkflowTask(
          id: 'verify-blocked',
          title: 'Verify the blocked step',
          validationCommand: 'dart test test/blocked_test.dart',
        ),
        ConversationWorkflowTask(
          id: 'verify-following',
          title: 'Verify the following step',
          validationCommand: 'dart test test/following_test.dart',
        ),
      ];
      final harness = _createWorkflowHarness(
        tasks: tasks,
        visibleTurns: [
          _ScriptedChatTurn(
            toolResults: [
              _commandResult(
                id: 'first-result',
                command: tasks.first.validationCommand,
                exitCode: 0,
              ),
            ],
          ),
        ],
        hiddenTurns: [
          _ScriptedChatTurn(
            toolResults: [
              _commandResult(
                id: 'blocked-result',
                command: tasks[1].validationCommand,
                exitCode: 1,
              ),
            ],
            hiddenAssistantResponse:
                'The saved task is blocked because its validation failed.',
          ),
        ],
      );
      addTearDown(harness.container.dispose);

      await harness.coordinator.runTask(
        currentConversation: harness.conversation,
        task: harness.task,
        languageCode: 'en',
        promptText: _executionPromptText,
      );

      final projectedTasks = harness.conversation.projectedExecutionTasks;
      expect(projectedTasks.map((task) => task.status), [
        ConversationWorkflowTaskStatus.completed,
        ConversationWorkflowTaskStatus.blocked,
        ConversationWorkflowTaskStatus.pending,
      ]);
      expect(harness.chatNotifier.hiddenPrompts, hasLength(1));
      expect(harness.chatNotifier.hasPendingTurns, isFalse);
    },
  );

  test(
    'an incomplete auto-continued task leaves the following task pending',
    () async {
      const tasks = [
        ConversationWorkflowTask(
          id: 'verify-first',
          title: 'Verify the first step',
          validationCommand: 'dart test test/first_test.dart',
        ),
        ConversationWorkflowTask(
          id: 'verify-incomplete',
          title: 'Implement the incomplete step',
        ),
        ConversationWorkflowTask(
          id: 'verify-following',
          title: 'Verify the following step',
          validationCommand: 'dart test test/following_test.dart',
        ),
      ];
      final harness = _createWorkflowHarness(
        tasks: tasks,
        visibleTurns: [
          _ScriptedChatTurn(
            toolResults: [
              _commandResult(
                id: 'first-result',
                command: tasks.first.validationCommand,
                exitCode: 0,
              ),
            ],
          ),
        ],
        hiddenTurns: [
          _ScriptedChatTurn(toolResults: [_syntheticUnexecutedCommandResult()]),
          const _ScriptedChatTurn(),
        ],
      );
      addTearDown(harness.container.dispose);

      await harness.coordinator.runTask(
        currentConversation: harness.conversation,
        task: harness.task,
        languageCode: 'en',
        promptText: _executionPromptText,
      );

      final projectedTasks = harness.conversation.projectedExecutionTasks;
      expect(projectedTasks.map((task) => task.status), [
        ConversationWorkflowTaskStatus.completed,
        ConversationWorkflowTaskStatus.inProgress,
        ConversationWorkflowTaskStatus.pending,
      ]);
      expect(harness.chatNotifier.hiddenPrompts, hasLength(2));
      expect(
        harness.chatNotifier.hiddenPrompts.first,
        contains('The previous saved task is complete.'),
      );
      expect(
        harness.chatNotifier.hiddenPrompts.last,
        contains('The saved task stalled without any concrete tool call'),
      );
      expect(harness.chatNotifier.hasPendingTurns, isFalse);
    },
  );

  test('runTask stops processing when liveness changes during send', () async {
    const task = ConversationWorkflowTask(
      id: 'verify-liveness',
      title: 'Verify task liveness',
      validationCommand: 'dart test test/liveness_test.dart',
    );
    final sendStarted = Completer<void>();
    final sendGate = Completer<void>();
    var pageMounted = true;
    final harness = _createWorkflowHarness(
      tasks: const [task],
      visibleTurns: [
        _ScriptedChatTurn(
          toolResults: [
            _commandResult(
              id: 'liveness-result',
              command: task.validationCommand,
              exitCode: 0,
            ),
          ],
          started: sendStarted,
          gate: sendGate.future,
        ),
      ],
      isPageMounted: () => pageMounted,
    );
    addTearDown(harness.container.dispose);

    final runFuture = harness.coordinator.runTask(
      currentConversation: harness.conversation,
      task: harness.task,
      languageCode: 'en',
      promptText: _executionPromptText,
    );
    await sendStarted.future;
    pageMounted = false;
    sendGate.complete();
    await runFuture;

    expect(harness.chatNotifier.toolResultReadCount, 0);
    expect(harness.chatNotifier.hiddenPrompts, isEmpty);
    expect(harness.conversationsNotifier.progressWrites, hasLength(1));
    expect(
      harness.conversation.projectedExecutionTasks.single.status,
      ConversationWorkflowTaskStatus.inProgress,
    );
  });

  test('runValidation stops processing after page unmount', () async {
    const task = ConversationWorkflowTask(
      id: 'verify-validation-liveness',
      title: 'Verify validation liveness',
      validationCommand: 'dart test test/validation_liveness_test.dart',
    );
    final sendStarted = Completer<void>();
    final sendGate = Completer<void>();
    var pageMounted = true;
    final harness = _createWorkflowHarness(
      tasks: const [task],
      visibleTurns: [
        _ScriptedChatTurn(
          toolResults: [
            _commandResult(
              id: 'validation-liveness-result',
              command: task.validationCommand,
              exitCode: 0,
            ),
          ],
          started: sendStarted,
          gate: sendGate.future,
        ),
      ],
      isPageMounted: () => pageMounted,
    );
    addTearDown(harness.container.dispose);

    final runFuture = harness.coordinator.runValidation(
      currentConversation: harness.conversation,
      task: harness.task,
      languageCode: 'en',
      promptText: _promptText,
    );
    await sendStarted.future;
    pageMounted = false;
    sendGate.complete();
    await runFuture;

    expect(harness.chatNotifier.toolResultReadCount, 0);
    expect(harness.chatNotifier.hiddenPrompts, isEmpty);
    expect(harness.conversationsNotifier.progressWrites, hasLength(1));
    expect(
      harness.conversation.projectedExecutionTasks.single.status,
      ConversationWorkflowTaskStatus.inProgress,
    );
  });
}
