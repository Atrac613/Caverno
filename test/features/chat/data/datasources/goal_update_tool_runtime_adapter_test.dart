import 'package:caverno/features/chat/data/datasources/goal_update_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/goal_update_ack.dart';
import 'package:caverno/features/chat/domain/services/goal_update_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:test/test.dart';

void main() {
  group('GoalUpdateToolRuntimeAdapter', () {
    test('persists and returns the exact completion acknowledgement', () {
      final request = _request(arguments: const {'completed': true});
      GoalUpdateCompletionAcknowledgement? persisted;
      final adapter = GoalUpdateToolRuntimeAdapter(
        runtimePort: CallbackGoalUpdateRuntimePort(
          isCurrent: (identity) => identity == request.identity,
          captureSnapshot: (identity) => _snapshot(request),
          persistAcknowledgement: (acknowledgement) {
            persisted = acknowledgement;
            return GoalUpdatePersistenceReceipt.acknowledged(
              identity: acknowledgement.identity,
            );
          },
        ),
      );

      final completion = adapter.handle(request);

      expect(completion.disposition, GoalUpdateRuntimeDisposition.completed);
      expect(completion.identity, request.identity);
      expect(completion.result.isSuccess, isTrue);
      expect(
        completion.outcome?.ackOutcome,
        GoalUpdateAckOutcome.completionRecorded,
      );
      expect(persisted, same(completion.outcome?.acknowledgement));
      expect(persisted?.belongsTo(request.identity), isTrue);
    });

    test('rejects a snapshot belonging to another owner', () {
      final request = _request(arguments: const {'completed': true});
      final poisoned = _request(
        owner: _owner('conversation-b', 4),
        arguments: const {'completed': true},
      );

      final completion = _adapter(
        request,
        snapshot: _snapshot(poisoned),
      ).handle(request);

      _expectBoundaryMismatch(completion, request);
    });

    test('rejects a same-owner snapshot from another call', () {
      final owner = _owner('conversation-a', 4);
      final request = _request(
        owner: owner,
        toolCallId: 'goal-call-a',
        arguments: const {'completed': true},
      );
      final poisoned = _request(
        owner: owner,
        toolCallId: 'goal-call-b',
        arguments: const {'completed': true},
      );

      final completion = _adapter(
        request,
        snapshot: _snapshot(poisoned),
      ).handle(request);

      _expectBoundaryMismatch(completion, request);
    });

    test('rejects a same-call snapshot with another argument digest', () {
      final owner = _owner('conversation-a', 4);
      final request = _request(
        owner: owner,
        arguments: const {'completed': true},
      );
      final poisoned = _request(
        owner: owner,
        arguments: const {'message': 'Still working'},
      );
      expect(
        request.identity.argumentDigest,
        isNot(poisoned.identity.argumentDigest),
      );

      final completion = _adapter(
        request,
        snapshot: _snapshot(poisoned),
      ).handle(request);

      _expectBoundaryMismatch(completion, request);
    });

    test('rejects a persistence receipt for another exact call', () {
      final owner = _owner('conversation-a', 4);
      final request = _request(
        owner: owner,
        arguments: const {'completed': true},
      );
      final poisoned = _request(
        owner: owner,
        toolCallId: 'other-call',
        arguments: const {'completed': true},
      );
      final adapter = GoalUpdateToolRuntimeAdapter(
        runtimePort: CallbackGoalUpdateRuntimePort(
          isCurrent: (_) => true,
          captureSnapshot: (_) => _snapshot(request),
          persistAcknowledgement: (_) =>
              GoalUpdatePersistenceReceipt.acknowledged(
                identity: poisoned.identity,
              ),
        ),
      );

      final completion = adapter.handle(request);

      _expectBoundaryMismatch(completion, request);
    });

    test('does not capture state for an already retired owner', () {
      final request = _request(arguments: const {'completed': true});
      var captured = false;
      var persisted = false;
      final adapter = GoalUpdateToolRuntimeAdapter(
        runtimePort: CallbackGoalUpdateRuntimePort(
          isCurrent: (_) => false,
          captureSnapshot: (_) {
            captured = true;
            return _snapshot(request);
          },
          persistAcknowledgement: (acknowledgement) {
            persisted = true;
            return GoalUpdatePersistenceReceipt.acknowledged(
              identity: acknowledgement.identity,
            );
          },
        ),
      );

      final completion = adapter.handle(request);

      _expectRetired(completion, request);
      expect(captured, isFalse);
      expect(persisted, isFalse);
    });

    test('drops an acknowledgement when the owner retires after capture', () {
      final request = _request(arguments: const {'completed': true});
      var currentChecks = 0;
      var persisted = false;
      final adapter = GoalUpdateToolRuntimeAdapter(
        runtimePort: CallbackGoalUpdateRuntimePort(
          isCurrent: (_) => currentChecks++ == 0,
          captureSnapshot: (_) => _snapshot(request),
          persistAcknowledgement: (acknowledgement) {
            persisted = true;
            return GoalUpdatePersistenceReceipt.acknowledged(
              identity: acknowledgement.identity,
            );
          },
        ),
      );

      final completion = adapter.handle(request);

      _expectRetired(completion, request);
      expect(persisted, isFalse);
    });

    test('honors retirement reported by acknowledgement persistence', () {
      final request = _request(arguments: const {'completed': true});
      final adapter = GoalUpdateToolRuntimeAdapter(
        runtimePort: CallbackGoalUpdateRuntimePort(
          isCurrent: (_) => true,
          captureSnapshot: (_) => _snapshot(request),
          persistAcknowledgement: (acknowledgement) =>
              GoalUpdatePersistenceReceipt.ownerRetired(
                identity: acknowledgement.identity,
              ),
        ),
      );

      final completion = adapter.handle(request);

      _expectRetired(completion, request);
    });

    test(
      'returns an inactive-goal acknowledgement through the same identity',
      () {
        final request = _request(arguments: const {'message': 'Progress'});
        final adapter = _adapter(
          request,
          snapshot: _snapshot(request, hasGoal: false),
        );

        final completion = adapter.handle(request);

        expect(completion.disposition, GoalUpdateRuntimeDisposition.completed);
        expect(
          completion.outcome?.ackOutcome,
          GoalUpdateAckOutcome.rejectedInactive,
        );
        expect(completion.result.isSuccess, isFalse);
        expect(
          completion.outcome?.acknowledgement.belongsTo(request.identity),
          isTrue,
        );
      },
    );
  });
}

GoalUpdateToolRuntimeAdapter _adapter(
  GoalUpdateToolRequest request, {
  required GoalUpdateOwnerSnapshot snapshot,
}) => GoalUpdateToolRuntimeAdapter(
  runtimePort: CallbackGoalUpdateRuntimePort(
    isCurrent: (_) => true,
    captureSnapshot: (_) => snapshot,
    persistAcknowledgement: (acknowledgement) =>
        GoalUpdatePersistenceReceipt.acknowledged(
          identity: acknowledgement.identity,
        ),
  ),
);

void _expectBoundaryMismatch(
  GoalUpdateRuntimeCompletion completion,
  GoalUpdateToolRequest request,
) {
  expect(completion.identity, request.identity);
  expect(completion.disposition, GoalUpdateRuntimeDisposition.boundaryMismatch);
  expect(completion.outcome, isNull);
  expect(completion.result.isSuccess, isFalse);
  expect(completion.result.toolName, canonicalGoalUpdateToolName);
}

void _expectRetired(
  GoalUpdateRuntimeCompletion completion,
  GoalUpdateToolRequest request,
) {
  expect(completion.identity, request.identity);
  expect(completion.disposition, GoalUpdateRuntimeDisposition.ownerRetired);
  expect(completion.outcome, isNull);
  expect(completion.result.isSuccess, isFalse);
  expect(completion.result.errorMessage, contains('turn expired'));
}

GoalUpdateToolRequest _request({
  ChatTurnOwner? owner,
  String toolCallId = 'goal-call-a',
  Map<String, dynamic> arguments = const {},
}) => GoalUpdateToolRequest(
  owner: owner ?? _owner('conversation-a', 4),
  toolCallId: toolCallId,
  toolName: canonicalGoalUpdateToolName,
  arguments: arguments,
);

GoalUpdateOwnerSnapshot _snapshot(
  GoalUpdateToolRequest request, {
  bool hasGoal = true,
}) => GoalUpdateOwnerSnapshot(
  identity: request.identity,
  goal: hasGoal ? _goal() : null,
  toolResults: const [],
  completionEvidence: const ToolResultCompletionEvidence(),
);

ChatTurnOwner _owner(String conversationId, int generation) => ChatTurnOwner(
  conversationId: conversationId,
  interactionGeneration: generation,
);

ConversationGoal _goal() {
  final at = DateTime.utc(2026, 7, 31);
  return ConversationGoal(
    id: 'goal-a',
    objective: 'Finish the exact owner task',
    status: ConversationGoalStatus.active,
    createdAt: at,
    updatedAt: at,
  );
}
