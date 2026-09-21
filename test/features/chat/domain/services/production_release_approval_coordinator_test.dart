import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/ask_user_question_turn_cache.dart';
import 'package:caverno/features/chat/domain/services/production_release_approval_coordinator.dart';
import 'package:caverno/features/chat/domain/services/production_release_dispatch_evidence.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  late Map<int, ChatTurnOwner> owners;
  late Map<int, String> activeConversations;
  late AskUserQuestionTurnCache questionResults;
  late ProductionReleaseApprovalCoordinator coordinator;
  const token = 'rel-0123456789abcdef';

  setUp(() {
    owners = {7: _owner()};
    activeConversations = {7: 'conversation-a'};
    questionResults = AskUserQuestionTurnCache();
    coordinator = ProductionReleaseApprovalCoordinator(
      activeConversationId: (generation) => activeConversations[generation],
      ownerForGeneration: (generation) => owners[generation],
      questionResults: questionResults,
      approvalTokenFactory: () => token,
    );
  });

  /// Records the user selecting the one offered option carrying [token].
  void selectTokenOption({String approveLabel = 'Approve $token'}) {
    questionResults.store(
      owner: _owner(),
      question: 'Approve the production release?',
      optionLabels: [approveLabel, 'Cancel'],
      result: McpToolResult(
        toolName: 'ask_user_question',
        result: jsonEncode({
          'status': 'answered',
          'question': 'Approve the production release?',
          'selected': [
            {'label': approveLabel},
          ],
          'answer': approveLabel,
        }),
        isSuccess: true,
      ),
    );
  }

  test('a chat message never approves, and the divergence is recorded', () {
    coordinator.captureProof(
      generation: 7,
      conversation: _conversation(),
      submittedContent: 'Run the production release now.',
    );

    final evidence = coordinator.evidenceFor(7);
    expect(evidence.approved, isFalse);
    expect(
      evidence.proseWouldApprove,
      isTrue,
      reason: 'the retired predicates still read this as approval',
    );
    expect(evidence.shadowDivergenceLogLine, isNotNull);
  });

  test('an affirmative reply after a prompt still does not approve', () {
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

    expect(coordinator.evidenceFor(7).approved, isFalse);
  });

  test('the shadow verdict agrees once the token option is selected', () {
    selectTokenOption();
    // Nothing is pending yet, so no token has been issued.
    expect(coordinator.evidenceFor(7).approved, isFalse);
  });

  test('a token issued for one conversation cannot approve another', () {
    final toolCall = ToolCallInfo(
      id: 'release-call',
      name: 'local_execute_command',
      arguments: const {'command': './release_ios_macos.sh'},
    );
    // Block in conversation-a, which issues the token there.
    coordinator.buildGuardResult(
      toolCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );
    expect(coordinator.approvalToken('conversation-a'), token);

    // The same answer, recorded against another conversation's turn owner.
    questionResults.store(
      owner: ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 7,
      ),
      question: 'Approve the production release?',
      optionLabels: ['Approve $token', 'Cancel'],
      result: McpToolResult(
        toolName: 'ask_user_question',
        result: jsonEncode({
          'status': 'answered',
          'selected': [
            {'label': 'Approve $token'},
          ],
        }),
        isSuccess: true,
      ),
    );

    expect(
      coordinator.evidenceFor(7).approved,
      isFalse,
      reason: 'approval is scoped to the turn owner that was blocked',
    );
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

    expect(coordinator.approvalToken('conversation-a'), token);

    // Prose approval leaves the release blocked.
    coordinator.captureProof(
      generation: 7,
      conversation: _conversation(),
      submittedContent: 'I explicitly approve the production release.',
    );
    expect(
      coordinator.buildGuardResult(
        toolCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      ),
      isNotNull,
    );

    // Selecting the token-bearing option releases it.
    selectTokenOption();
    final allowed = coordinator.buildGuardResult(
      toolCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );

    expect(allowed, isNull);
    expect(coordinator.pendingRelease('conversation-a'), isNull);
    expect(
      coordinator.approvalToken('conversation-a'),
      isNull,
      reason: 'the token authorized this release and nothing else',
    );
  });

  group('a release already dispatched in this turn', () {
    final releaseCall = ToolCallInfo(
      id: 'release-call',
      name: 'process_start',
      arguments: const {'command': 'bash tool/release_ios_macos.sh'},
    );

    /// The turn result of a release that really launched.
    ToolResultInfo dispatched({
      String command = 'bash tool/release_ios_macos.sh',
    }) => ToolResultInfo(
      id: 'release-result',
      name: 'process_start',
      arguments: {'command': command},
      result: jsonEncode({'ok': true, 'job_id': 'proc_1'}),
      outcome: const ToolOutcome(processState: ToolProcessState.running),
    );

    /// Approves and lets the release through, leaving the token spent.
    void approveAndDispatch() {
      coordinator.buildGuardResult(
        releaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      );
      selectTokenOption();
      expect(
        coordinator.buildGuardResult(
          releaseCall,
          currentAssistantContent: null,
          evidence: coordinator.evidenceFor(7),
        ),
        isNull,
        reason: 'the token authorized this release',
      );
      expect(coordinator.approvalToken('conversation-a'), isNull);
    }

    test('is refused as already executed rather than re-gated', () {
      approveAndDispatch();

      final repeated = coordinator.buildGuardResult(
        releaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
        executedToolResults: [dispatched()],
      );

      expect(repeated, isNotNull, reason: 'the release must not run twice');
      expect(
        jsonDecode(repeated!.result),
        containsPair('code', 'production_release_already_executed'),
      );
      expect(
        coordinator.approvalToken('conversation-a'),
        isNull,
        reason:
            'minting a second token is the livelock: the turn answer cache '
            'can only replay the answer carrying the spent one, so no answer '
            'the user gives could ever satisfy it',
      );
    });

    test('is matched across whitespace spellings of the same command', () {
      approveAndDispatch();

      final repeated = coordinator.buildGuardResult(
        ToolCallInfo(
          id: 'release-call-2',
          name: 'process_start',
          arguments: const {'command': 'bash  tool/release_ios_macos.sh'},
        ),
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
        executedToolResults: [dispatched()],
      );

      expect(
        jsonDecode(repeated!.result),
        containsPair('code', 'production_release_already_executed'),
      );
    });

    test('does not cover a different release command', () {
      approveAndDispatch();

      final other = coordinator.buildGuardResult(
        ToolCallInfo(
          id: 'other-release',
          name: 'process_start',
          arguments: const {
            'command': 'bash tool/publish_macos_sparkle_release.sh',
          },
        ),
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
        executedToolResults: [dispatched()],
      );

      expect(
        jsonDecode(other!.result),
        containsPair('code', 'production_release_explicit_approval_required'),
        reason: 'a release nobody approved still needs approval',
      );
    });

    test('is not inferred from a result that never ran the command', () {
      // The guard refusal is itself a turn result, and it carries no outcome.
      // Reading it as a dispatch would let an unapproved release through.
      final blocked = coordinator.buildGuardResult(
        releaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      );
      final blockedResult = ToolResultInfo(
        id: 'release-result',
        name: 'process_start',
        arguments: const {'command': 'bash tool/release_ios_macos.sh'},
        result: blocked!.result,
      );

      expect(
        const ProductionReleaseDispatchEvidence().hasDispatched(
          command: 'bash tool/release_ios_macos.sh',
          executedToolResults: [blockedResult],
        ),
        isFalse,
      );
      final repeated = coordinator.buildGuardResult(
        releaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
        executedToolResults: [blockedResult],
      );
      expect(
        jsonDecode(repeated!.result),
        containsPair('code', 'production_release_explicit_approval_required'),
      );
    });

    test('is not inferred from a launch that was denied', () {
      // A denied process reaches no exit, so both fields stay null. Flattening
      // that into "it ran" would strand the turn on a release it never made.
      expect(
        const ProductionReleaseDispatchEvidence().hasDispatched(
          command: 'bash tool/release_ios_macos.sh',
          executedToolResults: [
            ToolResultInfo(
              id: 'release-result',
              name: 'process_start',
              arguments: const {'command': 'bash tool/release_ios_macos.sh'},
              result: 'denied',
              outcome: const ToolOutcome(),
            ),
          ],
        ),
        isFalse,
      );
    });

    test('ignores a dry run, which is not a production release', () {
      expect(
        const ProductionReleaseDispatchEvidence().hasDispatched(
          command: 'bash tool/release_ios_macos.sh --dry-run',
          executedToolResults: [
            dispatched(command: 'bash tool/release_ios_macos.sh --dry-run'),
          ],
        ),
        isFalse,
      );
    });
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
