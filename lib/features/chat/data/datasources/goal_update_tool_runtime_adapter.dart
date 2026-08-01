import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/services/goal_update_tool_handler.dart';

typedef GoalUpdateOwnerCurrentCallback =
    bool Function(GoalUpdateOperationIdentity identity);
typedef GoalUpdateOwnerSnapshotCallback =
    GoalUpdateOwnerSnapshot? Function(GoalUpdateOperationIdentity identity);
typedef GoalUpdateAcknowledgementCallback =
    GoalUpdatePersistenceReceipt Function(
      GoalUpdateCompletionAcknowledgement acknowledgement,
    );

enum GoalUpdatePersistenceDisposition { acknowledged, ownerRetired }

/// Exact receipt returned after claim and shadow state are persisted.
final class GoalUpdatePersistenceReceipt {
  const GoalUpdatePersistenceReceipt.acknowledged({required this.identity})
    : disposition = GoalUpdatePersistenceDisposition.acknowledged;

  const GoalUpdatePersistenceReceipt.ownerRetired({required this.identity})
    : disposition = GoalUpdatePersistenceDisposition.ownerRetired;

  final GoalUpdateOperationIdentity identity;
  final GoalUpdatePersistenceDisposition disposition;
}

/// Owner-aware access to the goal, completion evidence, and claim state.
abstract interface class GoalUpdateRuntimePort {
  bool isCurrent(GoalUpdateOperationIdentity identity);

  GoalUpdateOwnerSnapshot? captureSnapshot(
    GoalUpdateOperationIdentity identity,
  );

  GoalUpdatePersistenceReceipt persistAcknowledgement(
    GoalUpdateCompletionAcknowledgement acknowledgement,
  );
}

/// Narrow callback bridge for the existing turn-scoped registries.
final class CallbackGoalUpdateRuntimePort implements GoalUpdateRuntimePort {
  const CallbackGoalUpdateRuntimePort({
    required GoalUpdateOwnerCurrentCallback isCurrent,
    required GoalUpdateOwnerSnapshotCallback captureSnapshot,
    required GoalUpdateAcknowledgementCallback persistAcknowledgement,
  }) : _isCurrent = isCurrent,
       _captureSnapshot = captureSnapshot,
       _persistAcknowledgement = persistAcknowledgement;

  final GoalUpdateOwnerCurrentCallback _isCurrent;
  final GoalUpdateOwnerSnapshotCallback _captureSnapshot;
  final GoalUpdateAcknowledgementCallback _persistAcknowledgement;

  @override
  bool isCurrent(GoalUpdateOperationIdentity identity) => _isCurrent(identity);

  @override
  GoalUpdateOwnerSnapshot? captureSnapshot(
    GoalUpdateOperationIdentity identity,
  ) => _captureSnapshot(identity);

  @override
  GoalUpdatePersistenceReceipt persistAcknowledgement(
    GoalUpdateCompletionAcknowledgement acknowledgement,
  ) => _persistAcknowledgement(acknowledgement);
}

enum GoalUpdateRuntimeDisposition { completed, ownerRetired, boundaryMismatch }

/// Exact runtime completion returned to the notifier dispatch boundary.
final class GoalUpdateRuntimeCompletion {
  GoalUpdateRuntimeCompletion.completed({
    required this.identity,
    required GoalUpdateToolHandlerOutcome this.outcome,
  }) : disposition = GoalUpdateRuntimeDisposition.completed,
       result = outcome.toolResult;

  GoalUpdateRuntimeCompletion.ownerRetired({required this.identity})
    : disposition = GoalUpdateRuntimeDisposition.ownerRetired,
      outcome = null,
      result = _failure(
        'The update_goal turn expired before its acknowledgement was '
        'recorded.',
      );

  GoalUpdateRuntimeCompletion.boundaryMismatch({required this.identity})
    : disposition = GoalUpdateRuntimeDisposition.boundaryMismatch,
      outcome = null,
      result = _failure(
        'The update_goal runtime returned state for another tool call.',
      );

  final GoalUpdateOperationIdentity identity;
  final GoalUpdateRuntimeDisposition disposition;
  final GoalUpdateToolHandlerOutcome? outcome;
  final McpToolResult result;

  static McpToolResult _failure(String message) => McpToolResult(
    toolName: canonicalGoalUpdateToolName,
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}

/// Runs goal acknowledgement against one exact live owner snapshot.
final class GoalUpdateToolRuntimeAdapter {
  const GoalUpdateToolRuntimeAdapter({
    required GoalUpdateRuntimePort runtimePort,
    GoalUpdateToolHandler handler = const GoalUpdateToolHandler(),
  }) : _runtimePort = runtimePort,
       _handler = handler;

  final GoalUpdateRuntimePort _runtimePort;
  final GoalUpdateToolHandler _handler;

  GoalUpdateRuntimeCompletion handle(GoalUpdateToolRequest request) {
    final identity = request.identity;
    if (!_runtimePort.isCurrent(identity)) {
      return GoalUpdateRuntimeCompletion.ownerRetired(identity: identity);
    }
    final snapshot = _runtimePort.captureSnapshot(identity);
    if (snapshot == null) {
      return GoalUpdateRuntimeCompletion.ownerRetired(identity: identity);
    }
    if (!snapshot.identity.belongsTo(identity)) {
      return GoalUpdateRuntimeCompletion.boundaryMismatch(identity: identity);
    }
    if (!_runtimePort.isCurrent(identity)) {
      return GoalUpdateRuntimeCompletion.ownerRetired(identity: identity);
    }

    final outcome = _handler.handle(request: request, ownerSnapshot: snapshot);
    if (!outcome.identity.belongsTo(identity) ||
        !outcome.acknowledgement.belongsTo(identity)) {
      return GoalUpdateRuntimeCompletion.boundaryMismatch(identity: identity);
    }
    if (!_runtimePort.isCurrent(identity)) {
      return GoalUpdateRuntimeCompletion.ownerRetired(identity: identity);
    }

    final receipt = _runtimePort.persistAcknowledgement(
      outcome.acknowledgement,
    );
    if (!receipt.identity.belongsTo(identity)) {
      return GoalUpdateRuntimeCompletion.boundaryMismatch(identity: identity);
    }
    if (receipt.disposition == GoalUpdatePersistenceDisposition.ownerRetired ||
        !_runtimePort.isCurrent(identity)) {
      return GoalUpdateRuntimeCompletion.ownerRetired(identity: identity);
    }
    return GoalUpdateRuntimeCompletion.completed(
      identity: identity,
      outcome: outcome,
    );
  }
}
