import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/presentation/providers/active_response_registry.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/turn_owner_snapshot_registry.dart';

void main() {
  group('ChatTurnOwner', () {
    test('validates, normalizes, and compares the composite identity', () {
      final owner = ChatTurnOwner(
        conversationId: ' conversation-a ',
        interactionGeneration: 7,
      );
      final equalOwner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 7,
      );

      expect(owner.conversationId, 'conversation-a');
      expect(owner.interactionGeneration, 7);
      expect(owner, same(owner));
      expect(owner, equalOwner);
      expect(owner.hashCode, equalOwner.hashCode);
      expect(
        owner,
        isNot(
          ChatTurnOwner(
            conversationId: 'conversation-b',
            interactionGeneration: 7,
          ),
        ),
      );
      expect(
        owner,
        isNot(
          ChatTurnOwner(
            conversationId: 'conversation-a',
            interactionGeneration: 8,
          ),
        ),
      );
      expect(owner, isNot(equals('conversation-a')));
      expect(
        owner.toString(),
        'ChatTurnOwner('
        'conversationId: conversation-a, '
        'interactionGeneration: 7'
        ')',
      );
    });

    test('rejects empty conversation ids and non-positive generations', () {
      expect(
        () => ChatTurnOwner(conversationId: '   ', interactionGeneration: 1),
        throwsArgumentError,
      );
      expect(
        () => ChatTurnOwner(
          conversationId: 'conversation-a',
          interactionGeneration: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TurnOwnerSnapshot.capture', () {
    test('derives owner facts and deeply freezes mutable inputs', () {
      final owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 7,
      );
      final messages = <Message>[
        _message(
          'historical-user',
          MessageRole.user,
          content: 'historical request',
        ),
        _message('assistant', MessageRole.assistant),
      ];
      final participantToolNames = <String>['read_file'];
      final allowedToolNames = <String>{'read_file', 'write_file'};
      final targetFiles = <String>['lib/alpha.dart'];
      final context = LlmSessionLogContext(
        workspaceMode: WorkspaceMode.coding,
        sessionId: 'session-a',
        conversationId: 'conversation-a',
        participantId: 'participant-a',
        participantToolNames: participantToolNames,
      );
      final savedTask = ConversationWorkflowTask(
        id: 'task-a',
        title: 'Implement alpha',
        targetFiles: targetFiles,
        validationCommand: 'flutter test',
      );
      final turnUserMessage = _message(
        'turn-user',
        MessageRole.user,
        content: '  current request  ',
        originalImagePath: '/tmp/reference.png',
      );
      final hiddenPromptToolNames = <String>['read_file'];
      final hiddenPrompt = Message(
        id: 'hidden-prompt',
        content: 'Continue privately',
        role: MessageRole.user,
        timestamp: DateTime(2026, 7, 28, 12),
        participantToolNames: hiddenPromptToolNames,
      );

      final snapshot = TurnOwnerSnapshot.capture(
        owner: owner,
        messages: messages,
        turnUserMessage: turnUserMessage,
        projectRoot: '  /workspace/alpha  ',
        sessionLogContext: context,
        conversation: _executionConversation(
          id: 'conversation-a',
          workspaceMode: WorkspaceMode.coding,
          planning: true,
        ),
        assistantModeOverride: null,
        configuredAssistantMode: AssistantMode.general,
        savedTask: savedTask,
        allowedToolNames: allowedToolNames,
        ownerRepositoryPath: '  /repositories/alpha  ',
        ownerWorktreePath: '  /repositories/alpha/worktrees/feature  ',
        hiddenPrompt: hiddenPrompt,
        persistHiddenPromptAssistantResponse: true,
        temporalReferenceContext: 'It is Tuesday at noon.',
      );

      messages.add(_message('poison-message', MessageRole.user));
      participantToolNames.add('delete_file');
      allowedToolNames.add('delete_file');
      targetFiles.add('lib/poison.dart');
      hiddenPromptToolNames.add('delete_file');

      expect(snapshot.owner, owner);
      expect(snapshot.messages.map((message) => message.id), [
        'historical-user',
        'assistant',
      ]);
      expect(snapshot.latestUserContent, 'current request');
      expect(snapshot.hasAttachments, isTrue);
      expect(snapshot.projectRoot, '/workspace/alpha');
      expect(snapshot.sessionLogContext.workspaceMode, WorkspaceMode.coding);
      expect(snapshot.sessionLogContext.sessionId, 'session-a');
      expect(snapshot.sessionLogContext.conversationId, 'conversation-a');
      expect(snapshot.sessionLogContext.participantId, 'participant-a');
      expect(snapshot.sessionLogContext.participantToolNames, ['read_file']);
      expect(snapshot.isCodingWorkspaceOrMode, isTrue);
      expect(snapshot.isPlanning, isTrue);
      expect(snapshot.hasPendingAutoContinueExecutionWorkflow, isTrue);
      expect(snapshot.savedTask?.id, 'task-a');
      expect(snapshot.savedTask?.targetFiles, ['lib/alpha.dart']);
      expect(snapshot.allowedToolNames, {'read_file', 'write_file'});
      expect(snapshot.ownerRepositoryPath, '/repositories/alpha');
      expect(
        snapshot.ownerWorktreePath,
        '/repositories/alpha/worktrees/feature',
      );
      expect(snapshot.hiddenPrompt?.content, 'Continue privately');
      expect(snapshot.hiddenPrompt?.participantToolNames, ['read_file']);
      expect(snapshot.persistHiddenPromptAssistantResponse, isTrue);
      expect(snapshot.temporalReferenceContext, 'It is Tuesday at noon.');

      expect(
        () => snapshot.messages.add(_message('blocked', MessageRole.user)),
        throwsUnsupportedError,
      );
      expect(
        () =>
            snapshot.sessionLogContext.participantToolNames.add('delete_file'),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.savedTask!.targetFiles.add('lib/blocked.dart'),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.allowedToolNames!.add('delete_file'),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.hiddenPrompt!.participantToolNames.add('delete_file'),
        throwsUnsupportedError,
      );
    });

    test('falls back to the latest non-empty user message', () {
      final snapshot = TurnOwnerSnapshot.capture(
        owner: ChatTurnOwner(
          conversationId: 'conversation-a',
          interactionGeneration: 1,
        ),
        messages: [
          _message(
            'older-user',
            MessageRole.user,
            content: ' older request ',
            imageBase64: 'image-payload',
          ),
          _message('blank-user', MessageRole.user, content: '   '),
          _message('assistant', MessageRole.assistant),
        ],
        turnUserMessage: _message(
          'blank-turn-user',
          MessageRole.user,
          content: ' ',
        ),
        projectRoot: ' ',
        sessionLogContext: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.chat,
          sessionId: 'session-a',
        ),
        conversation: null,
        assistantModeOverride: AssistantMode.coding,
        configuredAssistantMode: AssistantMode.general,
        savedTask: null,
        allowedToolNames: null,
      );

      expect(snapshot.latestUserContent, 'older request');
      expect(snapshot.hasAttachments, isTrue);
      expect(snapshot.projectRoot, isNull);
      expect(snapshot.isCodingWorkspaceOrMode, isTrue);
      expect(snapshot.isPlanning, isFalse);
      expect(snapshot.hasPendingAutoContinueExecutionWorkflow, isFalse);
      expect(snapshot.savedTask, isNull);
      expect(snapshot.allowedToolNames, isNull);
      expect(snapshot.ownerRepositoryPath, isNull);
      expect(snapshot.ownerWorktreePath, isNull);
    });

    test('represents no content, project, attachment, or allowed tools', () {
      final snapshot = TurnOwnerSnapshot.capture(
        owner: ChatTurnOwner(
          conversationId: 'conversation-a',
          interactionGeneration: 1,
        ),
        messages: [
          _message('assistant', MessageRole.assistant),
          _message('blank-user', MessageRole.user, content: ' '),
        ],
        turnUserMessage: null,
        projectRoot: null,
        sessionLogContext: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.chat,
          sessionId: 'session-a',
        ),
        conversation: _conversation(id: 'conversation-a'),
        assistantModeOverride: null,
        configuredAssistantMode: AssistantMode.general,
        savedTask: null,
        allowedToolNames: <String>{},
      );

      expect(snapshot.latestUserContent, isEmpty);
      expect(snapshot.hasAttachments, isFalse);
      expect(snapshot.projectRoot, isNull);
      expect(snapshot.isCodingWorkspaceOrMode, isFalse);
      expect(snapshot.isPlanning, isFalse);
      expect(snapshot.hasPendingAutoContinueExecutionWorkflow, isFalse);
      expect(snapshot.allowedToolNames, isEmpty);
      expect(snapshot.ownerRepositoryPath, isNull);
      expect(snapshot.ownerWorktreePath, isNull);
    });

    test(
      'detects configured coding mode and rejects non-executable workflows',
      () {
        final inactiveGoal = _executionConversation(
          id: 'conversation-a',
        ).copyWith(goal: _goal(autoContinue: false));
        final snapshot = TurnOwnerSnapshot.capture(
          owner: ChatTurnOwner(
            conversationId: 'conversation-a',
            interactionGeneration: 1,
          ),
          messages: const <Message>[],
          turnUserMessage: null,
          projectRoot: null,
          sessionLogContext: const LlmSessionLogContext(
            workspaceMode: WorkspaceMode.coding,
            sessionId: 'session-a',
          ),
          conversation: inactiveGoal,
          assistantModeOverride: null,
          configuredAssistantMode: AssistantMode.coding,
          savedTask: null,
          allowedToolNames: null,
        );

        expect(snapshot.isCodingWorkspaceOrMode, isTrue);
        expect(snapshot.hasPendingAutoContinueExecutionWorkflow, isFalse);
      },
    );
  });

  group('TurnOwnerSnapshot.buildSessionLogContext', () {
    test('prefers target and conversation identities for chat phases', () {
      final conversation = _conversation(
        id: 'conversation-a',
      ).copyWith(title: 'Alpha thread');

      final chatContext = TurnOwnerSnapshot.buildSessionLogContext(
        conversation: conversation,
        targetConversationId: 'target-conversation',
        fallbackConversationId: 'fallback-conversation',
        configuredAssistantMode: AssistantMode.general,
        hasHiddenPrompt: false,
        isRemoteInteraction: false,
      );
      final remoteContext = TurnOwnerSnapshot.buildSessionLogContext(
        conversation: conversation,
        targetConversationId: null,
        fallbackConversationId: 'fallback-conversation',
        configuredAssistantMode: AssistantMode.general,
        hasHiddenPrompt: false,
        isRemoteInteraction: true,
      );

      expect(chatContext.workspaceMode, WorkspaceMode.chat);
      expect(chatContext.sessionId, 'target-conversation');
      expect(chatContext.conversationId, 'target-conversation');
      expect(chatContext.sessionTitle, 'Alpha thread');
      expect(chatContext.phase, 'chat_turn');

      expect(remoteContext.workspaceMode, WorkspaceMode.chat);
      expect(remoteContext.sessionId, 'conversation-a');
      expect(remoteContext.conversationId, 'conversation-a');
      expect(remoteContext.sessionTitle, 'Alpha thread');
      expect(remoteContext.phase, 'remote_interaction');
    });

    test('maps coding and plan modes to coding session contexts', () {
      final codingContext = TurnOwnerSnapshot.buildSessionLogContext(
        conversation: null,
        targetConversationId: null,
        fallbackConversationId: 'coding-fallback',
        configuredAssistantMode: AssistantMode.coding,
        hasHiddenPrompt: true,
        isRemoteInteraction: true,
      );
      final planContext = TurnOwnerSnapshot.buildSessionLogContext(
        conversation: null,
        targetConversationId: null,
        fallbackConversationId: 'plan-fallback',
        configuredAssistantMode: AssistantMode.plan,
        hasHiddenPrompt: false,
        isRemoteInteraction: false,
      );

      expect(codingContext.workspaceMode, WorkspaceMode.coding);
      expect(codingContext.sessionId, 'coding-fallback');
      expect(codingContext.conversationId, 'coding-fallback');
      expect(codingContext.sessionTitle, isNull);
      expect(codingContext.phase, 'hidden_prompt');

      expect(planContext.workspaceMode, WorkspaceMode.coding);
      expect(planContext.sessionId, 'plan-fallback');
      expect(planContext.conversationId, 'plan-fallback');
      expect(planContext.sessionTitle, isNull);
      expect(planContext.phase, 'chat_turn');
    });

    test(
      'uses chat fallback and unassigned identities without a conversation',
      () {
        final fallbackContext = TurnOwnerSnapshot.buildSessionLogContext(
          conversation: null,
          targetConversationId: null,
          fallbackConversationId: 'chat-fallback',
          configuredAssistantMode: AssistantMode.general,
          hasHiddenPrompt: false,
          isRemoteInteraction: true,
        );
        final unassignedContext = TurnOwnerSnapshot.buildSessionLogContext(
          conversation: null,
          targetConversationId: null,
          fallbackConversationId: null,
          configuredAssistantMode: AssistantMode.general,
          hasHiddenPrompt: false,
          isRemoteInteraction: false,
        );

        expect(fallbackContext.workspaceMode, WorkspaceMode.chat);
        expect(fallbackContext.sessionId, 'chat-fallback');
        expect(fallbackContext.conversationId, 'chat-fallback');
        expect(fallbackContext.phase, 'remote_interaction');

        expect(unassignedContext.workspaceMode, WorkspaceMode.chat);
        expect(unassignedContext.sessionId, 'unassigned');
        expect(unassignedContext.conversationId, 'unassigned');
        expect(unassignedContext.sessionTitle, isNull);
        expect(unassignedContext.phase, 'chat_turn');
      },
    );
  });

  group('TurnOwnerSnapshot.savedTaskFor', () {
    test('returns null for missing conversations and workflows', () {
      expect(TurnOwnerSnapshot.savedTaskFor(null), isNull);
      expect(
        TurnOwnerSnapshot.savedTaskFor(_conversation(id: 'conversation-empty')),
        isNull,
      );
    });

    test('prefers a validation task and freezes its target files', () {
      final targetFiles = <String>['lib/validate.dart'];
      final conversation = _conversation(
        id: 'conversation-validation',
        workflowSpec: ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-validation',
              title: 'Validate the implementation',
              status: ConversationWorkflowTaskStatus.inProgress,
              targetFiles: targetFiles,
              validationCommand: 'flutter test',
            ),
            const ConversationWorkflowTask(
              id: 'task-next',
              title: 'Continue implementation',
            ),
          ],
        ),
      );

      final savedTask = TurnOwnerSnapshot.savedTaskFor(conversation);
      targetFiles.add('lib/poison.dart');

      expect(savedTask?.id, 'task-validation');
      expect(savedTask?.targetFiles, ['lib/validate.dart']);
      expect(
        () => savedTask!.targetFiles.add('lib/blocked.dart'),
        throwsUnsupportedError,
      );
    });

    test('falls back to the exact execution focus without validation', () {
      final conversation = _conversation(
        id: 'conversation-execution',
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-execution',
              title: 'Implement the feature',
              targetFiles: ['lib/feature.dart'],
            ),
          ],
        ),
      );

      final savedTask = TurnOwnerSnapshot.savedTaskFor(conversation);

      expect(savedTask?.id, 'task-execution');
      expect(savedTask?.targetFiles, ['lib/feature.dart']);
    });
  });

  group('TurnOwnerSnapshotRegistry', () {
    test('isolates equal generations across different conversations', () {
      final registry = TurnOwnerSnapshotRegistry();
      final ownerA = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 11,
      );
      final ownerB = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 11,
      );
      final snapshotA = _snapshot(
        ownerA,
        marker: 'alpha',
        allowedToolNames: {'read_file'},
        hiddenPrompt: _message(
          'hidden-alpha',
          MessageRole.user,
          content: 'private alpha',
        ),
        temporalReferenceContext: 'alpha time',
      );
      final snapshotB = _snapshot(
        ownerB,
        marker: 'beta',
        allowedToolNames: {'write_file'},
        hiddenPrompt: _message(
          'hidden-beta',
          MessageRole.user,
          content: 'private beta',
        ),
        temporalReferenceContext: 'beta time',
      );

      expect(registry.isEmpty, isTrue);
      registry.capture(snapshotA);
      registry.capture(snapshotB);

      expect(registry.length, 2);
      expect(registry.isEmpty, isFalse);
      expect(registry.snapshotFor(ownerA)?.latestUserContent, 'alpha');
      expect(registry.snapshotFor(ownerA)?.projectRoot, '/workspace/alpha');
      expect(registry.snapshotFor(ownerA)?.messages.single.content, 'alpha');
      expect(registry.snapshotFor(ownerA)?.allowedToolNames, {'read_file'});
      expect(
        registry.snapshotFor(ownerA)?.hiddenPrompt?.content,
        'private alpha',
      );
      expect(
        registry.snapshotFor(ownerA)?.temporalReferenceContext,
        'alpha time',
      );
      expect(registry.snapshotFor(ownerB)?.latestUserContent, 'beta');
      expect(registry.snapshotFor(ownerB)?.projectRoot, '/workspace/beta');
      expect(registry.snapshotFor(ownerB)?.messages.single.content, 'beta');
      expect(registry.snapshotFor(ownerB)?.allowedToolNames, {'write_file'});
      expect(
        registry.snapshotFor(ownerB)?.hiddenPrompt?.content,
        'private beta',
      );
      expect(
        registry.snapshotFor(ownerB)?.temporalReferenceContext,
        'beta time',
      );
    });

    test('updates and replaces only the exact owner', () {
      final registry = TurnOwnerSnapshotRegistry();
      final ownerA = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: 11,
      );
      final ownerB = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 11,
      );
      final missing = ChatTurnOwner(
        conversationId: 'conversation-missing',
        interactionGeneration: 11,
      );
      final snapshotB = _snapshot(
        ownerB,
        marker: 'beta',
        allowedToolNames: {'write_file'},
        hiddenPrompt: _message(
          'hidden-beta',
          MessageRole.user,
          content: 'private beta',
        ),
        temporalReferenceContext: 'beta time',
      );
      registry.capture(
        _snapshot(
          ownerA,
          marker: 'alpha',
          allowedToolNames: {'read_file'},
          hiddenPrompt: _message(
            'hidden-alpha',
            MessageRole.user,
            content: 'private alpha',
          ),
          temporalReferenceContext: 'alpha time',
        ),
      );
      registry.capture(snapshotB);

      final updatedTools = <String>{};
      expect(registry.updateAllowedToolNames(ownerA, updatedTools), isTrue);
      updatedTools.add('poison_tool');
      expect(registry.snapshotFor(ownerA)?.allowedToolNames, isEmpty);
      expect(
        registry.snapshotFor(ownerA)?.hiddenPrompt?.content,
        'private alpha',
      );
      expect(
        registry.snapshotFor(ownerA)?.temporalReferenceContext,
        'alpha time',
      );
      expect(registry.snapshotFor(ownerB), same(snapshotB));

      expect(registry.updateAllowedToolNames(ownerA, null), isTrue);
      expect(registry.snapshotFor(ownerA)?.allowedToolNames, isNull);
      expect(registry.snapshotFor(ownerB)?.allowedToolNames, {'write_file'});

      final updatedMessages = <Message>[
        _message('alpha-updated', MessageRole.user, content: 'updated alpha'),
      ];
      expect(registry.updateMessages(ownerA, updatedMessages), isTrue);
      updatedMessages.add(_message('poison-message', MessageRole.user));
      expect(
        registry.snapshotFor(ownerA)?.messages.map((message) => message.id),
        ['alpha-updated'],
      );
      expect(
        registry.snapshotFor(ownerA)?.hiddenPrompt?.content,
        'private alpha',
      );
      expect(
        registry.snapshotFor(ownerA)?.temporalReferenceContext,
        'alpha time',
      );
      expect(registry.snapshotFor(ownerB), same(snapshotB));
      expect(
        registry.snapshotFor(ownerB)?.hiddenPrompt?.content,
        'private beta',
      );
      expect(
        registry.snapshotFor(ownerB)?.temporalReferenceContext,
        'beta time',
      );

      final replacement = _snapshot(
        ownerA,
        marker: 'replacement',
        allowedToolNames: {'run_tests'},
      );
      registry.capture(replacement);

      expect(registry.snapshotFor(ownerA), same(replacement));
      expect(registry.snapshotFor(ownerB), same(snapshotB));
      expect(
        registry.updateAllowedToolNames(missing, {'delete_file'}),
        isFalse,
      );
      expect(
        registry.updateMessages(missing, [
          _message('missing', MessageRole.user),
        ]),
        isFalse,
      );
      expect(registry.snapshotFor(missing), isNull);
    });

    test(
      'dispose and clear cannot cross owner boundaries or revive owners',
      () {
        final registry = TurnOwnerSnapshotRegistry();
        final ownerA = ChatTurnOwner(
          conversationId: 'conversation-a',
          interactionGeneration: 11,
        );
        final ownerB = ChatTurnOwner(
          conversationId: 'conversation-b',
          interactionGeneration: 11,
        );
        final snapshotA = _snapshot(ownerA, marker: 'alpha');
        final snapshotB = _snapshot(
          ownerB,
          marker: 'beta',
          hiddenPrompt: _message('hidden-beta', MessageRole.user),
          temporalReferenceContext: 'beta time',
        );
        registry.capture(snapshotA);
        registry.capture(snapshotB);

        expect(registry.dispose(ownerA), same(snapshotA));
        expect(registry.snapshotFor(ownerA), isNull);
        expect(registry.snapshotFor(ownerB), same(snapshotB));
        expect(registry.snapshotFor(ownerB)?.hiddenPrompt?.id, 'hidden-beta');
        expect(
          registry.snapshotFor(ownerB)?.temporalReferenceContext,
          'beta time',
        );
        expect(registry.dispose(ownerA), isNull);
        expect(
          registry.updateAllowedToolNames(ownerA, {'delete_file'}),
          isFalse,
        );
        expect(
          registry.updateMessages(ownerA, [
            _message('revived', MessageRole.user),
          ]),
          isFalse,
        );
        expect(registry.snapshotFor(ownerA), isNull);

        registry.clear();

        expect(registry.isEmpty, isTrue);
        expect(registry.length, 0);
        expect(registry.snapshotFor(ownerB), isNull);
      },
    );
  });

  group('ActiveResponseRegistry snapshot lifecycle', () {
    test('registerWithSnapshot captures exact conversation facts', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final generation = registry.beginGeneration();
      final conversation = _executionConversation(
        id: 'conversation-a',
        workspaceMode: WorkspaceMode.coding,
        planning: true,
      );

      registry.registerWithSnapshot(
        generation: generation,
        targetConversationId: 'conversation-a',
        messages: [_message('alpha', MessageRole.user)],
        turnUserMessage: _message(
          'turn-user',
          MessageRole.user,
          content: 'current request',
        ),
        projectRoot: '/workspace/alpha',
        sessionLogContext: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: 'conversation-a',
          conversationId: 'conversation-a',
        ),
        conversation: conversation,
        ownerRepositoryPath: ' /repositories/alpha ',
        ownerWorktreePath: ' /repositories/alpha/worktrees/feature ',
        assistantModeOverride: null,
        configuredAssistantMode: AssistantMode.general,
      );

      final owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: generation,
      );
      final snapshot = registry.snapshotForOwner(owner);
      expect(snapshot?.latestUserContent, 'current request');
      expect(snapshot?.projectRoot, '/workspace/alpha');
      expect(snapshot?.isCodingWorkspaceOrMode, isTrue);
      expect(snapshot?.isPlanning, isTrue);
      expect(snapshot?.hasPendingAutoContinueExecutionWorkflow, isTrue);
      expect(snapshot?.savedTask?.id, 'task-a');
      expect(snapshot?.ownerRepositoryPath, '/repositories/alpha');
      expect(
        snapshot?.ownerWorktreePath,
        '/repositories/alpha/worktrees/feature',
      );
      expect(
        registry.sessionLogContextForGeneration(generation)?.sessionId,
        'conversation-a',
      );
      expect(registry.setTools(generation, {'read_file'}), isTrue);
      expect(registry.snapshotForOwner(owner)?.allowedToolNames, {'read_file'});
      expect(registry.denyTools(generation), isTrue);
      expect(registry.snapshotForOwner(owner)?.allowedToolNames, isEmpty);
      expect(
        registry.snapshotForOwner(owner)?.ownerRepositoryPath,
        '/repositories/alpha',
      );
      expect(
        registry.snapshotForOwner(owner)?.ownerWorktreePath,
        '/repositories/alpha/worktrees/feature',
      );
      expect(registry.setTools(99, {'delete_file'}), isFalse);
      registry.clearGeneration(generation);
      expect(registry.sessionLogContextForGeneration(generation), isNull);
    });

    test(
      'registerWithSnapshot rejects facts from a different conversation',
      () {
        final snapshots = TurnOwnerSnapshotRegistry();
        final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
        final generation = registry.beginGeneration();

        registry.registerWithSnapshot(
          generation: generation,
          targetConversationId: 'conversation-a',
          messages: [_message('alpha', MessageRole.user)],
          turnUserMessage: null,
          projectRoot: '/workspace/poison',
          sessionLogContext: const LlmSessionLogContext(
            workspaceMode: WorkspaceMode.chat,
            sessionId: 'conversation-a',
            conversationId: 'conversation-a',
          ),
          conversation: _executionConversation(
            id: 'conversation-b',
            workspaceMode: WorkspaceMode.coding,
            planning: true,
          ),
          ownerRepositoryPath: '/repositories/poison',
          ownerWorktreePath: '/repositories/poison/worktrees/feature',
          assistantModeOverride: null,
          configuredAssistantMode: AssistantMode.general,
        );

        final owner = ChatTurnOwner(
          conversationId: 'conversation-a',
          interactionGeneration: generation,
        );
        final snapshot = registry.snapshotForOwner(owner);
        expect(snapshot?.projectRoot, isNull);
        expect(snapshot?.isCodingWorkspaceOrMode, isFalse);
        expect(snapshot?.isPlanning, isFalse);
        expect(snapshot?.hasPendingAutoContinueExecutionWorkflow, isFalse);
        expect(snapshot?.savedTask, isNull);
        expect(snapshot?.ownerRepositoryPath, isNull);
        expect(snapshot?.ownerWorktreePath, isNull);
      },
    );

    test('keeps owner Git paths when another conversation becomes visible', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final generationA = registry.beginGeneration();
      registry.registerWithSnapshot(
        generation: generationA,
        targetConversationId: 'conversation-a',
        messages: [_message('alpha', MessageRole.user)],
        turnUserMessage: null,
        projectRoot: '/worktrees/alpha',
        sessionLogContext: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: 'conversation-a',
          conversationId: 'conversation-a',
        ),
        conversation: _executionConversation(
          id: 'conversation-a',
          workspaceMode: WorkspaceMode.coding,
        ),
        ownerRepositoryPath: '/repositories/alpha',
        ownerWorktreePath: '/worktrees/alpha',
        assistantModeOverride: null,
        configuredAssistantMode: AssistantMode.general,
      );
      final ownerA = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: generationA,
      );

      final generationB = registry.beginGeneration();
      registry.registerWithSnapshot(
        generation: generationB,
        targetConversationId: 'conversation-b',
        messages: [_message('beta', MessageRole.user)],
        turnUserMessage: null,
        projectRoot: '/worktrees/visible-poison',
        sessionLogContext: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: 'conversation-b',
          conversationId: 'conversation-b',
        ),
        conversation: _executionConversation(
          id: 'conversation-b',
          workspaceMode: WorkspaceMode.coding,
        ),
        ownerRepositoryPath: '/repositories/visible-poison',
        ownerWorktreePath: '/worktrees/visible-poison',
        assistantModeOverride: null,
        configuredAssistantMode: AssistantMode.general,
      );
      final ownerB = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: generationB,
      );

      expect(registry.currentConversationId, 'conversation-b');
      expect(
        registry.isDetachedForGeneration(
          generation: generationA,
          visibleConversationId: registry.currentConversationId,
        ),
        isTrue,
      );
      expect(
        registry.snapshotForOwner(ownerA)?.ownerRepositoryPath,
        '/repositories/alpha',
      );
      expect(
        registry.snapshotForOwner(ownerA)?.ownerWorktreePath,
        '/worktrees/alpha',
      );
      expect(
        registry.snapshotForOwner(ownerB)?.ownerRepositoryPath,
        '/repositories/visible-poison',
      );
      expect(
        registry.snapshotForOwner(ownerB)?.ownerWorktreePath,
        '/worktrees/visible-poison',
      );
    });

    test('keeps Git paths generation-scoped within one conversation', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final firstGeneration = registry.beginGeneration();
      registry.registerWithSnapshot(
        generation: firstGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('first', MessageRole.user)],
        turnUserMessage: null,
        projectRoot: '/worktrees/first',
        sessionLogContext: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: 'conversation-a',
          conversationId: 'conversation-a',
        ),
        conversation: _executionConversation(
          id: 'conversation-a',
          workspaceMode: WorkspaceMode.coding,
        ),
        ownerRepositoryPath: '/repositories/original',
        ownerWorktreePath: '/worktrees/first',
        assistantModeOverride: null,
        configuredAssistantMode: AssistantMode.general,
      );
      final firstOwner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: firstGeneration,
      );

      final secondGeneration = registry.beginGeneration();
      registry.registerWithSnapshot(
        generation: secondGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('second', MessageRole.user)],
        turnUserMessage: null,
        projectRoot: '/worktrees/second',
        sessionLogContext: const LlmSessionLogContext(
          workspaceMode: WorkspaceMode.coding,
          sessionId: 'conversation-a',
          conversationId: 'conversation-a',
        ),
        conversation: _executionConversation(
          id: 'conversation-a',
          workspaceMode: WorkspaceMode.coding,
        ),
        ownerRepositoryPath: '/repositories/replacement',
        ownerWorktreePath: '/worktrees/second',
        assistantModeOverride: null,
        configuredAssistantMode: AssistantMode.general,
      );
      final secondOwner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: secondGeneration,
      );

      expect(
        registry.generationForConversation('conversation-a'),
        secondGeneration,
      );
      expect(
        registry.snapshotForOwner(firstOwner)?.ownerRepositoryPath,
        '/repositories/original',
      );
      expect(
        registry.snapshotForOwner(firstOwner)?.ownerWorktreePath,
        '/worktrees/first',
      );
      expect(
        registry.snapshotForOwner(secondOwner)?.ownerRepositoryPath,
        '/repositories/replacement',
      );
      expect(
        registry.snapshotForOwner(secondOwner)?.ownerWorktreePath,
        '/worktrees/second',
      );

      registry.clearGeneration(firstGeneration);

      expect(registry.snapshotForOwner(firstOwner), isNull);
      expect(
        registry.snapshotForOwner(secondOwner)?.ownerWorktreePath,
        '/worktrees/second',
      );
    });

    test('keeps registration, snapshot, updates, and disposal in lockstep', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final generation = registry.beginGeneration();
      final initialMessages = <Message>[
        _message('alpha', MessageRole.user, content: 'alpha request'),
      ];

      registry.register(
        generation: generation,
        targetConversationId: ' conversation-a ',
        messages: initialMessages,
        snapshotBuilder: (owner, ownerMessages) =>
            _snapshot(owner, marker: 'alpha', messages: ownerMessages),
      );
      initialMessages.add(_message('poison-initial', MessageRole.user));

      final owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: generation,
      );
      final wrongOwner = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: generation,
      );
      expect(registry.ownerForGeneration(generation), owner);
      expect(registry.messagesForOwner(owner)?.map((message) => message.id), [
        'alpha',
      ]);
      expect(
        registry.snapshotForOwner(owner)?.messages.map((message) => message.id),
        ['alpha'],
      );
      expect(registry.snapshotForOwner(wrongOwner), isNull);
      expect(snapshots.snapshotFor(owner), registry.snapshotForOwner(owner));

      final allowedToolNames = <String>{'read_file'};
      expect(
        registry.updateAllowedToolNamesForOwner(owner, allowedToolNames),
        isTrue,
      );
      allowedToolNames.add('delete_file');
      expect(registry.snapshotForOwner(owner)?.allowedToolNames, {'read_file'});
      expect(
        registry.updateAllowedToolNamesForOwner(wrongOwner, {'delete_file'}),
        isFalse,
      );

      final updatedMessages = <Message>[
        _message(
          'alpha-updated',
          MessageRole.assistant,
          content: 'updated reply',
        ),
      ];
      expect(registry.cacheMessagesForOwner(owner, updatedMessages), isTrue);
      updatedMessages.add(_message('poison-updated', MessageRole.user));
      expect(registry.messagesForOwner(owner)?.map((message) => message.id), [
        'alpha-updated',
      ]);
      expect(
        registry.snapshotForOwner(owner)?.messages.map((message) => message.id),
        ['alpha-updated'],
      );

      expect(registry.clearOwner(owner), isTrue);
      expect(registry.ownerForGeneration(generation), isNull);
      expect(registry.snapshotForOwner(owner), isNull);
      expect(snapshots.snapshotFor(owner), isNull);
      expect(
        registry.updateAllowedToolNamesForOwner(owner, {'write_file'}),
        isFalse,
      );
      expect(
        registry.cacheMessagesForOwner(owner, [
          _message('disposed', MessageRole.user),
        ]),
        isFalse,
      );
    });

    test('supports direct registration without a snapshot builder', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final generation = registry.beginGeneration();
      registry.register(
        generation: generation,
        targetConversationId: 'conversation-a',
        messages: [_message('alpha', MessageRole.user)],
      );
      final owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: generation,
      );

      expect(registry.containsOwner(owner), isTrue);
      expect(registry.snapshotForOwner(owner), isNull);
      expect(snapshots.isEmpty, isTrue);
      expect(
        registry.updateAllowedToolNamesForOwner(owner, {'read_file'}),
        isFalse,
      );

      registry.cacheMessages(generation, [
        _message('alpha-updated', MessageRole.assistant),
      ]);

      expect(registry.messagesForOwner(owner)?.single.id, 'alpha-updated');
      expect(registry.snapshotForOwner(owner), isNull);
      registry.clearGeneration(generation);
      expect(registry.containsOwner(owner), isFalse);
    });

    test('rolls back registration when the snapshot owner mismatches', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final generation = registry.beginGeneration();

      registry.register(
        generation: generation,
        targetConversationId: 'conversation-a',
        messages: [_message('alpha', MessageRole.user)],
        snapshotBuilder: (owner, messages) => _snapshot(
          ChatTurnOwner(
            conversationId: 'conversation-b',
            interactionGeneration: owner.interactionGeneration,
          ),
          marker: 'poison',
          messages: messages,
        ),
      );

      expect(registry.ownerForGeneration(generation), isNull);
      expect(registry.hasActiveResponse, isFalse);
      expect(registry.openRegistrationCount, 0);
      expect(snapshots.isEmpty, isTrue);
    });

    test('rolls back if a builder invalidates its registration', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final generation = registry.beginGeneration();

      registry.register(
        generation: generation,
        targetConversationId: 'conversation-a',
        messages: [_message('alpha', MessageRole.user)],
        snapshotBuilder: (owner, messages) {
          registry.clearGeneration(generation);
          return _snapshot(owner, marker: 'alpha', messages: messages);
        },
      );

      expect(registry.ownerForGeneration(generation), isNull);
      expect(registry.hasActiveResponse, isFalse);
      expect(snapshots.isEmpty, isTrue);
    });

    test('null registration and missing generation stay absent', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);

      registry.register(
        generation: 1,
        targetConversationId: null,
        messages: [_message('orphan', MessageRole.user)],
        snapshotBuilder: (owner, messages) =>
            _snapshot(owner, marker: 'orphan', messages: messages),
      );
      registry.cacheMessages(1, [_message('missing', MessageRole.user)]);
      registry.clearGeneration(1);

      expect(registry.ownerForGeneration(1), isNull);
      expect(registry.hasActiveResponse, isFalse);
      expect(snapshots.isEmpty, isTrue);
    });

    test('clearAll removes every injected snapshot and registration', () {
      final snapshots = TurnOwnerSnapshotRegistry();
      final registry = ActiveResponseRegistry(ownerSnapshots: snapshots);
      final firstGeneration = registry.beginGeneration();
      registry.register(
        generation: firstGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('alpha', MessageRole.user)],
        snapshotBuilder: (owner, messages) =>
            _snapshot(owner, marker: 'alpha', messages: messages),
      );
      final secondGeneration = registry.beginGeneration();
      registry.register(
        generation: secondGeneration,
        targetConversationId: 'conversation-b',
        messages: [_message('beta', MessageRole.user)],
        snapshotBuilder: (owner, messages) =>
            _snapshot(owner, marker: 'beta', messages: messages),
      );

      expect(snapshots.length, 2);
      expect(registry.openRegistrationCount, 2);

      registry.clearAll();

      expect(snapshots.isEmpty, isTrue);
      expect(registry.hasActiveResponse, isFalse);
      expect(registry.openRegistrationCount, 0);
      expect(registry.currentConversationId, isNull);
      expect(registry.currentMessages, isNull);
    });
  });

  group('ActiveResponseRegistry owner validation', () {
    test('keeps detached lookup and mutations bound to the exact owner', () {
      final registry = ActiveResponseRegistry();
      final generation = registry.beginGeneration();
      final originalMessages = <Message>[
        _message('alpha', MessageRole.user, content: 'alpha'),
      ];
      registry.register(
        generation: generation,
        targetConversationId: 'conversation-a',
        messages: originalMessages,
      );
      final owner = ChatTurnOwner(
        conversationId: 'conversation-a',
        interactionGeneration: generation,
      );
      final mismatchedOwner = ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: generation,
      );

      expect(
        registry.ownerForGeneration(generation),
        ChatTurnOwner(
          conversationId: 'conversation-a',
          interactionGeneration: generation,
        ),
      );
      expect(
        registry.isDetached(visibleConversationId: 'conversation-b'),
        true,
      );
      expect(registry.containsOwner(owner), isTrue);
      expect(registry.messagesForOwner(owner), originalMessages);

      expect(registry.containsOwner(mismatchedOwner), isFalse);
      expect(registry.messagesForOwner(mismatchedOwner), isNull);
      expect(
        registry.cacheMessagesForOwner(mismatchedOwner, [
          _message('poison', MessageRole.user),
        ]),
        isFalse,
      );
      expect(registry.clearOwner(mismatchedOwner), isFalse);
      expect(registry.messagesForOwner(owner), originalMessages);

      final updatedMessages = <Message>[
        _message('alpha-updated', MessageRole.user, content: 'updated'),
      ];
      expect(registry.cacheMessagesForOwner(owner, updatedMessages), isTrue);
      updatedMessages.add(_message('poison', MessageRole.user));
      expect(registry.messagesForOwner(owner)?.map((message) => message.id), [
        'alpha-updated',
      ]);

      expect(registry.clearOwner(owner), isTrue);
      expect(registry.containsOwner(owner), isFalse);
      expect(registry.messagesForOwner(owner), isNull);
      expect(registry.ownerForGeneration(generation), isNull);
      expect(registry.clearOwner(owner), isFalse);
    });

    test('missing registrations never manufacture an owner', () {
      final registry = ActiveResponseRegistry();
      registry.register(
        generation: 1,
        targetConversationId: null,
        messages: [_message('orphan', MessageRole.user)],
      );

      expect(registry.ownerForGeneration(1), isNull);
      expect(
        registry.containsOwner(
          ChatTurnOwner(
            conversationId: 'conversation-a',
            interactionGeneration: 1,
          ),
        ),
        isFalse,
      );
    });

    test('normalizes registrations and rejects invalid owner identities', () {
      final registry = ActiveResponseRegistry();
      final generation = registry.beginGeneration();

      expect(registry.currentGeneration, generation);
      registry.register(
        generation: generation,
        targetConversationId: '  conversation-a  ',
        messages: [_message('alpha', MessageRole.user)],
      );

      expect(registry.currentConversationId, 'conversation-a');
      expect(registry.activeConversationIds, {'conversation-a'});
      expect(registry.isCurrentOrRegistered(generation), isTrue);
      expect(
        registry.conversationIdForGeneration(generation),
        'conversation-a',
      );
      expect(registry.generationForConversation('conversation-a'), generation);
      expect(
        registry.ownerForGeneration(generation),
        ChatTurnOwner(
          conversationId: 'conversation-a',
          interactionGeneration: generation,
        ),
      );

      expect(
        () => registry.register(
          generation: 0,
          targetConversationId: 'conversation-invalid',
          messages: const <Message>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => registry.register(
          generation: generation,
          targetConversationId: '   ',
          messages: const <Message>[],
        ),
        throwsArgumentError,
      );
    });

    test('retains the current mirror and reports detached generations', () {
      final registry = ActiveResponseRegistry();
      final firstGeneration = registry.beginGeneration();
      registry.register(
        generation: firstGeneration,
        targetConversationId: 'conversation-a',
        messages: [_message('alpha', MessageRole.user)],
      );
      final secondGeneration = registry.beginGeneration();

      expect(registry.currentGeneration, secondGeneration);
      expect(registry.isCurrentOrRegistered(firstGeneration), isTrue);
      expect(registry.isCurrentOrRegistered(secondGeneration), isTrue);
      expect(registry.isCurrentOrRegistered(99), isFalse);
      expect(
        registry.conversationIdForGeneration(secondGeneration),
        'conversation-a',
      );
      expect(
        registry.messagesForGeneration(secondGeneration)?.single.id,
        'alpha',
      );
      expect(
        registry.isDetachedForGeneration(
          generation: firstGeneration,
          visibleConversationId: 'conversation-b',
        ),
        isTrue,
      );
      expect(
        registry.isDetachedForGeneration(
          generation: firstGeneration,
          visibleConversationId: 'conversation-a',
        ),
        isFalse,
      );
      expect(
        registry.isDetachedForGeneration(
          generation: 99,
          visibleConversationId: 'conversation-a',
        ),
        isFalse,
      );
    });

    test(
      'keeps the newest registration for the same normalized conversation',
      () {
        final registry = ActiveResponseRegistry();
        final firstGeneration = registry.beginGeneration();
        registry.register(
          generation: firstGeneration,
          targetConversationId: ' conversation-a ',
          messages: [_message('alpha-first', MessageRole.user)],
        );
        final secondGeneration = registry.beginGeneration();
        registry.register(
          generation: secondGeneration,
          targetConversationId: 'conversation-a',
          messages: [_message('alpha-second', MessageRole.user)],
        );

        expect(
          registry.generationForConversation('conversation-a'),
          secondGeneration,
        );
        expect(registry.generationForConversation(null), isNull);
        expect(registry.openRegistrationCount, 2);
        expect(
          registry.describeOpenRegistrations(),
          contains('gen-$firstGeneration:conversa(1)'),
        );
        expect(
          registry.describeOpenRegistrations(),
          contains('gen-$secondGeneration:conversa(1)'),
        );
      },
    );
  });

  group('chatStateReportsConversationBusy', () {
    ChatState stateWith({
      Set<String> busy = const <String>{},
      bool isLoading = false,
      bool isGeneratingWorkflowProposal = false,
      bool isGeneratingTaskProposal = false,
    }) {
      return ChatState.initial().copyWith(
        busyConversationIds: busy,
        isLoading: isLoading,
        isGeneratingWorkflowProposal: isGeneratingWorkflowProposal,
        isGeneratingTaskProposal: isGeneratingTaskProposal,
      );
    }

    test('rejects empty and non-visible idle conversations', () {
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(isLoading: true),
          targetConversationId: ' ',
          visibleConversationId: 'conversation-a',
        ),
        isFalse,
      );
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-b',
        ),
        isFalse,
      );
    });

    test('reports mirrored and visible proposal activity', () {
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(busy: {'conversation-a'}),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-b',
        ),
        isTrue,
      );
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(isLoading: true),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-a',
        ),
        isTrue,
      );
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(isGeneratingWorkflowProposal: true),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-a',
        ),
        isTrue,
      );
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(isGeneratingTaskProposal: true),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-a',
        ),
        isTrue,
      );
      expect(
        chatStateReportsConversationBusy(
          state: stateWith(),
          targetConversationId: 'conversation-a',
          visibleConversationId: 'conversation-a',
        ),
        isFalse,
      );
    });
  });
}

TurnOwnerSnapshot _snapshot(
  ChatTurnOwner owner, {
  required String marker,
  Set<String>? allowedToolNames,
  List<Message>? messages,
  String? ownerRepositoryPath,
  String? ownerWorktreePath,
  Message? hiddenPrompt,
  String? temporalReferenceContext,
}) {
  return TurnOwnerSnapshot(
    owner: owner,
    messages: messages ?? [_message(marker, MessageRole.user, content: marker)],
    latestUserContent: marker,
    hasAttachments: marker == 'alpha',
    projectRoot: '/workspace/$marker',
    sessionLogContext: LlmSessionLogContext(
      workspaceMode: marker == 'alpha'
          ? WorkspaceMode.coding
          : WorkspaceMode.chat,
      sessionId: 'session-$marker',
      conversationId: owner.conversationId,
    ),
    isCodingWorkspaceOrMode: marker == 'alpha',
    isPlanning: marker == 'alpha',
    hasPendingAutoContinueExecutionWorkflow: marker == 'alpha',
    savedTask: ConversationWorkflowTask(
      id: 'task-$marker',
      title: 'Task $marker',
      targetFiles: ['lib/$marker.dart'],
    ),
    allowedToolNames: allowedToolNames,
    ownerRepositoryPath: ownerRepositoryPath,
    ownerWorktreePath: ownerWorktreePath,
    hiddenPrompt: hiddenPrompt,
    temporalReferenceContext: temporalReferenceContext,
  );
}

Conversation _executionConversation({
  required String id,
  WorkspaceMode workspaceMode = WorkspaceMode.chat,
  bool planning = false,
}) {
  return _conversation(
    id: id,
    workspaceMode: workspaceMode,
    executionMode: planning
        ? ConversationExecutionMode.planning
        : ConversationExecutionMode.normal,
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: const ConversationWorkflowSpec(
      goal: 'Ship alpha',
      tasks: [ConversationWorkflowTask(id: 'task-a', title: 'Implement alpha')],
    ),
    goal: _goal(autoContinue: true),
  );
}

Conversation _conversation({
  required String id,
  WorkspaceMode workspaceMode = WorkspaceMode.chat,
  ConversationExecutionMode executionMode = ConversationExecutionMode.normal,
  ConversationWorkflowStage workflowStage = ConversationWorkflowStage.idle,
  ConversationWorkflowSpec? workflowSpec,
  ConversationGoal? goal,
}) {
  final timestamp = DateTime(2026, 7, 28, 12);
  return Conversation(
    id: id,
    title: id,
    messages: const <Message>[],
    createdAt: timestamp,
    updatedAt: timestamp,
    workspaceMode: workspaceMode,
    executionMode: executionMode,
    workflowStage: workflowStage,
    workflowSpec: workflowSpec,
    goal: goal,
  );
}

ConversationGoal _goal({required bool autoContinue}) {
  final timestamp = DateTime(2026, 7, 28, 12);
  return ConversationGoal(
    id: 'goal-a',
    objective: 'Ship alpha',
    autoContinue: autoContinue,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Message _message(
  String id,
  MessageRole role, {
  String? content,
  String? imageBase64,
  String? originalImagePath,
}) {
  return Message(
    id: id,
    content: content ?? id,
    role: role,
    timestamp: DateTime(2026, 7, 28, 12),
    imageBase64: imageBase64,
    originalImagePath: originalImagePath,
  );
}
