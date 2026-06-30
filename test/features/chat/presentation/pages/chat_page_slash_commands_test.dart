import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/pages/chat_page.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/coding_environment_snapshot_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/custom_slash_commands_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_worktree_preparer.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/chat/presentation/slash_commands/slash_command_prompt_template.dart';
import 'package:caverno/features/chat/presentation/widgets/message_input.dart';
import 'package:caverno/features/routines/presentation/providers/routine_scheduler.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestTranslationLoader extends AssetLoader {
  const _TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final localeName = locale.countryCode == null || locale.countryCode!.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final file = File('$path/$localeName.json');
    final fallbackFile = File('$path/${locale.languageCode}.json');
    final source = file.existsSync() ? file : fallbackFile;
    return jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
  }
}

class _SlashSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      demoMode: false,
      mcpEnabled: false,
    );
  }

  @override
  Future<void> updateAssistantMode(AssistantMode assistantMode) async {
    state = state.copyWith(assistantMode: assistantMode);
  }
}

class _SlashChatNotifier extends ChatNotifier {
  _SlashChatNotifier({this.initialLoading = false});

  final bool initialLoading;
  int cancelCount = 0;
  int clearCount = 0;
  final List<String> sentMessages = <String>[];

  @override
  ChatState build() {
    return ChatState.initial().copyWith(isLoading: initialLoading);
  }

  @override
  void cancelStreaming() {
    cancelCount += 1;
    state = state.copyWith(isLoading: false);
  }

  @override
  void clearMessages() {
    clearCount += 1;
    state = ChatState.initial();
  }

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
  }
}

class _SlashConversationsNotifier extends ConversationsNotifier {
  _SlashConversationsNotifier({required this.initialState});

  final ConversationsState initialState;
  int createCount = 0;
  int clearPersistCount = 0;
  int enterPlanCount = 0;

  @override
  ConversationsState build() => initialState;

  @override
  void createNewConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
    String worktreePath = '',
  }) {
    createCount += 1;
    final resolvedWorkspace = workspaceMode ?? state.activeWorkspaceMode;
    final conversation = Conversation(
      id: 'created-$createCount',
      title: 'Created $createCount',
      messages: const <Message>[],
      createdAt: DateTime(2026, 5, 31, 10, createCount),
      updatedAt: DateTime(2026, 5, 31, 10, createCount),
      workspaceMode: resolvedWorkspace,
      projectId: projectId ?? '',
      worktreePath: worktreePath,
    );
    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspace,
      activeProjectId: projectId,
      clearActiveProject: projectId == null,
    );
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    clearPersistCount += messages.isEmpty ? 1 : 0;
    final current = state.currentConversation;
    if (current == null) return;
    final updated = current.copyWith(messages: messages);
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) =>
                conversation.id == updated.id ? updated : conversation,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> enterPlanningSession() async {
    enterPlanCount += 1;
    final current = state.currentConversation;
    if (current == null) return;
    final updated = current.copyWith(
      executionMode: ConversationExecutionMode.planning,
    );
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) =>
                conversation.id == updated.id ? updated : conversation,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _SlashCodingProjectsNotifier extends CodingProjectsNotifier {
  _SlashCodingProjectsNotifier([this.project]);

  final CodingProject? project;

  @override
  CodingProjectsState build() {
    final project = this.project;
    if (project == null) return CodingProjectsState.initial();
    return CodingProjectsState(
      projects: [project],
      selectedProjectId: project.id,
    );
  }

  @override
  Future<CodingProject?> addProject(String rootPath) async {
    final normalizedRootPath = rootPath.trim();
    if (normalizedRootPath.isEmpty) return null;
    for (final project in state.projects) {
      if (project.normalizedRootPath == normalizedRootPath) {
        state = state.copyWith(selectedProjectId: project.id);
        return project;
      }
    }
    final now = DateTime(2026, 5, 31, 11, state.projects.length);
    final project = CodingProject(
      id: 'project-${state.projects.length + 1}',
      name: normalizedRootPath.split('/').last,
      rootPath: normalizedRootPath,
      createdAt: now,
      updatedAt: now,
    );
    state = state.copyWith(
      projects: [project, ...state.projects],
      selectedProjectId: project.id,
    );
    return project;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  EasyLocalization.logger.printer = (_, {stackTrace, level, name}) {};

  tearDown(() {
    debugRemoteCodingMobilePlatformOverride = null;
  });

  testWidgets('/new creates a new conversation', (tester) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    await _submitComposerText(tester, '/new');

    expect(conversationsNotifier.createCount, 1);
    expect(
      container.read(conversationsNotifierProvider).currentConversationId,
      'created-1',
    );
  });

  testWidgets('/clear clears and persists current messages', (tester) async {
    final conversation = _chatConversation(
      messages: [
        Message(
          id: 'message-1',
          content: 'Keep this until clear',
          role: MessageRole.user,
          timestamp: DateTime(2026, 5, 31, 10),
        ),
      ],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    await _submitComposerText(tester, '/clear');

    expect(chatNotifier.clearCount, 1);
    expect(conversationsNotifier.clearPersistCount, 1);
    expect(
      container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.messages,
      isEmpty,
    );
  });

  testWidgets('/plan enters planning for a coding thread', (tester) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 31, 10),
      updatedAt: DateTime(2026, 5, 31, 10),
    );
    final conversation = _chatConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      messages: const <Message>[],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      codingProjectsNotifier: _SlashCodingProjectsNotifier(project),
    );

    await _submitComposerText(tester, '/plan');

    expect(conversationsNotifier.enterPlanCount, 1);
    expect(
      container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.isPlanningSession,
      isTrue,
    );
  });

  testWidgets('/agent queues a worktree agent task for a coding thread', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/Users/test/Workspace/caverno',
      createdAt: DateTime(2026, 5, 31, 10),
      updatedAt: DateTime(2026, 5, 31, 10),
    );
    final conversation = _chatConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      messages: const <Message>[],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      codingProjectsNotifier: _SlashCodingProjectsNotifier(project),
      runProcess: _gitRunner(),
    );

    await _submitComposerText(tester, '/agent Fix flaky widget test');

    final tasks = container
        .read(worktreeAgentTaskRegistryNotifierProvider)
        .tasks;
    expect(tasks, hasLength(1));
    final task = tasks.single;
    expect(task.status.name, 'queued');
    expect(task.title, 'Fix flaky widget test');
    expect(task.prompt, 'Fix flaky widget test');
    expect(task.verificationCommand, isEmpty);
    expect(task.codingProjectId, 'project-1');
    final assignmentSuffix = _expectBranchWithShortAssignmentId(
      task.branchName,
      'feature/ll13-fix-flaky-widget-test-',
    );
    expect(
      task.worktreePath,
      '/Users/test/Workspace/caverno-worktrees/$assignmentSuffix/caverno',
    );
    expect(
      find.text('Worktree agent task queued: ${task.branchName}'),
      findsOneWidget,
    );
    expect(find.text('1 worktree agent task(s)'), findsNothing);
  });

  testWidgets('/agent stores an optional verification command', (tester) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/Users/test/Workspace/caverno',
      createdAt: DateTime(2026, 5, 31, 10),
      updatedAt: DateTime(2026, 5, 31, 10),
    );
    final conversation = _chatConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      messages: const <Message>[],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      codingProjectsNotifier: _SlashCodingProjectsNotifier(project),
      runProcess: _gitRunner(),
    );

    await _submitComposerText(
      tester,
      '/agent Fix flaky widget test --verify fvm flutter test test/widget_test.dart',
    );

    final task = container
        .read(worktreeAgentTaskRegistryNotifierProvider)
        .tasks
        .single;
    expect(task.title, 'Fix flaky widget test');
    expect(task.prompt, 'Fix flaky widget test');
    expect(task.verificationCommand, 'fvm flutter test test/widget_test.dart');
    _expectBranchWithShortAssignmentId(
      task.branchName,
      'feature/ll13-fix-flaky-widget-test-',
    );
  });

  testWidgets('/agent --run starts the queued worktree task', (tester) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/Users/test/Workspace/caverno',
      createdAt: DateTime(2026, 5, 31, 10),
      updatedAt: DateTime(2026, 5, 31, 10),
    );
    final conversation = _chatConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      messages: const <Message>[],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final contexts = <WorktreeAgentTaskExecutionContext>[];
    final runProcess = _gitRunner();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      codingProjectsNotifier: _SlashCodingProjectsNotifier(project),
      runProcess: runProcess,
      worktreeAgentPreparer: WorktreeAgentGitWorktreePreparer(
        runProcess: runProcess,
        ensureParentDirectory: (_) async {},
      ),
      worktreeAgentDelegate: (context) async {
        contexts.add(context);
        return const WorktreeAgentTaskExecutionOutcome(
          resultSummary: 'Implemented the queued task.',
          verifiedGreen: true,
          verificationSummary: 'fvm flutter test passed',
        );
      },
    );

    await _submitComposerText(
      tester,
      '/agent Fix flaky widget test --run --verify fvm flutter test test/widget_test.dart',
    );
    await _pumpUntil(tester, () {
      final tasks = container
          .read(worktreeAgentTaskRegistryNotifierProvider)
          .tasks;
      return tasks.length == 1 && tasks.single.status.name == 'completed';
    });

    final task = container
        .read(worktreeAgentTaskRegistryNotifierProvider)
        .tasks
        .single;
    expect(contexts.single.taskId, task.id);
    expect(task.title, 'Fix flaky widget test');
    expect(task.verificationCommand, 'fvm flutter test test/widget_test.dart');
    expect(task.verifiedGreen, isTrue);
    expect(task.resultSummary, 'Implemented the queued task.');
    expect(
      find.text(
        'Worktree agent task queued and run started: '
        '${task.branchName}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('composer new worktree starts a normal coding session', (
    tester,
  ) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/Users/test/Workspace/caverno',
      createdAt: DateTime(2026, 5, 31, 10),
      updatedAt: DateTime(2026, 5, 31, 10),
    );
    final conversation = _chatConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      messages: const <Message>[],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final gitCalls = <List<String>>[];
    final runProcess = _gitRunner(calls: gitCalls);
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      codingProjectsNotifier: _SlashCodingProjectsNotifier(project),
      runProcess: runProcess,
      worktreeAgentPreparer: WorktreeAgentGitWorktreePreparer(
        runProcess: runProcess,
        ensureParentDirectory: (_) async {},
      ),
    );

    await tester.tap(find.byKey(const ValueKey('worktree-mode-selector')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<MessageInputWorktreeMode>,
        'New worktree',
      ),
    );
    await tester.pumpAndSettle();
    await _submitComposerText(tester, 'Build the composer UI');

    final projectsState = container.read(codingProjectsNotifierProvider);
    final selectedProject = projectsState.selectedProject;
    expect(projectsState.projects, hasLength(1));
    expect(selectedProject?.rootPath, '/Users/test/Workspace/caverno');
    expect(selectedProject?.id, 'project-1');
    expect(chatNotifier.sentMessages, ['Build the composer UI']);
    expect(
      container.read(conversationsNotifierProvider).activeProjectId,
      'project-1',
    );
    final currentConversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;
    expect(currentConversation?.projectId, 'project-1');
    final worktreeAddCall = gitCalls.singleWhere(
      (call) =>
          call.length >= 7 &&
          call[0] == 'git' &&
          call[1] == 'worktree' &&
          call[2] == 'add' &&
          call[3] == '-b',
    );
    final branchName = worktreeAddCall[4];
    final assignmentSuffix = _expectBranchWithShortAssignmentId(
      branchName,
      'feature/build-the-composer-ui-',
    );
    final worktreePath =
        '/Users/test/Workspace/caverno-worktrees/$assignmentSuffix/caverno';
    expect(currentConversation?.normalizedWorktreePath, worktreePath);
    expect(
      container.read(worktreeAgentTaskRegistryNotifierProvider).tasks,
      isEmpty,
    );
    expect(
      gitCalls,
      contains(
        equals([
          'git',
          'worktree',
          'add',
          '-b',
          branchName,
          worktreePath,
          'main',
        ]),
      ),
    );
    expect(find.text('Switched to worktree: $branchName'), findsOneWidget);
  });

  testWidgets('/agent requires a task before --verify', (tester) async {
    debugRemoteCodingMobilePlatformOverride = () => false;
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/Users/test/Workspace/caverno',
      createdAt: DateTime(2026, 5, 31, 10),
      updatedAt: DateTime(2026, 5, 31, 10),
    );
    final conversation = _chatConversation(
      workspaceMode: WorkspaceMode.coding,
      projectId: project.id,
      messages: const <Message>[],
    );
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.coding,
        activeProjectId: project.id,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      codingProjectsNotifier: _SlashCodingProjectsNotifier(project),
      runProcess: _gitRunner(),
    );

    await _submitComposerText(tester, '/agent --verify fvm flutter test');

    expect(
      container.read(worktreeAgentTaskRegistryNotifierProvider).tasks,
      isEmpty,
    );
    expect(find.text('Add a worktree-agent task.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/agent --verify fvm flutter test',
    );
  });

  testWidgets('/agent is blocked outside coding threads', (tester) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
      runProcess: _gitRunner(),
    );

    await _submitComposerText(tester, '/agent Fix flaky widget test');

    expect(
      container.read(worktreeAgentTaskRegistryNotifierProvider).tasks,
      isEmpty,
    );
    expect(
      find.text('Worktree agents are available in coding threads.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/agent Fix flaky widget test',
    );
  });

  testWidgets('/cancel cancels an active response', (tester) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier(initialLoading: true);
    await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    await _submitComposerText(tester, '/cancel');

    expect(chatNotifier.cancelCount, 1);
  });

  testWidgets('prompt slash commands expand arguments into prompt messages', (
    tester,
  ) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    const cases = [
      (
        command: '/review parser changes',
        expectedLead: 'Review the following code, diff, file path',
        expectedTarget: 'parser changes',
      ),
      (
        command: '/fix failing login flow',
        expectedLead: 'Fix or propose a fix for the following issue',
        expectedTarget: 'failing login flow',
      ),
      (
        command: '/explain provider lifecycle',
        expectedLead: 'Explain the following code, behavior, error, or concept',
        expectedTarget: 'provider lifecycle',
      ),
      (
        command: '/test slash command parser',
        expectedLead: 'Add or update tests for the following target',
        expectedTarget: 'slash command parser',
      ),
    ];

    for (final testCase in cases) {
      await _submitComposerText(tester, testCase.command);
    }

    expect(chatNotifier.sentMessages, hasLength(cases.length));
    for (var index = 0; index < cases.length; index += 1) {
      expect(
        chatNotifier.sentMessages[index],
        contains(cases[index].expectedLead),
      );
      expect(
        chatNotifier.sentMessages[index],
        contains(cases[index].expectedTarget),
      );
    }
  });

  testWidgets('custom prompt slash commands send configured templates', (
    tester,
  ) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier();
    final container = await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );
    await container
        .read(customSlashCommandsNotifierProvider.notifier)
        .upsert(
          const SlashCommandPromptTemplate(
            id: 'custom-summary',
            name: 'summarize',
            description: 'Summarize a target',
            aliases: ['sum'],
            argumentHint: '<target>',
            template: '''
Summarize this for release notes:
{input}

Command: {command}
''',
          ),
        );
    await tester.pumpAndSettle();

    await _submitComposerText(tester, '/sum parser changes');

    expect(chatNotifier.sentMessages, hasLength(1));
    expect(
      chatNotifier.sentMessages.single,
      contains('Summarize this for release notes:'),
    );
    expect(chatNotifier.sentMessages.single, contains('parser changes'));
    expect(chatNotifier.sentMessages.single, contains('Command: sum'));
  });

  testWidgets('/review is blocked while a response is active', (tester) async {
    final conversation = _chatConversation(messages: const <Message>[]);
    final conversationsNotifier = _SlashConversationsNotifier(
      initialState: ConversationsState(
        conversations: [conversation],
        currentConversationId: conversation.id,
        activeWorkspaceMode: WorkspaceMode.chat,
        activeProjectId: null,
      ),
    );
    final chatNotifier = _SlashChatNotifier(initialLoading: true);
    await _pumpSlashChatPage(
      tester,
      conversationsNotifier: conversationsNotifier,
      chatNotifier: chatNotifier,
    );

    await _submitComposerText(tester, '/review parser changes');

    expect(chatNotifier.sentMessages, isEmpty);
    expect(
      find.text('Wait for the current response to finish, or use /cancel.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/review parser changes',
    );
  });
}

Conversation _chatConversation({
  WorkspaceMode workspaceMode = WorkspaceMode.chat,
  String? projectId,
  required List<Message> messages,
}) {
  return Conversation(
    id: 'conversation-1',
    title: 'Conversation',
    messages: messages,
    createdAt: DateTime(2026, 5, 31, 10),
    updatedAt: DateTime(2026, 5, 31, 10),
    workspaceMode: workspaceMode,
    projectId: projectId ?? '',
  );
}

Future<ProviderContainer> _pumpSlashChatPage(
  WidgetTester tester, {
  required _SlashConversationsNotifier conversationsNotifier,
  required _SlashChatNotifier chatNotifier,
  _SlashCodingProjectsNotifier? codingProjectsNotifier,
  CodingEnvironmentProcessRunner? runProcess,
  WorktreeAgentGitWorktreePreparer? worktreeAgentPreparer,
  WorktreeAgentTaskExecutionDelegate? worktreeAgentDelegate,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      if (runProcess != null)
        codingEnvironmentProcessRunnerProvider.overrideWithValue(runProcess),
      if (worktreeAgentPreparer != null)
        worktreeAgentGitWorktreePreparerProvider.overrideWithValue(
          worktreeAgentPreparer,
        ),
      if (worktreeAgentDelegate != null)
        worktreeAgentTaskExecutionDelegateProvider.overrideWithValue(
          worktreeAgentDelegate,
        ),
      settingsNotifierProvider.overrideWith(_SlashSettingsNotifier.new),
      conversationsNotifierProvider.overrideWith(() => conversationsNotifier),
      codingProjectsNotifierProvider.overrideWith(
        () => codingProjectsNotifier ?? _SlashCodingProjectsNotifier(),
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
        builder: (context) {
          return UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const ChatPage(showDashboardOnStartup: false),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

CodingEnvironmentProcessRunner _gitRunner({
  List<String> branches = const <String>[],
  List<String> worktreePaths = const <String>[],
  List<List<String>>? calls,
}) {
  return (executable, arguments, {workingDirectory}) async {
    calls?.add([executable, ...arguments]);
    if (executable != 'git') {
      return ProcessResult(1, 1, '', 'unexpected executable');
    }
    if (_argumentsEqual(arguments, const ['rev-parse', '--show-toplevel'])) {
      return ProcessResult(1, 0, workingDirectory ?? '', '');
    }
    if (_argumentsEqual(arguments, const [
      'for-each-ref',
      '--format=%(refname:short)',
      'refs/heads',
    ])) {
      return ProcessResult(2, 0, branches.join('\n'), '');
    }
    if (_argumentsEqual(arguments, const ['worktree', 'list', '--porcelain'])) {
      return ProcessResult(3, 0, _worktreePorcelain(worktreePaths), '');
    }
    if (arguments.length >= 6 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'add' &&
        arguments[2] == '-b') {
      return ProcessResult(4, 0, 'worktree created', '');
    }
    return ProcessResult(4, 1, '', 'unexpected git command');
  };
}

bool _argumentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _worktreePorcelain(List<String> paths) {
  return paths.map((path) => 'worktree $path\nHEAD abc123\n').join();
}

String _expectBranchWithShortAssignmentId(String branchName, String prefix) {
  expect(branchName, startsWith(prefix));
  final suffix = branchName.substring(prefix.length);
  expect(suffix, matches(RegExp(r'^[0-9a-f]{8}$')));
  return suffix;
}

Future<void> _submitComposerText(WidgetTester tester, String text) async {
  await tester.tap(find.byType(TextField));
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for condition.');
}
