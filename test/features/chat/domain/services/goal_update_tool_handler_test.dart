import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/goal_update_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:test/test.dart';

const _handler = GoalUpdateToolHandler();

void main() {
  group('GoalUpdateToolHandler', () {
    test('rejects an update when the owning goal is absent', () {
      final outcome = _handle(
        hasGoal: false,
        arguments: const {'message': 'Made progress'},
      );

      expect(outcome.ackOutcome, GoalUpdateAckOutcome.rejectedInactive);
      expect(outcome.toolResult.toolName, 'update_goal');
      expect(outcome.toolResult.isSuccess, isFalse);
      expect(outcome.toolResult.result, isEmpty);
      expect(
        outcome.toolResult.errorMessage,
        'There is no active goal to update. Set a goal with /goal before '
        'reporting its progress.',
      );
      expect(outcome.isCompletionClaim, isFalse);
      expect(outcome.completionAccepted, isFalse);
      expect(outcome.shadowOutcome, isNull);
    });

    test('rejects an update for an inactive owning goal', () {
      final outcome = _handle(
        goal: _goal(status: ConversationGoalStatus.completed),
        arguments: const {'completed': true},
      );

      expect(outcome.ackOutcome, GoalUpdateAckOutcome.rejectedInactive);
      expect(outcome.isCompletionClaim, isFalse);
      expect(outcome.shadowOutcome, isNull);
    });

    test('returns the exact progress acknowledgement without a claim', () {
      final outcome = _handle(
        arguments: const {'message': '  Added the parser  '},
      );

      expect(outcome.ackOutcome, GoalUpdateAckOutcome.progressLogged);
      expect(outcome.toolResult.isSuccess, isTrue);
      expect(
        outcome.toolResult.result,
        'Progress logged: Added the parser. Keep working toward the goal.',
      );
      expect(outcome.toolResult.errorMessage, isNull);
      expect(outcome.isCompletionClaim, isFalse);
      expect(outcome.completionAccepted, isFalse);
      expect(outcome.shadowOutcome, isNull);
    });

    test('returns the exact blocker acknowledgement without a claim', () {
      final outcome = _handle(
        arguments: const {'blocked_reason': '  Waiting for credentials  '},
      );

      expect(outcome.ackOutcome, GoalUpdateAckOutcome.blockerLogged);
      expect(
        outcome.toolResult.result,
        'Goal marked blocked: Waiting for credentials. Resolve the blocker or '
        'ask the user before reactivating the goal.',
      );
      expect(outcome.isCompletionClaim, isFalse);
      expect(outcome.shadowOutcome, isNull);
    });

    test('accepts completion with no contradictory owner evidence', () {
      final outcome = _handle(arguments: const {'completed': true});

      expect(outcome.ackOutcome, GoalUpdateAckOutcome.completionRecorded);
      expect(outcome.toolResult.isSuccess, isTrue);
      expect(
        outcome.toolResult.result,
        'Completion accepted: no mechanical evidence contradicts it. It has '
        'not been independently verified, so state plainly what you did and '
        'what remains unchecked.',
      );
      expect(outcome.isCompletionClaim, isTrue);
      expect(outcome.completionAccepted, isTrue);
      expect(outcome.shadowOutcome, GoalUpdateAckOutcome.completionRecorded);
    });

    test('rejects completion from prior incomplete owner evidence', () {
      final outcome = _handle(
        arguments: const {'completed': true},
        ownerCompletionEvidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 2,
          unresolvedErrorPaths: ['lib/a.dart'],
        ),
      );

      expect(outcome.ackOutcome, GoalUpdateAckOutcome.completionRejected);
      expect(outcome.isCompletionClaim, isTrue);
      expect(outcome.completionAccepted, isFalse);
      expect(outcome.shadowOutcome, GoalUpdateAckOutcome.completionRejected);
      expect(
        outcome.toolResult.result,
        'Completion not recorded — the following remain outstanding:\n'
        '- 2 unresolved error(s) in lib/a.dart\n'
        'The goal is still active. Resolve these and report completion again.',
      );
      expect(outcome.toolResult.isSuccess, isTrue);
      expect(outcome.toolResult.errorMessage, isNull);
      expect(outcome.completionEvidence.unresolvedErrorCount, 2);
    });

    test('rejects completion from failures in current owner results', () {
      final outcome = _handle(
        arguments: const {'completed': true},
        ownerToolResults: [
          _result(
            name: 'dart_analyze_feedback',
            result: jsonEncode({
              'diagnostics': [
                {
                  'relative_path': 'lib/current.dart',
                  'path': '/tmp/project/lib/current.dart',
                  'severity': 'Error',
                  'code': 'compile_error',
                  'message': 'Current owner failure',
                },
              ],
            }),
          ),
        ],
      );

      expect(outcome.ackOutcome, GoalUpdateAckOutcome.completionRejected);
      expect(outcome.completionEvidence.unresolvedErrorCount, 1);
      expect(outcome.completionEvidence.unresolvedErrorPaths, [
        'lib/current.dart',
      ]);
      expect(
        outcome.toolResult.result,
        contains('1 unresolved error(s) in lib/current.dart'),
      );
    });

    test(
      'carries only durable evidence when current results do not settle it',
      () {
        final outcome = _handle(
          arguments: const {'completed': true},
          ownerToolResults: [
            _result(name: 'read_file', result: 'plain file contents'),
          ],
          ownerCompletionEvidence: const ToolResultCompletionEvidence(
            boundedToolLoopExhausted: true,
            unexecutedToolNames: ['edit_file'],
            hasUnexecutedActionClaim: true,
          ),
        );

        expect(outcome.completionEvidence.boundedToolLoopExhausted, isFalse);
        expect(outcome.completionEvidence.unexecutedToolNames, isEmpty);
        expect(outcome.completionEvidence.hasUnexecutedActionClaim, isTrue);
        expect(
          outcome.toolResult.result,
          isNot(contains('the tool loop stopped before the work converged')),
        );
        expect(
          outcome.toolResult.result,
          contains('an action was claimed in prose but never executed'),
        );
      },
    );

    test('successful current verification clears carried incompleteness', () {
      final outcome = _handle(
        arguments: const {'completed': true},
        ownerToolResults: [
          _result(
            name: 'local_execute_command',
            arguments: const {'command': 'dart test'},
            result: jsonEncode({'exit_code': 0, 'stdout': 'All tests passed'}),
          ),
        ],
        ownerCompletionEvidence: const ToolResultCompletionEvidence(
          unresolvedErrorCount: 1,
          unresolvedErrorPaths: ['lib/prior.dart'],
          hasFailedExecutionVerification: true,
        ),
      );

      expect(
        outcome.completionEvidence.hasSuccessfulExecutionVerification,
        isTrue,
      );
      expect(outcome.completionEvidence.hasIncompleteEvidence, isFalse);
      expect(outcome.ackOutcome, GoalUpdateAckOutcome.completionRecorded);
    });

    test('freezes carried evidence lists in the typed outcome', () {
      final paths = <String>['lib/owner-a.dart'];
      final diagnostics = <UnresolvedErrorDiagnostic>[
        const UnresolvedErrorDiagnostic(
          path: 'lib/owner-a.dart',
          code: 'compile_error',
          message: 'Owner failure',
        ),
      ];
      final outcome = _handle(
        arguments: const {'completed': true},
        ownerCompletionEvidence: ToolResultCompletionEvidence(
          unresolvedErrorCount: 1,
          unresolvedErrorPaths: paths,
          unresolvedErrorDiagnostics: diagnostics,
        ),
      );
      paths[0] = 'lib/visible-b.dart';
      diagnostics.clear();

      expect(outcome.completionEvidence.unresolvedErrorPaths, [
        'lib/owner-a.dart',
      ]);
      expect(
        outcome.completionEvidence.unresolvedErrorDiagnostics,
        hasLength(1),
      );
      expect(
        outcome.completionEvidence.unresolvedErrorDiagnostics.single.path,
        'lib/owner-a.dart',
      );
      expect(
        () => outcome.completionEvidence.unresolvedErrorPaths.add(
          'lib/mutation.dart',
        ),
        throwsUnsupportedError,
      );
    });

    test('binds the completion acknowledgement to the exact invocation', () {
      final ownerA = _owner('owner-a', 10);
      final request = _request(
        owner: ownerA,
        toolCallId: 'update-goal-a',
        arguments: const {'completed': true},
      );
      final outcome = _handler.handle(
        request: request,
        ownerSnapshot: _snapshot(request),
      );

      expect(outcome.identity, request.identity);
      expect(outcome.owner, ownerA);
      expect(outcome.acknowledgement.identity, request.identity);
      expect(outcome.acknowledgement.belongsTo(request.identity), isTrue);
      expect(outcome.ackOutcome, GoalUpdateAckOutcome.completionRecorded);
      expect(
        outcome.acknowledgement.belongsTo(
          _request(
            owner: _owner('visible-b', 11),
            toolCallId: 'update-goal-a',
            arguments: const {'completed': true},
          ).identity,
        ),
        isFalse,
      );
      expect(
        outcome.acknowledgement.belongsTo(
          _request(
            owner: ownerA,
            toolCallId: 'update-goal-b',
            arguments: const {'completed': true},
          ).identity,
        ),
        isFalse,
      );
      expect(
        outcome.acknowledgement.belongsTo(
          _request(
            owner: ownerA,
            toolCallId: 'update-goal-a',
            arguments: const {'message': 'Still working'},
          ).identity,
        ),
        isFalse,
      );
    });

    test('captures a raw call and exact owner snapshot before evaluation', () {
      final owner = _owner('owner-a', 12);
      final arguments = <String, dynamic>{'completed': true};
      final outcome = _handler.handleCall(
        owner: owner,
        toolCall: ToolCallInfo(
          id: 'update-goal-a',
          name: 'update_goal',
          arguments: arguments,
        ),
        goal: _goal(),
        toolResults: const [],
        completionEvidence: const ToolResultCompletionEvidence(),
      );
      arguments['completed'] = false;

      expect(outcome.owner, owner);
      expect(outcome.identity.toolCallId, 'update-goal-a');
      expect(outcome.ackOutcome, GoalUpdateAckOutcome.completionRecorded);
      expect(outcome.completionAccepted, isTrue);
    });

    test('rejects another owner snapshot before evaluating its goal', () {
      final ownerRequest = _request(
        owner: _owner('owner-a', 10),
        arguments: const {'completed': true},
      );
      final visibleRequest = _request(
        owner: _owner('visible-b', 11),
        arguments: const {'completed': true},
      );

      expect(
        () => _handler.handle(
          request: ownerRequest,
          ownerSnapshot: _snapshot(
            visibleRequest,
            goal: _goal(id: 'visible-goal'),
            toolResults: [
              _result(
                name: 'write_file',
                result: jsonEncode({'path': 'lib/visible.dart'}),
              ),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Goal update owner snapshot identity mismatch.',
          ),
        ),
      );
    });

    test('rejects a same-owner snapshot from another tool call', () {
      final owner = _owner('owner-a', 10);
      final expected = _request(
        owner: owner,
        toolCallId: 'update-goal-a',
        arguments: const {'completed': true},
      );
      final poisoned = _request(
        owner: owner,
        toolCallId: 'update-goal-b',
        arguments: const {'completed': true},
      );

      expect(
        () => _handler.handle(
          request: expected,
          ownerSnapshot: _snapshot(poisoned),
        ),
        throwsStateError,
      );
    });

    test('rejects a same-owner same-call snapshot with other arguments', () {
      final owner = _owner('owner-a', 10);
      final expected = _request(
        owner: owner,
        arguments: const {'completed': true},
      );
      final poisoned = _request(
        owner: owner,
        arguments: const {'message': 'Still working'},
      );

      expect(
        expected.identity.argumentDigest,
        isNot(poisoned.identity.argumentDigest),
      );
      expect(
        () => _handler.handle(
          request: expected,
          ownerSnapshot: _snapshot(poisoned),
        ),
        throwsStateError,
      );
    });

    test('requires a non-empty call ID and the canonical tool identity', () {
      expect(
        () => _request(toolCallId: '   ', arguments: const {}),
        throwsArgumentError,
      );
      for (final name in const [
        'Update_Goal',
        ' update_goal',
        'update_goal ',
      ]) {
        expect(
          () => _request(toolName: name, arguments: const {}),
          throwsArgumentError,
          reason: name,
        );
      }
    });

    test('recursively freezes request and tool-result arguments', () {
      final nestedList = <Object?>[1];
      final nestedMap = <String, Object?>{'steps': nestedList};
      final arguments = <String, dynamic>{
        'message': 'Working',
        'metadata': nestedMap,
      };
      final request = _request(arguments: arguments);
      final resultArguments = <String, dynamic>{
        'details': <String, Object?>{
          'paths': <Object?>['lib/a.dart'],
        },
      };
      final snapshot = _snapshot(
        request,
        toolResults: [
          _result(
            name: 'read_file',
            arguments: resultArguments,
            result: 'contents',
          ),
        ],
      );

      nestedList.add(2);
      nestedMap['other'] = true;
      arguments['message'] = 'Changed';
      (resultArguments['details'] as Map<String, Object?>)['paths'] = <Object?>[
        'lib/changed.dart',
      ];

      expect(request.arguments['message'], 'Working');
      final frozenMetadata =
          request.arguments['metadata'] as Map<String, dynamic>;
      expect(frozenMetadata['steps'], [1]);
      expect(() => frozenMetadata['other'] = true, throwsUnsupportedError);
      final frozenDetails =
          snapshot.toolResults.single.arguments['details']
              as Map<String, dynamic>;
      expect(frozenDetails['paths'], ['lib/a.dart']);
      expect(
        () => (frozenDetails['paths'] as List<Object?>).add('lib/b.dart'),
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON request and tool-result values', () {
      for (final invalid in <Object>[
        <String>{'not-json'},
        DateTime.utc(2026, 7, 31),
        double.nan,
      ]) {
        expect(
          () => _request(arguments: {'metadata': invalid}),
          throwsArgumentError,
          reason: '$invalid',
        );
      }
      expect(
        () => _request(
          arguments: <String, dynamic>{
            'metadata': <Object?, Object?>{1: 'not-a-string-key'},
          },
        ),
        throwsArgumentError,
      );

      final request = _request(arguments: const {'completed': true});
      expect(
        () => _snapshot(
          request,
          toolResults: [
            _result(
              name: 'read_file',
              arguments: {'captured_at': DateTime.utc(2026, 7, 31)},
              result: 'contents',
            ),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}

GoalUpdateToolHandlerOutcome _handle({
  bool hasGoal = true,
  ConversationGoal? goal,
  Map<String, dynamic> arguments = const {},
  List<ToolResultInfo> ownerToolResults = const [],
  ToolResultCompletionEvidence ownerCompletionEvidence =
      const ToolResultCompletionEvidence(),
}) {
  final request = _request(arguments: arguments);
  return _handler.handle(
    request: request,
    ownerSnapshot: _snapshot(
      request,
      hasGoal: hasGoal,
      goal: goal,
      toolResults: ownerToolResults,
      completionEvidence: ownerCompletionEvidence,
    ),
  );
}

GoalUpdateToolRequest _request({
  ChatTurnOwner? owner,
  String toolCallId = 'update-goal',
  String toolName = 'update_goal',
  required Map<String, dynamic> arguments,
}) => GoalUpdateToolRequest(
  owner: owner ?? _owner('owner-a', 1),
  toolCallId: toolCallId,
  toolName: toolName,
  arguments: arguments,
);

GoalUpdateOwnerSnapshot _snapshot(
  GoalUpdateToolRequest request, {
  bool hasGoal = true,
  ConversationGoal? goal,
  List<ToolResultInfo> toolResults = const [],
  ToolResultCompletionEvidence completionEvidence =
      const ToolResultCompletionEvidence(),
}) => GoalUpdateOwnerSnapshot(
  identity: request.identity,
  goal: hasGoal ? goal ?? _goal() : null,
  toolResults: toolResults,
  completionEvidence: completionEvidence,
);

ToolResultInfo _result({
  required String name,
  Map<String, dynamic> arguments = const {},
  required String result,
}) => ToolResultInfo(
  id: '$name-result',
  name: name,
  arguments: arguments,
  result: result,
);

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

ConversationGoal _goal({
  String id = 'goal-1',
  ConversationGoalStatus status = ConversationGoalStatus.active,
}) {
  final timestamp = DateTime.utc(2026, 7, 31);
  return ConversationGoal(
    id: id,
    objective: 'Finish the owner task',
    status: status,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}
