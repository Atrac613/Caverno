import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_turn_cache.dart';
import 'package:caverno/features/chat/domain/services/production_release_approval_coordinator.dart';
import 'package:test/test.dart';

void main() {
  late Map<int, ChatTurnOwner> owners;
  late Map<int, String> activeConversations;
  late ProductionReleaseApprovalCoordinator coordinator;

  setUp(() {
    owners = {7: _owner()};
    activeConversations = {7: 'conversation-a'};
    coordinator = ProductionReleaseApprovalCoordinator(
      activeConversationId: (generation) => activeConversations[generation],
      ownerForGeneration: (generation) => owners[generation],
      questionResults: AskUserQuestionTurnCache(),
    );
  });

  test('keeps captured approval scoped to its generation and conversation', () {
    coordinator.captureProof(
      generation: 7,
      conversation: _conversation(),
      submittedContent: 'Run the production release now.',
    );

    expect(coordinator.evidenceFor(7).approved, isTrue);

    activeConversations[7] = 'conversation-b';
    expect(coordinator.evidenceFor(7).approved, isFalse);

    activeConversations[7] = 'conversation-a';
    coordinator.clearGeneration(7);
    expect(coordinator.evidenceFor(7).approved, isFalse);
  });

  test('accepts an affirmative reply only after an approval prompt', () {
    coordinator.captureProof(
      generation: 7,
      conversation: _conversation(
        messages: [
          _message(
            MessageRole.assistant,
            'Do you approve the production release command?',
          ),
        ],
      ),
      submittedContent: 'Yes, proceed.',
    );

    expect(coordinator.evidenceFor(7).approved, isTrue);
  });

  test('tracks a blocked release until the owner approves it', () {
    final toolCall = ToolCallInfo(
      id: 'release-call',
      name: 'local_execute_command',
      arguments: const {'command': './release_ios_macos.sh'},
    );
    final blocked = coordinator.buildGuardResult(
      toolCall,
      currentAssistantContent: 'I will release now.',
      evidence: coordinator.evidenceFor(7),
    );

    expect(blocked, isNotNull);
    expect(
      jsonDecode(blocked!.result),
      containsPair('code', 'production_release_explicit_approval_required'),
    );
    expect(
      coordinator.pendingRelease('conversation-a')?.command,
      './release_ios_macos.sh',
    );

    coordinator.captureProof(
      generation: 7,
      conversation: _conversation(),
      submittedContent: 'I explicitly approve the production release.',
    );
    final allowed = coordinator.buildGuardResult(
      toolCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );

    expect(allowed, isNull);
    expect(coordinator.pendingRelease('conversation-a'), isNull);
  });
}

ChatTurnOwner _owner() =>
    ChatTurnOwner(conversationId: 'conversation-a', interactionGeneration: 7);

Conversation _conversation({List<Message> messages = const []}) {
  final now = DateTime(2026, 8, 15);
  return Conversation(
    id: 'conversation-a',
    title: 'Release',
    messages: messages,
    createdAt: now,
    updatedAt: now,
  );
}

Message _message(MessageRole role, String content) => Message(
  id: 'message',
  content: content,
  role: role,
  timestamp: DateTime(2026, 8, 15),
);
