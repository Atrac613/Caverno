import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/presentation/coordinators/chat_page_workspace_navigation_coordinator.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _WorkspaceActivation {
  const _WorkspaceActivation({
    required this.workspaceMode,
    required this.projectId,
    required this.createIfMissing,
    required this.createFreshOnFirstOpen,
    required this.deferFreshConversationCreation,
  });

  final WorkspaceMode workspaceMode;
  final String? projectId;
  final bool createIfMissing;
  final bool createFreshOnFirstOpen;
  final bool deferFreshConversationCreation;
}

class _RecordingConversationsNotifier extends ConversationsNotifier {
  final activations = <_WorkspaceActivation>[];
  final selectedConversationIds = <String>[];

  @override
  void activateWorkspace({
    required WorkspaceMode workspaceMode,
    String? projectId,
    bool createIfMissing = true,
    bool createFreshOnFirstOpen = false,
    bool deferFreshConversationCreation = false,
  }) {
    activations.add(
      _WorkspaceActivation(
        workspaceMode: workspaceMode,
        projectId: projectId,
        createIfMissing: createIfMissing,
        createFreshOnFirstOpen: createFreshOnFirstOpen,
        deferFreshConversationCreation: deferFreshConversationCreation,
      ),
    );
  }

  @override
  void selectConversation(String id) {
    selectedConversationIds.add(id);
  }
}

class _RecordingCodingProjectsNotifier extends CodingProjectsNotifier {
  final selectedProjectIds = <String?>[];

  @override
  void selectProject(String? id) {
    selectedProjectIds.add(id);
  }
}

class _Harness {
  _Harness({
    ConversationsState? conversationsState,
    CodingProjectsState? codingProjectsState,
    this.assistantMode = AssistantMode.general,
  }) : conversationsState = conversationsState ?? ConversationsState.initial(),
       codingProjectsState =
           codingProjectsState ?? CodingProjectsState.initial() {
    coordinator = ChatPageWorkspaceNavigationCoordinator(
      conversationsNotifier: conversationsNotifier,
      codingProjectsNotifier: codingProjectsNotifier,
      readConversationsState: () => this.conversationsState,
      readCodingProjectsState: () => this.codingProjectsState,
      readAssistantMode: () => assistantMode,
      updateAssistantMode: (mode) async {
        assistantMode = mode;
        assistantModeUpdates.add(mode);
      },
      leaveDashboard: () => leaveDashboardCalls += 1,
      clearRoutineSelection: () => clearRoutineSelectionCalls += 1,
    );
  }

  final _RecordingConversationsNotifier conversationsNotifier =
      _RecordingConversationsNotifier();
  final _RecordingCodingProjectsNotifier codingProjectsNotifier =
      _RecordingCodingProjectsNotifier();
  final ConversationsState conversationsState;
  final CodingProjectsState codingProjectsState;
  AssistantMode assistantMode;
  final assistantModeUpdates = <AssistantMode>[];
  int leaveDashboardCalls = 0;
  int clearRoutineSelectionCalls = 0;
  late final ChatPageWorkspaceNavigationCoordinator coordinator;
}

void main() {
  group('switchWorkspaceMode', () {
    test('activates a fresh Chat scope and selects General mode', () async {
      final harness = _Harness(assistantMode: AssistantMode.coding);

      await harness.coordinator.switchWorkspaceMode(WorkspaceMode.chat);

      expect(harness.leaveDashboardCalls, 1);
      expect(harness.conversationsNotifier.activations, hasLength(1));
      _expectActivation(
        harness.conversationsNotifier.activations.single,
        workspaceMode: WorkspaceMode.chat,
        projectId: null,
        createIfMissing: true,
        createFreshOnFirstOpen: true,
        deferFreshConversationCreation: false,
      );
      expect(harness.assistantModeUpdates, [AssistantMode.general]);
    });

    test('opens Routines home without changing assistant mode', () async {
      final harness = _Harness(assistantMode: AssistantMode.plan);

      await harness.coordinator.switchWorkspaceMode(WorkspaceMode.routines);

      expect(harness.leaveDashboardCalls, 1);
      _expectActivation(
        harness.conversationsNotifier.activations.single,
        workspaceMode: WorkspaceMode.routines,
        projectId: null,
        createIfMissing: false,
        createFreshOnFirstOpen: false,
        deferFreshConversationCreation: false,
      );
      expect(harness.clearRoutineSelectionCalls, 1);
      expect(harness.assistantModeUpdates, isEmpty);
    });

    test(
      'prefers the active Coding project and defers a fresh thread',
      () async {
        final harness = _Harness(
          conversationsState: ConversationsState.initial().copyWith(
            activeWorkspaceMode: WorkspaceMode.coding,
            activeProjectId: 'active-project',
          ),
          codingProjectsState: _projectsState(
            selectedProjectId: 'selected-project',
          ),
        );

        await harness.coordinator.switchWorkspaceMode(WorkspaceMode.coding);

        expect(harness.leaveDashboardCalls, 2);
        expect(harness.codingProjectsNotifier.selectedProjectIds, [
          'active-project',
        ]);
        _expectActivation(
          harness.conversationsNotifier.activations.single,
          workspaceMode: WorkspaceMode.coding,
          projectId: 'active-project',
          createIfMissing: true,
          createFreshOnFirstOpen: true,
          deferFreshConversationCreation: true,
        );
        expect(harness.assistantModeUpdates, [AssistantMode.coding]);
      },
    );

    test('uses the selected project when no active project exists', () async {
      final harness = _Harness(
        codingProjectsState: _projectsState(
          selectedProjectId: 'selected-project',
        ),
      );

      await harness.coordinator.switchWorkspaceMode(WorkspaceMode.coding);

      expect(harness.codingProjectsNotifier.selectedProjectIds, [
        'selected-project',
      ]);
      expect(
        harness.conversationsNotifier.activations.single.projectId,
        'selected-project',
      );
    });

    test('opens an empty Coding scope when no project is selected', () async {
      final harness = _Harness();

      await harness.coordinator.switchWorkspaceMode(WorkspaceMode.coding);

      expect(harness.leaveDashboardCalls, 1);
      expect(harness.codingProjectsNotifier.selectedProjectIds, isEmpty);
      _expectActivation(
        harness.conversationsNotifier.activations.single,
        workspaceMode: WorkspaceMode.coding,
        projectId: null,
        createIfMissing: false,
        createFreshOnFirstOpen: false,
        deferFreshConversationCreation: false,
      );
      expect(harness.assistantModeUpdates, [AssistantMode.coding]);
    });
  });

  test(
    'activateCodingProject preserves a non-General assistant mode',
    () async {
      final harness = _Harness(assistantMode: AssistantMode.plan);

      await harness.coordinator.activateCodingProject('project-1');

      expect(harness.leaveDashboardCalls, 1);
      expect(harness.codingProjectsNotifier.selectedProjectIds, ['project-1']);
      _expectActivation(
        harness.conversationsNotifier.activations.single,
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: false,
        createFreshOnFirstOpen: false,
        deferFreshConversationCreation: false,
      );
      expect(harness.assistantModeUpdates, [AssistantMode.plan]);
    },
  );

  group('selectConversation', () {
    test('exits the dashboard but ignores a missing conversation', () async {
      final harness = _Harness();

      await harness.coordinator.selectConversation('missing');

      expect(harness.leaveDashboardCalls, 1);
      expect(harness.conversationsNotifier.selectedConversationIds, isEmpty);
      expect(harness.codingProjectsNotifier.selectedProjectIds, isEmpty);
      expect(harness.assistantModeUpdates, isEmpty);
    });

    test('selects the Coding project and promotes General mode', () async {
      final conversation = _conversation(
        id: 'thread-1',
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      final harness = _Harness(
        conversationsState: _conversationsState([conversation]),
      );

      await harness.coordinator.selectConversation(conversation.id);

      expect(harness.leaveDashboardCalls, 1);
      expect(harness.codingProjectsNotifier.selectedProjectIds, ['project-1']);
      expect(harness.conversationsNotifier.selectedConversationIds, [
        'thread-1',
      ]);
      expect(harness.assistantModeUpdates, [AssistantMode.coding]);
    });

    test(
      'does not select a project for an unscoped Coding conversation',
      () async {
        final conversation = _conversation(
          id: 'thread-1',
          workspaceMode: WorkspaceMode.coding,
        );
        final harness = _Harness(
          conversationsState: _conversationsState([conversation]),
          assistantMode: AssistantMode.plan,
        );

        await harness.coordinator.selectConversation(conversation.id);

        expect(harness.codingProjectsNotifier.selectedProjectIds, isEmpty);
        expect(harness.conversationsNotifier.selectedConversationIds, [
          'thread-1',
        ]);
        expect(harness.assistantModeUpdates, [AssistantMode.plan]);
      },
    );

    test('selects General mode for a Chat conversation', () async {
      final conversation = _conversation(
        id: 'chat-1',
        workspaceMode: WorkspaceMode.chat,
      );
      final harness = _Harness(
        conversationsState: _conversationsState([conversation]),
        assistantMode: AssistantMode.coding,
      );

      await harness.coordinator.selectConversation(conversation.id);

      expect(harness.conversationsNotifier.selectedConversationIds, ['chat-1']);
      expect(harness.assistantModeUpdates, [AssistantMode.general]);
    });

    test(
      'does not change assistant mode for a Routines conversation',
      () async {
        final conversation = _conversation(
          id: 'routine-1',
          workspaceMode: WorkspaceMode.routines,
        );
        final harness = _Harness(
          conversationsState: _conversationsState([conversation]),
          assistantMode: AssistantMode.plan,
        );

        await harness.coordinator.selectConversation(conversation.id);

        expect(harness.conversationsNotifier.selectedConversationIds, [
          'routine-1',
        ]);
        expect(harness.assistantModeUpdates, isEmpty);
      },
    );
  });
}

void _expectActivation(
  _WorkspaceActivation activation, {
  required WorkspaceMode workspaceMode,
  required String? projectId,
  required bool createIfMissing,
  required bool createFreshOnFirstOpen,
  required bool deferFreshConversationCreation,
}) {
  expect(activation.workspaceMode, workspaceMode);
  expect(activation.projectId, projectId);
  expect(activation.createIfMissing, createIfMissing);
  expect(activation.createFreshOnFirstOpen, createFreshOnFirstOpen);
  expect(
    activation.deferFreshConversationCreation,
    deferFreshConversationCreation,
  );
}

CodingProjectsState _projectsState({required String selectedProjectId}) {
  final now = DateTime(2026, 7, 19, 10);
  return CodingProjectsState(
    projects: [
      CodingProject(
        id: selectedProjectId,
        name: 'sample_app',
        rootPath: '/tmp/sample_app',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    selectedProjectId: selectedProjectId,
  );
}

ConversationsState _conversationsState(List<Conversation> conversations) {
  return ConversationsState(
    conversations: conversations,
    currentConversationId: null,
    activeWorkspaceMode: WorkspaceMode.chat,
    activeProjectId: null,
  );
}

Conversation _conversation({
  required String id,
  required WorkspaceMode workspaceMode,
  String projectId = '',
}) {
  final now = DateTime(2026, 7, 19, 10);
  return Conversation(
    id: id,
    title: id,
    messages: const [],
    createdAt: now,
    updatedAt: now,
    workspaceMode: workspaceMode,
    projectId: projectId,
  );
}
