import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/worktree_agent_assignment_planner.dart';
import 'package:caverno/features/chat/presentation/coordinators/slash_command_action_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_launcher.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_orchestrator.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command_prompt_template.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 7, 17, 16);

class _ActionConversationsNotifier extends ConversationsNotifier {
  _ActionConversationsNotifier(this.operations);

  final List<String> operations;
  Conversation? ensuredConversation;

  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  void startDraftConversation({
    required WorkspaceMode workspaceMode,
    String? projectId,
  }) {
    operations.add('draft:${workspaceMode.name}:$projectId');
  }

  @override
  void createNewConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
    String worktreePath = '',
  }) {
    operations.add('new:${workspaceMode?.name}:$projectId');
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    operations.add('persist:${messages.length}');
  }

  @override
  Future<void> enterPlanningSession() async {
    operations.add('enter-plan');
  }

  @override
  Future<void> exitPlanningSession() async {
    operations.add('exit-plan');
  }

  @override
  Conversation? ensureCurrentConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    operations.add('ensure:${workspaceMode?.name}:$projectId');
    return ensuredConversation;
  }
}

class _Harness {
  _Harness() : notifier = _ActionConversationsNotifier(<String>[]) {
    operations = notifier.operations;
    coordinator = SlashCommandActionCoordinator(
      conversationsNotifier: notifier,
      clearMessages: () => operations.add('clear-messages'),
      cancelStreaming: () => operations.add('cancel'),
      dismissPlanProposal: () => operations.add('dismiss-plan'),
      updateAssistantMode: (mode) async {
        operations.add('mode:${mode.name}');
      },
      leaveDashboard: () => operations.add('leave-dashboard'),
      showHelp: (commands) async {
        shownCommands = commands;
        operations.add('help');
      },
      handleGoal:
          (conversation, args, {required sendObjectiveAsInitialPrompt}) async {
            goalConversation = conversation;
            goalArgs = args;
            goalStartsPrompt = sendObjectiveAsInitialPrompt;
            operations.add('goal');
            return const SlashCommandExecutionResult(
              feedbackMessage: 'goal-result',
            );
          },
      submitFeedback: (conversation, text) async {
        feedbackConversation = conversation;
        feedbackText = text;
        operations.add('feedback');
        return const SlashCommandExecutionResult(
          feedbackMessage: 'feedback-result',
        );
      },
      enqueueWorktreeAgent: (request) async {
        enqueuedRequests.add(request);
        final error = enqueueError;
        if (error != null) throw error;
        return _launchResult();
      },
      startReadyWorktreeAgents: (request) async {
        runRequests.add(request);
      },
      text: _text,
    );
  }

  final _ActionConversationsNotifier notifier;
  late final List<String> operations;
  late final SlashCommandActionCoordinator coordinator;
  List<SlashCommandDefinition>? shownCommands;
  Conversation? goalConversation;
  String? goalArgs;
  bool? goalStartsPrompt;
  Conversation? feedbackConversation;
  String? feedbackText;
  Object? enqueueError;
  final enqueuedRequests = <WorktreeAgentTaskLaunchRequest>[];
  final runRequests = <WorktreeAgentTaskRunRequest>[];

  Future<SlashCommandExecutionResult> handle(
    SlashCommandAction action, {
    String args = '',
    SlashCommandActionContext? context,
    String? promptTemplateId,
  }) {
    final name = action.name;
    return coordinator.handle(
      SlashCommandInvocation(
        definition: SlashCommandDefinition(
          name: name,
          action: action,
          description: name,
          promptTemplateId: promptTemplateId,
          enabledWhileLoading:
              action == SlashCommandAction.help ||
              action == SlashCommandAction.cancel,
        ),
        rawInput: '/$name $args',
        commandName: name,
        args: args,
      ),
      commandContext: context ?? _context(),
    );
  }
}

void main() {
  test(
    'blocks non-enabled commands while loading without side effects',
    () async {
      final harness = _Harness();

      final result = await harness.handle(
        SlashCommandAction.clear,
        context: _context(isLoading: true),
      );

      expect(result.clearInput, isFalse);
      expect(result.feedbackMessage, 'chat.slash_blocked_while_loading');
      expect(harness.operations, isEmpty);
    },
  );

  test('help builds and presents the complete command catalog', () async {
    final harness = _Harness();
    const custom = SlashCommandPromptTemplate(
      id: 'custom',
      name: 'custom',
      description: 'Custom',
      template: '{input}',
    );

    final result = await harness.handle(
      SlashCommandAction.help,
      context: _context(isLoading: true, customTemplates: const [custom]),
    );

    expect(result.clearInput, isTrue);
    expect(harness.operations, ['help']);
    expect(harness.shownCommands!.last.name, 'custom');
  });

  test('new starts a coding draft for an active project', () async {
    final harness = _Harness();

    final result = await harness.handle(
      SlashCommandAction.newConversation,
      context: _context(isCoding: true, project: _project()),
    );

    expect(harness.operations, ['leave-dashboard', 'draft:coding:project-1']);
    expect(result.feedbackMessage, 'chat.slash_new_thread_started');
  });

  test('new creates a normal conversation outside coding', () async {
    final harness = _Harness();

    final result = await harness.handle(
      SlashCommandAction.newConversation,
      context: _context(activeWorkspaceMode: WorkspaceMode.chat),
    );

    expect(harness.operations, ['leave-dashboard', 'new:chat:null']);
    expect(result.feedbackMessage, 'chat.slash_new_conversation_started');
  });

  test('clear resets memory before persisting an empty conversation', () async {
    final harness = _Harness();

    final result = await harness.handle(SlashCommandAction.clear);

    expect(harness.operations, ['clear-messages', 'persist:0']);
    expect(result.feedbackMessage, 'chat.slash_cleared');
  });

  for (final entry in [
    (action: SlashCommandAction.general, mode: AssistantMode.general),
    (action: SlashCommandAction.coding, mode: AssistantMode.coding),
  ]) {
    test('${entry.action.name} exits planning before changing mode', () async {
      final harness = _Harness();
      final conversation = _conversation(planning: true);

      final result = await harness.handle(
        entry.action,
        context: _context(conversation: conversation),
      );

      expect(harness.operations, [
        'exit-plan',
        'dismiss-plan',
        'mode:${entry.mode.name}',
      ]);
      expect(result.feedbackMessage, contains('chat.slash_mode_changed'));
    });
  }

  test('plan rejects a non-coding context', () async {
    final harness = _Harness();

    final result = await harness.handle(SlashCommandAction.plan);

    expect(result.clearInput, isFalse);
    expect(result.feedbackMessage, 'chat.slash_plan_unavailable');
  });

  test('plan enters planning for a coding conversation', () async {
    final harness = _Harness();

    final result = await harness.handle(
      SlashCommandAction.plan,
      context: _context(isCoding: true, conversation: _conversation()),
    );

    expect(harness.operations, ['enter-plan']);
    expect(result.feedbackMessage, 'chat.slash_plan_started');
  });

  test('goal creates a first coding conversation before delegation', () async {
    final harness = _Harness();
    final ensured = _conversation();
    harness.notifier.ensuredConversation = ensured;

    final result = await harness.handle(
      SlashCommandAction.goal,
      args: 'Build it',
      context: _context(
        isCoding: true,
        project: _project(),
        activeProjectId: 'fallback-project',
      ),
    );

    expect(harness.operations, ['ensure:coding:project-1', 'goal']);
    expect(harness.goalConversation, same(ensured));
    expect(harness.goalArgs, 'Build it');
    expect(harness.goalStartsPrompt, isTrue);
    expect(result.feedbackMessage, 'goal-result');
  });

  test('goal rejects unavailable contexts', () async {
    final harness = _Harness();

    final result = await harness.handle(SlashCommandAction.goal);

    expect(result.clearInput, isFalse);
    expect(result.feedbackMessage, 'chat.slash_goal_unavailable');
    expect(harness.operations, isEmpty);
  });

  test(
    'goal delegates an existing conversation without initial prompt',
    () async {
      final harness = _Harness();
      final conversation = _conversation();

      await harness.handle(
        SlashCommandAction.goal,
        context: _context(isCoding: true, conversation: conversation),
      );

      expect(harness.goalConversation, same(conversation));
      expect(harness.goalStartsPrompt, isFalse);
    },
  );

  test('cancel reports idle without cancellation', () async {
    final harness = _Harness();

    final result = await harness.handle(SlashCommandAction.cancel);

    expect(harness.operations, isEmpty);
    expect(result.feedbackMessage, 'chat.slash_cancel_idle');
  });

  test('cancel interrupts active generation', () async {
    final harness = _Harness();

    final result = await harness.handle(
      SlashCommandAction.cancel,
      context: _context(isLoading: true),
    );

    expect(harness.operations, ['cancel']);
    expect(result.feedbackMessage, 'chat.slash_cancelled');
  });

  test('feedback delegates the current conversation and text', () async {
    final harness = _Harness();
    final conversation = _conversation();

    final result = await harness.handle(
      SlashCommandAction.feedback,
      args: 'Needs work',
      context: _context(conversation: conversation),
    );

    expect(harness.operations, ['feedback']);
    expect(harness.feedbackConversation, same(conversation));
    expect(harness.feedbackText, 'Needs work');
    expect(result.feedbackMessage, 'feedback-result');
  });

  test(
    'worktree agent rejects unavailable project, prompt, and verifier',
    () async {
      final unavailable = _Harness();
      final unavailableResult = await unavailable.handle(
        SlashCommandAction.worktreeAgent,
        args: 'Task',
      );
      expect(unavailableResult.clearInput, isFalse);
      expect(unavailableResult.feedbackMessage, 'chat.slash_agent_unavailable');

      final missingPrompt = _Harness();
      final missingPromptResult = await missingPrompt.handle(
        SlashCommandAction.worktreeAgent,
        args: '--run',
        context: _context(isCoding: true, project: _project()),
      );
      expect(
        missingPromptResult.feedbackMessage,
        'chat.slash_agent_prompt_required',
      );

      final missingVerifier = _Harness();
      final missingVerifierResult = await missingVerifier.handle(
        SlashCommandAction.worktreeAgent,
        args: 'Task --verify',
        context: _context(isCoding: true, project: _project()),
      );
      expect(
        missingVerifierResult.feedbackMessage,
        'chat.slash_agent_verify_required',
      );
    },
  );

  test('worktree agent queues parsed task metadata', () async {
    final harness = _Harness();

    final result = await harness.handle(
      SlashCommandAction.worktreeAgent,
      args: 'Implement feature --verify fvm flutter test',
      context: _context(isCoding: true, project: _project()),
    );

    final request = harness.enqueuedRequests.single;
    expect(request.title, 'Implement feature');
    expect(request.prompt, 'Implement feature');
    expect(request.codingProjectId, 'project-1');
    expect(request.projectRootPath, '/repo');
    expect(request.verificationCommand, 'fvm flutter test');
    expect(harness.runRequests, isEmpty);
    expect(
      result.feedbackMessage,
      'chat.slash_agent_queued(branch=feature/task)',
    );
  });

  test('worktree agent starts queued work without awaiting it', () async {
    final harness = _Harness();

    final result = await harness.handle(
      SlashCommandAction.worktreeAgent,
      args: 'Implement feature --run',
      context: _context(isCoding: true, project: _project()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(harness.runRequests.single.fallbackProjectRootPath, '/repo');
    expect(
      result.feedbackMessage,
      'chat.slash_agent_queued_and_started(branch=feature/task)',
    );
  });

  test('worktree agent converts enqueue failures to retained input', () async {
    final harness = _Harness();
    harness.enqueueError = StateError('branch collision');

    final result = await harness.handle(
      SlashCommandAction.worktreeAgent,
      args: 'Implement feature',
      context: _context(isCoding: true, project: _project()),
    );

    expect(result.clearInput, isFalse);
    expect(result.feedbackMessage, contains('branch collision'));
  });

  for (final action in [
    SlashCommandAction.review,
    SlashCommandAction.fix,
    SlashCommandAction.explain,
    SlashCommandAction.test,
  ]) {
    test('${action.name} expands its built-in prompt template', () async {
      final harness = _Harness();

      final result = await harness.handle(action, args: 'target.dart');

      expect(result.clearInput, isTrue);
      expect(result.promptToSend, contains('target.dart'));
    });
  }

  test('promptTemplate expands a custom template', () async {
    final harness = _Harness();
    const custom = SlashCommandPromptTemplate(
      id: 'custom',
      name: 'custom',
      description: 'Custom',
      template: 'Custom {input}',
    );

    final result = await harness.handle(
      SlashCommandAction.promptTemplate,
      args: 'value',
      promptTemplateId: 'custom',
      context: _context(customTemplates: const [custom]),
    );

    expect(result.promptToSend, 'Custom value');
  });

  test('promptTemplate retains input when its ID cannot be resolved', () async {
    final harness = _Harness();

    final result = await harness.handle(
      SlashCommandAction.promptTemplate,
      promptTemplateId: 'missing',
    );

    expect(result.clearInput, isFalse);
    expect(result.feedbackMessage, 'message.slash_command_failed');
  });

  group('worktree argument helpers', () {
    test('parses boundary-delimited run and verify markers', () {
      final args = parseWorktreeAgentCommandArgs(
        'Fix runtime --run --verify fvm flutter test',
      );

      expect(args.prompt, 'Fix runtime');
      expect(args.runAfterQueue, isTrue);
      expect(args.hasVerificationMarker, isTrue);
      expect(args.verificationCommand, 'fvm flutter test');
    });

    test('keeps marker-like substrings as prompt text', () {
      final args = parseWorktreeAgentCommandArgs('Fix --runner and x--verify');

      expect(args.prompt, 'Fix --runner and x--verify');
      expect(args.runAfterQueue, isFalse);
      expect(args.hasVerificationMarker, isFalse);
    });

    test(
      'builds titles from the first line and truncates to 80 characters',
      () {
        expect(
          worktreeAgentTaskTitle('\n  First line  \nSecond'),
          'First line',
        );
        expect(worktreeAgentTaskTitle('   '), 'Worktree agent');
        final title = worktreeAgentTaskTitle(List.filled(90, 'a').join());
        expect(title, hasLength(80));
        expect(title, endsWith('...'));
      },
    );
  });
}

SlashCommandActionContext _context({
  bool isLoading = false,
  bool isCoding = false,
  CodingProject? project,
  Conversation? conversation,
  WorkspaceMode activeWorkspaceMode = WorkspaceMode.chat,
  String? activeProjectId,
  List<SlashCommandPromptTemplate> customTemplates = const [],
}) => SlashCommandActionContext(
  isLoading: isLoading,
  isCodingWorkspace: isCoding,
  activeProject: project,
  currentConversation: conversation,
  conversationsState: ConversationsState(
    conversations: conversation == null ? const [] : [conversation],
    currentConversationId: conversation?.id,
    activeWorkspaceMode: activeWorkspaceMode,
    activeProjectId: activeProjectId,
  ),
  customPromptTemplates: customTemplates,
);

Conversation _conversation({bool planning = false}) => Conversation(
  id: 'conversation-1',
  title: 'Slash test',
  messages: const [],
  createdAt: _now,
  updatedAt: _now,
  workspaceMode: WorkspaceMode.coding,
  projectId: 'project-1',
  executionMode: planning
      ? ConversationExecutionMode.planning
      : ConversationExecutionMode.normal,
);

CodingProject _project() => CodingProject(
  id: 'project-1',
  name: 'Project',
  rootPath: '/repo',
  createdAt: _now,
  updatedAt: _now,
);

WorktreeAgentTaskLaunchResult _launchResult() {
  final task = WorktreeAgentTask(
    id: 'task-1',
    title: 'Task',
    prompt: 'Task',
    branchName: 'feature/task',
    worktreePath: '/repo-worktrees/task',
    createdAt: _now,
    updatedAt: _now,
  );
  return WorktreeAgentTaskLaunchResult(
    plan: const WorktreeAgentAssignmentPlan(
      title: 'Task',
      prompt: 'Task',
      codingProjectId: 'project-1',
      baseBranch: 'main',
      branchName: 'feature/task',
      worktreePath: '/repo-worktrees/task',
      checkpointLineageId: '',
      endpointId: '',
      verificationCommand: '',
    ),
    task: task,
  );
}

String _text(String key, {Map<String, String>? namedArgs}) {
  if (namedArgs == null || namedArgs.isEmpty) return key;
  final values = namedArgs.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return '$key(${values.map((entry) => '${entry.key}=${entry.value}').join(',')})';
}
