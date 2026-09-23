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

  /// Records the user selecting the one offered option for the pending release.
  void selectTokenOption({String? approveLabel, String? question}) {
    final pending = coordinator.pendingRelease('conversation-a');
    final issuedToken = coordinator.approvalToken('conversation-a') ?? token;
    final label =
        approveLabel ??
        (pending?.executionIdentity == null
            ? 'Approve $issuedToken'
            : productionReleaseApprovalOptionLabel(
                executionIdentity: pending!.executionIdentity!,
                approvalToken: issuedToken,
              ));
    final trustedQuestion = pending?.executionIdentity == null
        ? 'Approve the production release?'
        : productionReleaseApprovalQuestion(
            toolName: pending!.toolName,
            command: pending.command,
            workingDirectory: pending.workingDirectory,
            background: pending.background,
          );
    final answeredQuestion = question ?? trustedQuestion;
    questionResults.store(
      owner: _owner(),
      question: answeredQuestion,
      optionLabels: [label, 'Cancel'],
      result: McpToolResult(
        toolName: 'ask_user_question',
        result: jsonEncode({
          'status': 'answered',
          'question': answeredQuestion,
          'selected': [
            {'label': label},
          ],
          'answer': label,
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

  test('an approval cannot authorize a different release command', () {
    final releaseCall = ToolCallInfo(
      id: 'release-call',
      name: 'local_execute_command',
      arguments: const {'command': './release_ios_macos.sh'},
    );
    final differentReleaseCall = ToolCallInfo(
      id: 'different-release-call',
      name: 'process_start',
      arguments: const {'command': './publish_macos_sparkle_release.sh'},
    );

    coordinator.buildGuardResult(
      releaseCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );
    selectTokenOption();

    final blockedDifferentRelease = coordinator.buildGuardResult(
      differentReleaseCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );

    expect(blockedDifferentRelease, isNotNull);
    final blockedPayload =
        jsonDecode(blockedDifferentRelease!.result) as Map<String, dynamic>;
    expect(
      blockedPayload,
      containsPair('code', productionReleaseApprovalConflictCode),
    );
    expect(blockedPayload['required_action'], isNot(contains(token)));
    expect(
      coordinator.pendingRelease('conversation-a')?.command,
      './release_ios_macos.sh',
    );
    expect(coordinator.approvalToken('conversation-a'), token);

    expect(
      coordinator.buildGuardResult(
        releaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      ),
      isNull,
    );
    expect(coordinator.approvalToken('conversation-a'), isNull);
  });

  test('binds the approval UI to the harness-owned execution summary', () {
    final releaseCall = ToolCallInfo(
      id: 'release-call',
      name: 'local_execute_command',
      arguments: const {
        'command': './release_ios_macos.sh --publish',
        'working_directory': '/tmp/project',
      },
    );
    coordinator.buildGuardResult(
      releaseCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );
    final pending = coordinator.pendingRelease('conversation-a')!;
    final approvalLabel = productionReleaseApprovalOptionLabel(
      executionIdentity: pending.executionIdentity!,
      approvalToken: token,
    );

    final bound = coordinator.bindPendingApprovalQuestion(
      'conversation-a',
      ToolCallInfo(
        id: 'approval-question',
        name: 'ask_user_question',
        arguments: {
          'question': 'Approve a different release?',
          'help': 'Model-authored explanation.',
          'options': [
            {'label': approvalLabel, 'description': 'Approve something else.'},
          ],
          'allow_other': true,
        },
      ),
    );

    expect(
      bound.arguments['question'],
      productionReleaseApprovalQuestion(
        toolName: pending.toolName,
        command: pending.command,
        workingDirectory: pending.workingDirectory,
        background: pending.background,
      ),
    );
    expect(bound.arguments['question'], contains('/tmp/project'));
    expect(bound.arguments['question'], contains('--publish'));
    expect(bound.arguments['allow_other'], isFalse);
    expect(bound.arguments['allow_multiple'], isFalse);
    final options = bound.arguments['options'] as List;
    expect(options, hasLength(2));
    expect((options.first as Map)['label'], approvalLabel);
    expect(
      (options.first as Map)['description'],
      isNot(contains('something else')),
    );
  });

  test('a model-authored question cannot mislabel the pending release', () {
    final releaseCall = ToolCallInfo(
      id: 'release-call',
      name: 'local_execute_command',
      arguments: const {'command': './release_ios_macos.sh'},
    );
    coordinator.buildGuardResult(
      releaseCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );
    selectTokenOption(question: 'Approve a different production release?');

    expect(coordinator.evidenceFor(7).approved, isFalse);
    final refused = coordinator.buildGuardResult(
      releaseCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );
    expect(refused, isNotNull);
    expect(
      jsonDecode(refused!.result),
      containsPair('code', 'production_release_explicit_approval_required'),
    );
  });

  test(
    'keeps the first pending release when another is blocked before approval',
    () {
      final firstReleaseCall = ToolCallInfo(
        id: 'first-release-call',
        name: 'local_execute_command',
        arguments: const {'command': './release_ios_macos.sh'},
      );
      final secondReleaseCall = ToolCallInfo(
        id: 'second-release-call',
        name: 'process_start',
        arguments: const {'command': './publish_macos_sparkle_release.sh'},
      );

      coordinator.buildGuardResult(
        firstReleaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      );
      final firstToken = coordinator.approvalToken('conversation-a');

      final secondBlock = coordinator.buildGuardResult(
        secondReleaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      );
      expect(secondBlock, isNotNull);
      final secondPayload = jsonDecode(secondBlock!.result);
      expect(
        secondPayload,
        containsPair('code', productionReleaseApprovalConflictCode),
      );
      expect(
        (secondPayload as Map<String, dynamic>)['required_action'],
        isNot(contains(firstToken!)),
      );
      expect(
        coordinator.pendingRelease('conversation-a')?.command,
        './release_ios_macos.sh',
      );
      expect(coordinator.approvalToken('conversation-a'), firstToken);

      selectTokenOption(approveLabel: 'Approve the second release $firstToken');
      expect(
        coordinator.buildGuardResult(
          firstReleaseCall,
          currentAssistantContent: null,
          evidence: coordinator.evidenceFor(7),
        ),
        isNotNull,
      );

      selectTokenOption();
      expect(
        coordinator.buildGuardResult(
          secondReleaseCall,
          currentAssistantContent: null,
          evidence: coordinator.evidenceFor(7),
        ),
        isNotNull,
      );
      expect(
        coordinator.buildGuardResult(
          firstReleaseCall,
          currentAssistantContent: null,
          evidence: coordinator.evidenceFor(7),
        ),
        isNull,
      );
    },
  );

  test('an approval cannot change the release working directory', () {
    final releaseCall = ToolCallInfo(
      id: 'release-call',
      name: 'local_execute_command',
      arguments: const {
        'command': './release_ios_macos.sh',
        'working_directory': '/tmp/project',
      },
    );
    final differentDirectoryCall = ToolCallInfo(
      id: 'different-directory-call',
      name: 'local_execute_command',
      arguments: const {
        'command': './release_ios_macos.sh',
        'working_directory': '/tmp/project/subproject',
      },
    );

    coordinator.buildGuardResult(
      releaseCall,
      currentAssistantContent: null,
      evidence: coordinator.evidenceFor(7),
    );
    selectTokenOption();

    expect(
      coordinator.buildGuardResult(
        differentDirectoryCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      ),
      isNotNull,
    );
    expect(coordinator.approvalToken('conversation-a'), token);
    expect(
      coordinator.buildGuardResult(
        releaseCall,
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
      ),
      isNull,
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
      String? workingDirectory,
    }) => ToolResultInfo(
      id: 'release-result',
      name: 'process_start',
      arguments: {'command': command, 'working_directory': ?workingDirectory},
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

    test('does not cover the same command in a different directory', () {
      final otherDirectory = coordinator.buildGuardResult(
        ToolCallInfo(
          id: 'other-directory-release',
          name: 'process_start',
          arguments: const {
            'command': 'bash tool/release_ios_macos.sh',
            'working_directory': '/tmp/project-b',
          },
        ),
        currentAssistantContent: null,
        evidence: coordinator.evidenceFor(7),
        executedToolResults: [dispatched(workingDirectory: '/tmp/project-a')],
      );

      expect(
        jsonDecode(otherDirectory!.result),
        containsPair('code', 'production_release_explicit_approval_required'),
        reason: 'a release in another working directory still needs approval',
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
          toolCall: releaseCall,
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
          toolCall: releaseCall,
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
          toolCall: ToolCallInfo(
            id: 'dry-run-call',
            name: 'process_start',
            arguments: {'command': 'bash tool/release_ios_macos.sh --dry-run'},
          ),
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
