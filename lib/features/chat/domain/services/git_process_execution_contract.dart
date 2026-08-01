import '../entities/chat_turn_owner.dart';

String _validatedGitProcessValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, name);
  return normalized;
}

final class GitProcessExecutionIdentity {
  GitProcessExecutionIdentity({
    required this.owner,
    required String toolCallId,
    required String toolName,
    required String repositoryIdentity,
    required String worktreeIdentity,
    required String argumentDigest,
  }) : toolCallId = _validatedGitProcessValue(toolCallId, 'toolCallId'),
       toolName = _validatedGitProcessValue(toolName, 'toolName'),
       repositoryIdentity = _validatedGitProcessValue(
         repositoryIdentity,
         'repositoryIdentity',
       ),
       worktreeIdentity = _validatedGitProcessValue(
         worktreeIdentity,
         'worktreeIdentity',
       ),
       argumentDigest = _validatedGitProcessValue(
         argumentDigest,
         'argumentDigest',
       );

  final ChatTurnOwner owner;
  final String toolCallId, toolName, repositoryIdentity;
  final String worktreeIdentity, argumentDigest;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is GitProcessExecutionIdentity &&
            other.owner == owner &&
            other.toolCallId == toolCallId &&
            other.toolName == toolName &&
            other.repositoryIdentity == repositoryIdentity &&
            other.worktreeIdentity == worktreeIdentity &&
            other.argumentDigest == argumentDigest;
  }

  @override
  int get hashCode => Object.hash(
    owner,
    toolCallId,
    toolName,
    repositoryIdentity,
    worktreeIdentity,
    argumentDigest,
  );
}

enum GitProcessReserveDisposition {
  reserved,
  ownerRetired,
  resourceBusy,
  attemptConflict,
}

enum GitProcessStartDisposition {
  started,
  alreadyStarted,
  ownerRetired,
  alreadyCompleted,
  invalidAttempt,
}

enum GitProcessAbandonDisposition {
  abandoned,
  alreadyAbandoned,
  alreadyStarted,
  alreadyCompleted,
  ownerRetired,
  invalidAttempt,
}

enum GitProcessCancellationCause { timeout, userRequested, ownerRetired }

enum GitProcessCancellationDisposition {
  requested,
  alreadyRequested,
  notRunning,
  alreadyCompleted,
  invalidAttempt,
}

enum GitProcessEffectKind { noEffect, committed, partialOrUnknown }

enum GitProcessCompletionDisposition {
  noEffect,
  effectCommitted,
  reconciliationRequired,
  notStarted,
  alreadyCompleted,
  invalidAttempt,
}

enum GitProcessReconciliationDisposition {
  recorded,
  alreadyRecorded,
  notRequired,
  invalidEffectReceipt,
  invalidAttempt,
}

enum GitProcessRequireReconciliationDisposition {
  required,
  alreadyRequired,
  notCommitted,
  invalidEffectReceipt,
  invalidAttempt,
}

enum GitProcessReleaseDisposition {
  released,
  reconciledAndReleased,
  reconciliationRequired,
  invalidReconciliationReceipt,
  notCompleted,
  alreadyReleased,
  invalidAttempt,
}
