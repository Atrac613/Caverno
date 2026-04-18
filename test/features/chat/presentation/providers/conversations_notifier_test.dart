import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';

class _MockConversationBox extends Mock implements Box<String> {}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Conversation? getById(String id) => _store[id];

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

void main() {
  late _FakeConversationRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakeConversationRepository();
    container = ProviderContainer(
      overrides: [conversationRepositoryProvider.overrideWithValue(repository)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'updateCurrentWorkflow persists workflow data for current thread',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.plan,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Plan the next feature slice',
          constraints: ['Keep the first iteration small'],
          acceptanceCriteria: ['Prompt receives workflow context'],
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Persist tasks with the conversation',
            ),
          ],
        ),
      );

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(currentConversation, isNotNull);
      expect(
        currentConversation!.workflowStage,
        ConversationWorkflowStage.plan,
      );
      expect(
        currentConversation.workflowSpec,
        const ConversationWorkflowSpec(
          goal: 'Plan the next feature slice',
          constraints: ['Keep the first iteration small'],
          acceptanceCriteria: ['Prompt receives workflow context'],
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Persist tasks with the conversation',
            ),
          ],
        ),
      );

      final persisted = repository.getById(currentConversation.id);
      expect(persisted?.workflowStage, ConversationWorkflowStage.plan);
      expect(persisted?.workflowSpec?.goal, 'Plan the next feature slice');
      expect(
        persisted?.workflowSpec?.tasks.single.title,
        'Persist tasks with the conversation',
      );
      expect(persisted?.planArtifact?.normalizedApprovedMarkdown, isNotNull);
      expect(
        persisted?.planArtifact?.normalizedApprovedMarkdown,
        contains('Plan the next feature slice'),
      );
    },
  );

  test('planning session state is persisted per conversation', () async {
    final notifier = container.read(conversationsNotifierProvider.notifier);

    notifier.activateWorkspace(
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-1',
      createIfMissing: true,
    );

    await notifier.enterPlanningSession();

    final currentConversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;

    expect(currentConversation, isNotNull);
    expect(currentConversation!.isPlanningSession, isTrue);
    expect(
      repository.getById(currentConversation.id)?.executionMode,
      ConversationExecutionMode.planning,
    );

    await notifier.exitPlanningSession();

    final updatedConversation = container
        .read(conversationsNotifierProvider)
        .currentConversation;

    expect(updatedConversation, isNotNull);
    expect(updatedConversation!.isPlanningSession, isFalse);
    expect(
      repository.getById(updatedConversation.id)?.executionMode,
      ConversationExecutionMode.normal,
    );
  });

  test(
    'updateCurrentPlanArtifact persists plan markdown for the thread',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentPlanArtifact(
        planArtifact: ConversationPlanArtifact(
          draftMarkdown: '# Plan\n\n## Goal\nShip PR3',
          approvedMarkdown: '# Plan\n\n## Goal\nShip PR2',
          updatedAt: DateTime(2026, 4, 18, 9, 30),
        ),
      );

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(currentConversation, isNotNull);
      expect(currentConversation!.planArtifact, isNotNull);
      expect(
        currentConversation.planArtifact!.normalizedDraftMarkdown,
        '# Plan\n\n## Goal\nShip PR3',
      );
      expect(
        currentConversation.planArtifact!.normalizedApprovedMarkdown,
        '# Plan\n\n## Goal\nShip PR2',
      );

      final persisted = repository.getById(currentConversation.id);
      expect(
        persisted?.planArtifact?.normalizedDraftMarkdown,
        '# Plan\n\n## Goal\nShip PR3',
      );
      expect(
        persisted?.planArtifact?.normalizedApprovedMarkdown,
        '# Plan\n\n## Goal\nShip PR2',
      );
    },
  );

  test(
    'selectConversation backfills a plan artifact from legacy workflow data',
    () async {
      final now = DateTime(2026, 4, 18, 11, 0);
      final legacyConversation = Conversation(
        id: 'legacy-conversation',
        title: 'Legacy workflow',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          goal: 'Keep the approved plan readable',
          tasks: [
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Backfill the plan document',
            ),
          ],
        ),
      );
      await repository.save(legacyConversation);

      container.dispose();
      container = ProviderContainer(
        overrides: [
          conversationRepositoryProvider.overrideWithValue(repository),
        ],
      );

      final notifier = container.read(conversationsNotifierProvider.notifier);
      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: false,
      );
      notifier.selectConversation('legacy-conversation');
      await Future<void>.delayed(Duration.zero);

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(currentConversation, isNotNull);
      expect(currentConversation!.planArtifact, isNotNull);
      expect(
        currentConversation.planArtifact!.normalizedApprovedMarkdown,
        contains('Keep the approved plan readable'),
      );
    },
  );

  test(
    'refreshCurrentWorkflowProjectionFromApprovedPlan stores projection metadata',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Run execution from the approved plan\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Refresh projection metadata\n'
              '   - Status: inProgress\n'
              '   - Validation: flutter test\n',
        ),
      );

      final refreshed = await notifier
          .refreshCurrentWorkflowProjectionFromApprovedPlan();

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(refreshed, isTrue);
      expect(currentConversation, isNotNull);
      expect(
        currentConversation!.workflowStage,
        ConversationWorkflowStage.implement,
      );
      expect(
        currentConversation.workflowSpec?.goal,
        'Run execution from the approved plan',
      );
      expect(
        currentConversation.workflowSpec?.tasks.single.title,
        'Refresh projection metadata',
      );
      expect(currentConversation.workflowSourceHash, isNotEmpty);
      expect(currentConversation.workflowDerivedAt, isNotNull);
    },
  );

  test(
    'refreshCurrentWorkflowProjectionFromApprovedPlan prunes stale execution progress',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Run execution from the approved plan\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Keep the first derived task\n'
              '   - Status: pending\n',
        ),
      );
      await notifier.refreshCurrentWorkflowProjectionFromApprovedPlan();

      final firstConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      final firstTaskId = firstConversation!.projectedExecutionTasks.single.id;

      await notifier.updateCurrentExecutionTaskProgress(
        taskId: firstTaskId,
        status: ConversationWorkflowTaskStatus.completed,
        summary: 'Completed before the plan changed.',
      );
      expect(
        container
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.executionProgress,
        hasLength(1),
      );

      await notifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Run execution from the approved plan\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Replace the derived task\n'
              '   - Status: pending\n',
        ),
      );
      await notifier.refreshCurrentWorkflowProjectionFromApprovedPlan();

      final refreshedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(refreshedConversation, isNotNull);
      expect(refreshedConversation!.executionProgress, isEmpty);
    },
  );

  test(
    'refreshCurrentWorkflowProjectionFromApprovedPlan preserves progress for wording-only task updates',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Run execution from the approved plan\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Ship the execution handoff\n'
              '   - Status: pending\n'
              '   - Target files: lib/features/chat/presentation/pages/chat_page.dart\n'
              '   - Validation: flutter test\n',
        ),
      );
      await notifier.refreshCurrentWorkflowProjectionFromApprovedPlan();

      final firstConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      final firstTaskId = firstConversation!.projectedExecutionTasks.single.id;

      await notifier.updateCurrentExecutionTaskProgress(
        taskId: firstTaskId,
        status: ConversationWorkflowTaskStatus.completed,
        summary: 'Completed before the wording-only replan.',
      );

      await notifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Run execution from the approved plan\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Ship the execution handoff flow\n'
              '   - Status: pending\n'
              '   - Target files: lib/features/chat/presentation/pages/chat_page.dart\n'
              '   - Validation: flutter test\n',
        ),
      );
      await notifier.refreshCurrentWorkflowProjectionFromApprovedPlan();

      final refreshedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(refreshedConversation, isNotNull);
      expect(refreshedConversation!.executionProgress, hasLength(1));
      expect(
        refreshedConversation.executionProgress.single.taskId,
        refreshedConversation.projectedExecutionTasks.single.id,
      );
      expect(
        refreshedConversation.executionProgress.single.summary,
        'Completed before the wording-only replan.',
      );
    },
  );

  test(
    'updateCurrentExecutionTaskProgress stores rich execution metadata',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentExecutionTaskProgress(
        taskId: 'task-1',
        status: ConversationWorkflowTaskStatus.blocked,
        summary: 'Waiting for a follow-up fix.',
        blockedReason: 'The current validation run is failing.',
        lastValidationCommand: 'flutter test',
        lastValidationSummary: '1 smoke test failed on macOS.',
        validationStatus: ConversationExecutionValidationStatus.failed,
        lastValidationAt: DateTime(2026, 4, 18, 13, 30),
      );

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(currentConversation, isNotNull);
      final progress = currentConversation!.executionProgress.single;
      expect(progress.taskId, 'task-1');
      expect(progress.status, ConversationWorkflowTaskStatus.blocked);
      expect(progress.summary, 'Waiting for a follow-up fix.');
      expect(progress.blockedReason, 'The current validation run is failing.');
      expect(progress.lastValidationCommand, 'flutter test');
      expect(progress.lastValidationSummary, '1 smoke test failed on macOS.');
      expect(
        progress.validationStatus,
        ConversationExecutionValidationStatus.failed,
      );
      expect(progress.lastValidationAt, DateTime(2026, 4, 18, 13, 30));
    },
  );

  test(
    'updateCurrentExecutionTaskProgressFromAssistantTurn infers blocked validation state',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      notifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );

      await notifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown:
              '# Plan\n'
              '\n'
              '## Stage\n'
              'implement\n'
              '\n'
              '## Goal\n'
              'Track assistant-driven execution progress\n'
              '\n'
              '## Tasks\n'
              '\n'
              '1. Run validation from the approved plan\n'
              '   - Status: inProgress\n'
              '   - Validation: flutter test\n',
        ),
      );
      await notifier.refreshCurrentWorkflowProjectionFromApprovedPlan();

      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;
      final task = currentConversation!.projectedExecutionTasks.single;

      await notifier.updateCurrentExecutionTaskProgressFromAssistantTurn(
        task: task,
        assistantResponse:
            'Validation failed because flutter test reported one failing smoke test.',
        isValidationRun: true,
      );

      final progress = container
          .read(conversationsNotifierProvider)
          .currentConversation
          ?.executionProgress
          .single;
      expect(progress, isNotNull);
      expect(progress!.status, ConversationWorkflowTaskStatus.blocked);
      expect(
        progress.validationStatus,
        ConversationExecutionValidationStatus.failed,
      );
      expect(progress.blockedReason, contains('Validation failed'));
      expect(progress.lastValidationCommand, 'flutter test');
      expect(
        progress.lastValidationSummary,
        contains('Validation failed because flutter test reported'),
      );
    },
  );

  test(
    'updateCurrentConversation keeps the default title for image-only input',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);
      final currentConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(currentConversation, isNotNull);
      expect(currentConversation!.title, defaultConversationTitle);

      await notifier.updateCurrentConversation([
        Message(
          id: 'user-image',
          content: '',
          role: MessageRole.user,
          timestamp: DateTime(2026),
          imageBase64: 'image-data',
          imageMimeType: 'image/png',
        ),
      ]);

      final updatedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(updatedConversation, isNotNull);
      expect(updatedConversation!.title, defaultConversationTitle);
      expect(
        repository.getById(updatedConversation.id)?.title,
        defaultConversationTitle,
      );
    },
  );

  test(
    'updateCurrentConversation uses the first non-empty user text for title',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      await notifier.updateCurrentConversation([
        Message(
          id: 'user-image',
          content: '',
          role: MessageRole.user,
          timestamp: DateTime(2026),
          imageBase64: 'image-data',
          imageMimeType: 'image/png',
        ),
        Message(
          id: 'assistant-1',
          content: 'What should I focus on?',
          role: MessageRole.assistant,
          timestamp: DateTime(2026),
        ),
        Message(
          id: 'user-text',
          content: 'Summarize the attached dashboard metrics',
          role: MessageRole.user,
          timestamp: DateTime(2026),
        ),
      ]);

      final updatedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(updatedConversation, isNotNull);
      expect(updatedConversation!.title, 'Summarize the attached dashboa...');
      expect(
        repository.getById(updatedConversation.id)?.title,
        'Summarize the attached dashboa...',
      );
    },
  );

  test(
    'updateCurrentConversation trims and truncates long user titles',
    () async {
      final notifier = container.read(conversationsNotifierProvider.notifier);

      await notifier.updateCurrentConversation([
        Message(
          id: 'user-text',
          content:
              '   This title should trim leading spaces and stop after thirty visible chars   ',
          role: MessageRole.user,
          timestamp: DateTime(2026),
        ),
      ]);

      final updatedConversation = container
          .read(conversationsNotifierProvider)
          .currentConversation;

      expect(updatedConversation, isNotNull);
      expect(updatedConversation!.title, 'This title should trim leading...');
      expect(
        repository.getById(updatedConversation.id)?.title,
        'This title should trim leading...',
      );
    },
  );
}
